import Foundation

public enum MalformedReason: Equatable, Sendable {
    case tooLong, unparseable, missingScheme, missingHost
}

public enum Rejection: Equatable, Sendable {
    case unsupportedScheme(String)
    case malformed(MalformedReason)
}
// Core has no "empty" case: it only ever receives a URL object. Empty or unparseable typed
// text is rejected by the caller before Core (e.g. the dry run's "not a valid URL").

public enum Classification: Equatable, Sendable {
    /// e.g. "host github.com, path /TruckerPoints/trucker-points"
    case matched(RuleID, explanation: String)
    case rejected(Rejection)
}

public enum CatalogState: Equatable, Sendable {
    case loaded(ProfileCatalog)
    case unavailable(LocalStateError)
}

public enum ProfileIssue: Equatable, Sendable {
    /// No binding for this rule (including the fallback).
    case unset
    /// The bound directory is no longer in `info_cache`.
    case missing(ProfileBinding)
    /// Directory reused, signed in, signed out, or another account since binding.
    case identityMismatch(ProfileBinding, current: ChromeProfile)
    case catalogUnavailable(LocalStateError)
    /// Corrupt or unsupported configuration file; routing is refused.
    case configUnavailable(ConfigError)
}

/// Which Chrome profile a launch targets.
public enum LaunchProfile: Equatable, Sendable {
    /// A fixed profile, passed as `--profile-directory=<directory>`.
    case directory(String)
    /// No `--profile-directory`: Chrome opens the URL in its most recently active profile
    /// (running), or in `profile.last_used` from Local State (closed). Only an unset R4 uses it.
    case lastActiveChrome

    /// The directory, or "last active Chrome profile"; for logs and explanations.
    public var label: String {
        switch self {
        case .directory(let directory): directory
        case .lastActiveChrome: "last active Chrome profile"
        }
    }
}

public struct LaunchTarget: Equatable, Sendable {
    /// The original URL object as received; never rebuilt from components.
    public let url: URL
    public let rule: RuleID
    public let profile: LaunchProfile

    public init(url: URL, rule: RuleID, profile: LaunchProfile) {
        self.url = url
        self.rule = rule
        self.profile = profile
    }

    /// A fixed-profile target.
    public init(url: URL, rule: RuleID, directory: String) {
        self.init(url: url, rule: rule, profile: .directory(directory))
    }

    /// The fixed profile directory; nil in last-active mode.
    public var directory: String? {
        if case .directory(let directory) = profile { return directory }
        return nil
    }
}

public enum RoutingDecision: Equatable, Sendable {
    case launch(LaunchTarget, explanation: String)
    case needsProfile(url: URL, rule: RuleID, issue: ProfileIssue, explanation: String)
    case rejected(url: URL, Rejection)
}
