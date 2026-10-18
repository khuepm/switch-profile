import Foundation
import Testing
@testable import SwitchProfileCore

/// #14: user rules match an exact host, or an exact host plus a path prefix on whole segments.
@Suite struct RuleMatchTests {
    static let r5 = RuleID(number: 5)
    static let r6 = RuleID(number: 6)

    static func rule(_ id: RuleID, _ match: RuleMatch, binding: ProfileBinding? = nil) -> RoutingRule {
        RoutingRule(id: id, match: match, binding: binding)
    }

    static func classify(_ string: String, _ rules: [RoutingRule]) -> RuleID? {
        if case .matched(let rule, _) = URLClassifier.classify(URL(string: string)!, rules: rules) { return rule }
        return nil
    }

    // MARK: Exact host

    static let exampleHost = [rule(r5, .host("example.org"))]

    @Test(arguments: [
        "https://example.org", "https://example.org/", "https://EXAMPLE.org/a/b", "https://example.org./x",
        "https://example.org:8443/x", "https://user:pw@example.org/x", "http://example.org/?q=1#f",
    ])
    func exactHostMatches(_ string: String) {
        #expect(Self.classify(string, Self.exampleHost) == Self.r5)
    }

    @Test(arguments: [
        "https://www.example.org/", "https://sub.example.org/", "https://example.org.evil.test/", "https://notexample.org/",
        "https://example.com/?u=https://example.org/",
    ])
    func noSubdomainOrLookalikeMatch(_ string: String) {
        #expect(Self.classify(string, Self.exampleHost) == .fallback)
    }

    @Test(arguments: ["https://www.github.com/x", "https://gist.github.com/x", "https://sub.git.fis.vn/"])
    func defaultHostsHaveNoSubdomainMatch(_ string: String) {
        let rules = [Self.rule(Self.r5, .host("github.com")), Self.rule(Self.r6, .host("git.fis.vn"))]
        #expect(Self.classify(string, rules) == .fallback)
    }

    // MARK: Path prefix

    static let acmeApp = [rule(r5, .hostPathPrefix(host: "github.com", pathPrefix: "/acme/app"))]

    @Test(arguments: [
        "https://github.com/acme/app", "https://github.com/acme/app/", "https://github.com/ACME/App/pull/1",
        "https://github.com/acme/app.git", "https://github.com/acme/app.GIT/x", "https://github.com/%61cme/app",
        "https://github.com/acme/app?tab=1#readme",
    ])
    func prefixMatchesOnSegmentBoundaries(_ string: String) {
        #expect(Self.classify(string, Self.acmeApp) == Self.r5)
    }

    @Test(arguments: [
        "https://github.com/acme/app-other", "https://github.com/acme/appx", "https://github.com/acme",
        "https://github.com/acme/", "https://github.com//acme/app", "https://github.com/acme//app",
        "https://github.com/acme/app%2Fx", "https://github.com/x/../acme/app", "https://github.com/?p=/acme/app",
        "https://github.com/#/acme/app", "https://example.com/acme/app",
    ])
    func prefixDoesNotMatchAcrossBoundaries(_ string: String) {
        #expect(Self.classify(string, Self.acmeApp) == .fallback)
    }

    @Test func singleAndThreeSegmentPrefixes() {
        let owner = [Self.rule(Self.r5, .hostPathPrefix(host: "github.com", pathPrefix: "/acme"))]
        #expect(Self.classify("https://github.com/acme", owner) == Self.r5)
        #expect(Self.classify("https://github.com/acme/anything/else", owner) == Self.r5)
        #expect(Self.classify("https://github.com/acme.git", owner) == Self.r5)
        #expect(Self.classify("https://github.com/acmex", owner) == .fallback)

        let tree = [Self.rule(Self.r5, .hostPathPrefix(host: "github.com", pathPrefix: "/acme/app/tree"))]
        #expect(Self.classify("https://github.com/acme/app/tree/main", tree) == Self.r5)
        #expect(Self.classify("https://github.com/acme/app/blob/main", tree) == .fallback)
        #expect(Self.classify("https://github.com/acme/app", tree) == .fallback)
    }

