//
//  TAFlagsAutoRegistrationTests.swift
//  TAFlagsTests
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
import TAFlagsMacros
import Testing
@testable import TAFlags

enum AutoRegisteredExperimentVariant: String, Equatable {
    case control
    case variantB = "variant_b"
}

private final class AutoRegistrationFlagsAdaptor: TAFlagsAdaptor, @unchecked Sendable {
    private(set) var defaults: [String: NSObject] = [:]

    var updatesPublisher: AnyPublisher<Set<String>, Never> {
        Empty<Set<String>, Never>().eraseToAnyPublisher()
    }

    func start() async throws {}

    func register(defaults: [String : NSObject]) {
        self.defaults = defaults
    }

    func rawValue(forKey key: String) -> TAFlagRawValue {
        if let defaultValue = defaults[key] {
            return TAFlagRawValue(defaultObject: defaultValue)
        }

        return TAFlagRawValue(string: "")
    }

    func fetchAndActivate() async throws -> Set<String> {
        []
    }
}

@TAFlagNamespace
extension TAFlags.Keys {
    static let autoRegisteredBoolean = TAFlag("auto_registered_boolean", default: false)
    static let ignoredHelper = "ignore me"
    static let autoRegisteredVariant = TAFlag<AutoRegisteredExperimentVariant>(
        "auto_registered_variant",
        default: .control
    )
}

@MainActor
struct TAFlagsAutoRegistrationTests {
    @Test
    func generatedAllFlagsPreservesDeclaredFlagOrder() {
        let keys = TAFlags.Keys.allFlags.map { $0.erasedDefinition.key }
        #expect(keys == ["auto_registered_boolean", "auto_registered_variant"])
    }

    @Test
    func generatedAllFlagsCanRegisterDefaults() async {
        let adaptor = AutoRegistrationFlagsAdaptor()
        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: TAFlags.Keys.allFlags
            )
        )

        await flags.start()

        #expect(adaptor.defaults.keys.sorted() == [
            "auto_registered_boolean",
            "auto_registered_variant"
        ])
    }
}
