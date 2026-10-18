import Foundation

/// The Chrome profile a rule routes to, persisted as directory plus an email snapshot.
public struct ProfileBinding: Codable, Equatable, Sendable {
    /// Routing key (`--profile-directory`). Decoding validates it with the Local State key pattern.
    public var directory: String
    /// Profile `user_name` at bind time; nil means the profile was signed out.
    public var email: String?
    /// Display snapshot only; never compared.
    public var displayName: String
    /// Non-nil only for unconfirmed auto-detected (seeded) bindings. UI only, never used for routing.
    public var matchedBy: MatchKind?

    public init(directory: String, email: String?, displayName: String, matchedBy: MatchKind?) {
        self.directory = directory
        self.email = email
        self.displayName = displayName
        self.matchedBy = matchedBy
    }
}

extension ProfileBinding {
    // Declared in an extension so they never suppress the explicit memberwise init above.

    /// Binds to `profile`; the email is normalized (trimmed, empty → nil).
    public init(profile: ChromeProfile, matchedBy: MatchKind?) {
        self.init(directory: profile.directory,
                  email: LocalStateLoader.normalizedEmail(profile.email),
                  displayName: profile.displayName,
                  matchedBy: matchedBy)
    }

    /// Decodes, then validates `directory`; an invalid key throws `DecodingError.dataCorrupted`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let directory = try container.decode(String.self, forKey: .directory)
        guard LocalStateLoader.isValidDirectoryKey(directory) else {
            throw DecodingError.dataCorruptedError(forKey: .directory, in: container,
                                                   debugDescription: "invalid profile directory key")
        }
        self.init(directory: directory,
                  email: try container.decodeIfPresent(String.self, forKey: .email),
                  displayName: try container.decode(String.self, forKey: .displayName),
                  matchedBy: try container.decodeIfPresent(MatchKind.self, forKey: .matchedBy))
    }
}

public struct RuleTarget: Codable, Equatable, Sendable {
    /// Human label used by seeding, Detect and display; routing ignores it.
    public var identity: String?
    public var binding: ProfileBinding?

    public init(identity: String? = nil, binding: ProfileBinding? = nil) {
        self.identity = identity
        self.binding = binding
    }
}

public struct DefaultBrowserRecord: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var path: String

    public init(bundleIdentifier: String, path: String) {
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }
}

/// One user-editable routing rule. The fallback is not a `RoutingRule`; it is `AppConfig.fallback`.
public struct RoutingRule: Codable, Equatable, Sendable {
    public var id: RuleID
    public var match: RuleMatch
    /// Human label used by seeding, Detect and display; routing ignores it.
    public var identity: String?
    public var binding: ProfileBinding?

    public init(id: RuleID, match: RuleMatch, identity: String? = nil, binding: ProfileBinding? = nil) {
        self.id = id
        self.match = match
        self.identity = identity
        self.binding = binding
    }

    public var target: RuleTarget {
        RuleTarget(identity: identity, binding: binding)
    }
}

/// Configuration file schema version 2: an ordered, user-editable rule list plus the fallback.
public struct AppConfig: Equatable, Sendable {
    /// Must be `currentSchemaVersion`.
    public var schemaVersion: Int
    /// True until the first successful seed.
    public var seedPending: Bool
    /// Evaluated top to bottom; the first match wins. Never contains the fallback id.
    public var rules: [RoutingRule]
    /// Used when no rule matches. A nil binding means "Last active Chrome profile".
    public var fallback: RuleTarget
    /// The number of the next added rule (`R<n>`); only ever increases, so ids are never reused.
    public var nextRuleNumber: Int
    public var previousDefaultBrowser: DefaultBrowserRecord?

    public init(schemaVersion: Int = AppConfig.currentSchemaVersion, seedPending: Bool, rules: [RoutingRule],
                fallback: RuleTarget, nextRuleNumber: Int = AppConfig.firstUserRuleNumber,
                previousDefaultBrowser: DefaultBrowserRecord?) {
        self.schemaVersion = schemaVersion
        self.seedPending = seedPending
        self.rules = rules
        self.fallback = fallback
        self.nextRuleNumber = nextRuleNumber
        self.previousDefaultBrowser = previousDefaultBrowser
    }

