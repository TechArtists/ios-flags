//
//  TAFlagNamespace.swift
//  TAFlagsMacros
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

/// Generates `TAFlags.Keys.allFlags` for the attached `extension TAFlags.Keys`.
///
/// The macro collects stored `static let` declarations that look like `TAFlag`
/// definitions and synthesizes an `allFlags` registry in declaration order.
///
/// ```swift
/// import TAFlags
/// import TAFlagsMacros
///
/// @TAFlagNamespace
/// extension TAFlags.Keys {
///     static let newPaywall = TAFlag("new_paywall", default: false)
/// }
///
/// let config = TAFlagsConfig(
///     adaptor: adaptor,
///     registeredFlags: TAFlags.Keys.allFlags
/// )
/// ```
@attached(member, names: named(allFlags))
public macro TAFlagNamespace() = #externalMacro(
    module: "TAFlagsMacrosDeclarations",
    type: "TAFlagNamespaceMacro"
)
