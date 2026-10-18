import Foundation

/// Schema migrations, applied in memory at load. Nothing is written until the next successful save.
enum ConfigMigration {
    /// Version 1 → 2. R1–R3 become the default rules (same matches, so routing is identical) with
    /// their identities and bindings; R4 becomes the fallback.
    static func v2(from v1: AppConfigV1) -> AppConfig {
        let targets = [RuleID.r1: v1.targets.R1, .r2: v1.targets.R2, .r3: v1.targets.R3]
        let rules = AppConfig.defaultRules.map { rule in
            let target = targets[rule.id] ?? RuleTarget()
            return RoutingRule(id: rule.id, match: rule.match, identity: target.identity, binding: target.binding)
        }
        return AppConfig(seedPending: v1.seedPending,
                         rules: rules,
                         fallback: v1.targets.R4,
                         nextRuleNumber: AppConfig.firstUserRuleNumber,
                         previousDefaultBrowser: v1.previousDefaultBrowser)
    }
}
