import Foundation
import Testing
@testable import SwitchProfileCore

/// #14: add, edit, delete and reorder rules; the fallback always stays last and cannot be changed.
@Suite struct RuleEditorTests {
    static let r5 = RuleID(number: 5)
    static let r6 = RuleID(number: 6)
    static let bound = ProfileBinding(directory: "Profile 8", email: "bob@example.com", displayName: "Profile 8", matchedBy: nil)

    static func hostDraft(_ host: String, binding: ProfileBinding? = nil) -> RuleDraft {
        RuleDraft(matchType: .host, host: host, binding: binding)
    }

    @Test func addAppendsAboveTheFallbackWithNewIds() throws {
        var config = AppConfig.unseededDefault
        let first = try RuleEditor.add(Self.hostDraft("example.org", binding: Self.bound), to: &config)
        #expect(first == Self.r5)
        #expect(config.nextRuleNumber == 6)
        let second = try RuleEditor.add(RuleDraft(matchType: .hostPathPrefix, host: "github.com", pathPrefix: "/acme"), to: &config)
        #expect(second == Self.r6)
        #expect(config.nextRuleNumber == 7)
        #expect(config.ruleOrder == [.r1, .r2, .r3, Self.r5, Self.r6, .fallback])
        #expect(config.rule(Self.r5) == RoutingRule(id: Self.r5, match: .host("example.org"), identity: nil, binding: Self.bound))
        #expect(config.rule(Self.r6)?.binding == nil)
    }

    @Test func idsAreNeverReusedAfterDelete() throws {
        var config = AppConfig.unseededDefault
        let added = try RuleEditor.add(Self.hostDraft("example.org"), to: &config)
        try RuleEditor.delete(added, from: &config)
        try RuleEditor.delete(.r3, from: &config)
        let next = try RuleEditor.add(Self.hostDraft("example.org"), to: &config)
        #expect(next == Self.r6)
        #expect(config.ruleOrder == [.r1, .r2, Self.r6, .fallback])
    }

    @Test func invalidAddThrowsAndChangesNothing() {
        var config = AppConfig.unseededDefault
        #expect(throws: RuleEditError.invalid([.wildcardHost])) {
            try RuleEditor.add(Self.hostDraft("*.example.org"), to: &config)
        }
        #expect(throws: RuleEditError.invalid([.duplicate(of: .r3)])) {
            try RuleEditor.add(Self.hostDraft("GitHub.com"), to: &config)
        }
        #expect(config == AppConfig.unseededDefault)
    }

    @Test func updateChangesTheMatchAndKeepsIdIdentityAndBinding() throws {
        var config = AppConfig.unseededDefault
        config.setBinding(Self.bound, for: .r2)
        try RuleEditor.update(.r2, draft: RuleDraft(matchType: .hostPathPrefix, host: "github.com", pathPrefix: "/other/repo"),
                              in: &config)
        let rule = try #require(config.rule(.r2))
        #expect(rule.match == .hostPathPrefix(host: "github.com", pathPrefix: "/other/repo"))
        #expect(rule.identity == "khue@truckerpoints.ai")
        #expect(rule.binding == Self.bound)
        #expect(config.ruleOrder == [.r1, .r2, .r3, .fallback])
        #expect(config.nextRuleNumber == 5)

        // Changing the match type works too.
        try RuleEditor.update(.r2, draft: Self.hostDraft("gitlab.com"), in: &config)
        #expect(config.rule(.r2)?.match == .host("gitlab.com"))
    }

    @Test func invalidUpdateThrowsAndChangesNothing() {
        var config = AppConfig.unseededDefault
        #expect(throws: RuleEditError.invalid([.duplicate(of: .r1)])) {
            try RuleEditor.update(.r3, draft: Self.hostDraft("git.fis.vn"), in: &config)
        }
        #expect(throws: RuleEditError.invalid([.emptyPath])) {
            try RuleEditor.update(.r3, draft: RuleDraft(matchType: .hostPathPrefix, host: "github.com"), in: &config)
        }
        #expect(config == AppConfig.unseededDefault)
    }

    @Test func unknownRuleIsNotFound() {
        var config = AppConfig.unseededDefault
        #expect(throws: RuleEditError.ruleNotFound) { try RuleEditor.update(Self.r5, draft: Self.hostDraft("a.example"), in: &config) }
        #expect(throws: RuleEditError.ruleNotFound) { try RuleEditor.delete(Self.r5, from: &config) }
        #expect(throws: RuleEditError.ruleNotFound) { try RuleEditor.move(Self.r5, by: -1, in: &config) }
        #expect(config == AppConfig.unseededDefault)
    }

    @Test func fallbackIsImmutable() {
        var config = AppConfig.unseededDefault
        #expect(throws: RuleEditError.fallbackImmutable) { try RuleEditor.update(.fallback, draft: Self.hostDraft("a.example"), in: &config) }
        #expect(throws: RuleEditError.fallbackImmutable) { try RuleEditor.delete(.fallback, from: &config) }
        #expect(throws: RuleEditError.fallbackImmutable) { try RuleEditor.move(.fallback, by: -1, in: &config) }
        #expect(config == AppConfig.unseededDefault)
    }

    @Test func moveReorders() throws {
        var config = AppConfig.unseededDefault
        try RuleEditor.move(.r3, by: -1, in: &config)
        #expect(config.ruleOrder == [.r1, .r3, .r2, .fallback])
        try RuleEditor.move(.r1, by: 1, in: &config)
        #expect(config.ruleOrder == [.r3, .r1, .r2, .fallback])
        #expect(throws: RuleEditError.cannotMove) { try RuleEditor.move(.r3, by: -1, in: &config) }
        #expect(throws: RuleEditError.cannotMove) { try RuleEditor.move(.r2, by: 1, in: &config) }
        #expect(throws: RuleEditError.cannotMove) { try RuleEditor.move(.r1, by: 2, in: &config) }
        #expect(config.ruleOrder == [.r3, .r1, .r2, .fallback])
    }

    @Test func fallbackStaysLastAfterEveryOperation() throws {
        var config = AppConfig.unseededDefault
        let added = try RuleEditor.add(Self.hostDraft("example.org"), to: &config)
        #expect(config.ruleOrder.last == .fallback)
        try RuleEditor.move(added, by: -1, in: &config)
        #expect(config.ruleOrder.last == .fallback)
        #expect(throws: RuleEditError.cannotMove) { try RuleEditor.move(.r3, by: 1, in: &config) }
        try RuleEditor.delete(.r1, from: &config)
        try RuleEditor.delete(.r2, from: &config)
        try RuleEditor.delete(.r3, from: &config)
        try RuleEditor.delete(added, from: &config)
        #expect(config.ruleOrder == [.fallback])
        #expect(!config.rules.contains { $0.id == .fallback })
    }

    @Test func editedConfigRoundTripsThroughJSON() throws {
        var config = AppConfig.unseededDefault
        try RuleEditor.add(RuleDraft(matchType: .hostPathPrefix, host: "github.com", pathPrefix: "/acme/app", binding: Self.bound),
                           to: &config)
        try RuleEditor.move(Self.r5, by: -1, in: &config)
        try RuleEditor.delete(.r1, from: &config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }
}
