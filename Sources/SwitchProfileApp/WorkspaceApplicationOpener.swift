import AppKit
import SwitchProfileCore

/// NSWorkspace implementation of the launcher's locator and opener.
/// Opens Chrome as a new instance with discrete arguments; never asks for a URL's default handler.
final class WorkspaceApplicationOpener: ChromeLocating, ApplicationOpening, Sendable {
    /// Cold-start wait: poll every 100 ms, at most 5 s.
    private static let pollInterval: UInt64 = 100_000_000
    private static let maxPolls = 50

    func chromeApplicationURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeApp.bundleIdentifier)
    }

    func bundleIdentifier(at url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    func open(_ request: LaunchRequest) async throws {
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: ChromeApp.bundleIdentifier).isEmpty

        let configuration = NSWorkspace.OpenConfiguration()
        // Required while Chrome runs: otherwise LaunchServices only activates it and drops the arguments.
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.arguments = request.arguments

        let application = try await NSWorkspace.shared.openApplication(at: request.applicationURL,
                                                                       configuration: configuration)
        guard !wasRunning else { return }

        // Cold start: let the singleton finish starting before the next URL is forwarded.
        for _ in 0..<Self.maxPolls {
            if application.isFinishedLaunching { return }
            try? await Task.sleep(nanoseconds: Self.pollInterval)
        }
        Log.launch.info("Chrome did not finish launching within 5 s; continuing")
    }
}