    @Test func prefixWithTrailingSlashBehavesTheSame() throws {
        let validation = RuleValidator.validate(RuleDraft(matchType: .hostPathPrefix, host: "github.com", pathPrefix: "/acme/app/"),
                                                existing: [], editing: nil)
        let match = try #require(validation.match)
        #expect(match == .hostPathPrefix(host: "github.com", pathPrefix: "/acme/app"))
        let rules = [Self.rule(Self.r5, match)]
        #expect(Self.classify("https://github.com/acme/app", rules) == Self.r5)
        #expect(Self.classify("https://github.com/acme/app-x", rules) == .fallback)
    }

    // MARK: Order

    @Test func firstMatchWinsInListOrder() {
        let narrow = Self.rule(Self.r5, .hostPathPrefix(host: "github.com", pathPrefix: "/acme/app"))
        let broad = Self.rule(Self.r6, .host("github.com"))
        let url = "https://github.com/acme/app/pull/1"
        #expect(Self.classify(url, [narrow, broad]) == Self.r5)
        #expect(Self.classify(url, [broad, narrow]) == Self.r6)
        #expect(Self.classify("https://github.com/other", [narrow, broad]) == Self.r6)
    }

    @Test func emptyRuleListIsAlwaysFallback() {
        #expect(Self.classify("https://github.com/TruckerPoints/trucker-points", []) == .fallback)
        #expect(Self.classify("https://git.fis.vn/x", []) == .fallback)
    }

    @Test func explanationIsTheMatchSummary() {
        let rules = [Self.rule(Self.r5, .hostPathPrefix(host: "github.com", pathPrefix: "/Acme/App"))]
        #expect(URLClassifier.classify(URL(string: "https://github.com/acme/app")!, rules: rules)
            == .matched(Self.r5, explanation: "host github.com, path /Acme/App"))
    }

    // MARK: Routing and launch

    @Test func userRuleLaunchesWithItsProfileAndTheUnchangedURL() throws {
        let profile8 = try #require(Fixture.validCatalog().profile(directory: "Profile 8"))
        var config = AppConfig.unseededDefault
        config.seedPending = false
        config.rules.insert(Self.rule(Self.r5, .host("example.org"), binding: ProfileBinding(profile: profile8, matchedBy: nil)),
                            at: 0)
        let url = URL(string: "https://Example.org:443/a%20b/c?x=1&y=%2F#frag")!
        let decision = Router.decide(url, config: .loaded(config), catalog: .loaded(Fixture.validCatalog()))
        guard case .launch(let target, let explanation) = decision else {
            Issue.record("expected .launch, got \(decision)")
            return
        }
        #expect(target.rule == Self.r5)
        #expect(target.directory == "Profile 8")
        #expect(explanation == "R5: host example.org, profile Profile 8")
        let launcher = ChromeLauncher(locator: FakeLocator(), opener: FakeOpener(), ownBundleIdentifier: "io.github.khuepm.switchprofile")
        let request = try launcher.makeRequest(for: target)
        #expect(request.arguments == ["--profile-directory=Profile 8", url.absoluteString])
        #expect(request.arguments.last == "https://Example.org:443/a%20b/c?x=1&y=%2F#frag")
    }

    @Test func unboundUserRuleNeedsAProfile() {
        var config = AppConfig.unseededDefault
        config.seedPending = false
        config.rules.append(Self.rule(Self.r5, .host("example.org")))
        let decision = Router.decide(URL(string: "https://example.org/")!, config: .loaded(config),
                                     catalog: .loaded(Fixture.validCatalog()))
        guard case .needsProfile(_, Self.r5, .unset, _) = decision else {
            Issue.record("expected needsProfile(.unset) for R5, got \(decision)")
            return
        }
    }
}
