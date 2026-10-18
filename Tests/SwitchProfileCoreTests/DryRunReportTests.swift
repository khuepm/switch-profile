import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct DryRunReportTests {
    static let app = URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)

    private func launch(_ string: String, directory: String, rule: RuleID = .r2) -> (URL, RoutingDecision, LaunchRequest) {
        let url = URL(string: string)!
        let target = LaunchTarget(url: url, rule: rule, directory: directory)
        let decision = RoutingDecision.launch(target, explanation: "\(rule.rawValue): explained, profile \(directory)")
        let request = LaunchRequest(applicationURL: Self.app, arguments: ["--profile-directory=" + directory, url.absoluteString])
        return (url, decision, request)
    }

    @Test func launchWithChromeRunning() {
        let (url, decision, request) = launch("https://github.com/TruckerPoints/trucker-points", directory: "Profile 47")
        let text = DryRunReport.render(url: url, decision: decision, request: .success(request), chromeRunning: true)
        #expect(text == """
            url: https://github.com/TruckerPoints/trucker-points
            decision: launch, R2: explained, profile Profile 47
            profile-directory: Profile 47
            chrome-state: running, new instance forwards the command line to the running Chrome (ProcessSingleton)
            application: /Applications/Google Chrome.app
            argv: ["--profile-directory=Profile 47","https://github.com/TruckerPoints/trucker-points"]
            equivalent (display only, never executed): open -na '/Applications/Google Chrome.app' --args '--profile-directory=Profile 47' 'https://github.com/TruckerPoints/trucker-points'
            """)
    }

    @Test func launchWithChromeClosed() {
        let (url, decision, request) = launch("https://git.fis.vn/x", directory: "Profile 30", rule: .r1)
        let text = DryRunReport.render(url: url, decision: decision, request: .success(request), chromeRunning: false)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.contains("chrome-state: closed, cold start; waits up to 5 s for isFinishedLaunching before the next URL"))
        #expect(lines.contains(#"argv: ["--profile-directory=Profile 30","https://git.fis.vn/x"]"#))
        #expect(!text.contains("ProcessSingleton"))
    }

    private func lastActive(_ string: String) -> (URL, RoutingDecision, LaunchRequest) {
        let url = URL(string: string)!
        let target = LaunchTarget(url: url, rule: .r4, profile: .lastActiveChrome)
        let decision = RoutingDecision.launch(target, explanation: "R4: last active Chrome profile (host example.com matches no rule; fallback)")
        let request = LaunchRequest(applicationURL: Self.app, arguments: [url.absoluteString])
        return (url, decision, request)
    }

    @Test func lastActiveWithChromeRunning() {
        let (url, decision, request) = lastActive("https://example.com/")
        let text = DryRunReport.render(url: url, decision: decision, request: .success(request), chromeRunning: true)
        #expect(text == """
            url: https://example.com/
            decision: launch, R4: last active Chrome profile (host example.com matches no rule; fallback)
            profile-directory: none (last active Chrome profile)
            chrome-state: running, new instance forwards the command line to the running Chrome (ProcessSingleton), which opens it in the profile of the most recently active window
            application: /Applications/Google Chrome.app
            argv: ["https://example.com/"]
            equivalent (display only, never executed): open -na '/Applications/Google Chrome.app' --args 'https://example.com/'
            """)
    }

    @Test func lastActiveWithChromeClosed() {
        let (url, decision, request) = lastActive("https://example.com/")
        let text = DryRunReport.render(url: url, decision: decision, request: .success(request), chromeRunning: false)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.contains("chrome-state: closed, cold start in Chrome's last used profile (profile.last_used in Local State); waits up to 5 s for isFinishedLaunching before the next URL"))
        #expect(lines.contains(#"argv: ["https://example.com/"]"#))
        #expect(!text.contains("ProcessSingleton"))
    }

    /// End to end: real Router with the built-in defaults and an unreadable Local State, real launcher.
    @MainActor
    @Test func lastActiveArgvHasNoProfileDirectory() throws {
        let url = URL(string: "https://example.com/")!
        let decision = Router.decide(url, config: .loaded(.unseededDefault),
                                     catalog: .unavailable(.unreadable("/x/Local State", "permission denied")))
        guard case .launch(let target, _) = decision else {
            Issue.record("expected .launch, got \(decision)")
            return
        }
        let launcher = ChromeLauncher(locator: FakeLocator(), opener: FakeOpener(), ownBundleIdentifier: "io.github.khuepm.switchprofile")
        let request = try launcher.makeRequest(for: target)
        let text = DryRunReport.render(url: url, decision: decision, request: .success(request), chromeRunning: true)
        #expect(text.contains("R4: last active Chrome profile"))
        #expect(text.contains(#"argv: ["https://example.com/"]"#))
        #expect(!text.contains("--profile-directory"))
    }

    @Test func singleQuotesAreEscapedInTheDisplayLine() {
        let (url, decision, request) = launch("https://example.com/it's", directory: "Default", rule: .r4)
        let text = DryRunReport.render(url: url, decision: decision, request: .success(request), chromeRunning: true)
        #expect(text.contains(#"--args '--profile-directory=Default' 'https://example.com/it'\''s'"#))
        #expect(text.contains(#"argv: ["--profile-directory=Default","https://example.com/it's"]"#))
        #expect(DryRunReport.shellQuoted("a'b") == #"'a'\''b'"#)
    }

    @Test func launchErrorIsShownWithoutArgv() {
        let (url, decision, _) = launch("https://github.com/x", directory: "Default", rule: .r3)
        let text = DryRunReport.render(url: url, decision: decision, request: .failure(.loopDetected("com.apple.Safari")), chromeRunning: true)
        #expect(text.contains("launch-error: loop guard, located application is com.apple.Safari, not com.google.Chrome"))
        #expect(!text.contains("argv:"))
    }

    @Test func needsProfileHasNoArgv() {
        let url = URL(string: "https://example.com/page")!
        let decision = RoutingDecision.needsProfile(url: url, rule: .r4, issue: .unset, explanation: "host example.com matches no rule; fallback")
        let text = DryRunReport.render(url: url, decision: decision, request: nil, chromeRunning: false)
        #expect(text == """
            url: https://example.com/page
            decision: needs profile, R4 has no profile set (host example.com matches no rule; fallback)
            profile-directory: none
            launch: none, the link would wait in the pending window
            """)
    }

    /// #12: an unseeded rule reports `.unset` while Local State is unreadable; the cause is the catalog.
    @Test func unsetWithUnreadableCatalogSaysProfilesUnavailable() {
        let url = URL(string: "https://git.fis.vn/x")!
        let decision = RoutingDecision.needsProfile(url: url, rule: .r1, issue: .unset, explanation: "host git.fis.vn")
        let text = DryRunReport.render(url: url, decision: decision, request: nil, chromeRunning: true,
                                       catalogError: .unreadable("/x/Local State", "permission denied"))
        #expect(text == """
            url: https://git.fis.vn/x
            decision: needs profile, Chrome profiles unavailable, so no profile can be chosen for R1 (host git.fis.vn)
            profile-directory: none
            launch: none, the link would wait in the pending window
            """)
        #expect(!text.contains("has no profile set"))
    }

    @Test func catalogUnavailableIssueSaysProfilesUnavailable() {
        let url = URL(string: "https://github.com/x")!
        let decision = RoutingDecision.needsProfile(url: url, rule: .r3, issue: .catalogUnavailable(.noProfiles), explanation: "host github.com")
        let text = DryRunReport.render(url: url, decision: decision, request: nil, chromeRunning: true)
        #expect(text.contains("decision: needs profile, Chrome profiles unavailable, so the R3 profile cannot be checked (host github.com)"))
    }

    @Test func localStateNoteForUnreadableCatalogNamesTheFix() {
        let note = DryRunReport.localStateNote(path: "/x/Local State",
                                               catalog: .unavailable(.unreadable("/x/Local State", "permission denied")))
        #expect(note == """
            local-state: /x/Local State (unavailable)
            error: Chrome profiles unavailable: could not read /x/Local State (permission denied)
            fix: macOS may be blocking access. Allow the terminal app that runs this command in System Settings → Privacy & Security (App Data or Full Disk Access), then run it again.
            """)
    }

    @Test func localStateNoteForLoadedCatalogCountsProfiles() {
        let catalog = ProfileCatalog(profiles: [ChromeProfile(directory: "Default", displayName: "A", email: nil),
                                                ChromeProfile(directory: "Profile 1", displayName: "B", email: nil)])
        #expect(DryRunReport.localStateNote(path: "/x/Local State", catalog: .loaded(catalog))
            == "local-state: /x/Local State (2 profiles)")
    }

    @Test func rejectedHasNoArgv() {
        let url = URL(string: "ftp://github.com/x")!
        let text = DryRunReport.render(url: url, decision: .rejected(url: url, .unsupportedScheme("ftp")), request: nil, chromeRunning: true)
        #expect(text == """
            url: ftp://github.com/x
            decision: rejected, unsupported scheme ftp
            launch: none
            """)
    }

    // MARK: #14: rules header

    @Test func rulesNoteListsEvaluationOrder() {
        #expect(DryRunReport.rulesNote(.loaded(.unseededDefault))
            == "rules: R1 host git.fis.vn; R2 host github.com, path /TruckerPoints/trucker-points; R3 host github.com; R4 fallback")

        var config = AppConfig.unseededDefault
        config.rules.insert(RoutingRule(id: RuleID(number: 5), match: .host("example.org")), at: 2)
        config.nextRuleNumber = 6
        #expect(DryRunReport.rulesNote(.loaded(config))
            == "rules: R1 host git.fis.vn; R2 host github.com, path /TruckerPoints/trucker-points; R5 host example.org; R3 host github.com; R4 fallback")

        config.rules = []
        #expect(DryRunReport.rulesNote(.loaded(config)) == "rules: R4 fallback")
    }

    @Test func rulesNoteForUnavailableConfig() {
        #expect(DryRunReport.rulesNote(.unavailable(.unsupportedVersion(3)))
            == "rules: built-in defaults (configuration unavailable)")
    }

    @Test func prefixRuleExplanationInDecisionLine() {
        let url = URL(string: "https://github.com/TruckerPoints/trucker-points")!
        var config = AppConfig.unseededDefault
        config.seedPending = false
        let decision = Router.decide(url, config: .loaded(config), catalog: .loaded(Fixture.validCatalog()))
        let text = DryRunReport.render(url: url, decision: decision, request: nil, chromeRunning: true)
        #expect(text.components(separatedBy: "\n").contains(
            "decision: needs profile, R2 has no profile set (host github.com, path /TruckerPoints/trucker-points)"))
    }

    @Test func neverMentionsTheOpenBinaryPath() {
        let (url, decision, request) = launch("https://github.com/x", directory: "Default", rule: .r3)
        for running in [true, false] {
            #expect(!DryRunReport.render(url: url, decision: decision, request: .success(request), chromeRunning: running)
                .contains("/usr/bin/"))
        }
    }
}
