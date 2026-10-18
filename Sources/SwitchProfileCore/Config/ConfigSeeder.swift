import Foundation

/// First-run seeding: resolves the built-in identities into bindings for unbound rules.
public enum ConfigSeeder {
    /// Pure. For every rule with no binding and a non-nil identity, a `.unique` resolution becomes a
    /// binding marked with `matchedBy`. Existing bindings are never touched; the fallback is never
    /// seeded. The result always has `seedPending == false`.
    public static func seed(_ config: AppConfig, catalog: ProfileCatalog) -> AppConfig {
        var seeded = config
        for index in seeded.rules.indices {
            let rule = seeded.rules[index]
            guard rule.binding == nil, let identity = rule.identity else { continue }
            if case .unique(let profile, let matchedBy) = ProfileResolver.resolve(identity: identity, in: catalog) {
                seeded.rules[index].binding = ProfileBinding(profile: profile, matchedBy: matchedBy)
            }
        }
        seeded.seedPending = false
        return seeded
    }
}
