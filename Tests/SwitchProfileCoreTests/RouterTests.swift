import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct RouterTests {
    static let fis = ChromeProfile(directory: "Profile 30", displayName: "khuepm18", email: "khuepm18@example.com")
    static let tp = ChromeProfile(directory: "Profile 47", displayName: "truckerpoints.ai", email: "khue@truckerpoints.ai")
    static let personal = ChromeProfile(directory: "Default", displayName: "Person 1", email: "pmkhue.2013@example.com")
    static let other = ChromeProfile(directory: "Profile 10", displayName: "Other", email: "other@example.com")
    static let signedOut = ChromeProfile(directory: "Profile 9", displayName: "Guest", email: nil)

    static let catalog = CatalogState.loaded(ProfileCatalog(profiles: [fis, tp, personal, other, signedOut]))

    static let fisURL = URL(string: "https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests")!
    static let tpURL = URL(string: "https://github.com/TruckerPoints/trucker-points")!
    static let githubURL = URL(string: "https://github.com/khuepm/LumiBase")!
    static let fallbackURL = URL(string: "https://example.com/page")!

    static func binding(_ profile: ChromeProfile, matchedBy: MatchKind? = nil) -> ProfileBinding {
        ProfileBinding(profile: profile, matchedBy: matchedBy)
    }

    /// R1..R3 bound to the README identities, R4 unset unless given.
    static func config(r1: ProfileBinding? = binding(fis),
                       r2: ProfileBinding? = binding(tp),
                       r3: ProfileBinding? = binding(personal),
                       r4: ProfileBinding? = nil) -> RoutingConfig {
        var config = AppConfig.unseededDefault
        config.seedPending = false
        config.setBinding(r1, for: .r1)
        config.setBinding(r2, for: .r2)
        config.setBinding(r3, for: .r3)
        config.setBinding(r4, for: .r4)
        return .loaded(config)
    }

    private func launchTarget(_ decision: RoutingDecision) -> LaunchTarget? {
        if case .launch(let target, _) = decision { return target }
        return nil
    }

    private func issue(_ decision: RoutingDecision) -> ProfileIssue? {
        if case .needsProfile(_, _, let issue, _) = decision { return issue }
        return nil
    }

    @Test func readmeSamplesRouteToTheirBoundDirectories() {
        let config = Self.config()
        #expect(launchTarget(Router.decide(Self.fisURL, config: config, catalog: Self.catalog))
            == LaunchTarget(url: Self.fisURL, rule: .r1, directory: "Profile 30"))
        #expect(launchTarget(Router.decide(Self.tpURL, config: config, catalog: Self.catalog))
            == LaunchTarget(url: Self.tpURL, rule: .r2, directory: "Profile 47"))
        #expect(launchTarget(Router.decide(Self.githubURL, config: config, catalog: Self.catalog))
            == LaunchTarget(url: Self.githubURL, rule: .r3, directory: "Default"))
    }

    @Test func launchCarriesTheOriginalURLObject() {
        let url = URL(string: "https://user@GitHub.com.:443/TruckerPoints/trucker-points/pull/1?a=1&b=%20#L10-L20")!
        let target = launchTarget(Router.decide(url, config: Self.config(), catalog: Self.catalog))
        #expect(target?.url == url)
        #expect(target?.url.absoluteString == url.absoluteString)
        #expect(target?.rule == .r2)
    }

    @Test func siblingRepositoryGoesToR3() {
        let url = URL(string: "https://github.com/TruckerPoints/trucker-points-other")!
        #expect(launchTarget(Router.decide(url, config: Self.config(), catalog: Self.catalog))
            == LaunchTarget(url: url, rule: .r3, directory: "Default"))
    }

    @Test func r2TakesPrecedenceOverR3() {
        // Distinct bindings: R2 → Profile 47, R3 → Default.
        let decision = Router.decide(Self.tpURL, config: Self.config(), catalog: Self.catalog)
        #expect(launchTarget(decision)?.directory == "Profile 47")
        #expect(launchTarget(decision)?.rule == .r2)
    }

    @Test func unsetFallbackLaunchesInLastActiveChrome() {
        // AC-12 (#13)
        let decision = Router.decide(Self.fallbackURL, config: Self.config(), catalog: Self.catalog)
        #expect(decision == .launch(LaunchTarget(url: Self.fallbackURL, rule: .r4, profile: .lastActiveChrome),
                                    explanation: "R4: last active Chrome profile (host example.com matches no rule; fallback)"))
    }

    @Test(arguments: [LocalStateError.noProfiles, .unreadable("/x/Local State", "denied")])
    func unsetFallbackLaunchesEvenWithCatalogUnavailable(_ error: LocalStateError) {
        let decision = Router.decide(Self.fallbackURL, config: Self.config(), catalog: .unavailable(error))
        #expect(launchTarget(decision) == LaunchTarget(url: Self.fallbackURL, rule: .r4, profile: .lastActiveChrome))
    }

    @Test func brokenFixedFallbackNeverDropsToLastActive() {
        let gone = ProfileBinding(directory: "Profile 99", email: "other@example.com", displayName: "Other", matchedBy: nil)
        let decision = Router.decide(Self.fallbackURL, config: Self.config(r4: gone), catalog: Self.catalog)
        #expect(decision == .needsProfile(url: Self.fallbackURL, rule: .r4, issue: .missing(gone),
                                          explanation: "host example.com matches no rule; fallback"))
    }

    @Test func configUnavailableStillRefusesTheFallback() {
        let decision = Router.decide(Self.fallbackURL, config: .unavailable(.corrupt("x")), catalog: Self.catalog)
        #expect(issue(decision) == .configUnavailable(.corrupt("x")))
        #expect(launchTarget(decision) == nil)
    }

    @Test func ruleMatchedLinksKeepTheirProfilesWithFallbackUnset() {
        let config = Self.config(r4: nil)
        #expect(launchTarget(Router.decide(Self.fisURL, config: config, catalog: Self.catalog))?.profile == .directory("Profile 30"))
        #expect(launchTarget(Router.decide(Self.tpURL, config: config, catalog: Self.catalog))?.profile == .directory("Profile 47"))
        #expect(launchTarget(Router.decide(Self.githubURL, config: config, catalog: Self.catalog))?.profile == .directory("Default"))
    }

    @Test func unsetRuleNeverFallsBack() {
        let decision = Router.decide(Self.githubURL, config: Self.config(r3: nil, r4: Self.binding(Self.other)), catalog: Self.catalog)
        #expect(issue(decision) == .unset)
        #expect(launchTarget(decision) == nil)
    }

    @Test func boundFallbackLaunches() {
        let decision = Router.decide(Self.fallbackURL, config: Self.config(r4: Self.binding(Self.other)), catalog: Self.catalog)
        #expect(launchTarget(decision) == LaunchTarget(url: Self.fallbackURL, rule: .r4, directory: "Profile 10"))
    }

    @Test func missingDirectoryNeverLaunchesEvenWithFallbackBound() {
        // AC-13
        let gone = ProfileBinding(directory: "Profile 99", email: "pmkhue.2013@example.com", displayName: "Person 1", matchedBy: nil)
        let decision = Router.decide(Self.githubURL, config: Self.config(r3: gone, r4: Self.binding(Self.other)), catalog: Self.catalog)
        #expect(decision == .needsProfile(url: Self.githubURL, rule: .r3, issue: .missing(gone), explanation: "host github.com"))
        #expect(launchTarget(decision) == nil)
    }

    @Test func identityMismatchOtherAccount() {
        let stale = ProfileBinding(directory: "Profile 10", email: "someone@example.com", displayName: "Other", matchedBy: nil)
        let decision = Router.decide(Self.fallbackURL, config: Self.config(r4: stale), catalog: Self.catalog)
        #expect(issue(decision) == .identityMismatch(stale, current: Self.other))
    }

    @Test func identityMismatchNowSignedOut() {
        let wasSignedIn = ProfileBinding(directory: "Profile 9", email: "guest@example.com", displayName: "Guest", matchedBy: nil)
        let decision = Router.decide(Self.fallbackURL, config: Self.config(r4: wasSignedIn), catalog: Self.catalog)
        #expect(issue(decision) == .identityMismatch(wasSignedIn, current: Self.signedOut))
    }

    @Test func identityMismatchBoundSignedOutNowSignedIn() {
        let wasSignedOut = ProfileBinding(directory: "Profile 10", email: nil, displayName: "Other", matchedBy: nil)
        let decision = Router.decide(Self.fallbackURL, config: Self.config(r4: wasSignedOut), catalog: Self.catalog)
        #expect(issue(decision) == .identityMismatch(wasSignedOut, current: Self.other))
    }

    @Test func signedOutBothTimesLaunches() {
        let decision = Router.decide(Self.fallbackURL, config: Self.config(r4: Self.binding(Self.signedOut)), catalog: Self.catalog)
        #expect(launchTarget(decision)?.directory == "Profile 9")
    }

    @Test func emailComparisonIgnoresCaseAndWhitespace() {
        let bound = ProfileBinding(directory: "Profile 47", email: "Khue@TruckerPoints.ai", displayName: "tp", matchedBy: nil)
        let current = ChromeProfile(directory: "Profile 47", displayName: "renamed", email: " khue@truckerpoints.ai")
        let decision = Router.decide(Self.tpURL, config: Self.config(r2: bound), catalog: .loaded(ProfileCatalog(profiles: [current])))
        #expect(launchTarget(decision)?.directory == "Profile 47")
    }

    @Test func displayNameChangesAreIgnored() {
        let bound = ProfileBinding(directory: "Default", email: "pmkhue.2013@example.com", displayName: "Old name", matchedBy: nil)
        #expect(launchTarget(Router.decide(Self.githubURL, config: Self.config(r3: bound), catalog: Self.catalog))?.directory == "Default")
    }

    @Test func matchedByDoesNotAffectRouting() {
        let plain = Router.decide(Self.githubURL, config: Self.config(), catalog: Self.catalog)
        let autoDetected = Router.decide(Self.githubURL, config: Self.config(r3: Self.binding(Self.personal, matchedBy: .localPart)), catalog: Self.catalog)
        #expect(plain == autoDetected)
    }

    @Test func catalogUnavailablePassesThrough() {
        let decision = Router.decide(Self.githubURL, config: Self.config(), catalog: .unavailable(.notFound("/x/Local State")))
        #expect(issue(decision) == .catalogUnavailable(.notFound("/x/Local State")))
    }

    @Test func unsetIsReportedBeforeCatalogUnavailable() {
        let decision = Router.decide(Self.githubURL, config: Self.config(r3: nil), catalog: .unavailable(.noProfiles))
        #expect(issue(decision) == .unset)
    }

    @Test func configUnavailablePassesThrough() {
        let decision = Router.decide(Self.githubURL, config: .unavailable(.corrupt("x")), catalog: Self.catalog)
        #expect(decision == .needsProfile(url: Self.githubURL, rule: .r3, issue: .configUnavailable(.corrupt("x")), explanation: "host github.com"))
    }

    @Test(arguments: ["ftp://github.com/x", "file:///tmp/a.html", "mailto:a@example.com", "javascript:alert(1)",
                      "chrome://settings", "about:blank", "https:///foo"])
    func rejectedNeverLaunches(_ string: String) {
        // AC-14: even with every rule bound.
        let url = URL(string: string)!
        let decision = Router.decide(url, config: Self.config(r4: Self.binding(Self.other)), catalog: Self.catalog)
        guard case .rejected(let rejectedURL, _) = decision else {
            Issue.record("expected .rejected, got \(decision)")
            return
        }
        #expect(rejectedURL == url)
    }

    @Test func rejectionWinsOverUnavailableConfig() {
        let url = URL(string: "ftp://github.com/x")!
        #expect(Router.decide(url, config: .unavailable(.corrupt("x")), catalog: .unavailable(.noProfiles))
            == .rejected(url: url, .unsupportedScheme("ftp")))
    }

    // MARK: AC-11 fidelity through ChromeLauncher.makeRequest

    static let acceptedVectors = URLClassifierTests.r1 + URLClassifierTests.r2 + URLClassifierTests.r3 + URLClassifierTests.r4

    @MainActor
    private func request(for string: String) throws -> (URL, LaunchRequest) {
        let url = try #require(URL(string: string))
        let decision = Router.decide(url, config: Self.config(r4: Self.binding(Self.other)), catalog: Self.catalog)
        let target = try #require(launchTarget(decision))
        let launcher = ChromeLauncher(locator: FakeLocator(), opener: FakeOpener(), ownBundleIdentifier: "io.github.khuepm.switchprofile")
        return (url, try launcher.makeRequest(for: target))
    }

    @MainActor
    @Test(arguments: acceptedVectors)
    func forwardedURLIsTheReceivedAbsoluteString(_ string: String) throws {
        let (url, request) = try request(for: string)
        #expect(request.arguments.last == url.absoluteString)
        // IDN and full-width hosts are rewritten by URL(string:) before Switch Profile sees them,
        // so only the ASCII vectors are also compared with the source literal.
        if string.allSatisfy(\.isASCII) {
            #expect(request.arguments.last == string)
        }
    }

    @MainActor
    @Test func queryAndFragmentAreForwardedLiterally() throws {
        let literal = "https://github.com/TruckerPoints/trucker-points/pull/1?a=1&b=%20#L10-L20"
        let (_, request) = try request(for: literal)
        #expect(request.arguments == ["--profile-directory=Profile 47", literal])
    }

    @Test func deterministic() {
        let urls = [Self.fisURL, Self.tpURL, Self.githubURL, Self.fallbackURL, URL(string: "ftp://x/")!]
        for url in urls {
            let first = Router.decide(url, config: Self.config(), catalog: Self.catalog)
            let second = Router.decide(url, config: Self.config(), catalog: Self.catalog)
            #expect(first == second)
        }
    }

    // MARK: #14: user rules

    /// The `config-v2-valid` layout: a user rule R5 between R2 and R3.
    @Test func userRuleAboveR3Wins() {
        guard case .loaded(var config) = Self.config() else { return }
        let r5 = RuleID(number: 5)
        config.rules.insert(RoutingRule(id: r5, match: .hostPathPrefix(host: "github.com", pathPrefix: "/khuepm"),
                                        binding: Self.binding(Self.other)), at: 2)
        config.nextRuleNumber = 6
        let decision = Router.decide(Self.githubURL, config: .loaded(config), catalog: Self.catalog)
        #expect(launchTarget(decision) == LaunchTarget(url: Self.githubURL, rule: r5, directory: "Profile 10"))
        // R2 is still above R5, and other github.com links still reach R3.
        #expect(launchTarget(Router.decide(Self.tpURL, config: .loaded(config), catalog: Self.catalog))?.rule == .r2)
        let sibling = URL(string: "https://github.com/TruckerPoints/trucker-points-other")!
        #expect(launchTarget(Router.decide(sibling, config: .loaded(config), catalog: Self.catalog))?.rule == .r3)
    }

    @Test func deletedDefaultRuleFallsThrough() {
        guard case .loaded(var config) = Self.config() else { return }
        config.rules.removeAll { $0.id == .r2 }
        #expect(launchTarget(Router.decide(Self.tpURL, config: .loaded(config), catalog: Self.catalog))
            == LaunchTarget(url: Self.tpURL, rule: .r3, directory: "Default"))
        config.rules.removeAll()
        #expect(launchTarget(Router.decide(Self.fisURL, config: .loaded(config), catalog: Self.catalog))
            == LaunchTarget(url: Self.fisURL, rule: .r4, profile: .lastActiveChrome))
    }

    @Test func configUnavailableClassifiesWithBuiltInRules() {
        let unavailable = RoutingConfig.unavailable(.unsupportedVersion(3))
        let expected: [(URL, RuleID)] = [(Self.fisURL, .r1), (Self.tpURL, .r2), (Self.githubURL, .r3), (Self.fallbackURL, .r4)]
        for (url, rule) in expected {
            let decision = Router.decide(url, config: unavailable, catalog: Self.catalog)
            #expect(decision == .needsProfile(url: url, rule: rule, issue: .configUnavailable(.unsupportedVersion(3)),
                                              explanation: URLClassifierTests.explanation(url)))
        }
    }
}
