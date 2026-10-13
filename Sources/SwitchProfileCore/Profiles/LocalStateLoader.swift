import Foundation

/// Reads Chrome's `Local State` file into a `ProfileCatalog`. Reads exactly one file and never writes.
public enum LocalStateLoader {
    public static func load(from fileURL: URL) throws(LocalStateError) -> ProfileCatalog {
        let path = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw .notFound(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw .notFound(path)
        } catch {
            throw .unreadable(path, error.localizedDescription)
        }
        return try parse(data)
    }

    public static func parse(_ data: Data) throws(LocalStateError) -> ProfileCatalog {
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: data)
        } catch let error as DecodingError {
            throw .malformed(error.summary)
        } catch {
            throw .malformed(error.localizedDescription)
        }

        var profiles: [ChromeProfile] = []
        for (key, entry) in root.profile.info_cache {
            guard isValidDirectoryKey(key) else {
                Log.profiles.error("Skipped invalid Local State profile key \(key, privacy: .public)")
                continue
            }
            let displayName = (entry.name?.isEmpty == false) ? entry.name! : key
            profiles.append(ChromeProfile(directory: key, displayName: displayName, email: normalizedEmail(entry.user_name)))
        }
        guard !profiles.isEmpty else { throw .noProfiles }
        return ProfileCatalog(profiles: profiles)
    }

    /// Directory key pattern `^[A-Za-z0-9 ._-]{1,255}$`, not `.` or `..`, no leading `-`.
    /// Shared with `ProfileBinding` decoding so persisted directories obey the same rule.
    static func isValidDirectoryKey(_ key: String) -> Bool {
        let scalars = key.unicodeScalars
        guard (1...255).contains(scalars.count), key != ".", key != "..", !key.hasPrefix("-") else {
            return false
        }
        return scalars.allSatisfy { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", " ", ".", "_", "-": return true
            default: return false
            }
        }
    }

    /// Trimmed; empty becomes nil.
    static func normalizedEmail(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // Minimal view of Local State; unknown keys are ignored.
    private struct Root: Decodable {
        let profile: ProfileSection
    }

    private struct ProfileSection: Decodable {
        let info_cache: [String: Entry]
    }

    private struct Entry: Decodable {
        let name: String?
        let user_name: String?
        let gaia_name: String?
    }
}
