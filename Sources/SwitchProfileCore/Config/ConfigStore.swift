import Foundation

/// Loads and saves the configuration file at an injected URL. Only `ConfigController` holds one.
public struct ConfigStore: Sendable {
    public let fileURL: URL
    private let writeData: @Sendable (Data, URL) throws -> Void

    public init(fileURL: URL) {
        self.init(fileURL: fileURL, writeData: { try $0.write(to: $1, options: .atomic) })
    }

    /// Test seam: replaces the atomic write so a save can fail after a successful backup.
    init(fileURL: URL, writeData: @escaping @Sendable (Data, URL) throws -> Void) {
        self.fileURL = fileURL
        self.writeData = writeData
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    /// Two-pass decode: the version probe first, then the full schema.
    public func load() -> ConfigState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .absent
        } catch {
            return failed(.unreadable(error.localizedDescription))
        }

        let version: Int
        do {
            version = try JSONDecoder().decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            return failed(.corrupt(Self.summary(error)))
        }
        // Version 1 is migrated in memory; the file is only rewritten (as the current version) by
        // the next successful save. Any other version, including a newer one, is never touched.
        do {
            switch version {
            case 1:
                return .loaded(ConfigMigration.v2(from: try JSONDecoder().decode(AppConfigV1.self, from: data)))
            case AppConfig.currentSchemaVersion:
                return .loaded(try JSONDecoder().decode(AppConfig.self, from: data))
            default:
                return failed(.unsupportedVersion(version))
            }
        } catch {
            return failed(.corrupt(Self.summary(error)))
        }
    }

    /// Atomic write; directory created as 0700, file set to 0600 after every write.
    public func save(_ config: AppConfig) throws(ConfigError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let fileManager = FileManager.default
        do {
            let data = try encoder.encode(config)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            try writeData(data, fileURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.config.error("Saving configuration failed: \(error.localizedDescription, privacy: .public)")
            throw .writeFailed(error.localizedDescription)
        }
    }

    /// Renames the current file to `config.corrupt-<yyyyMMdd-HHmmss>[-N].json` in the same directory.
    /// Returns nil when there is no file to back up (it was removed in the meantime).
    @discardableResult
    public func backupCorruptFile(now: Date, timeZone: TimeZone = .current) throws(ConfigError) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = "\(fileURL.deletingPathExtension().lastPathComponent).corrupt-\(formatter.string(from: now))"
        let directory = fileURL.deletingLastPathComponent()

        for suffix in [""] + (2...99).map({ "-\($0)" }) {
            let candidate = directory.appendingPathComponent("\(stem)\(suffix).json")
            guard !fileManager.fileExists(atPath: candidate.path) else { continue }
            do {
                try fileManager.moveItem(at: fileURL, to: candidate)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                Log.config.error("Backing up configuration failed: \(error.localizedDescription, privacy: .public)")
                throw .writeFailed(error.localizedDescription)
            }
            Log.config.notice("Backed up configuration to \(candidate.lastPathComponent, privacy: .public)")
            return candidate
        }
        Log.config.error("Backing up configuration failed: backup name exhausted")
        throw .writeFailed("backup name exhausted")
    }

    private func failed(_ error: ConfigError) -> ConfigState {
        Log.config.error("Configuration unavailable: \(String(describing: error), privacy: .public)")
        return .unavailable(error)
    }

    private static func summary(_ error: any Error) -> String {
        (error as? DecodingError)?.summary ?? error.localizedDescription
    }
}
