import Foundation

/// First-run seeding: resolves the built-in identities into bindings for unbound rules.
public enum ConfigSeeder {
    /// Pure. For R1 to R3 with no binding and a non-nil identity, a `.unique` resolution becomes a
    /// binding marked with `matchedBy`. Existing bindings are never touched; R4 is never seeded.
    /// The result always has `seedPending == false`.
    public static func seed(_ config: AppConfig, catalog: ProfileCatalog) -> AppConfig {
        var seeded = config
        for rule in RuleID.allCases where rule != .r4 {
            let target = seeded.targets[rule]
            guard target.binding == nil, let identity = target.identity else { continue }
            if case .unique(let profile, let matchedBy) = ProfileResolver.resolve(identity: identity, in: catalog) {
                seeded.targets[rule].binding = ProfileBinding(profile: profile, matchedBy: matchedBy)
            }
        }
        seeded.seedPending = false
        return seeded
    }
}
