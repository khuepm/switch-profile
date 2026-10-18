import Foundation
import Testing
@testable import SwitchProfileCore

/// #13: an unset fallback (R4 `{}` or `"binding": null`) means "Last active Chrome profile" on load,
/// with no schema bump and no write. Fixed fallbacks are kept.
@MainActor
@Suite struct FallbackMigrationTests {
    static let fallbackURL = URL(string: "https://example.com/")!
    static let catalog = CatalogState.loaded(Fixture.validCatalog())

    private func install(_ data: Data, in dir: TempDir) throws -> URL {
        let file = dir.url.appendingPathComponent("config.json")
        try data.write(to: file)
        return file
    }

    private func modificationDate(_ file: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
    }

    private func launcher() -> ChromeLauncher {
        ChromeLauncher(locator: FakeLocator(), opener: FakeOpener(), ownBundleIdentifier: "io.github.khuepm.switchprofile")
    }

    /// Loads `file`, checks R4 routes and validates as last active, and that nothing was written.
    private func expectLastActiveWithoutWrite(_ file: URL) throws {
        let bytes = try Data(contentsOf: file)
        let modified = try modificationDate(file)

        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        guard case .loaded(let config) = controller.state else {
            Issue.record("expected a loaded config, got \(controller.state)")
            return
        }
        #expect(config.targets.R4.binding == nil)
        let decision = Router.decide(Self.fallbackURL, config: controller.routingConfig, catalog: Self.catalog)
        guard case .launch(let target, _) = decision else {
            Issue.record("expected .launch, got \(decision)")
            return
        }
        #expect(target.profile == .lastActiveChrome)
        #expect(ConfigValidator.status(config: config, catalog: Self.catalog)[.r4] == .lastActiveChrome)

        #expect(try Data(contentsOf: file) == bytes)
        #expect(try modificationDate(file) == modified)
    }

    @Test func unsetFallbackConfigMigratesWithoutAWrite() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install(Fixture.data("config-v1-valid"), in: dir)
        try expectLastActiveWithoutWrite(file)
    }

    @Test func nullBindingFallbackMigrates() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let json = """
            {
              "schemaVersion": 1,
              "seedPending": false,
              "targets": {
                "R1": { "identity": "khuepm18" },
                "R2": { "identity": "khue@truckerpoints.ai" },
                "R3": { "identity": "pmkhue.2013" },
                "R4": { "binding": null }
              }
            }
            """
        let file = try install(Data(json.utf8), in: dir)
        try expectLastActiveWithoutWrite(file)
    }

    @Test func fixedFallbackIsKept() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install(Fixture.data("config-v1-fixed-fallback"), in: dir)
        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        guard case .loaded(let config) = controller.state else {
            Issue.record("expected a loaded config, got \(controller.state)")
            return
        }
        #expect(config.targets.R4.binding?.directory == "Profile 8")

        let decision = Router.decide(Self.fallbackURL, config: controller.routingConfig, catalog: Self.catalog)
        guard case .launch(let target, _) = decision else {
            Issue.record("expected .launch, got \(decision)")
            return
        }
        #expect(target.profile == .directory("Profile 8"))
        #expect(try launcher().makeRequest(for: target).arguments == ["--profile-directory=Profile 8", "https://example.com/"])
    }

    @Test func fixedFallbackPersistsAcrossRelaunch() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install(Fixture.data("config-v1-valid"), in: dir)
        let profile8 = try #require(Fixture.validCatalog().profile(directory: "Profile 8"))

        let first = ConfigController(store: ConfigStore(fileURL: file))
        first.load()
        try first.update { $0.targets.R4.binding = ProfileBinding(profile: profile8, matchedBy: nil) }

        let relaunched = ConfigController(store: ConfigStore(fileURL: file))
        relaunched.load()
        guard case .loaded(let reloaded) = relaunched.state else {
            Issue.record("expected a loaded config, got \(relaunched.state)")
            return
        }
        #expect(reloaded.targets.R4.binding == ProfileBinding(profile: profile8, matchedBy: nil))

        // Choosing "Last active Chrome profile" again saves R4 without a binding.
        try relaunched.update { $0.targets.R4.binding = nil }
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let targets = try #require(json["targets"] as? [String: Any])
        let r4 = try #require(targets["R4"] as? [String: Any])
        #expect(r4["binding"] == nil)

        let third = ConfigController(store: ConfigStore(fileURL: file))
        third.load()
        let decision = Router.decide(Self.fallbackURL, config: third.routingConfig, catalog: Self.catalog)
        guard case .launch(let target, _) = decision else {
            Issue.record("expected .launch, got \(decision)")
            return
        }
        #expect(target.profile == .lastActiveChrome)
    }

    @Test func defaultsAndResetUseLastActive() {
        #expect(AppConfig.unseededDefault.targets.R4.binding == nil)
        let decision = Router.decide(Self.fallbackURL, config: .loaded(.unseededDefault), catalog: Self.catalog)
        guard case .launch(let target, _) = decision else {
            Issue.record("expected .launch, got \(decision)")
            return
        }
        #expect(target.profile == .lastActiveChrome)
    }

    @Test func schemaVersionUnchanged() throws {
        #expect(AppConfig.currentSchemaVersion == 1)
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = try install(Fixture.data("config-v2"), in: dir)
        let bytes = try Data(contentsOf: file)
        let controller = ConfigController(store: ConfigStore(fileURL: file))
        controller.load()
        #expect(controller.state == .unavailable(.unsupportedVersion(2)))
        #expect(throws: ConfigError.writeFailed("configuration unavailable")) {
            try controller.update { $0.targets.R4.binding = nil }
        }
        #expect(try Data(contentsOf: file) == bytes)
    }
}
