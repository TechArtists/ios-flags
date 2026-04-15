//
//  FirebaseRemoteConfigFlagsAdaptor.swift
//  TAFlagsAdaptorFirebaseRemoteConfig
//
//  Copyright (c) 2026 Tech Artists Agency SRL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Combine
import Foundation
import Logging
import TAFlags

/// A ``TAFlagsAdaptor`` implementation backed by Firebase Remote Config.
public final class FirebaseRemoteConfigFlagsAdaptor: TAFlagsAdaptor, @unchecked Sendable {
    /// Runtime settings applied to `RemoteConfig.configSettings`.
    public struct Configuration: Equatable {
        #if DEBUG
        private static let defaultMinimumFetchInterval: TimeInterval = 0
        #else
        private static let defaultMinimumFetchInterval: TimeInterval = 12 * 60 * 60
        #endif

        /// The minimum interval between fetches, in seconds.
        public let minimumFetchInterval: TimeInterval

        /// The maximum amount of time to wait for a fetch request, in seconds.
        public let fetchTimeout: TimeInterval

        /// Creates a Firebase Remote Config configuration.
        public init(
            minimumFetchInterval: TimeInterval? = nil,
            fetchTimeout: TimeInterval = 60
        ) {
            self.minimumFetchInterval = minimumFetchInterval ?? Self.defaultMinimumFetchInterval
            self.fetchTimeout = fetchTimeout
        }
    }

    private let configuration: Configuration
    private let client: any FirebaseRemoteConfigClientProtocol
    private let updatesSubject = PassthroughSubject<Set<String>, Never>()
    private let logger: Logger

    private var registeredKeys: Set<String> = []
    private var listenerRegistration: (any FirebaseRemoteConfigListenerRegistration)?

    /// Publishes the registered keys whose active values changed because of a live Remote Config
    /// update.
    public var updatesPublisher: AnyPublisher<Set<String>, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    /// Creates an adaptor backed by `RemoteConfig.remoteConfig()`.
    public init(
        configuration: Configuration = .init(),
        logger: Logger = Logger(label: "firebase-remote-config-flags-adaptor")
    ) {
        self.configuration = configuration
        self.logger = logger
        self.client = FirebaseRemoteConfigClient()
    }

    internal init(
        configuration: Configuration = .init(),
        logger: Logger = Logger(label: "firebase-remote-config-flags-adaptor"),
        client: any FirebaseRemoteConfigClientProtocol
    ) {
        self.configuration = configuration
        self.logger = logger
        self.client = client
    }

    deinit {
        listenerRegistration?.remove()
    }

    /// Initializes Firebase Remote Config, applies settings, and starts listening for live config
    /// updates.
    public func start() async throws {
        guard listenerRegistration == nil else { return }

        try await client.ensureInitialized()
        client.applySettings(
            minimumFetchInterval: configuration.minimumFetchInterval,
            fetchTimeout: configuration.fetchTimeout
        )

        listenerRegistration = client.addOnConfigUpdateListener { [weak self] updatedKeys, error in
            guard let self else { return }

            if let error {
                self.logger.error("Remote Config update listener error: \(error.localizedDescription)")
                return
            }

            let relevantKeys = updatedKeys.intersection(self.registeredKeys)
            guard !relevantKeys.isEmpty else { return }

            Task {
                do {
                    _ = try await self.client.activate()
                    self.updatesSubject.send(relevantKeys)
                } catch {
                    self.logger.error("Failed to activate updated Remote Config values: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Registers default values with Firebase Remote Config and records which keys this adaptor
    /// should track.
    public func register(defaults: [String: NSObject]) {
        registeredKeys = Set(defaults.keys)
        client.setDefaults(defaults)
    }

    /// Returns the currently active Firebase Remote Config value for a key.
    public func rawValue(forKey key: String) -> TAFlagRawValue {
        client.rawValue(forKey: key)
    }

    /// Fetches and activates remote values, then returns the registered keys whose active values
    /// changed.
    public func fetchAndActivate() async throws -> Set<String> {
        let beforeSnapshot = snapshot(for: registeredKeys)
        let fetchOutcome = try await client.fetchAndActivate()

        guard fetchOutcome != .error else {
            throw FirebaseRemoteConfigFlagsAdaptorError.fetchAndActivateFailed
        }

        let afterSnapshot = snapshot(for: registeredKeys)
        return Set(afterSnapshot.compactMap { key, value in
            beforeSnapshot[key] != value ? key : nil
        })
    }

    private func snapshot(for keys: Set<String>) -> [String: TAFlagRawValue] {
        Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, client.rawValue(forKey: key))
        })
    }
}
