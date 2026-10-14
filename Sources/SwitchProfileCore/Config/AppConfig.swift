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

/// Fixed per-rule targets. A struct (not a dictionary) so it encodes as a JSON object
/// and synthesized decoding requires all four keys.
public struct RuleTargets: Codable, Equatable, Sendable {
    public var R1: RuleTarget
    public var R2: RuleTarget
    public var R3: RuleTarget
    public var R4: RuleTarget

    public init(R1: RuleTarget, R2: RuleTarget, R3: RuleTarget, R4: RuleTarget) {
        self.R1 = R1
        self.R2 = R2
        self.R3 = R3
        self.R4 = R4
    }

    public subscript(rule: RuleID) -> RuleTarget {
        get {
            switch rule {
            case .r1: R1
            case .r2: R2
            case .r3: R3
            case .r4: R4
            }
        }
        set {
            switch rule {
            case .r1: R1 = newValue
            case .r2: R2 = newValue
            case .r3: R3 = newValue
            case .r4: R4 = newValue
            }
        }
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

/// Configuration file schema version 1.
public struct AppConfig: Codable, Equatable, Sendable {
    /// Must be 1.
    public var schemaVersion: Int
    /// True until the first successful seed.
    public var seedPending: Bool
    public var targets: RuleTargets
    public var previousDefaultBrowser: DefaultBrowserRecord?

    public init(schemaVersion: Int, seedPending: Bool, targets: RuleTargets, previousDefaultBrowser: DefaultBrowserRecord?) {
        self.schemaVersion = schemaVersion
        self.seedPending = seedPending
        self.targets = targets
        self.previousDefaultBrowser = previousDefaultBrowser
    }

    public static let currentSchemaVersion = 1

    /// Built-in identities, no bindings, seeding pending.
    public static let unseededDefault = AppConfig(
        schemaVersion: currentSchemaVersion,
        seedPending: true,
        targets: RuleTargets(
            R1: RuleTarget(identity: "khuepm18"),
            R2: RuleTarget(identity: "khue@truckerpoints.ai"),
            R3: RuleTarget(identity: "pmkhue.2013"),
            R4: RuleTarget()
        ),
        previousDefaultBrowser: nil
    )
}
