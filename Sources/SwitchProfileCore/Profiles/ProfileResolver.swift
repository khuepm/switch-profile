import Foundation

/// How an identity matched a profile. Persisted in `ProfileBinding.matchedBy` for auto-detected bindings.
public enum MatchKind: String, Codable, Sendable {
    case email, displayName, localPart
}

/// Resolves a human identity (email, display name or email local part) to a Chrome profile.
public enum ProfileResolver {
    public enum Resolution: Equatable, Sendable {
        /// Exactly one profile matched; `matchedBy` is the strongest kind that matched (email > displayName > localPart).
        case unique(ChromeProfile, matchedBy: MatchKind)
        /// More than one profile matched; sorted by directory key. No directory is chosen.
        case ambiguous([ChromeProfile])
        case notFound
    }

    /// Union of email / display-name / local-part matches, case-insensitive, de-duplicated by directory.
    public static func resolve(identity: String, in catalog: ProfileCatalog) -> Resolution {
        let needle = identity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return .notFound }
        let hasAt = needle.contains("@")

        var matches: [(profile: ChromeProfile, kind: MatchKind)] = []
        for profile in catalog.profiles {
            if let kind = strongestMatch(needle: needle, hasAt: hasAt, profile: profile) {
                matches.append((profile, kind))
            }
        }

        switch matches.count {
        case 0:
            return .notFound
        case 1:
            return .unique(matches[0].profile, matchedBy: matches[0].kind)
        default:
            // catalog.profiles is unique by directory and sorted, so matches already are too.
            return .ambiguous(matches.map(\.profile).sorted { $0.directory < $1.directory })
        }
    }

    private static func strongestMatch(needle: String, hasAt: Bool, profile: ChromeProfile) -> MatchKind? {
        let email = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hasAt, let email, email == needle {
            return .email
        }
        if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle {
            return .displayName
        }
        if !hasAt, let email, let at = email.lastIndex(of: "@"), String(email[..<at]) == needle {
            return .localPart
        }
        return nil
    }
}
