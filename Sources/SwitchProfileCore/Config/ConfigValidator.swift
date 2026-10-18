import Foundation

/// Per-rule binding status for the Settings UI.
public enum TargetStatus: Equatable, Sendable {
    case ok(ChromeProfile, autoDetected: MatchKind?)
    /// R4 without a binding: unmatched links open in the last active Chrome profile.
    case lastActiveChrome
    case unset
    case missing(ProfileBinding)
    case identityMismatch(ProfileBinding, current: ChromeProfile)
    case catalogUnavailable(LocalStateError)
}

public enum ConfigValidator {
    /// Same checks as router steps 3 to 6, through the shared `bindingStatus`.
    public static func status(config: AppConfig, catalog: CatalogState) -> [RuleID: TargetStatus] {
        var result: [RuleID: TargetStatus] = [:]
        for rule in config.ruleOrder {
            switch bindingStatus(rule: rule, config.binding(for: rule), catalog: catalog) {
            case .ok(let binding, let profile):
                result[rule] = .ok(profile, autoDetected: binding.matchedBy)
            case .lastActiveChrome:
                result[rule] = .lastActiveChrome
            case .unset:
                result[rule] = .unset
            case .missing(let binding):
                result[rule] = .missing(binding)
            case .identityMismatch(let binding, let current):
                result[rule] = .identityMismatch(binding, current: current)
            case .catalogUnavailable(let error):
                result[rule] = .catalogUnavailable(error)
            }
        }
        return result
    }

    /// Binding that "Confirm" / "Use '<name>' (now <email>)" writes; nil when the status has nothing to confirm.
    public static func confirmedBinding(for status: TargetStatus) -> ProfileBinding? {
        switch status {
        case .ok(let profile, autoDetected: .some):
            // The existing binding with matchedBy cleared. Status .ok means directory and email agree
            // with the profile; the display snapshot is refreshed to the current name.
            return ProfileBinding(profile: profile, matchedBy: nil)
        case .identityMismatch(_, let current):
            return ProfileBinding(profile: current, matchedBy: nil)
        case .ok(_, autoDetected: nil), .lastActiveChrome, .unset, .missing, .catalogUnavailable:
            return nil
        }
    }

    /// Rules whose binding is broken: exactly the .missing and .identityMismatch statuses, in `order`
    /// (the configuration's evaluation order). .unset (normal on first run), .lastActiveChrome, .ok and
    /// .catalogUnavailable never count.
    public static func needsAttention(_ statuses: [RuleID: TargetStatus], order: [RuleID]) -> [RuleID] {
        order.filter { rule in
            switch statuses[rule] {
            case .missing?, .identityMismatch?: true
            case .ok?, .lastActiveChrome?, .unset?, .catalogUnavailable?, nil: false
            }
        }
    }
}
