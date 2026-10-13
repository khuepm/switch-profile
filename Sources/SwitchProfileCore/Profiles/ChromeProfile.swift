import Foundation

/// One entry of Chrome's `Local State` `profile.info_cache`.
public struct ChromeProfile: Equatable, Hashable, Sendable {
    /// The `info_cache` key, e.g. `Default` or `Profile 30`. Passed to Chrome as `--profile-directory`.
    public let directory: String
    /// `name`, or the directory key when `name` is missing or empty.
    public let displayName: String
    /// `user_name`, trimmed; nil when missing or empty (signed out).
    public let email: String?

    public init(directory: String, displayName: String, email: String?) {
        self.directory = directory
        self.displayName = displayName
        self.email = email
    }
}

/// The set of Chrome profiles read from one `Local State` file, sorted by directory key.
public struct ProfileCatalog: Equatable, Sendable {
    /// Sorted by `directory` with plain `<`.
    public let profiles: [ChromeProfile]

    public init(profiles: [ChromeProfile]) {
        self.profiles = profiles.sorted { $0.directory < $1.directory }
    }

    public func profile(directory: String) -> ChromeProfile? {
        profiles.first { $0.directory == directory }
    }
}

/// Why a `Local State` catalog could not be produced. All cases are recoverable once the user fixes the condition.
public enum LocalStateError: Error, Equatable, Sendable {
    /// The file does not exist (also: Chrome not installed or never run).
    case notFound(String)
    /// Read error (permissions, I/O). Path and `localizedDescription`.
    case unreadable(String, String)
    /// Not JSON, or `profile.info_cache` missing or of the wrong type.
    case malformed(String)
    /// `info_cache` present but has zero valid entries.
    case noProfiles
}
