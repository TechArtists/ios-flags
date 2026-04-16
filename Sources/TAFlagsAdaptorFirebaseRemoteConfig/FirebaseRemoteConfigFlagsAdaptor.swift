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
public final class FirebaseRemoteConfigFlagsAdaptor: TAFlagsAdaptor {
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
    private final class ListenerLifetime {
        var registration: (any FirebaseRemoteConfigListenerRegistration)?

        deinit {
            registration?.remove()
        }
    }

    private actor RuntimeUpdateBridge {
        weak var adaptor: FirebaseRemoteConfigFlagsAdaptor?

        init(adaptor: FirebaseRemoteConfigFlagsAdaptor) {
            self.adaptor = adaptor
        }

        func handle(updatedKeys: Set<String>, error: Error?) async {
            await adaptor?.handleRuntimeUpdate(updatedKeys: updatedKeys, error: error)
        }
    }

    private let clientFactory: @MainActor () -> any FirebaseRemoteConfigClientProtocol
    private let updatesSubject = PassthroughSubject<Set<String>, Never>()
    private let logger: Logging.Logger

    private var registeredKeys: Set<String> = []
    private let listenerLifetime = ListenerLifetime()
    private var cachedClient: (any FirebaseRemoteConfigClientProtocol)?
    private lazy var runtimeUpdateBridge = RuntimeUpdateBridge(adaptor: self)

    /// Publishes the registered keys whose active values changed because of a live Remote Config
    /// update.
    public var updatesPublisher: AnyPublisher<Set<String>, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    /// Creates an adaptor backed by `RemoteConfig.remoteConfig()` on first use.
    public init(
        configuration: Configuration = .init(),
        logger: Logging.Logger = Logging.Logger(label: "firebase-remote-config-flags-adaptor")
    ) {
        self.configuration = configuration
        self.logger = logger
        self.clientFactory = { FirebaseRemoteConfigClient() }
    }

    internal init(
        configuration: Configuration = .init(),
        logger: Logging.Logger = Logging.Logger(label: "firebase-remote-config-flags-adaptor"),
        client: any FirebaseRemoteConfigClientProtocol
    ) {
        self.configuration = configuration
        self.logger = logger
        self.clientFactory = { client }
    }

    internal init(
        configuration: Configuration = .init(),
        logger: Logging.Logger = Logging.Logger(label: "firebase-remote-config-flags-adaptor"),
        clientFactory: @escaping @MainActor () -> any FirebaseRemoteConfigClientProtocol
    ) {
        self.configuration = configuration
        self.logger = logger
        self.clientFactory = clientFactory
    }

    /// Initializes Firebase Remote Config, applies settings, and starts listening for live config
    /// updates.
    public func start() async throws {
        guard listenerLifetime.registration == nil else { return }

        let client = resolvedClient()

        try await client.ensureInitialized()
        client.applySettings(
            minimumFetchInterval: configuration.minimumFetchInterval,
            fetchTimeout: configuration.fetchTimeout
        )

        let runtimeUpdateBridge = self.runtimeUpdateBridge
        listenerLifetime.registration = client.addOnConfigUpdateListener { updatedKeys, error in
            Task {
                await runtimeUpdateBridge.handle(updatedKeys: updatedKeys, error: error)
            }
        }
    }

    /// Registers default values with Firebase Remote Config and records which keys this adaptor
    /// should track.
    public func register(defaults: [String: NSObject]) {
        registeredKeys = Set(defaults.keys)
        resolvedClient().setDefaults(defaults)
    }

    /// Returns the currently active Firebase Remote Config value for a key.
    public func rawValue(forKey key: String) -> TAFlagRawValue {
        resolvedClient().rawValue(forKey: key)
    }

    /// Fetches and activates remote values, then returns the registered keys whose active values
    /// changed.
    public func fetchAndActivate() async throws -> Set<String> {
        let client = resolvedClient()
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

    @MainActor
    private func handleRuntimeUpdate(updatedKeys: Set<String>, error: Error?) async {
        if let error {
            logger.error("Remote Config update listener error: \(error.localizedDescription)")
            return
        }

        let relevantKeys = updatedKeys.intersection(registeredKeys)
        guard !relevantKeys.isEmpty else { return }

        do {
            _ = try await resolvedClient().activate()
            updatesSubject.send(relevantKeys)
        } catch {
            logger.error("Failed to activate updated Remote Config values: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func snapshot(for keys: Set<String>) -> [String: TAFlagRawValue] {
        Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, resolvedClient().rawValue(forKey: key))
        })
    }

    @MainActor
    private func resolvedClient() -> any FirebaseRemoteConfigClientProtocol {
        if let cachedClient {
            return cachedClient
        }

        let client = clientFactory()
        cachedClient = client
        return client
    }
}
