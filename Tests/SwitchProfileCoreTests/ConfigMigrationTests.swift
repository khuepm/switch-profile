import Foundation
import Testing
@testable import SwitchProfileCore

/// #14: schema version 1 (four fixed rules) migrates in memory to version 2 (an editable rule list)
/// with identical routing; the file is rewritten only by the next successful save. Corrupt and newer
/// files are never overwritten.
@MainActor
@Suite struct ConfigMigrationTests {
    static let catalog = CatalogState.loaded(Fixture.validCatalog())

    private func install(_ name: String, in dir: TempDir) throws -> URL {
        let file = dir.url.appendingPathComponent("config.json")
        try Fixture.data(name).write(to: file)
        return file
    }

    private func modificationDate(_ file: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
    }

    private func loaded(_ file: URL) throws -> AppConfig {
        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        guard case .loaded(let config) = controller.state else {
            throw Failure("expected a loaded config, got \(controller.state)")
        }
        return config
    }

    private func json(_ file: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    // MARK: Migration

    @Test func v1ValidMigratesToEquivalentRules() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let config = try loaded(try install("config-v1-valid", in: dir))
        #expect(config.schemaVersion == 2)
        #expect(config.seedPending == false)
        #expect(config.rules.map(\.id) == [.r1, .r2, .r3])
        #expect(config.rules.map(\.match) == [
            .host("git.fis.vn"),
            .hostPathPrefix(host: "github.com", pathPrefix: "/TruckerPoints/trucker-points"),
            .host("github.com"),
        ])
        #expect(config.rules.map(\.identity) == ["khuepm18", "khue@truckerpoints.ai", "pmkhue.2013"])
        #expect(config.binding(for: .r1) == ProfileBinding(directory: "Profile 30", email: "khuepm18@example.com",
                                                          displayName: "khuepm18", matchedBy: .displayName))
        #expect(config.binding(for: .r2) == ProfileBinding(directory: "Profile 47", email: "khue@truckerpoints.ai",
                                                          displayName: "truckerpoints.ai", matchedBy: nil))
        #expect(config.binding(for: .r3) == nil)
        #expect(config.fallback == RuleTarget())
        #expect(config.nextRuleNumber == 5)
        #expect(config.ruleOrder == [.r1, .r2, .r3, .r4])
        #expect(config.previousDefaultBrowser == DefaultBrowserRecord(bundleIdentifier: "com.google.Chrome",
                                                                      path: "/Applications/Google Chrome.app"))
    }

    @Test func v1FixedFallbackMigrates() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let config = try loaded(try install("config-v1-fixed-fallback", in: dir))
        #expect(config.fallback.binding == ProfileBinding(directory: "Profile 8", email: "bob@example.com",
                                                          displayName: "Profile 8", matchedBy: nil))
        #expect(config.rules.map(\.id) == [.r1, .r2, .r3])
    }

    @Test func migrationDoesNotWrite() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install("config-v1-valid", in: dir)
        let bytes = try Data(contentsOf: file)
        let modified = try modificationDate(file)
        _ = try loaded(file)
        _ = Router.decide(URL(string: "https://github.com/x")!, config: .loaded(try loaded(file)), catalog: Self.catalog)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try modificationDate(file) == modified)
    }

    /// Every classifier vector routes to the same rule as before #14 when loaded from a v1 file.
    @Test func migratedRoutingIsIdentical() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let config = RoutingConfig.loaded(try loaded(try install("config-v1-valid", in: dir)))
        let expected: [(RuleID, [String])] = [
            (.r1, URLClassifierTests.r1), (.r2, URLClassifierTests.r2),
            (.r3, URLClassifierTests.r3), (.r4, URLClassifierTests.r4),
        ]
        for (rule, vectors) in expected {
            for string in vectors {
                let decision = Router.decide(URL(string: string)!, config: config, catalog: Self.catalog)
                switch decision {
                case .launch(let target, _): #expect(target.rule == rule, "\(string)")
                case .needsProfile(_, let decided, _, _): #expect(decided == rule, "\(string)")
                case .rejected: Issue.record("\(string) was rejected")
                }
            }
        }

        // README samples.
        func decide(_ string: String) -> RoutingDecision {
            Router.decide(URL(string: string)!, config: config, catalog: Self.catalog)
        }
        guard case .launch(let fis, _) = decide("https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests"),
              case .launch(let tp, _) = decide("https://github.com/TruckerPoints/trucker-points"),
              case .needsProfile(_, let lumi, .unset, _) = decide("https://github.com/khuepm/LumiBase"),
              case .launch(let other, _) = decide("https://example.com/")
        else {
            Issue.record("unexpected README sample decisions")
            return
        }
        #expect(fis.directory == "Profile 30")
        #expect(tp.directory == "Profile 47")
        #expect(lumi == .r3)
        #expect(other.rule == .r4)
        #expect(other.profile == .lastActiveChrome)
    }

    @Test func firstUpdateWritesV2() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install("config-v1-valid", in: dir)
        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        try controller.update { $0.setBinding(nil, for: .r1) }
        let object = try json(file)
        #expect(object["schemaVersion"] as? Int == 2)
        #expect(object["targets"] == nil)
        #expect((object["rules"] as? [[String: Any]])?.map { $0["id"] as? String } == ["R1", "R2", "R3"])
        #expect(object["fallback"] is [String: Any])
        #expect(object["nextRuleNumber"] as? Int == 5)
    }

    @Test func v2SurvivesRelaunch() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install("config-v1-valid", in: dir)
        let first = ConfigController(store: ConfigStore(fileURL: file))
        first.load()
        try first.update { _ in }
        guard case .loaded(let before) = first.state else {
            Issue.record("expected a loaded config")
            return
        }
        #expect(try loaded(file) == before)
    }

    @Test func v2ValidFixtureLoads() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let config = try loaded(try install("config-v2-valid", in: dir))
        #expect(config.ruleOrder == [.r1, .r2, RuleID(number: 5), .r3, .r4])
        #expect(config.rule(RuleID(number: 5))?.match == .host("example.org"))
        #expect(config.binding(for: RuleID(number: 5))?.directory == "Profile 8")
        #expect(config.nextRuleNumber == 6)
    }

    @Test func unseededDefaultEqualsMigratedV1Default() throws {
        let v1 = AppConfigV1(schemaVersion: 1, seedPending: true,
                             targets: RuleTargets(R1: RuleTarget(identity: "khuepm18"),
                                                  R2: RuleTarget(identity: "khue@truckerpoints.ai"),
                                                  R3: RuleTarget(identity: "pmkhue.2013"),
                                                  R4: RuleTarget()),
                             previousDefaultBrowser: nil)
        #expect(ConfigMigration.v2(from: v1) == AppConfig.unseededDefault)
    }

    // MARK: Never overwritten

    @Test(arguments: ["config-corrupt", "config-missing-r4", "config-missing-seedpending", "config-bad-directory"])
    func invalidV1FilesStayCorruptAndUntouched(_ fixture: String) throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install(fixture, in: dir)
        let bytes = try Data(contentsOf: file)
        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        guard case .unavailable(.corrupt) = controller.state else {
            Issue.record("expected .corrupt, got \(controller.state)")
            return
        }
        #expect(throws: ConfigError.writeFailed("configuration unavailable")) {
            try controller.update { _ in }
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func newerVersionIsNeverOverwritten() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install("config-v3", in: dir)
        let bytes = try Data(contentsOf: file)
        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        #expect(controller.state == .unavailable(.unsupportedVersion(3)))
        #expect(throws: ConfigError.writeFailed("configuration unavailable")) {
            try controller.update { _ in }
        }
        controller.catalogDidLoad(Fixture.validCatalog())   // seeding is refused too
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func corruptV2IsNeverOverwritten() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install("config-v2-corrupt", in: dir)
        let bytes = try Data(contentsOf: file)
        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        guard case .unavailable(.corrupt) = controller.state else {
            Issue.record("expected .corrupt, got \(controller.state)")
            return
        }
        controller.catalogDidLoad(Fixture.validCatalog())
        #expect(throws: ConfigError.writeFailed("configuration unavailable")) {
            try controller.update { _ in }
        }
        let decision = Router.decide(URL(string: "https://github.com/x")!, config: controller.routingConfig,
                                     catalog: Self.catalog)
        guard case .needsProfile(_, .r3, .configUnavailable, _) = decision else {
            Issue.record("expected configUnavailable for R3, got \(decision)")
            return
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func resetFromCorruptV2BacksUpAndWritesV2Defaults() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install("config-v2-corrupt", in: dir)
        let bytes = try Data(contentsOf: file)
        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        try controller.resetToDefaults(catalogLoader: { .unavailable(.noProfiles) })
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
            .filter { $0.hasPrefix("config.corrupt-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: dir.url.appendingPathComponent(try #require(backups.first))) == bytes)
        #expect(try loaded(file) == AppConfig.unseededDefault)
        #expect(try json(file)["schemaVersion"] as? Int == 2)
    }

    // MARK: v2 decode validation

    nonisolated static let validRule = #"{"id":"R1","match":{"type":"host","host":"git.fis.vn"}}"#

    nonisolated static func document(rules: [String], nextRuleNumber: Int = 5) -> String {
        #"{"schemaVersion":2,"seedPending":false,"rules":["# + rules.joined(separator: ",")
            + #"],"fallback":{},"nextRuleNumber":\#(nextRuleNumber)}"#
    }

    nonisolated static let rejectedDocuments: [String] = [
        document(rules: [validRule, validRule]),                                                    // duplicate ids
        document(rules: [#"{"id":"X1","match":{"type":"host","host":"a.example"}}"#]),              // bad id
        document(rules: [#"{"id":"R0","match":{"type":"host","host":"a.example"}}"#]),              // bad id
        document(rules: [#"{"id":"R4","match":{"type":"host","host":"a.example"}}"#]),              // fallback id
        document(rules: [#"{"id":"R7","match":{"type":"host","host":"a.example"}}"#], nextRuleNumber: 7),
        document(rules: [validRule], nextRuleNumber: 4),
        document(rules: [#"{"id":"R1","match":{"type":"wildcard","host":"*.example"}}"#]),          // unknown type
        document(rules: [#"{"id":"R1","match":{"type":"host","host":"https://github.com"}}"#]),     // invalid host
        document(rules: [#"{"id":"R1","match":{"type":"host","host":""}}"#]),                       // empty host
        document(rules: [#"{"id":"R1","match":{"type":"hostPathPrefix","host":"github.com","pathPrefix":"owner/repo"}}"#]),
        document(rules: [#"{"id":"R1","match":{"type":"hostPathPrefix","host":"github.com"}}"#]),  // missing path
        #"{"schemaVersion":2,"seedPending":false,"rules":[],"nextRuleNumber":5}"#,                   // missing fallback
        #"{"schemaVersion":2,"seedPending":false,"fallback":{},"nextRuleNumber":5}"#,               // missing rules
    ]

    @Test(arguments: rejectedDocuments)
    func v2DecodeRejects(_ document: String) throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = dir.url.appendingPathComponent("config.json")
        try Data(document.utf8).write(to: file)
        let state = ConfigStore(fileURL: file).load()
        guard case .unavailable(.corrupt) = state else {
            Issue.record("expected .corrupt, got \(state)")
            return
        }
        #expect(try Data(contentsOf: file) == Data(document.utf8))
    }

    @Test func v2DecodeNormalizesAndAllowsDuplicateMatches() throws {
        let document = Self.document(rules: [
            #"{"id":"R1","match":{"type":"host","host":"GitHub.com."}}"#,
            #"{"id":"R2","match":{"type":"host","host":"github.com"}}"#,
            #"{"id":"R6","match":{"type":"hostPathPrefix","host":"github.com","pathPrefix":"/Acme/App/"}}"#,
        ], nextRuleNumber: 9)
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(document.utf8))
        #expect(config.rules.map(\.match) == [
            .host("github.com"), .host("github.com"), .hostPathPrefix(host: "github.com", pathPrefix: "/Acme/App"),
        ])
        #expect(config.nextRuleNumber == 9)
    }
}
