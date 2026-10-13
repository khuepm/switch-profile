import Foundation
import os
import Testing
@testable import SwitchProfileCore

@MainActor
@Suite struct ConfigControllerTests {
    let dir = TempDir()
    var file: URL { dir.url.appendingPathComponent("config.json") }

    private func controller(writeData: (@Sendable (Data, URL) throws -> Void)? = nil) -> ConfigController {
        let store = writeData.map { ConfigStore(fileURL: file, writeData: $0) } ?? ConfigStore(fileURL: file)
        return ConfigController(store: store)
    }

    private func installFixture(_ name: String) throws {
        try Fixture.data(name).write(to: file)
    }

    private func loadedConfig(_ controller: ConfigController) -> AppConfig? {
        if case .loaded(let config) = controller.state { return config }
        return nil
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
            .filter { $0.hasPrefix("config.corrupt-") && $0.hasSuffix(".json") }
            .sorted()
    }

    /// A loader over the fixture catalog that calls the seeding hook, like the production closure.
    private func fixtureLoader(_ controller: ConfigController, counter: CallCounter? = nil) -> @MainActor () -> CatalogState {
        {
            counter?.value += 1
            let catalog = Fixture.validCatalog()
            controller.catalogDidLoad(catalog)
            return .loaded(catalog)
        }
    }

    @Test func initialStateIsNotLoaded() {
        defer { dir.cleanup() }
        let controller = controller()
        #expect(controller.state == .unavailable(.unreadable("not loaded")))
        #expect(controller.routingConfig == .unavailable(.unreadable("not loaded")))
        #expect(!controller.isWritable)
        #expect(throws: ConfigError.writeFailed("configuration unavailable")) {
            try controller.update { $0.seedPending = false }
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func absentFileLoadsUnseededDefaultWithoutWriting() {
        defer { dir.cleanup() }
        let controller = controller()
        controller.load()
        #expect(controller.state == .loaded(.unseededDefault))
        #expect(controller.routingConfig == .loaded(.unseededDefault))
        #expect(controller.isWritable)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func catalogDidLoadSeedsOnce() throws {
        defer { dir.cleanup() }
        let controller = controller()
        controller.load()
        controller.catalogDidLoad(Fixture.validCatalog())

        let seeded = try #require(loadedConfig(controller))
        #expect(seeded.seedPending == false)
        #expect(seeded.targets.R1.binding?.directory == "Profile 30")
        #expect(seeded.targets.R2.binding?.directory == "Profile 47")
        #expect(seeded.targets.R3.binding?.directory == "Default")
        #expect(ConfigStore(fileURL: file).load() == .loaded(seeded))

        let bytes = try Data(contentsOf: file)
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        controller.catalogDidLoad(Fixture.validCatalog())
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == modified)
        #expect(controller.state == .loaded(seeded))
    }

    @Test func updateBeforeSeedingPersistsSeedPending() throws {
        defer { dir.cleanup() }
        let first = controller()
        first.load()
        let record = DefaultBrowserRecord(bundleIdentifier: "com.apple.Safari", path: "/Applications/Safari.app")
        try first.update { $0.previousDefaultBrowser = record }

        guard case .loaded(let onDisk) = ConfigStore(fileURL: file).load() else {
            Issue.record("expected a saved file")
            return
        }
        #expect(onDisk.seedPending)
        #expect(onDisk.previousDefaultBrowser == record)

        let second = controller()
        second.load()
        second.catalogDidLoad(Fixture.validCatalog())
        let seeded = try #require(loadedConfig(second))
        #expect(seeded.seedPending == false)
        #expect(seeded.targets.R1.binding?.directory == "Profile 30")
        #expect(seeded.previousDefaultBrowser == record)
    }

    @Test func seedingKeepsUserBinding() throws {
        defer { dir.cleanup() }
        let controller = controller()
        controller.load()
        let choice = ProfileBinding(directory: "Profile 9", email: nil, displayName: "Signed out", matchedBy: nil)
        try controller.update { $0.targets.R1.binding = choice }
        controller.catalogDidLoad(Fixture.validCatalog())
        let seeded = try #require(loadedConfig(controller))
        #expect(seeded.targets.R1.binding == choice)
        #expect(seeded.targets.R2.binding?.directory == "Profile 47")
    }

