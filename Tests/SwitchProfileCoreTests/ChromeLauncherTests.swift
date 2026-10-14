import Foundation
import Testing
@testable import SwitchProfileCore

@MainActor
@Suite struct ChromeLauncherTests {
    nonisolated static let ownID = "io.github.khuepm.switchprofile"
    nonisolated static let url = URL(string: "https://github.com/khuepm/LumiBase")!

    private func launcher(_ locator: FakeLocator = FakeLocator(), opener: FakeOpener) -> ChromeLauncher {
        ChromeLauncher(locator: locator, opener: opener, ownBundleIdentifier: Self.ownID)
    }

    private func target(_ directory: String = "Profile 30") -> LaunchTarget {
        LaunchTarget(url: Self.url, rule: .r3, directory: directory)
    }

    @Test func requestIsExactlyTwoArguments() throws {
        // AC-21
        let request = try launcher(opener: FakeOpener()).makeRequest(for: target())
        #expect(request.applicationURL == FakeLocator.chromeURL)
        #expect(request.arguments == ["--profile-directory=Profile 30", "https://github.com/khuepm/LumiBase"])
    }

    @Test func directoryWithSpacesStaysOneElement() throws {
        let request = try launcher(opener: FakeOpener()).makeRequest(for: target("My Profile 2"))
        #expect(request.arguments.count == 2)
        #expect(request.arguments[0] == "--profile-directory=My Profile 2")
    }

    @Test func launchOpensTheRequest() async throws {
        let opener = FakeOpener()
        try await launcher(opener: opener).launch(target())
        #expect(opener.requests == [LaunchRequest(applicationURL: FakeLocator.chromeURL,
                                                  arguments: ["--profile-directory=Profile 30", Self.url.absoluteString])])
    }

    @Test func missingChromeIsNotInstalled() async {
        let opener = FakeOpener()
        let launcher = launcher(FakeLocator(url: nil), opener: opener)
        #expect(throws: LaunchError.chromeNotInstalled) { try launcher.makeRequest(for: target()) }
        do {
            try await launcher.launch(target())
            Issue.record("expected .chromeNotInstalled")
        } catch {
            #expect(error == .chromeNotInstalled)
        }
        #expect(opener.requests.isEmpty)
    }

    @Test(arguments: [(String?.some(ownID), ownID), ("com.apple.Safari", "com.apple.Safari"), (nil, "<no bundle identifier>")])
    func loopGuardNeverCallsTheOpener(_ bundleID: String?, _ reported: String) async {
        // AC-22, NIT #4
        let opener = FakeOpener()
        let launcher = launcher(FakeLocator(bundleID: bundleID), opener: opener)
        #expect(throws: LaunchError.loopDetected(reported)) { try launcher.makeRequest(for: target()) }
        do {
            try await launcher.launch(target())
            Issue.record("expected .loopDetected")
        } catch {
            #expect(error == .loopDetected(reported))
        }
        #expect(opener.requests.isEmpty)
    }

    @Test func openerErrorBecomesOpenFailed() async {
        let opener = FakeOpener()
        opener.failingCalls = [1]
        do {
            try await launcher(opener: opener).launch(target())
            Issue.record("expected .openFailed")
        } catch {
            #expect(error == .openFailed("fake open failure"))
        }
        #expect(opener.callCount == 1)
    }
}
