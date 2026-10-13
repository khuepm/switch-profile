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

    @Test func rejectedHasNoArgv() {
        let url = URL(string: "ftp://github.com/x")!
        let text = DryRunReport.render(url: url, decision: .rejected(url: url, .unsupportedScheme("ftp")), request: nil, chromeRunning: true)
        #expect(text == """
            url: ftp://github.com/x
            decision: rejected, unsupported scheme ftp
            launch: none
            """)
    }

    @Test func neverMentionsTheOpenBinaryPath() {
        let (url, decision, request) = launch("https://github.com/x", directory: "Default", rule: .r3)
        for running in [true, false] {
            #expect(!DryRunReport.render(url: url, decision: decision, request: .success(request), chromeRunning: running)
                .contains("/usr/bin/"))
        }
    }
}
