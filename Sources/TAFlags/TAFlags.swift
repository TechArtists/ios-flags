//
//  TAFlags.swift
//  TAFlags
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

/// The main entry point for reading, observing, and refreshing strongly typed feature flags.
///
/// ``TAFlags`` keeps current decoded values in memory, exposes them synchronously through
/// `value` and subscript APIs, and coordinates bootstrap plus refresh work through a pluggable
/// ``TAFlagsAdaptor``.
@MainActor
public final class TAFlags: ObservableObject {
    /// The lifecycle state of the initial bootstrap sequence.
    public enum BootstrapState: Equatable {
        /// The flag system has not started yet.
        case idle

        /// Defaults are registered and the adaptor is currently starting or fetching.
        case bootstrapping

        /// The initial startup and fetch flow completed successfully.
        case bootstrapped

        /// The initial startup or fetch flow failed with a user-readable message.
        case failed(String)
    }

    /// The immutable configuration used to construct this instance.
    public let config: TAFlagsConfig

    /// The current lifecycle state of the initial bootstrap sequence.
    @Published public private(set) var bootstrapState: BootstrapState = .idle

    /// Indicates whether the initial bootstrap finished successfully at least once.
    public var hasCompletedInitialBootstrap: Bool {
        if case .bootstrapped = bootstrapState {
            return true
        }
        return false
    }

    private let logger: Logger

    private var updatesCancellable: AnyCancellable?
    private var hasStarted = false

    private lazy var flagsByKey: [String: AnyTAFlagDefinition] = Dictionary(
        uniqueKeysWithValues: config.registeredFlags.map { ($0.key, $0) }
    )

    /// Creates a flag store with the supplied configuration and logger.
    public init(
        config: TAFlagsConfig,
        logger: Logger = Logger(label: "ta-flags")
    ) {
        self.config = config
        self.logger = logger
    }

    /// Starts the flag system if it has not already been started.
    ///
    /// Startup registers all defaults, subscribes to runtime backend updates, then executes the
    /// configured startup policy from ``TAFlagsConfig/startupPolicy``.
    public func start() async {
        guard !hasStarted else { return }

        hasStarted = true
        bootstrapState = .bootstrapping

        registerDefaults()
        subscribeToAdaptorUpdatesIfNeeded()

        do {
            try await config.adaptor.start()
        } catch {
            logger.error("Failed to start flags adaptor: \(error.localizedDescription)")
            hasStarted = false
            bootstrapState = .failed(error.localizedDescription)
            return
        }

        switch config.startupPolicy {
        case .publishCurrentThenFetch:
            publishCurrentValues()
            await refreshInitialBootstrap()
        case .publishCurrentOnly:
            publishCurrentValues()
            bootstrapState = .bootstrapped
        case .fetchOnly:
            await refreshInitialBootstrap()
        }
    }

    /// Fetches and activates the latest remote values.
    ///
    /// If the flag system has not started yet, this method first performs the full startup flow.
    public func refresh() async {
        if !hasStarted {
            await start()
            return
        }

        do {
            let changedKeys = try await config.adaptor.fetchAndActivate()
            publishValues(forKeys: changedKeys, reason: "manual-refresh")
            bootstrapState = .bootstrapped
        } catch {
            logger.error("Failed to refresh flags: \(error.localizedDescription)")
        }
    }

    /// Returns the current value for an instance-based flag declaration.
    public func value<Value>(_ flag: TAFlag<Value>) -> Value {
        flag.publisher.value
    }

    /// Returns a publisher that emits the current and future values for an instance-based flag.
    public func publisher<Value>(_ flag: TAFlag<Value>) -> AnyPublisher<Value, Never> {
        flag.publisher.eraseToAnyPublisher()
    }

    /// Returns the current value for an instance-based flag declaration.
    public subscript<Value>(_ flag: TAFlag<Value>) -> Value {
        value(flag)
    }

    private func refreshInitialBootstrap() async {
        do {
            let changedKeys = try await config.adaptor.fetchAndActivate()
            publishValues(forKeys: changedKeys, reason: "initial-bootstrap")
            bootstrapState = .bootstrapped
        } catch {
            logger.error("Initial bootstrap fetch failed: \(error.localizedDescription)")
            bootstrapState = .failed(error.localizedDescription)
        }
    }

    private func publishCurrentValues() {
        publishValues(
            forKeys: Set(flagsByKey.keys),
            reason: "startup-active-values"
        )
    }

    private func registerDefaults() {
        let defaults = Dictionary(
            uniqueKeysWithValues: config.registeredFlags.map {
                ($0.key, $0.defaultRemoteValue)
            }
        )

        config.adaptor.register(defaults: defaults)
    }

    private func subscribeToAdaptorUpdatesIfNeeded() {
        guard updatesCancellable == nil else { return }

        updatesCancellable = config.adaptor.updatesPublisher
            .sink { [weak self] updatedKeys in
                guard let self else { return }

                Task { @MainActor [weak self] in
                    self?.publishValues(
                        forKeys: updatedKeys,
                        reason: "runtime-update"
                    )
                }
            }
    }

    private func publishValues(
        forKeys keys: Set<String>,
        reason: String
    ) {
        guard !keys.isEmpty else { return }

        var didChangeAnyValue = false

        for key in keys.sorted() {
            guard let definition = flagsByKey[key] else { continue }

            do {
                let rawValue = config.adaptor.rawValue(forKey: key)
                let didChange = try definition.publishValue(from: rawValue)

                if didChange {
                    didChangeAnyValue = true
                    logger.debug("Published updated flag '\(key)' from \(reason).")
                }
            } catch {
                logger.error("Failed to decode flag '\(key)': \(error.localizedDescription)")
            }
        }

        if didChangeAnyValue {
            objectWillChange.send()
        }
    }
}
