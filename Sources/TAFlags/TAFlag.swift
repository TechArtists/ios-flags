//
//  TAFlag.swift
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

/// Errors thrown while decoding a raw provider value into a typed published flag value.
public enum TAFlagDecodingError: LocalizedError, Equatable {
    /// The raw string could not be converted into the expected ``RawRepresentable`` case.
    case invalidRawRepresentable(key: String, rawValue: String)

    /// The raw string could not be converted into an integer.
    case invalidInteger(key: String, rawValue: String)

    /// The raw string could not be converted into a floating-point value.
    case invalidDouble(key: String, rawValue: String)

    /// The raw value could not be decoded from JSON into the expected type.
    case invalidJSON(key: String, errorDescription: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRawRepresentable(key, rawValue):
            "Could not decode string value '\(rawValue)' for flag '\(key)'."
        case let .invalidInteger(key, rawValue):
            "Could not decode integer value '\(rawValue)' for flag '\(key)'."
        case let .invalidDouble(key, rawValue):
            "Could not decode double value '\(rawValue)' for flag '\(key)'."
        case let .invalidJSON(key, errorDescription):
            "Could not decode JSON value for flag '\(key)': \(errorDescription)"
        }
    }
}

/// A value that can be registered with ``TAFlagsConfig`` using the instance-based API.
public protocol TAFlagRegistrable {
    /// A type-erased representation of the flag used by ``TAFlags`` at runtime.
    var erasedDefinition: AnyTAFlagDefinition { get }
}

extension TAFlags {
    /// A namespace for app-defined instance-based flags.
    ///
    /// Extend this type in your app to group static flag declarations:
    ///
    /// ```swift
    /// extension TAFlags.Keys {
    ///     static let newPaywall = TAFlag<Bool>("new_paywall", default: false)
    /// }
    /// ```
    public class Keys {}
}

/// A strongly typed feature-flag declaration backed by a ``CurrentValueSubject``.
public final class TAFlag<Value: Equatable>: TAFlagRegistrable, @unchecked Sendable {
    /// The backend key used to read and update this flag.
    public let key: String

    /// The local fallback value used before a remote value becomes available.
    public let defaultValue: Value

    /// The live source of truth for the current typed published value of this flag.
    ///
    /// Subscribers receive the current typed value immediately, then all future changes.
    public let publisher: CurrentValueSubject<Value, Never>

    /// Converts a raw provider value into the typed value published by this flag.
    private let decodeClosure: (TAFlagRawValue) throws -> Value

    /// Converts the typed default value into the backend object format used during registration.
    private let encodeClosure: (Value) -> NSObject

    public var erasedDefinition: AnyTAFlagDefinition {
        AnyTAFlagDefinition(self)
    }

    /// Creates a flag with custom decoding and default-value encoding logic.
    ///
    /// - Parameters:
    ///   - key: The remote-config key.
    ///   - defaultValue: The value exposed until a remote override is activated.
    ///   - decode: Converts the raw provider value into the typed published value.
    ///   - encodeDefaultValue: Converts the typed default value into the backend's object format.
    public init(
        _ key: String,
        default defaultValue: Value,
        decode: @escaping (TAFlagRawValue) throws -> Value,
        encodeDefaultValue: @escaping (Value) -> NSObject
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.publisher = CurrentValueSubject(defaultValue)
        self.decodeClosure = decode
        self.encodeClosure = encodeDefaultValue
    }

    /// Publishes the local default value again if the current value differs from it.
    public func resetToDefault() {
        _ = publish(defaultValue)
    }

    @discardableResult
    func publish(_ value: Value) -> Bool {
        guard publisher.value != value else { return false }

        publisher.send(value)
        return true
    }

    var defaultRemoteValue: NSObject {
        encodeClosure(defaultValue)
    }

    /// Decodes a raw provider value into the typed value that will be published for this flag.
    func decodeValue(from rawValue: TAFlagRawValue) throws -> Value {
        try decodeClosure(rawValue)
    }
}