    @Test func unavailableStateRefusesWritesAndSeeding() throws {
        defer { dir.cleanup() }
        try installFixture("config-corrupt")
        let before = try Data(contentsOf: file)
        let controller = controller()
        controller.load()
        guard case .unavailable(.corrupt) = controller.state else {
            Issue.record("expected .corrupt, got \(controller.state)")
            return
        }
        #expect(!controller.isWritable)
        #expect(throws: ConfigError.writeFailed("configuration unavailable")) {
            try controller.update { $0.seedPending = false }
        }
        controller.catalogDidLoad(Fixture.validCatalog())
        #expect(try Data(contentsOf: file) == before)
        guard case .unavailable = controller.routingConfig else {
            Issue.record("expected unavailable routing config")
            return
        }
    }

    @Test func resetBacksUpWritesDefaultAndSeeds() throws {
        defer { dir.cleanup() }
        try installFixture("config-corrupt")
        let controller = controller()
        controller.load()
        let loads = CallCounter()
        try controller.resetToDefaults(catalogLoader: fixtureLoader(controller, counter: loads))

        #expect(loads.value == 1)
        let names = try backups()
        #expect(names.count == 1)
        #expect(try Data(contentsOf: dir.url.appendingPathComponent(names[0])) == Data("{".utf8))

        let seeded = try #require(loadedConfig(controller))
        #expect(seeded.seedPending == false)
        #expect(seeded.targets.R3.binding?.directory == "Default")
        #expect(ConfigStore(fileURL: file).load() == .loaded(seeded))
    }

    @Test func resetWithUnavailableCatalogKeepsSeedPending() throws {
        defer { dir.cleanup() }
        try installFixture("config-corrupt")
        let controller = controller()
        controller.load()
        try controller.resetToDefaults(catalogLoader: { .unavailable(.notFound("/x")) })
        #expect(controller.state == .loaded(.unseededDefault))
        #expect(ConfigStore(fileURL: file).load() == .loaded(.unseededDefault))
    }

    @Test func onChangeFiresOnSuccessOnly() throws {
        defer { dir.cleanup() }
        let controller = controller()
        let changes = CallCounter()
        controller.onChange = { changes.value += 1 }

        controller.load()
        #expect(changes.value == 1)

        try controller.update { $0.targets.R4.identity = "x" }
        #expect(changes.value == 2)

        controller.catalogDidLoad(Fixture.validCatalog())   // seeding save
        #expect(changes.value == 3)

        controller.catalogDidLoad(Fixture.validCatalog())   // no-op
        #expect(changes.value == 3)

        // Failed update: the directory becomes read-only.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.url.path)
        #expect(throws: ConfigError.self) {
            try controller.update { $0.targets.R4.identity = "y" }
        }
        #expect(changes.value == 3)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.url.path)

        try controller.resetToDefaults(catalogLoader: { .unavailable(.noProfiles) })
        #expect(changes.value == 4)
    }

    @Test func saveFailureLeavesMemoryUnchanged() throws {
        defer { dir.cleanup() }
        let controller = controller()
        controller.load()
        try controller.update { $0.targets.R4.identity = "kept" }
        let before = controller.state
        let bytes = try Data(contentsOf: file)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.url.path) }
        do {
            try controller.update { $0.targets.R4.identity = "lost" }
            Issue.record("expected .writeFailed")
        } catch {
            guard case .writeFailed = error else {
                Issue.record("expected .writeFailed, got \(error)")
                return
            }
        }
        #expect(controller.state == before)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func seedSaveFailureKeepsSeedPending() throws {
        defer { dir.cleanup() }
        let controller = controller(writeData: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        controller.load()
        controller.catalogDidLoad(Fixture.validCatalog())
        #expect(controller.state == .loaded(.unseededDefault))
    }

    @Test func resetSaveFailureAfterBackupThenSecondResetSucceeds() throws {
        // NIT #9: the backup succeeds, the save fails.
        defer { dir.cleanup() }
        try installFixture("config-corrupt")
        let failWrites = OSAllocatedUnfairLock(initialState: true)
        let controller = controller(writeData: { data, url in
            if failWrites.withLock({ $0 }) { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        controller.load()
        let corruptState = controller.state

        do {
            try controller.resetToDefaults(catalogLoader: fixtureLoader(controller))
            Issue.record("expected .writeFailed")
        } catch {
            guard case .writeFailed = error else {
                Issue.record("expected .writeFailed, got \(error)")
                return
            }
        }
        #expect(controller.state == corruptState)
        guard case .unavailable = controller.state else {
            Issue.record("expected .unavailable")
            return
        }
        #expect(try backups().count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        failWrites.withLock { $0 = false }
        try controller.resetToDefaults(catalogLoader: fixtureLoader(controller))
        let seeded = try #require(loadedConfig(controller))
        #expect(seeded.seedPending == false)
        #expect(seeded.targets.R1.binding?.directory == "Profile 30")
        #expect(ConfigStore(fileURL: file).load() == .loaded(seeded))
        #expect(try backups().count == 1)
    }
}

/// Main-actor counter for closures in tests.
@MainActor
final class CallCounter {
    var value = 0
}
