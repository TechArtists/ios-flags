//
//  AnyTAFlagDefinition.swift
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

/// A type-erased flag declaration used internally by ``TAFlags`` and exposed for advanced
/// configuration scenarios.
///
/// This wrapper keeps the flag's key and encoded default value, plus a type-erased operation that
/// can turn a raw provider value into the flag's typed published value.
public struct AnyTAFlagDefinition {
    /// The provider key associated with the flag.
    public let key: String

    /// The flag's default value encoded into the object format expected by the adaptor.
    public let defaultRemoteValue: NSObject

    /// Decodes a raw provider value and publishes the resulting typed value into the underlying
    /// flag if it changed.
    private let publishFromRawValueClosure: (TAFlagRawValue) throws -> Bool

    /// Erases an instance-based flag declaration.
    public init<Value>(_ flag: TAFlag<Value>) where Value: Equatable {
        self.key = flag.key
        self.defaultRemoteValue = flag.defaultRemoteValue
        self.publishFromRawValueClosure = { rawValue in
            let decodedValue = try flag.decodeValue(from: rawValue)
            return flag.publish(decodedValue)
        }
    }

    
    /// Applies a raw provider value to this erased flag by decoding it and publishing the typed
    /// value if needed.
    @discardableResult
    func publishValue(from rawValue: TAFlagRawValue) throws -> Bool {
        try publishFromRawValueClosure(rawValue)
    }
}