public extension TAFlag where Value == Bool {
    /// Creates a Boolean flag.
    convenience init(_ key: String, default defaultValue: Bool) {
        self.init(
            key,
            default: defaultValue,
            decode: { $0.boolValue },
            encodeDefaultValue: { NSNumber(value: $0) }
        )
    }
}

public extension TAFlag where Value == String {
    /// Creates a string flag.
    convenience init(_ key: String, default defaultValue: String) {
        self.init(
            key,
            default: defaultValue,
            decode: { $0.stringValue },
            encodeDefaultValue: { NSString(string: $0) }
        )
    }
}

public extension TAFlag where Value == Int {
    /// Creates an integer flag decoded from the provider's string value.
    convenience init(_ key: String, default defaultValue: Int) {
        self.init(
            key,
            default: defaultValue,
            decode: { rawValue in
                let trimmed = rawValue.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Int(trimmed) else {
                    throw TAFlagDecodingError.invalidInteger(key: key, rawValue: rawValue.stringValue)
                }

                return value
            },
            encodeDefaultValue: { NSNumber(value: $0) }
        )
    }
}

public extension TAFlag where Value == Double {
    /// Creates a double flag decoded from the provider's string value.
    convenience init(_ key: String, default defaultValue: Double) {
        self.init(
            key,
            default: defaultValue,
            decode: { rawValue in
                let trimmed = rawValue.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Double(trimmed) else {
                    throw TAFlagDecodingError.invalidDouble(key: key, rawValue: rawValue.stringValue)
                }

                return value
            },
            encodeDefaultValue: { NSNumber(value: $0) }
        )
    }
}

public extension TAFlag where Value == Float {
    /// Creates a float flag decoded from the provider's string value.
    convenience init(_ key: String, default defaultValue: Float) {
        self.init(
            key,
            default: defaultValue,
            decode: { rawValue in
                let trimmed = rawValue.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Float(trimmed) else {
                    throw TAFlagDecodingError.invalidDouble(key: key, rawValue: rawValue.stringValue)
                }

                return value
            },
            encodeDefaultValue: { NSNumber(value: $0) }
        )
    }
}

public extension TAFlag where Value == Data {
    /// Creates a binary-data flag.
    convenience init(_ key: String, default defaultValue: Data) {
        self.init(
            key,
            default: defaultValue,
            decode: { $0.dataValue },
            encodeDefaultValue: { $0 as NSData }
        )
    }
}

public extension TAFlag where Value: RawRepresentable, Value.RawValue == String {
    /// Creates a flag backed by a string-valued ``RawRepresentable`` type, such as an enum.
    convenience init(_ key: String, default defaultValue: Value) {
        self.init(
            key,
            default: defaultValue,
            decode: { rawValue in
                guard let value = Value(rawValue: rawValue.stringValue) else {
                    throw TAFlagDecodingError.invalidRawRepresentable(
                        key: key,
                        rawValue: rawValue.stringValue
                    )
                }

                return value
            },
            encodeDefaultValue: { NSString(string: $0.rawValue) }
        )
    }
}

public extension TAFlag where Value: Codable {
    /// Creates a flag backed by JSON-encoded ``Codable`` values.
    static func codable(
        _ key: String,
        default defaultValue: Value,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) -> TAFlag<Value> {
        TAFlag<Value>(
            key,
            default: defaultValue,
            decode: { rawValue in
                do {
                    return try decoder.decode(Value.self, from: rawValue.dataValue)
                } catch {
                    throw TAFlagDecodingError.invalidJSON(
                        key: key,
                        errorDescription: error.localizedDescription
                    )
                }
            },
            encodeDefaultValue: { value in
                do {
                    return try encoder.encode(value) as NSData
                } catch {
                    preconditionFailure(
                        "Could not encode default JSON value for flag '\(key)': \(error)"
                    )
                }
            }
        )
    }
}
