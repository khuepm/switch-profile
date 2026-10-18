import Foundation

/// The single choke point every forward passes through (routed links, "Open once", "Open and use").
/// Loop-prevention invariant: it only ever opens the application whose bundle identifier is exactly
/// `com.google.Chrome` and is not our own, and never asks LaunchServices for a URL's default handler.
/// The guard runs before argv is built, for fixed profiles and last-active mode alike; the request
/// has one or two argv elements (`--profile-directory=<dir>` only for a fixed profile, then the URL).
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
        // 3. Discrete argv elements; the URL is the received object's absoluteString. Last-active mode
        //    omits `--profile-directory`, so Chrome picks its most recently active profile.
        let arguments: [String]
        switch target.profile {
        case .directory(let directory):
            arguments = ["--profile-directory=" + directory, target.url.absoluteString]
        case .lastActiveChrome:
            arguments = [target.url.absoluteString]
        }
        return LaunchRequest(applicationURL: applicationURL, arguments: arguments)
    }

    /// Builds the request and opens it. Opener errors become `.openFailed(localizedDescription)`.
    public func launch(_ target: LaunchTarget) async throws(LaunchError) {
        let request = try makeRequest(for: target)
        do {
            try await opener.open(request)
        } catch {
            Log.launch.error("Open failed for \(target.rule.rawValue, privacy: .public), profile \(target.profile.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw .openFailed(error.localizedDescription)
        }
        Log.launch.info("Launched \(target.rule.rawValue, privacy: .public) in profile \(target.profile.label, privacy: .public)")
    }
}
