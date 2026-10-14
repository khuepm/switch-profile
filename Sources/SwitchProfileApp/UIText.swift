import Foundation
import SwitchProfileCore

/// User-facing texts shared by the menu, Settings and the resolution window.
enum UIText {
    static func ruleDescription(_ rule: RuleID) -> String {
        switch rule {
        case .r1: "git.fis.vn (any path)"
        case .r2: "github.com/TruckerPoints/trucker-points and sub-paths"
        case .r3: "Other github.com links"
        case .r4: "Fallback: every other http(s) link"
        }
    }

    static func catalogError(_ error: LocalStateError) -> String {
        switch error {
        case .notFound(let path): "Google Chrome profile data not found at \(path)"
        case .unreadable(let path, let reason): "Could not read \(path): \(reason)"
        case .malformed(let reason): "Chrome Local State is malformed: \(reason)"
        case .noProfiles: "No Chrome profiles found in Local State"
        }
    }

    static func configError(_ error: ConfigError) -> String {
        switch error {
        case .unreadable(let reason): "configuration unreadable: \(reason)"
        case .corrupt(let reason): "configuration corrupt: \(reason)"
        case .unsupportedVersion(let version): "unsupported configuration version \(version)"
        case .writeFailed(let reason): "could not write the configuration: \(reason)"
        }
    }

    static func launchError(_ error: LaunchError) -> String {
        switch error {
        case .chromeNotInstalled: "Google Chrome is not installed"
        case .loopDetected(let found): "the located browser is \(found), not Google Chrome"
        case .openFailed(let reason): reason
        }
    }

    static func issue(_ issue: ProfileIssue, rule: RuleID) -> String {
        switch issue {
        case .unset:
            rule == .r4 ? "No fallback profile is set" : "No profile is set for \(rule.rawValue)"
        case .missing(let binding):
            "Profile '\(binding.directory)' no longer exists"
        case .identityMismatch(let binding, let current):
            "Profile '\(binding.directory)' was bound to \(binding.email ?? "signed out") and is now \(current.email ?? "signed out")"
        case .catalogUnavailable(let error):
            "Chrome profiles unavailable: \(catalogError(error))"
        case .configUnavailable(let error):
            "Configuration unavailable: \(configError(error))"
        }
    }

    static func pendingKind(_ kind: PendingKind, rule: RuleID) -> String {
        switch kind {
        case .needsProfile(let profileIssue): issue(profileIssue, rule: rule)
        case .launchFailed(let error): "Chrome could not be opened: \(launchError(error))"
        }
    }

    static func pendingActionError(_ error: PendingActionError) -> String {
        switch error {
        case .itemNotFound: "This link is no longer pending"
        case .notApplicable: "This action does not apply to this link"
        case .configUnavailable: "Configuration file is invalid – Reset to defaults… first"
        case .profileNotFound(let directory): "Profile '\(directory)' no longer exists – press Refresh profiles"
        case .catalogUnavailable(let error): "Chrome profiles unavailable: \(catalogError(error))"
        case .saveFailed(let error): "Could not save: \(configError(error))"
        }
    }

    static func profileLabel(_ profile: ChromeProfile) -> String {
        if let email = profile.email {
            return "\(profile.displayName) — \(email) (\(profile.directory))"
        }
        return "\(profile.displayName) (\(profile.directory))"
    }

    static func matchKind(_ kind: MatchKind) -> String {
        switch kind {
        case .email: "email"
        case .displayName: "display name"
        case .localPart: "email local part"
        }
    }

    static func handler(_ handler: DefaultBrowserService.SchemeHandler) -> String {
        switch handler {
        case .thisApp: "Switch Profile"
        case .otherCopy(let url): "another Switch Profile copy at \(url.path)"
        case .other(let name, _, _): name
        case .none: "none"
        }
    }
}
