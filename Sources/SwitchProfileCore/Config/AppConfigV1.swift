import Foundation

/// Fixed per-rule targets of schema version 1. A struct (not a dictionary) so synthesized
/// decoding requires all four keys.
struct RuleTargets: Codable, Equatable, Sendable {
    var R1: RuleTarget
    var R2: RuleTarget
    var R3: RuleTarget
    var R4: RuleTarget
}

/// Configuration file schema version 1 (v0.2.0 and #13): four fixed rules. Only read, then
/// migrated to version 2 in memory; never written.
struct AppConfigV1: Codable, Equatable, Sendable {
    /// Must be 1.
    var schemaVersion: Int
    var seedPending: Bool
    var targets: RuleTargets
    var previousDefaultBrowser: DefaultBrowserRecord?
}
