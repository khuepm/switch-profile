import Foundation

/// The single choke point every forward passes through (routed links, "Open once", test links).
/// Loop-prevention invariant: it only ever opens the application whose bundle identifier is exactly
/// `com.google.Chrome` and is not our own, and never asks LaunchServices for a URL's default handler.
public struct ChromeLauncher: Sendable {
    private let locator: any ChromeLocating
    private let opener: any ApplicationOpening
    private let ownBundleIdentifier: String

    public init(locator: any ChromeLocating, opener: any ApplicationOpening, ownBundleIdentifier: String) {
        self.locator = locator
        self.opener = opener
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    /// Builds the exact request for `target` without opening anything.
    public func makeRequest(for target: LaunchTarget) throws(LaunchError) -> LaunchRequest {
        // 1. Locate Chrome.
        guard let applicationURL = locator.chromeApplicationURL() else {
            Log.launch.error("Chrome is not installed")
            throw .chromeNotInstalled
        }
        // 2. Loop guard.
        let foundID = locator.bundleIdentifier(at: applicationURL)
        guard let foundID, foundID == ChromeApp.bundleIdentifier, foundID != ownBundleIdentifier else {
            let reported = foundID ?? "<no bundle identifier>"
            Log.launch.fault("Loop guard: located application is \(reported, privacy: .public)")
            throw .loopDetected(reported)
        }
        // 3. Two discrete argv elements; the URL is the received object's absoluteString.
        return LaunchRequest(applicationURL: applicationURL,
                             arguments: ["--profile-directory=" + target.directory, target.url.absoluteString])
    }

    /// Builds the request and opens it. Opener errors become `.openFailed(localizedDescription)`.
    public func launch(_ target: LaunchTarget) async throws(LaunchError) {
        let request = try makeRequest(for: target)
        do {
            try await opener.open(request)
        } catch {
            Log.launch.error("Open failed for \(target.rule.rawValue, privacy: .public), profile \(target.directory, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw .openFailed(error.localizedDescription)
        }
        Log.launch.info("Launched \(target.rule.rawValue, privacy: .public) in profile \(target.directory, privacy: .public)")
    }
}
