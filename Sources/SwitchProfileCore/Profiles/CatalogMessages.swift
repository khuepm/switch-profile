import Foundation

/// User-facing texts for an unavailable Chrome profile catalog, shared by Settings and the dry run.
/// While the catalog is unavailable, an unseeded rule reports `.unset`; callers use these texts so the
/// user sees the real cause ("Chrome profiles unavailable") and how to fix it, not "no profile set" (#12).
public enum CatalogMessages {
    /// Who needs the file access: the app itself, or the terminal running `--dry-run`.
    public enum Requester: Sendable {
        case app
        case terminal
    }

    public static func unavailable(_ error: LocalStateError) -> String {
        switch error {
        case .notFound(let path):
            "Chrome profiles unavailable: Google Chrome profile data not found at \(path)"
        case .unreadable(let path, let reason):
            "Chrome profiles unavailable: could not read \(path) (\(reason))"
        case .malformed(let reason):
            "Chrome profiles unavailable: Chrome Local State is malformed: \(reason)"
        case .noProfiles:
            "Chrome profiles unavailable: no Chrome profiles found in Local State"
        }
    }

    /// `.unreadable` is almost always macOS privacy protection (App Data / Full Disk Access).
    public static func remedy(_ error: LocalStateError, requester: Requester) -> String {
        switch (error, requester) {
        case (.unreadable, .app):
            "macOS may be blocking access. Allow Switch Profile in System Settings → Privacy & Security (App Data or Full Disk Access), then press Refresh."
        case (.unreadable, .terminal):
            "macOS may be blocking access. Allow the terminal app that runs this command in System Settings → Privacy & Security (App Data or Full Disk Access), then run it again."
        case (.notFound, _):
            "Install Google Chrome in /Applications and start it once."
        case (.malformed, _), (.noProfiles, _):
            "Start Google Chrome once so it rewrites its profile list, then try again."
        }
    }
}
