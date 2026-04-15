import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(TAFlagsMacrosDeclarations)
@testable import TAFlagsMacros
@testable import TAFlagsMacrosDeclarations
#endif

final class TAFlagNamespaceMacroTests: XCTestCase {
    func testExpansionBuildsAllFlagsRegistry() throws {
        #if canImport(TAFlagsMacrosDeclarations)
        let testMacros: [String: Macro.Type] = [
            "TAFlagNamespace": TAFlagNamespaceMacro.self
        ]

        assertMacroExpansion(
            """
            enum TestVariant: String, Equatable {
                case control
            }

            @TAFlagNamespace
            extension TAFlags.Keys {
                static let newPaywallEnabled = TAFlag("new_paywall_enabled", default: false)
                static let helper = "ignore me"
                static let onboardingVariant = TAFlag<TestVariant>("onboarding_variant", default: .control)
            }
            """,
            expandedSource:
            """
            enum TestVariant: String, Equatable {
                case control
            }
            extension TAFlags.Keys {
                static let newPaywallEnabled = TAFlag("new_paywall_enabled", default: false)
                static let helper = "ignore me"
                static let onboardingVariant = TAFlag<TestVariant>("onboarding_variant", default: .control)

                static var allFlags: [any TAFlagRegistrable] {
                    [
                        Self.newPaywallEnabled,
                        Self.onboardingVariant
                    ]
                }
            }
            """,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }
}
