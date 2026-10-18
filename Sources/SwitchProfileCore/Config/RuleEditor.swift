import Foundation

public enum RuleEditError: Error, Equatable, Sendable {
    /// The draft failed validation; nothing changed.
    case invalid([RuleFieldError])
    case ruleNotFound
    /// The fallback cannot be edited, moved or deleted.
    case fallbackImmutable
    /// Already first (up) or last (down).
    case cannotMove
    /// The configuration file is invalid; only "Reset to defaults…" can write.
    case configUnavailable
    case saveFailed(ConfigError)
}

/// Pure editing operations on the rule list. The fallback is not in `rules`, so it always stays last.
public enum RuleEditor {
    /// Appends a rule directly above the fallback with the next unused id (`R<nextRuleNumber>`).
    @discardableResult
    public static func add(_ draft: RuleDraft, to config: inout AppConfig) throws(RuleEditError) -> RuleID {
        let validation = RuleValidator.validate(draft, existing: config.rules, editing: nil)
        guard let match = validation.match else { throw .invalid(validation.errors) }
        let id = RuleID(number: config.nextRuleNumber)
        config.rules.append(RoutingRule(id: id, match: match, identity: nil, binding: draft.binding))
        config.nextRuleNumber += 1
        return id
    }

    /// Replaces the match; id, identity and binding are kept.
    public static func update(_ id: RuleID, draft: RuleDraft, in config: inout AppConfig) throws(RuleEditError) {
        let index = try index(of: id, in: config)
        let validation = RuleValidator.validate(draft, existing: config.rules, editing: id)
        guard let match = validation.match else { throw .invalid(validation.errors) }
        config.rules[index].match = match
    }

    public static func delete(_ id: RuleID, from config: inout AppConfig) throws(RuleEditError) {
        config.rules.remove(at: try index(of: id, in: config))
    }

    /// `offset` -1 moves up one place, +1 down one place.
    public static func move(_ id: RuleID, by offset: Int, in config: inout AppConfig) throws(RuleEditError) {
        let index = try index(of: id, in: config)
        let target = index + offset
        guard abs(offset) == 1, config.rules.indices.contains(target) else { throw .cannotMove }
        config.rules.swapAt(index, target)
    }

    private static func index(of id: RuleID, in config: AppConfig) throws(RuleEditError) -> Int {
        guard id != .fallback else { throw .fallbackImmutable }
        guard let index = config.rules.firstIndex(where: { $0.id == id }) else { throw .ruleNotFound }
        return index
    }
}
