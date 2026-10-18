import Foundation
import Testing
@testable import SwitchProfileCore

/// #14: Settings warns about a rule that can never match because a broader rule above always wins.
@Suite struct RuleAnalysisTests {
    static let r5 = RuleID(number: 5)
    static let r6 = RuleID(number: 6)

    static func config(_ rules: [RoutingRule]) -> AppConfig {
        var config = AppConfig.unseededDefault
        config.rules = rules
        config.nextRuleNumber = 7
        return config
    }

    static func host(_ id: RuleID, _ host: String) -> RoutingRule {
        RoutingRule(id: id, match: .host(host))
    }

    static func prefix(_ id: RuleID, _ host: String, _ path: String) -> RoutingRule {
        RoutingRule(id: id, match: .hostPathPrefix(host: host, pathPrefix: path))
    }

    @Test func defaultConfigHasNoIssues() {
        #expect(RuleAnalysis.issues(.unseededDefault).isEmpty)
    }

    @Test func repositoryRuleBelowItsHostIsShadowed() {
        var config = AppConfig.unseededDefault
        config.rules.swapAt(1, 2)   // R1, R3 (github.com), R2 (github.com/TruckerPoints/trucker-points)
        #expect(RuleAnalysis.issues(config) == [.r2: .shadowed(by: .r3)])
    }

    @Test func longerPrefixBelowShorterPrefixIsShadowed() {
        let config = Self.config([Self.prefix(Self.r5, "github.com", "/acme"), Self.prefix(Self.r6, "github.com", "/ACME/app")])
        #expect(RuleAnalysis.issues(config) == [Self.r6: .shadowed(by: Self.r5)])
    }

    @Test func gitSuffixSegmentIsShadowedByItsRepository() {
        let config = Self.config([Self.prefix(Self.r5, "github.com", "/acme/app"),
                                  Self.prefix(Self.r6, "github.com", "/acme/app.git/info")])
        #expect(RuleAnalysis.issues(config) == [Self.r6: .shadowed(by: Self.r5)])
    }

    @Test func segmentBoundaryNeverWarns() {
        let config = Self.config([Self.prefix(Self.r5, "github.com", "/a"), Self.prefix(Self.r6, "github.com", "/ab")])
        #expect(RuleAnalysis.issues(config).isEmpty)
    }

    @Test func narrowerAboveBroaderNeverWarns() {
        let config = Self.config([Self.prefix(Self.r5, "github.com", "/acme/app"), Self.prefix(Self.r6, "github.com", "/acme")])
        #expect(RuleAnalysis.issues(config).isEmpty)
    }

    @Test func prefixNeverShadowsAnExactHost() {
        let config = Self.config([Self.prefix(Self.r5, "github.com", "/acme"), Self.host(Self.r6, "github.com")])
        #expect(RuleAnalysis.issues(config).isEmpty)
    }

    @Test func differentHostNeverWarns() {
        let config = Self.config([Self.host(Self.r5, "github.com"), Self.prefix(Self.r6, "www.github.com", "/acme"),
                                  Self.host(.r1, "gist.github.com")])
        #expect(RuleAnalysis.issues(config).isEmpty)
    }

    @Test func storedDuplicateIsFlaggedOnTheLaterRowOnly() {
        let config = Self.config([Self.host(.r1, "git.fis.vn"), Self.host(Self.r5, "example.org"), Self.host(Self.r6, "git.fis.vn")])
        #expect(RuleAnalysis.issues(config) == [Self.r6: .duplicate(of: .r1)])
    }

    @Test func fallbackIsNeverFlagged() {
        let config = Self.config([Self.host(Self.r5, "example.org")])
        #expect(RuleAnalysis.issues(config)[.fallback] == nil)
        #expect(RuleAnalysis.issues(Self.config([])).isEmpty)
    }
}
