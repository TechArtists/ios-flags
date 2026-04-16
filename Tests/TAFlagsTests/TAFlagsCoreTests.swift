//
//  TAFlagsCoreTests.swift
//  TAFlagsTests
//
//  Copyright (c) 2022 Tech Artists Agency SRL
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

@preconcurrency import Combine
import Foundation
import Testing
@testable import TAFlags

private enum TestExperimentVariant: String, Equatable {
    case control
    case variantB = "variant_b"
}

private struct TestJSONPayload: Codable, Equatable {
    let title: String
    let isEnabled: Bool
}

@MainActor
private final class FakeFlagsAdaptor: TAFlagsAdaptor {
    let updatesSubject = PassthroughSubject<Set<String>, Never>()

    var defaults: [String: NSObject] = [:]
    var activeValues: [String: TAFlagRawValue] = [:]
    var fetchChangedKeys: Set<String> = []
    var fetchHook: (() -> Void)?
    var startCallCount = 0

    var updatesPublisher: AnyPublisher<Set<String>, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    func start() async throws {
        startCallCount += 1
    }

    func register(defaults: [String: NSObject]) {
        self.defaults = defaults
        for (key, value) in defaults where activeValues[key] == nil {
            activeValues[key] = TAFlagRawValue(defaultObject: value)
        }
    }

    func rawValue(forKey key: String) -> TAFlagRawValue {
        if let value = activeValues[key] {
            return value
        }

        if let defaultValue = defaults[key] {
            return TAFlagRawValue(defaultObject: defaultValue)
        }

        return TAFlagRawValue(string: "")
    }

    func fetchAndActivate() async throws -> Set<String> {
        fetchHook?()
        return fetchChangedKeys
    }
}

@MainActor
struct TAFlagsCoreTests {
    @Test
    func defaultValueIsAvailableImmediatelyBeforeFetch() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        #expect(flags.value(flag) == false)

        await flags.start()

