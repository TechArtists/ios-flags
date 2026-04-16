//
//  FirebaseRemoteConfigClient.swift
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

import FirebaseRemoteConfig
import Foundation
import TAFlags

@MainActor
internal final class FirebaseRemoteConfigClient: FirebaseRemoteConfigClientProtocol {
    private let remoteConfig: RemoteConfig

    init(remoteConfig: RemoteConfig = .remoteConfig()) {
        self.remoteConfig = remoteConfig
    }

    func applySettings(
        minimumFetchInterval: TimeInterval,
        fetchTimeout: TimeInterval
    ) {
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = minimumFetchInterval
        settings.fetchTimeout = fetchTimeout
        remoteConfig.configSettings = settings
    }

    func ensureInitialized() async throws {
        try await remoteConfig.ensureInitialized()
    }

    func setDefaults(_ defaults: [String: NSObject]) {
        remoteConfig.setDefaults(defaults)
    }

    func rawValue(forKey key: String) -> TAFlagRawValue {
        let value = remoteConfig.configValue(forKey: key)
        return TAFlagRawValue(
            stringValue: value.stringValue,
            dataValue: value.dataValue,
            numberValue: value.numberValue,
            boolValue: value.boolValue
        )
    }

    func fetchAndActivate() async throws -> FirebaseRemoteConfigFetchOutcome {
        switch try await remoteConfig.fetchAndActivate() {
        case .successFetchedFromRemote:
            .successFetchedFromRemote
        case .successUsingPreFetchedData:
            .successUsingPreFetchedData
        case .error:
            .error
        @unknown default:
            .error
        }
    }

    func activate() async throws -> Bool {
        try await remoteConfig.activate()
    }

    func addOnConfigUpdateListener(
        _ listener: @escaping @Sendable (Set<String>, Error?) -> Void
    ) -> any FirebaseRemoteConfigListenerRegistration {
        FirebaseRemoteConfigListenerRegistrationAdapter(
            registration: remoteConfig.addOnConfigUpdateListener { update, error in
                listener(update?.updatedKeys ?? [], error)
            }
        )
    }
}
