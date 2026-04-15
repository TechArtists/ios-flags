//
//  TAFlagsAdaptor.swift
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

/// The backend interface used by ``TAFlags`` to register defaults, read current values,
/// fetch fresh values, and observe runtime updates.
public protocol TAFlagsAdaptor: AnyObject, Sendable {
    /// A publisher that emits the set of keys whose active values changed outside an explicit
    /// ``fetchAndActivate()`` call, such as push-style provider updates.
    var updatesPublisher: AnyPublisher<Set<String>, Never> { get }

    /// Performs one-time startup work for the backend client.
    ///
    /// ``TAFlags`` calls this during ``TAFlags/start()`` after registering defaults and before
    /// reading the provider's currently active values.
    func start() async throws

    /// Registers the local default values for all known flags with the backend.
    ///
    /// Providers should make these defaults available immediately when no remote value has been
    /// activated yet.
    func register(defaults: [String: NSObject])

    /// Returns the provider's current raw value for a key.
    ///
    /// The returned value should reflect the provider's active state at the time of the call,
    /// including defaults when no remote override exists.
    func rawValue(forKey key: String) -> TAFlagRawValue

    /// Fetches and activates fresh remote values, then returns the subset of registered keys
    /// whose active values changed as a result of that activation.
    func fetchAndActivate() async throws -> Set<String>
}
