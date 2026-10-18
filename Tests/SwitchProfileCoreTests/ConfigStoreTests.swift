import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct ConfigStoreTests {
    static let utc = TimeZone(identifier: "UTC")!

    static func sampleConfig() -> AppConfig {
        var config = AppConfig.unseededDefault
        config.seedPending = false
        config.setBinding(ProfileBinding(directory: "Profile 30", email: "khuepm18@example.com", displayName: "khuepm18", matchedBy: .displayName), for: .r1)
        config.setBinding(ProfileBinding(directory: "Profile 9", email: nil, displayName: "Guest", matchedBy: nil), for: .r4)
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

    @Test func encodingOmitsNilOptionalsAndRulesIsAnOrderedList() throws {
        let data = try JSONEncoder().encode(AppConfig.unseededDefault)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["schemaVersion", "seedPending", "rules", "fallback", "nextRuleNumber"])
        #expect(json["schemaVersion"] as? Int == 2)
        #expect(json["nextRuleNumber"] as? Int == 5)
        #expect(json["targets"] == nil)
        let rules = try #require(json["rules"] as? [[String: Any]])
        #expect(rules.map { $0["id"] as? String } == ["R1", "R2", "R3"])
        let r1 = rules[0]
        #expect(Set(r1.keys) == ["id", "match", "identity"])
        #expect(r1["identity"] as? String == "khuepm18")
        #expect(r1["match"] as? [String: String] == ["type": "host", "host": "git.fis.vn"])
        #expect(rules[1]["match"] as? [String: String]
            == ["type": "hostPathPrefix", "host": "github.com", "pathPrefix": "/TruckerPoints/trucker-points"])
        let fallback = try #require(json["fallback"] as? [String: Any])
        #expect(fallback.isEmpty)

        let signedOut = ProfileBinding(directory: "Profile 9", email: nil, displayName: "Guest", matchedBy: nil)
        let bindingJSON = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(signedOut)) as? [String: Any])
        #expect(Set(bindingJSON.keys) == ["directory", "displayName"])
    }

    @Test func decodingAcceptsAbsentAndNullOptionals() throws {
        let json = #"""
        {"schemaVersion":2,"seedPending":true,"previousDefaultBrowser":null,"nextRuleNumber":5,
         "rules":[{"id":"R1","match":{"type":"host","host":"git.fis.vn"},"identity":null,
                   "binding":{"directory":"Default","email":null,"displayName":"P","matchedBy":null}},
                  {"id":"R2","match":{"type":"host","host":"a.example"}},
                  {"id":"R3","match":{"type":"host","host":"b.example"},"binding":null}],
         "fallback":{"identity":"x"}}
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.previousDefaultBrowser == nil)
        #expect(config.target(.r1) == RuleTarget(identity: nil, binding: ProfileBinding(directory: "Default", email: nil, displayName: "P", matchedBy: nil)))
        #expect(config.target(.r2) == RuleTarget())
        #expect(config.target(.r3) == RuleTarget())
        #expect(config.target(.r4) == RuleTarget(identity: "x"))
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
        #expect(config.binding(for: .r1)?.matchedBy == .displayName)
        #expect(config.binding(for: .r2)?.directory == "Profile 47")
        #expect(config.target(.r3) == RuleTarget(identity: "pmkhue.2013"))
        #expect(config.target(.r4) == RuleTarget())
        #expect(config.previousDefaultBrowser?.bundleIdentifier == "com.google.Chrome")
    }

    @Test func absentFile() {
        let dir = TempDir()
        defer { dir.cleanup() }
        #expect(ConfigStore(fileURL: dir.url.appendingPathComponent("config.json")).load() == .absent)
    }

    @Test(arguments: ["config-corrupt", "config-missing-r4", "config-missing-seedpending", "config-bad-directory",
                      "config-v2-corrupt"])
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
        let file = try installFixture("config-v3", in: dir)
        let before = try Data(contentsOf: file)
        #expect(ConfigStore(fileURL: file).load() == .unavailable(.unsupportedVersion(3)))
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
