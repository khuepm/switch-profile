import AppKit
import SwitchProfileCore

/// Reads and changes the http/https handlers. Changes happen only from explicit button handlers.
@MainActor
final class DefaultBrowserService {
    enum SchemeHandler: Equatable {
        case thisApp
        /// Same bundle identifier, different path (another Switch Profile copy).
        case otherCopy(URL)
        case other(name: String, bundleID: String, url: URL)
        case none
    }

    struct Status: Equatable {
        var http: SchemeHandler
        var https: SchemeHandler

        var isDefault: Bool { http == .thisApp && https == .thisApp }
    }

    static let schemes = ["http", "https"]

    private let ownBundleIdentifier: String
    private let ownBundleURL: URL

    init(ownBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "io.github.khuepm.switchprofile",
         ownBundleURL: URL = Bundle.main.bundleURL) {
        self.ownBundleIdentifier = ownBundleIdentifier
        self.ownBundleURL = ownBundleURL
    }

    func status() -> Status {
        Status(http: handler(scheme: "http"), https: handler(scheme: "https"))
    }

    func handler(scheme: String) -> SchemeHandler {
        guard let url = handlerURL(scheme: scheme) else { return .none }
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
        if bundleID == ownBundleIdentifier {
            return Self.samePath(url, ownBundleURL) ? .thisApp : .otherCopy(url)
        }
        return .other(name: Self.displayName(of: url), bundleID: bundleID, url: url)
    }

    /// True when `application` is the handler for `scheme`.
    func isHandler(_ application: URL, scheme: String) -> Bool {
        guard let url = handlerURL(scheme: scheme) else { return false }
        return Self.samePath(url, application)
    }

    /// Asks macOS to make `application` (default: this app) the handler; macOS may show a confirmation dialog.
    func setDefault(scheme: String, application: URL? = nil) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: application ?? ownBundleURL, toOpenURLsWithScheme: scheme)
    }

    static func displayName(of application: URL) -> String {
        let name = FileManager.default.displayName(atPath: application.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private func handlerURL(scheme: String) -> URL? {
        guard let probe = URL(string: "\(scheme)://example.com") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath() == rhs.standardizedFileURL.resolvingSymlinksInPath()
    }
}
