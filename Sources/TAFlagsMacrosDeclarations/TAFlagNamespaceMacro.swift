//
//  TAFlagNamespaceMacro.swift
//  TAFlagsMacrosDeclarations
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

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TAFlagNamespaceMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let extensionDecl = declaration.as(ExtensionDeclSyntax.self) else {
            throw TAFlagNamespaceMacroError.notAttachedToExtension
        }

        guard normalizedTypeName(for: extensionDecl.extendedType) == "TAFlags.Keys" else {
            throw TAFlagNamespaceMacroError.notAttachedToTAFlagsKeys
        }

        guard !containsAllFlagsDeclaration(in: extensionDecl) else {
            throw TAFlagNamespaceMacroError.allFlagsAlreadyDeclared
        }

        let flagNames = declaredFlagNames(in: extensionDecl.memberBlock.members)
        return [DeclSyntax(stringLiteral: allFlagsDeclaration(for: flagNames))]
    }
}

private extension TAFlagNamespaceMacro {
    static func normalizedTypeName(for type: TypeSyntax) -> String {
        type.description.filter { !$0.isWhitespace }
    }

    static func containsAllFlagsDeclaration(in extensionDecl: ExtensionDeclSyntax) -> Bool {
        extensionDecl.memberBlock.members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                return false
            }

            return variable.bindings.contains { binding in
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
                    return false
                }

                return identifier.text == "allFlags"
            }
        }
    }

    static func declaredFlagNames(
        in members: MemberBlockItemListSyntax
    ) -> [String] {
        members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                return nil
            }

            guard variable.bindingSpecifier.tokenKind == .keyword(.let) else {
                return nil
            }

            guard variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else {
                return nil
            }

            guard variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  binding.accessorBlock == nil,
                  looksLikeFlagDeclaration(binding),
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            else {
                return nil
            }

            return identifier
        }
    }

    static func looksLikeFlagDeclaration(_ binding: PatternBindingSyntax) -> Bool {
        if let typeAnnotation = binding.typeAnnotation {
            return normalizedExpression(typeAnnotation.type.description).contains("TAFlag<")
        }

        guard let initializer = binding.initializer else {
            return false
        }

        return looksLikeFlagFactoryCall(initializer.value)
    }

    static func looksLikeFlagFactoryCall(_ expression: ExprSyntax) -> Bool {
        let normalized = normalizedExpression(expression.description)

        guard normalized.contains("TAFlag") else {
            return false
        }

        if normalized.contains("TAFlag(") || normalized.contains("TAFlag<") {
            return true
        }

        return normalized.contains(".codable(")
    }

    static func normalizedExpression(_ expression: String) -> String {
        expression.filter { !$0.isWhitespace }
    }

    static func allFlagsDeclaration(for flagNames: [String]) -> String {
        guard !flagNames.isEmpty else {
            return [
                "static var allFlags: [any TAFlagRegistrable] {",
                "    []",
                "}"
            ].joined(separator: "\n")
        }

        let lines = flagNames
            .map { "        Self.\($0)" }
            .joined(separator: ",\n")

        return [
            "static var allFlags: [any TAFlagRegistrable] {",
            "    [",
            lines,
            "    ]",
            "}"
        ].joined(separator: "\n")
    }
}

enum TAFlagNamespaceMacroError: Error {
    case notAttachedToExtension
    case notAttachedToTAFlagsKeys
    case allFlagsAlreadyDeclared
}

extension TAFlagNamespaceMacroError: CustomStringConvertible {
    var description: String {
        switch self {
        case .notAttachedToExtension:
            "@TAFlagNamespace must be attached to an extension."
        case .notAttachedToTAFlagsKeys:
            "@TAFlagNamespace must be attached to extension TAFlags.Keys."
        case .allFlagsAlreadyDeclared:
            "@TAFlagNamespace cannot be used when allFlags is already declared."
        }
    }
}
