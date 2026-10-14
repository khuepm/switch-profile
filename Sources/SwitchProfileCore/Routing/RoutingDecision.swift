import Foundation

public enum MalformedReason: Equatable, Sendable {
    case tooLong, unparseable, missingScheme, missingHost
}

public enum Rejection: Equatable, Sendable {
    case unsupportedScheme(String)
    case malformed(MalformedReason)
}
// Core has no "empty" case: it only ever receives a URL object. Empty or unparseable typed
// text is UI-only validation in the preview field and never reaches Core.

public enum Classification: Equatable, Sendable {
    /// e.g. "host github.com, repository TruckerPoints/trucker-points"
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

public struct LaunchTarget: Equatable, Sendable {
    /// The original URL object as received; never rebuilt from components.
    public let url: URL
    public let rule: RuleID
    public let directory: String

    public init(url: URL, rule: RuleID, directory: String) {
        self.url = url
        self.rule = rule
        self.directory = directory
    }
}

public enum RoutingDecision: Equatable, Sendable {
    case launch(LaunchTarget, explanation: String)
    case needsProfile(url: URL, rule: RuleID, issue: ProfileIssue, explanation: String)
    case rejected(url: URL, Rejection)
}
