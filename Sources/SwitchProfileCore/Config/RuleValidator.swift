import Foundation

/// The rule editor's input: what the user typed, before validation.
public struct RuleDraft: Equatable, Sendable {
    public var matchType: RuleMatchType
    public var host: String
    /// Used only for `.hostPathPrefix`.
    public var pathPrefix: String
    /// Profile for a new rule; ignored when editing (the row's profile picker changes it).
    public var binding: ProfileBinding?

    public init(matchType: RuleMatchType, host: String, pathPrefix: String = "", binding: ProfileBinding? = nil) {
        self.matchType = matchType
        self.host = host
        self.pathPrefix = pathPrefix
        self.binding = binding
    }

    /// The draft that edits `rule` unchanged.
    public init(rule: RoutingRule) {
        self.init(matchType: rule.match.type, host: rule.match.host,
                  pathPrefix: rule.match.pathPrefix ?? "", binding: rule.binding)
    }
}

/// Which editor field an error belongs to.
public enum RuleField: Equatable, Sendable {
    case host
    case path
    /// The rule as a whole (duplicates).
    case rule
}

public enum RuleFieldError: Equatable, Sendable {
    case emptyHost
    /// `*` is not supported; rules match exact hosts only.
    case wildcardHost
    /// A scheme, path, port, userinfo, whitespace or an invalid label.
    case invalidHost
    case emptyPath
    case pathMissingLeadingSlash
    /// `/` alone; an exact host rule does that.
    case pathIsRoot
    /// `?`, `#`, whitespace, an empty segment, a `.` or `..` segment, or bad percent-encoding.
    case invalidPath
    /// Another rule already matches exactly the same links.
    case duplicate(of: RuleID)

    public var field: RuleField {
        switch self {
        case .emptyHost, .wildcardHost, .invalidHost: .host
        case .emptyPath, .pathMissingLeadingSlash, .pathIsRoot, .invalidPath: .path
        case .duplicate: .rule
        }
    }
}

/// `match` is non-nil exactly when `errors` is empty.
public struct RuleValidation: Equatable, Sendable {
    public let match: RuleMatch?
    public let errors: [RuleFieldError]

    public var isValid: Bool { errors.isEmpty }

    public func errors(for field: RuleField) -> [RuleFieldError] {
        errors.filter { $0.field == field }
    }
}

/// Pure validation of rule drafts, shared by Settings and configuration decoding.
public enum RuleValidator {
    static let maxLabelLength = 63
    static let maxHostLength = 253

    /// Syntax checks plus the duplicate check against `existing`, ignoring the rule being edited.
    public static func validate(_ draft: RuleDraft, existing: [RoutingRule], editing: RuleID?) -> RuleValidation {
        let syntax = match(type: draft.matchType, host: draft.host, pathPrefix: draft.pathPrefix)
        guard let candidate = syntax.match else { return syntax }
        if let other = existing.first(where: { $0.id != editing && $0.match.key == candidate.key }) {
            return RuleValidation(match: nil, errors: [.duplicate(of: other.id)])
        }
        return syntax
    }

    /// Syntax checks only; every field error is reported. A valid result is normalized.
    static func match(type: RuleMatchType, host rawHost: String, pathPrefix rawPath: String) -> RuleValidation {
        var errors: [RuleFieldError] = []
        let host = validateHost(rawHost, errors: &errors)
        var path: String?
        if type == .hostPathPrefix {
            path = validatePath(rawPath, errors: &errors)
        }
        guard errors.isEmpty, let host else { return RuleValidation(match: nil, errors: errors) }
        switch type {
        case .host:
            return RuleValidation(match: .host(host), errors: [])
        case .hostPathPrefix:
            guard let path else { return RuleValidation(match: nil, errors: [.invalidPath]) }
            return RuleValidation(match: .hostPathPrefix(host: host, pathPrefix: path), errors: [])
        }
    }

    private static func validateHost(_ raw: String, errors: inout [RuleFieldError]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errors.append(.emptyHost)
            return nil
        }
        guard !trimmed.contains("*") else {
            errors.append(.wildcardHost)
            return nil
        }
        let forbidden = CharacterSet(charactersIn: "/:@?#[]").union(.whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: forbidden) == nil,
              let parsed = URLComponents(string: "https://\(trimmed)/")?.host, !parsed.isEmpty
        else {
            errors.append(.invalidHost)
            return nil
        }
        let host = HostName.normalize(parsed)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !host.isEmpty, host.utf8.count <= maxHostLength,
              labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= maxLabelLength })
        else {
            errors.append(.invalidHost)
            return nil
        }
        return host
    }

    private static func validatePath(_ raw: String, errors: inout [RuleFieldError]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errors.append(.emptyPath)
            return nil
        }
        guard trimmed.hasPrefix("/") else {
            errors.append(.pathMissingLeadingSlash)
            return nil
        }
        guard trimmed != "/" else {
            errors.append(.pathIsRoot)
            return nil
        }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "?#").union(.whitespacesAndNewlines)) == nil else {
            errors.append(.invalidPath)
            return nil
        }
        var path = trimmed
        if path.hasSuffix("/") { path.removeLast() }
        let pieces = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && String($0).removingPercentEncoding != nil })
        else {
            errors.append(.invalidPath)
            return nil
        }
        return path
    }
}