        #expect(flags.value(flag) == false)
        #expect(flags.bootstrapState == .bootstrapped)
        #expect(adaptor.startCallCount == 1)
    }

    @Test
    func defaultStartupPolicyPublishesCurrentThenFetches() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.activeValues[flag.key] = .init(bool: true)
        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            adaptor.activeValues[flag.key] = .init(bool: false)
        }

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        var receivedValues: [Bool] = []
        let cancellable = flags.publisher(flag)
            .sink { receivedValues.append($0) }

        defer { cancellable.cancel() }

        await flags.start()

        #expect(receivedValues == [false, true, false])
        #expect(flags[flag] == false)
    }

    @Test
    func publishCurrentOnlySkipsInitialFetch() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.activeValues[flag.key] = .init(bool: true)
        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            Issue.record("fetchAndActivate should not be called for publishCurrentOnly")
        }

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag],
                startupPolicy: .publishCurrentOnly
            )
        )

        var receivedValues: [Bool] = []
        let cancellable = flags.publisher(flag)
            .sink { receivedValues.append($0) }

        defer { cancellable.cancel() }

        await flags.start()

        #expect(receivedValues == [false, true])
        #expect(flags[flag] == true)
        #expect(flags.bootstrapState == .bootstrapped)
    }

    @Test
    func fetchOnlySkipsPublishingCurrentValuesBeforeFetch() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.activeValues[flag.key] = .init(bool: true)
        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            adaptor.activeValues[flag.key] = .init(bool: false)
        }

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag],
                startupPolicy: .fetchOnly
            )
        )

        var receivedValues: [Bool] = []
        let cancellable = flags.publisher(flag)
            .sink { receivedValues.append($0) }

        defer { cancellable.cancel() }

        await flags.start()

        #expect(receivedValues == [false])
        #expect(flags[flag] == false)
        #expect(flags.bootstrapState == .bootstrapped)
    }

    @Test
    func activatedRemoteValueWinsOnLaterLaunch() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.activeValues[flag.key] = .init(bool: true)

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        await flags.start()

        #expect(flags.value(flag) == true)
        #expect(flag.publisher.value == true)
    }

    @Test
    func startupFetchRepublishesOnlyChangedFlags() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            adaptor.activeValues[flag.key] = .init(bool: true)
        }

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        var receivedValues: [Bool] = []
        let cancellable = flags.publisher(flag)
            .sink { receivedValues.append($0) }

        defer { cancellable.cancel() }

        await flags.start()

        #expect(receivedValues == [false, true])
    }

    @Test
    func malformedRemoteValuesDoNotOverwriteLastValidValue() async {
        let flag = makeExperimentFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.activeValues[flag.key] = .init(
            string: TestExperimentVariant.variantB.rawValue
        )

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        await flags.start()
        #expect(flags.value(flag) == .variantB)

        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            adaptor.activeValues[flag.key] = .init(
                string: "unexpected_variant"
            )
        }

        await flags.refresh()

        #expect(flags.value(flag) == .variantB)
        #expect(flag.publisher.value == .variantB)
    }

    @Test
    func lateSubscribersReceiveCurrentValueImmediately() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.activeValues[flag.key] = .init(bool: true)

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        await flags.start()

        var receivedValues: [Bool] = []
        let cancellable = flags.publisher(flag)
            .sink { receivedValues.append($0) }

        defer { cancellable.cancel() }

        #expect(receivedValues == [true])
    }

    @Test
    func flagsSupportSubscriptAndValueAccess() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.activeValues[flag.key] = .init(bool: true)

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        await flags.start()

        #expect(flags[flag] == true)
        #expect(flags.value(flag) == true)
    }

    @Test
    func instanceFlagsPublishUpdatedValuesAfterRefresh() async {
        let flag = makeExperimentFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            adaptor.activeValues[flag.key] = .init(
                string: TestExperimentVariant.variantB.rawValue
            )
        }

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        var receivedValues: [TestExperimentVariant] = []
        let cancellable = flags.publisher(flag)
            .sink { receivedValues.append($0) }

        defer { cancellable.cancel() }

        await flags.start()

        #expect(receivedValues == [.control, .variantB])
        #expect(flags[flag] == .variantB)
    }

    @Test
    func objectWillChangeEmitsWhenInstanceFlagsChange() async {
        let flag = makeBoolFlag()
        let adaptor = FakeFlagsAdaptor()
        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            adaptor.activeValues[flag.key] = .init(bool: true)
        }

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        var objectWillChangeCount = 0
        let cancellable = flags.objectWillChange
            .sink { objectWillChangeCount += 1 }

        defer { cancellable.cancel() }

        await flags.start()

        #expect(objectWillChangeCount > 0)
    }

    @Test
    func codableFlagsDecodeJSONValues() async throws {
        let flag = makeJSONFlag()
        let adaptor = FakeFlagsAdaptor()
        let expectedValue = TestJSONPayload(title: "Remote", isEnabled: true)

        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            adaptor.activeValues[flag.key] = .init(data: try! JSONEncoder().encode(expectedValue))
        }

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        var receivedValues: [TestJSONPayload] = []
        let cancellable = flags.publisher(flag)
            .sink { receivedValues.append($0) }

        defer { cancellable.cancel() }

        await flags.start()

        #expect(receivedValues == [flag.defaultValue, expectedValue])
        #expect(flags[flag] == expectedValue)
    }

    @Test
    func malformedJSONDoesNotOverwriteLastValidValue() async throws {
        let flag = makeJSONFlag()
        let adaptor = FakeFlagsAdaptor()
        let initialValue = TestJSONPayload(title: "Remote", isEnabled: true)

        adaptor.activeValues[flag.key] = .init(data: try JSONEncoder().encode(initialValue))

        let flags = TAFlags(
            config: .init(
                adaptor: adaptor,
                registeredFlags: [flag]
            )
        )

        await flags.start()
        #expect(flags[flag] == initialValue)

        adaptor.fetchChangedKeys = [flag.key]
        adaptor.fetchHook = {
            adaptor.activeValues[flag.key] = .init(string: "{bad json")
        }

        await flags.refresh()

        #expect(flags[flag] == initialValue)
        #expect(flag.publisher.value == initialValue)
    }

    private func makeBoolFlag() -> TAFlag<Bool> {
        TAFlag("feature_bool", default: false)
    }

    private func makeExperimentFlag() -> TAFlag<TestExperimentVariant> {
        TAFlag("experiment_variant", default: .control)
    }

    private func makeJSONFlag() -> TAFlag<TestJSONPayload> {
        TAFlag.codable(
            "json_payload",
            default: TestJSONPayload(title: "Default", isEnabled: false)
        )
    }
}