    public static let currentSchemaVersion = 2
    /// `R1`–`R3` are the defaults and `R4` is the fallback, so added rules start at `R5`.
    public static let firstUserRuleNumber = 5

    /// The built-in rules, in order, with their identities and no bindings.
    public static let defaultRules: [RoutingRule] = [
        RoutingRule(id: .r1, match: .host("git.fis.vn"), identity: "khuepm18"),
        RoutingRule(id: .r2, match: .hostPathPrefix(host: "github.com", pathPrefix: "/TruckerPoints/trucker-points"),
                    identity: "khue@truckerpoints.ai"),
        RoutingRule(id: .r3, match: .host("github.com"), identity: "pmkhue.2013"),
    ]

    /// Built-in rules and identities, no bindings, seeding pending.
    public static let unseededDefault = AppConfig(
        seedPending: true,
        rules: defaultRules,
        fallback: RuleTarget(),
        previousDefaultBrowser: nil
    )

    // MARK: Accessors

    /// Evaluation order: the rules, then the fallback.
    public var ruleOrder: [RuleID] {
        rules.map(\.id) + [.fallback]
    }

    public func rule(_ id: RuleID) -> RoutingRule? {
        rules.first { $0.id == id }
    }

    /// The rule's identity and binding; the fallback's for `.fallback`; nil for an unknown id.
    public func target(_ id: RuleID) -> RuleTarget? {
        id == .fallback ? fallback : rule(id)?.target
    }

    /// True for the fallback and every rule in `rules`.
    public func contains(_ id: RuleID) -> Bool {
        target(id) != nil
    }

    public func binding(for id: RuleID) -> ProfileBinding? {
        target(id)?.binding
    }

    public func identity(for id: RuleID) -> String? {
        target(id)?.identity
    }

    /// Returns false (and changes nothing) for an unknown id.
    @discardableResult
    public mutating func setBinding(_ binding: ProfileBinding?, for id: RuleID) -> Bool {
        if id == .fallback {
            fallback.binding = binding
            return true
        }
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return false }
        rules[index].binding = binding
        return true
    }
}

extension AppConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, seedPending, rules, fallback, nextRuleNumber, previousDefaultBrowser
    }

    /// Rejects (as `DecodingError.dataCorrupted`) invalid or duplicate ids, the fallback id inside
    /// `rules`, invalid matches, and a `nextRuleNumber` that could reuse an id. Duplicate or shadowed
    /// matches are allowed (the first match wins); Settings flags them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rules = try container.decode([RoutingRule].self, forKey: .rules)
        var seen: Set<RuleID> = []
        for rule in rules {
            guard rule.id != .fallback else {
                throw DecodingError.dataCorruptedError(forKey: .rules, in: container,
                                                       debugDescription: "the fallback \(rule.id) cannot be a rule")
            }
            guard seen.insert(rule.id).inserted else {
                throw DecodingError.dataCorruptedError(forKey: .rules, in: container,
                                                       debugDescription: "duplicate rule id \(rule.id)")
            }
        }
        let nextRuleNumber = try container.decode(Int.self, forKey: .nextRuleNumber)
        let highest = rules.map(\.id.number).max() ?? 0
        guard nextRuleNumber >= Self.firstUserRuleNumber, nextRuleNumber > highest else {
            throw DecodingError.dataCorruptedError(forKey: .nextRuleNumber, in: container,
                                                   debugDescription: "nextRuleNumber \(nextRuleNumber) could reuse a rule id")
        }
        self.init(schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
                  seedPending: try container.decode(Bool.self, forKey: .seedPending),
                  rules: rules,
                  fallback: try container.decode(RuleTarget.self, forKey: .fallback),
                  nextRuleNumber: nextRuleNumber,
                  previousDefaultBrowser: try container.decodeIfPresent(DefaultBrowserRecord.self,
                                                                        forKey: .previousDefaultBrowser))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(seedPending, forKey: .seedPending)
        try container.encode(rules, forKey: .rules)
        try container.encode(fallback, forKey: .fallback)
        try container.encode(nextRuleNumber, forKey: .nextRuleNumber)
        try container.encodeIfPresent(previousDefaultBrowser, forKey: .previousDefaultBrowser)
    }
}
