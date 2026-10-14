import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct ConfigStoreTests {
    static let utc = TimeZone(identifier: "UTC")!

    static func sampleConfig() -> AppConfig {
        var config = AppConfig.unseededDefault
        config.seedPending = false
        config.targets.R1.binding = ProfileBinding(directory: "Profile 30", email: "khuepm18@example.com", displayName: "khuepm18", matchedBy: .displayName)
        config.targets.R4.binding = ProfileBinding(directory: "Profile 9", email: nil, displayName: "Guest", matchedBy: nil)
        config.previousDefaultBrowser = DefaultBrowserRecord(bundleIdentifier: "com.google.Chrome", path: "/Applications/Google Chrome.app")
        return config
    }

    private func posixMode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as! NSNumber).intValue & 0o777
    }

    private func installFixture(_ name: String, in dir: TempDir) throws -> URL {
        let file = dir.url.appendingPathComponent("config.json")
        try Fixture.data(name).write(to: file)
        return file
    }

    // MARK: AppConfig coding (pure Data level)

    @Test func encodingOmitsNilOptionalsAndTargetsIsAnObject() throws {
        let data = try JSONEncoder().encode(AppConfig.unseededDefault)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["previousDefaultBrowser"] == nil)
        let targets = try #require(json["targets"] as? [String: Any])
        #expect(Set(targets.keys) == ["R1", "R2", "R3", "R4"])
        let r1 = try #require(targets["R1"] as? [String: Any])
        #expect(r1["identity"] as? String == "khuepm18")
        #expect(r1["binding"] == nil)
        let r4 = try #require(targets["R4"] as? [String: Any])
        #expect(r4.isEmpty)

        let signedOut = ProfileBinding(directory: "Profile 9", email: nil, displayName: "Guest", matchedBy: nil)
        let bindingJSON = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(signedOut)) as? [String: Any])
        #expect(Set(bindingJSON.keys) == ["directory", "displayName"])
    }

    @Test func decodingAcceptsAbsentAndNullOptionals() throws {
        let json = #"""
        {"schemaVersion":1,"seedPending":true,"previousDefaultBrowser":null,
         "targets":{"R1":{"identity":null,"binding":{"directory":"Default","email":null,"displayName":"P","matchedBy":null}},
                    "R2":{},"R3":{"binding":null},"R4":{"identity":"x"}}}
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.previousDefaultBrowser == nil)
        #expect(config.targets.R1 == RuleTarget(identity: nil, binding: ProfileBinding(directory: "Default", email: nil, displayName: "P", matchedBy: nil)))
        #expect(config.targets.R2 == RuleTarget())
        #expect(config.targets.R3 == RuleTarget())
        #expect(config.targets.R4 == RuleTarget(identity: "x"))
    }

    @Test func roundTrip() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let store = ConfigStore(fileURL: dir.url.appendingPathComponent("config.json"))
        try store.save(Self.sampleConfig())
        #expect(store.load() == .loaded(Self.sampleConfig()))
    }

    @Test func validFixtureLoads() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let store = ConfigStore(fileURL: try installFixture("config-v1-valid", in: dir))
        guard case .loaded(let config) = store.load() else {
            Issue.record("expected .loaded")
            return
        }
        #expect(config.seedPending == false)
        #expect(config.targets.R1.binding?.matchedBy == .displayName)
        #expect(config.targets.R2.binding?.directory == "Profile 47")
        #expect(config.targets.R3 == RuleTarget(identity: "pmkhue.2013"))
        #expect(config.targets.R4 == RuleTarget())
        #expect(config.previousDefaultBrowser?.bundleIdentifier == "com.google.Chrome")
    }

    @Test func absentFile() {
        let dir = TempDir()
        defer { dir.cleanup() }
        #expect(ConfigStore(fileURL: dir.url.appendingPathComponent("config.json")).load() == .absent)
    }

    @Test(arguments: ["config-corrupt", "config-missing-r4", "config-missing-seedpending", "config-bad-directory"])
    func invalidFilesAreCorruptAndUntouched(_ fixture: String) throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try installFixture(fixture, in: dir)
        let before = try Data(contentsOf: file)
        let state = ConfigStore(fileURL: file).load()
        guard case .unavailable(.corrupt(let summary)) = state else {
            Issue.record("expected .corrupt, got \(state)")
            return
        }
        #expect(!summary.isEmpty)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func versionProbeRunsFirst() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try installFixture("config-v2", in: dir)
        let before = try Data(contentsOf: file)
        #expect(ConfigStore(fileURL: file).load() == .unavailable(.unsupportedVersion(2)))
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func stringSchemaVersionIsCorrupt() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = dir.url.appendingPathComponent("config.json")
        var json = String(decoding: Fixture.data("config-v1-valid"), as: UTF8.self)
        json = json.replacingOccurrences(of: #""schemaVersion": 1"#, with: #""schemaVersion": "1""#)
        try Data(json.utf8).write(to: file)
        guard case .unavailable(.corrupt) = ConfigStore(fileURL: file).load() else {
            Issue.record("expected .corrupt")
            return
        }
    }

    @Test func unreadableFile() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try installFixture("config-v1-valid", in: dir)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        guard case .unavailable(.unreadable) = ConfigStore(fileURL: file).load() else {
            Issue.record("expected .unreadable")
            return
        }
    }

    @Test func fileAndDirectoryModes() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let supportDir = dir.url.appendingPathComponent("SwitchProfile", isDirectory: true)
        let file = supportDir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)

        try store.save(Self.sampleConfig())
        #expect(try posixMode(file) == 0o600)
        #expect(try posixMode(supportDir) == 0o700)

        var changed = Self.sampleConfig()
        changed.seedPending = true
        try store.save(changed)
        #expect(try posixMode(file) == 0o600)
        #expect(store.load() == .loaded(changed))
    }

    @Test func writerFailureIsWriteFailed() {
        let dir = TempDir()
        defer { dir.cleanup() }
        let store = ConfigStore(fileURL: dir.url.appendingPathComponent("config.json"),
                                writeData: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        do {
            try store.save(Self.sampleConfig())
            Issue.record("expected .writeFailed")
        } catch {
            guard case .writeFailed = error else {
                Issue.record("expected .writeFailed, got \(error)")
                return
            }
        }
    }

    @Test func backupNameUsesInjectedDateAndCollisionSuffix() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = dir.url.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)
        let epoch = Date(timeIntervalSince1970: 0)

        try Data("{".utf8).write(to: file)
        let first = try #require(try store.backupCorruptFile(now: epoch, timeZone: Self.utc))
        #expect(first.lastPathComponent == "config.corrupt-19700101-000000.json")
        #expect(!FileManager.default.fileExists(atPath: file.path))

        try Data("second".utf8).write(to: file)
        let second = try #require(try store.backupCorruptFile(now: epoch, timeZone: Self.utc))
        #expect(second.lastPathComponent == "config.corrupt-19700101-000000-2.json")

        #expect(try Data(contentsOf: first) == Data("{".utf8))
        #expect(try Data(contentsOf: second) == Data("second".utf8))
    }

    @Test func backupUsesPOSIXLocaleAndGivenTimeZone() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = dir.url.appendingPathComponent("config.json")
        try Data("{".utf8).write(to: file)
        // 2025-10-13 04:35:00 UTC is 11:35:00 in UTC+7.
        let date = Date(timeIntervalSince1970: 1_760_330_100)
        let backup = try #require(try ConfigStore(fileURL: file).backupCorruptFile(now: date, timeZone: TimeZone(secondsFromGMT: 7 * 3600)!))
        #expect(backup.lastPathComponent == "config.corrupt-20251013-113500.json")
    }

    @Test func backupOfMissingFileIsTolerated() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let store = ConfigStore(fileURL: dir.url.appendingPathComponent("config.json"))
        #expect(try store.backupCorruptFile(now: Date(), timeZone: Self.utc) == nil)
    }

    @Test func backupNameExhausted() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = dir.url.appendingPathComponent("config.json")
        let names = ["config.corrupt-19700101-000000.json"] + (2...99).map { "config.corrupt-19700101-000000-\($0).json" }
        for name in names {
            try Data().write(to: dir.url.appendingPathComponent(name))
        }
        try Data("{".utf8).write(to: file)
        #expect(throws: ConfigError.writeFailed("backup name exhausted")) {
            try ConfigStore(fileURL: file).backupCorruptFile(now: Date(timeIntervalSince1970: 0), timeZone: Self.utc)
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
