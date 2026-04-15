//
//  TAFlagsConfig.swift
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

import Foundation

/// Configuration for a ``TAFlags`` instance.
public struct TAFlagsConfig {
    /// Controls how ``TAFlags/start()`` initializes values during startup.
    public enum StartupPolicy: Sendable {
        /// Publishes currently active provider values, then performs an initial fetch.
        case publishCurrentThenFetch

        /// Publishes currently active provider values without performing an initial fetch.
        case publishCurrentOnly

        /// Skips publishing current provider values and only performs the initial fetch.
        case fetchOnly
    }

    /// The backend adaptor that supplies raw flag values and remote updates.
    public let adaptor: any TAFlagsAdaptor

    /// The complete set of flags this instance knows how to decode and publish.
    public let registeredFlags: [AnyTAFlagDefinition]

    /// The startup behavior used by ``TAFlags/start()``.
    public let startupPolicy: StartupPolicy

    /// Creates a configuration from already-erased flag definitions.
    ///
    /// - Precondition: All registered flags must have unique keys.
    public init(
        adaptor: any TAFlagsAdaptor,
        registeredFlags: [AnyTAFlagDefinition],
        startupPolicy: StartupPolicy = .publishCurrentThenFetch
    ) {
        let keys = registeredFlags.map(\.key)

        precondition(
            Set(keys).count == keys.count,
            "TAFlagsConfig contains duplicate flag keys."
        )

        self.adaptor = adaptor
        self.registeredFlags = registeredFlags
        self.startupPolicy = startupPolicy
    }

    /// Creates a configuration from instance-based flag declarations.
    public init(
        adaptor: any TAFlagsAdaptor,
        registeredFlags: [any TAFlagRegistrable],
        startupPolicy: StartupPolicy = .publishCurrentThenFetch
    ) {
        var erasedFlags: [AnyTAFlagDefinition] = []
        erasedFlags.reserveCapacity(registeredFlags.count)

        for flag in registeredFlags {
            erasedFlags.append(flag.erasedDefinition)
        }

        self.init(
            adaptor: adaptor,
            registeredFlags: erasedFlags,
            startupPolicy: startupPolicy
        )
    }

    /// Creates a configuration from a variadic list of instance-based flag declarations.
    public init(
        adaptor: any TAFlagsAdaptor,
        startupPolicy: StartupPolicy = .publishCurrentThenFetch,
        registeredFlags: any TAFlagRegistrable...
    ) {
        self.init(
            adaptor: adaptor,
            registeredFlags: registeredFlags,
            startupPolicy: startupPolicy
        )
    }
}
