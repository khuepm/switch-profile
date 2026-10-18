import Foundation

/// A problem with a stored rule's position in the list. Never blocks routing: the first match wins.
public enum RuleIssue: Equatable, Sendable {
    /// An earlier rule matches exactly the same links (only possible in a hand-edited file).
    case duplicate(of: RuleID)
    /// An earlier, broader rule matches every link this rule matches, so this rule never matches.
    case shadowed(by: RuleID)
}

/// Pure checks over the ordered rule list, for Settings.
public enum RuleAnalysis {
    /// At most one issue per rule, naming the first earlier rule that duplicates or shadows it.
    /// The fallback is never flagged and never shadows.
    public static func issues(_ config: AppConfig) -> [RuleID: RuleIssue] {
        var result: [RuleID: RuleIssue] = [:]
        for (index, rule) in config.rules.enumerated() {
            for earlier in config.rules[..<index] {
                if earlier.match.key == rule.match.key {
                    result[rule.id] = .duplicate(of: earlier.id)
                    break
                }
                if alwaysWins(earlier.match, over: rule.match) {
                    result[rule.id] = .shadowed(by: earlier.id)
                    break
                }
            }
        }
        return result
    }

    /// True when every URL `later` matches is also matched by `earlier` (and the two differ).
    /// Same host is required: an exact host rule covers everything on that host; a path prefix covers
    /// a strictly longer prefix that starts with its segments (the last one also as `<segment>.git`).
    static func alwaysWins(_ earlier: RuleMatch, over later: RuleMatch) -> Bool {
        guard earlier.host == later.host, earlier.key != later.key else { return false }
        switch (earlier, later) {
        case (.host, _):
            return true
        case (.hostPathPrefix, .host):
            return false
        case (.hostPathPrefix, .hostPathPrefix):
            let broad = earlier.prefixSegments
            let narrow = later.prefixSegments
            guard !broad.isEmpty, broad.count < narrow.count else { return false }
            let last = broad.count - 1
            guard Array(narrow[..<last]) == Array(broad[..<last]) else { return false }
            return narrow[last] == broad[last] || narrow[last] == broad[last] + ".git"
        }
    }
}
