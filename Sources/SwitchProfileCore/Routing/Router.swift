import Foundation

/// Pure, total routing decision: no I/O, clock or randomness. Never substitutes another
/// rule's profile or the fallback when a rule's profile is unresolved.
public enum Router {
    public static func decide(_ url: URL, config: RoutingConfig, catalog: CatalogState) -> RoutingDecision {
        // 1. Classify.
        let rule: RuleID
        let explanation: String
        switch URLClassifier.classify(url) {
        case .rejected(let rejection):
            return .rejected(url: url, rejection)
        case .matched(let matchedRule, let matchedExplanation):
            rule = matchedRule
            explanation = matchedExplanation
        }

        // 2. Configuration must be usable.
        let appConfig: AppConfig
        switch config {
        case .unavailable(let error):
            return .needsProfile(url: url, rule: rule, issue: .configUnavailable(error), explanation: explanation)
        case .loaded(let loaded):
            appConfig = loaded
        }

        // 3.–6. Binding, catalog, directory, identity.
        switch bindingStatus(appConfig.targets[rule].binding, catalog: catalog) {
        case .unset:
            return .needsProfile(url: url, rule: rule, issue: .unset, explanation: explanation)
        case .catalogUnavailable(let error):
            return .needsProfile(url: url, rule: rule, issue: .catalogUnavailable(error), explanation: explanation)
        case .missing(let binding):
            return .needsProfile(url: url, rule: rule, issue: .missing(binding), explanation: explanation)
        case .identityMismatch(let binding, let current):
            return .needsProfile(url: url, rule: rule, issue: .identityMismatch(binding, current: current), explanation: explanation)
        case .ok(let binding, _):
            // 7. Launch with the original URL object.
            return .launch(LaunchTarget(url: url, rule: rule, directory: binding.directory),
                           explanation: "\(rule.rawValue): \(explanation), profile \(binding.directory)")
        }
    }
}

/// Outcome of checking one rule's binding against the catalog (router steps 3 to 6).
/// Shared by `Router` and `ConfigValidator` so routing and Settings cannot diverge.
enum BindingStatus: Equatable, Sendable {
    case ok(ProfileBinding, ChromeProfile)
    case unset
    case missing(ProfileBinding)
    case identityMismatch(ProfileBinding, current: ChromeProfile)
    case catalogUnavailable(LocalStateError)
}

func bindingStatus(_ binding: ProfileBinding?, catalog: CatalogState) -> BindingStatus {
    // 3. A rule without a binding is unset (including the fallback).
    guard let binding else { return .unset }
    // 4. The catalog must be available.
    let profiles: ProfileCatalog
    switch catalog {
    case .unavailable(let error): return .catalogUnavailable(error)
    case .loaded(let loaded): profiles = loaded
    }
    // 5. The bound directory must still exist.
    guard let profile = profiles.profile(directory: binding.directory) else {
        return .missing(binding)
    }
    // 6. Signed-in identity unchanged: normalized optional emails must be equal (covers
    //    another account, now signed out, and bound signed out but now signed in).
    //    Display names are never compared.
    guard comparableEmail(binding.email) == comparableEmail(profile.email) else {
        return .identityMismatch(binding, current: profile)
    }
    return .ok(binding, profile)
}

/// Trimmed, lowercased; empty becomes nil.
private func comparableEmail(_ email: String?) -> String? {
    LocalStateLoader.normalizedEmail(email)?.lowercased()
}
