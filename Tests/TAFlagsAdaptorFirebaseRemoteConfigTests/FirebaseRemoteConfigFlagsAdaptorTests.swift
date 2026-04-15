//
//  FirebaseRemoteConfigFlagsAdaptorTests.swift
//  TAFlagsAdaptorFirebaseRemoteConfigTests
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
import Testing
@testable import TAFlagsAdaptorFirebaseRemoteConfig
@testable import TAFlags

private final class FakeListenerRegistration: FirebaseRemoteConfigListenerRegistration {
    private(set) var removeCallCount = 0

    func remove() {
        removeCallCount += 1
    }
}

private final class FakeFirebaseRemoteConfigClient: FirebaseRemoteConfigClientProtocol {
    var appliedMinimumFetchInterval: TimeInterval?
    var appliedFetchTimeout: TimeInterval?
    var defaults: [String: NSObject] = [:]
    var currentValues: [String: TAFlagRawValue] = [:]
    var fetchOutcome: FirebaseRemoteConfigFetchOutcome = .successFetchedFromRemote
    var fetchHook: (() -> Void)?
    var listener: (@Sendable (Set<String>, Error?) -> Void)?
    let registration = FakeListenerRegistration()

    func applySettings(minimumFetchInterval: TimeInterval, fetchTimeout: TimeInterval) {
        appliedMinimumFetchInterval = minimumFetchInterval
        appliedFetchTimeout = fetchTimeout
    }

    func ensureInitialized() async throws {}

    func setDefaults(_ defaults: [String: NSObject]) {
        self.defaults = defaults
        for (key, value) in defaults where currentValues[key] == nil {
            currentValues[key] = TAFlagRawValue(defaultObject: value)
        }
    }

    func rawValue(forKey key: String) -> TAFlagRawValue {
        if let value = currentValues[key] {
            return value
        }

        if let value = defaults[key] {
            return TAFlagRawValue(defaultObject: value)
        }

        return TAFlagRawValue(string: "")
    }

    func fetchAndActivate() async throws -> FirebaseRemoteConfigFetchOutcome {
        fetchHook?()
        return fetchOutcome
    }

    func activate() async throws -> Bool {
        true
    }

    func addOnConfigUpdateListener(
        _ listener: @escaping @Sendable (Set<String>, Error?) -> Void
    ) -> any FirebaseRemoteConfigListenerRegistration {
        self.listener = listener
        return registration
    }
}

struct FirebaseRemoteConfigFlagsAdaptorTests {
    @Test
    func defaultConfigurationUsesExpectedFetchIntervalForBuildConfiguration() async throws {
        let client = FakeFirebaseRemoteConfigClient()
        let adaptor = FirebaseRemoteConfigFlagsAdaptor(client: client)

        try await adaptor.start()

        #if DEBUG
        #expect(client.appliedMinimumFetchInterval == 0)
        #else
        #expect(client.appliedMinimumFetchInterval == 12 * 60 * 60)
        #endif
        #expect(client.appliedFetchTimeout == 60)
    }

    @Test
    func registerDefaultsPassesValuesToClient() {
        let client = FakeFirebaseRemoteConfigClient()
        let adaptor = FirebaseRemoteConfigFlagsAdaptor(client: client)

        adaptor.register(defaults: [
            "feature_bool": NSNumber(value: true),
            "welcome_copy": NSString(string: "hello")
        ])

        #expect(client.defaults["feature_bool"] as? NSNumber == NSNumber(value: true))
        #expect(client.defaults["welcome_copy"] as? NSString == "hello")
    }

    @Test
    func fetchAndActivateDiffsRegisteredKeysOnly() async throws {
        let client = FakeFirebaseRemoteConfigClient()
        client.currentValues["feature_bool"] = .init(bool: false)
        client.currentValues["ignored_key"] = .init(string: "before")
        client.fetchHook = {
            client.currentValues["feature_bool"] = .init(bool: true)
            client.currentValues["ignored_key"] = .init(string: "after")
        }

        let adaptor = FirebaseRemoteConfigFlagsAdaptor(client: client)
        adaptor.register(defaults: [
            "feature_bool": NSNumber(value: false)
        ])

        let changedKeys = try await adaptor.fetchAndActivate()

        #expect(changedKeys == ["feature_bool"])
    }

    @Test
    func startAppliesSettingsAndPublishesFilteredRuntimeUpdates() async throws {
        let client = FakeFirebaseRemoteConfigClient()
        let adaptor = FirebaseRemoteConfigFlagsAdaptor(
            configuration: .init(
                minimumFetchInterval: 5,
                fetchTimeout: 15
            ),
            client: client
        )

        adaptor.register(defaults: [
            "feature_bool": NSNumber(value: false)
        ])

        var receivedKeySets: [Set<String>] = []
        let cancellable = adaptor.updatesPublisher
            .sink { receivedKeySets.append($0) }

        defer { cancellable.cancel() }

        try await adaptor.start()
        client.listener?(Set(["feature_bool", "other_key"]), nil)
        await Task.yield()

        #expect(client.appliedMinimumFetchInterval == 5)
        #expect(client.appliedFetchTimeout == 15)
        #expect(receivedKeySets == [Set(["feature_bool"])])
    }

    @Test
    func fetchAndActivateThrowsWhenFirebaseReturnsErrorStatus() async {
        let client = FakeFirebaseRemoteConfigClient()
        client.fetchOutcome = .error

        let adaptor = FirebaseRemoteConfigFlagsAdaptor(client: client)
        adaptor.register(defaults: [
            "feature_bool": NSNumber(value: false)
        ])

        await #expect(throws: Error.self) {
            _ = try await adaptor.fetchAndActivate()
        }
    }
}
