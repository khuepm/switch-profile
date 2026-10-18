import Foundation

/// The Chrome bundle identifier, shared by the launcher's loop guard and the app's opener,
/// so `WorkspaceApplicationOpener` does not need to reference `ChromeLauncher`.
public enum ChromeApp {
    public static let bundleIdentifier = "com.google.Chrome"
}

/// One Chrome invocation: the application to open and its exact argv (no shell, no quoting):
/// `["--profile-directory=<dir>", url]` for a fixed profile, `[url]` in last-active mode.
public struct LaunchRequest: Equatable, Sendable {
    public let applicationURL: URL
    public let arguments: [String]

    public init(applicationURL: URL, arguments: [String]) {
        self.applicationURL = applicationURL
        self.arguments = arguments
    }
}

/// Finds the Chrome application and reads bundle identifiers (NSWorkspace in the app).
public protocol ChromeLocating: Sendable {
    func chromeApplicationURL() -> URL?
    func bundleIdentifier(at url: URL) -> String?
}

/// Opens an application with arguments as a new instance (NSWorkspace in the app). Throws any error.
/// The new instance forwards its argv to a running Chrome; without `--profile-directory` Chrome
/// opens the URL in its most recently active profile.
public protocol ApplicationOpening: Sendable {
    func open(_ request: LaunchRequest) async throws
}

public enum LaunchError: Error, Equatable, Sendable {
    /// No application registered for `com.google.Chrome`.
    case chromeNotInstalled
    /// The located application is not Chrome, or is Switch Profile itself. Payload: the found bundle ID.
    case loopDetected(String)
    /// The opener failed. Payload: the error's `localizedDescription`.
    case openFailed(String)
}
