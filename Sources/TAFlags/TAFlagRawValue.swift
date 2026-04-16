//
//  TAFlagRawValue.swift
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

/// The raw value returned by a backend provider for a flag key.
///
/// ``TAFlagsAdaptor`` implementations return this type from `rawValue(forKey:)` before any
/// flag-specific decoding happens. Each ``TAFlag`` then decodes this provider value into its own
/// strongly typed published value, such as `Bool`, `String`, an enum, or a `Codable` model.
public struct TAFlagRawValue: Equatable, Sendable {
    /// The provider value represented as a string.
    public let stringValue: String

    /// The provider value represented as binary data.
    public let dataValue: Data

    /// The provider value represented as a number when available.
    public let numberValue: NSNumber

    /// The provider value represented as a Boolean using the package's normalization rules.
    public let boolValue: Bool

    /// Creates a raw value from fully specified primitive representations.
    public init(
        stringValue: String,
        dataValue: Data,
        numberValue: NSNumber,
        boolValue: Bool
    ) {
        self.stringValue = stringValue
        self.dataValue = dataValue
        self.numberValue = numberValue
        self.boolValue = boolValue
    }

    /// Creates a raw value from a string.
    ///
    /// Boolean normalization treats `"1"`, `"true"`, `"yes"`, `"y"`, and `"on"` as `true`.
    public init(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            stringValue: string,
            dataValue: Data(string.utf8),
            numberValue: NSNumber(value: Double(trimmed) ?? 0),
            boolValue: Self.makeBoolValue(from: trimmed)
        )
    }

    /// Creates a raw value from a Boolean.
    public init(bool: Bool) {
        self.init(
            stringValue: bool ? "true" : "false",
            dataValue: Data((bool ? "true" : "false").utf8),
            numberValue: NSNumber(value: bool),
            boolValue: bool
        )
    }

    /// Creates a raw value from an integer.
    public init(int: Int) {
        self.init(
            stringValue: String(int),
            dataValue: Data(String(int).utf8),
            numberValue: NSNumber(value: int),
            boolValue: int != 0
        )
    }

    /// Creates a raw value from a double.
    public init(double: Double) {
        self.init(
            stringValue: String(double),
            dataValue: Data(String(double).utf8),
            numberValue: NSNumber(value: double),
            boolValue: double != 0
        )
    }

    /// Creates a raw value from binary data.
    ///
    /// When the data is valid UTF-8, ``stringValue`` contains that text; otherwise it contains
    /// the Base64-encoded form.
    public init(data: Data) {
        let stringValue = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        self.init(
            stringValue: stringValue,
            dataValue: data,
            numberValue: NSNumber(value: 0),
            boolValue: Self.makeBoolValue(from: stringValue)
        )
    }

    init(defaultObject object: NSObject) {
        switch object {
        case let number as NSNumber:
            let stringValue = number.stringValue
            self.init(
                stringValue: stringValue,
                dataValue: Data(stringValue.utf8),
                numberValue: number,
                boolValue: number.boolValue
            )
        case let string as NSString:
            self.init(string: string as String)
        case let data as NSData:
            self.init(data: data as Data)
        default:
            self.init(string: object.description)
        }
    }

    private static func makeBoolValue(from string: String) -> Bool {
        switch string.lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }
}
