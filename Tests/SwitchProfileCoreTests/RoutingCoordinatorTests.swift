import Foundation
import Testing
@testable import SwitchProfileCore

/// A counting catalog loader that calls the seeding hook, like the production closure.
@MainActor
final class FakeCatalogLoader {
    var state: CatalogState
    /// When false, the loader skips the seeding hook (only `ConfigController.resetToDefaults` seeds).
    var seeds = true
    private(set) var count = 0
    private let config: ConfigController

    init(state: CatalogState, config: ConfigController) {
        self.state = state
        self.config = config
    }

    func load() -> CatalogState {
        count += 1
        if seeds, case .loaded(let catalog) = state { config.catalogDidLoad(catalog) }
        return state
    }
}

/// A real `ConfigController` over a temp-dir `ConfigStore`, a counting loader and a `FakeOpener`.
@MainActor
final class CoordinatorHarness {
    let dir = TempDir()
    let file: URL
    let config: ConfigController
    let loader: FakeCatalogLoader
    let opener = FakeOpener()
    let coordinator: RoutingCoordinator

    init(configFixture: String? = nil, catalog: CatalogState = .loaded(Fixture.validCatalog()), ready: Bool = true) throws {
        file = dir.url.appendingPathComponent("config.json")
        if let configFixture {
            try Fixture.data(configFixture).write(to: file)
        }
        config = ConfigController(store: ConfigStore(fileURL: file))
        config.load()
        let loader = FakeCatalogLoader(state: catalog, config: config)
        self.loader = loader
        let launcher = ChromeLauncher(locator: FakeLocator(), opener: opener, ownBundleIdentifier: "io.github.khuepm.switchprofile")
        coordinator = RoutingCoordinator(config: config, catalogLoader: { loader.load() }, launcher: launcher)
        if ready { coordinator.markReady() }
    }

    func cleanup() { dir.cleanup() }

    /// Turns seeding off and sets exactly these bindings (others nil).
    func bind(_ bindings: [RuleID: ProfileBinding]) throws {
        try config.update { config in
            config.seedPending = false
            for rule in config.ruleOrder {
                config.setBinding(bindings[rule], for: rule)
            }
        }
    }

    var loadedConfig: AppConfig? {
        if case .loaded(let config) = config.state { return config }
        return nil
    }

    func pendingItem(_ url: URL) -> PendingItem? {
        coordinator.pending.items.first { $0.url == url }
    }

    func enqueue(_ urls: URL...) {
        coordinator.enqueue(urls, source: .external)
    }
}

/// Binding to a fixture profile, or a synthetic one for a directory not in the fixture.
private func b(_ directory: String) -> ProfileBinding {
    if let profile = Fixture.validCatalog().profile(directory: directory) {
        return ProfileBinding(profile: profile, matchedBy: nil)
    }
    return ProfileBinding(directory: directory, email: nil, displayName: directory, matchedBy: nil)
}

private enum Links {
    static func r1(_ n: Int) -> URL { URL(string: "https://git.fis.vn/fis-gs/x/\(n)")! }
    static func r2(_ n: Int) -> URL { URL(string: "https://github.com/TruckerPoints/trucker-points/pull/\(n)")! }
    static func r3(_ n: Int) -> URL { URL(string: "https://github.com/khuepm/LumiBase/issues/\(n)")! }
    static func r4(_ n: Int) -> URL { URL(string: "https://example.com/page/\(n)")! }

    /// Cycles R1, R2, R3, R4.
    static func mixed(_ n: Int) -> URL {
        switch n % 4 {
        case 1: r1(n)
        case 2: r2(n)
        case 3: r3(n)
        default: r4(n)
        }
    }
}

private let allBound: [RuleID: ProfileBinding] = [.r1: b("Profile 30"), .r2: b("Profile 47"), .r3: b("Default"), .r4: b("Profile 7")]
private let directoryByRule: [RuleID: String] = [.r1: "Profile 30", .r2: "Profile 47", .r3: "Default", .r4: "Profile 7"]

@MainActor
@Suite struct RoutingCoordinatorTests {
    // MARK: Queue and worker

    @Test func burstOfSixPlusSixOpensTwelveInSeqOrder() async throws {
        // AC-23
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.opener.suspendedCalls = [1]

        let first = (1...6).map(Links.mixed)
        h.coordinator.enqueue(first, source: .external)
        await h.opener.waitUntilCallStarted(1)
        let second = (7...12).map(Links.mixed)
        for url in second {
            h.coordinator.enqueue([url], source: .external)
        }
        h.opener.resume(1)
        await h.coordinator.waitUntilIdle()

        let all = first + second
        #expect(h.opener.urls == all.map(\.absoluteString))
        let rules: [RuleID] = [.r4, .r1, .r2, .r3]   // Links.mixed cycles by n % 4
        #expect(h.opener.directories == (1...12).map { directoryByRule[rules[$0 % 4]]! })
        #expect(h.coordinator.pending.items.isEmpty)
        #expect(h.coordinator.unfinishedCount == 0)
        #expect(h.coordinator.recent.count == 12)
    }

    @Test func sameURLTwiceOpensTwice() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.enqueue(Links.r3(1), Links.r3(1))
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.urls == [Links.r3(1).absoluteString, Links.r3(1).absoluteString])
    }

    @Test func urlsBeforeMarkReadyAreBufferedThenLaunched() async throws {
        let h = try CoordinatorHarness(ready: false)
        defer { h.cleanup() }
        try h.bind(allBound)
        h.enqueue(Links.r1(1), Links.r2(2))
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.callCount == 0)
        #expect(h.coordinator.unfinishedCount == 2)
        #expect(h.loader.count == 0)

        h.coordinator.markReady()
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.urls == [Links.r1(1).absoluteString, Links.r2(2).absoluteString])
        #expect(h.coordinator.unfinishedCount == 0)
    }

    @Test func launchFailureBecomesPendingAndLaterURLsStillLaunch() async throws {
        // AC-24
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.opener.failingCalls = [2]
        let urls = (1...5).map(Links.r3)
        h.coordinator.enqueue(urls, source: .external)
        await h.coordinator.waitUntilIdle()

        #expect(h.opener.urls == urls.map(\.absoluteString))
        #expect(h.coordinator.pending.items.count == 1)
        let item = try #require(h.pendingItem(urls[1]))
        #expect(item.kind == .launchFailed(.openFailed("fake open failure")))
        #expect(item.lastAttempt == .route)
        #expect(item.rule == .r3)
        #expect(h.coordinator.recent.filter { if case .opened = $0 { true } else { false } }.count == 4)
    }

    @Test func needsProfileGoesToPendingNotToTheOpener() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r1: b("Profile 30")])
        h.enqueue(Links.r3(1), Links.r1(2))
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.urls == [Links.r1(2).absoluteString])
        let item = try #require(h.pendingItem(Links.r3(1)))
        #expect(item.kind == .needsProfile(.unset))
        #expect(item.rule == .r3)
        #expect(item.seq == 1)
    }

    @Test func batchRuleLoadsTheCatalogOncePerBatch() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.opener.suspendedCalls = [1]
        h.coordinator.enqueue((1...3).map(Links.r3), source: .external)
        await h.opener.waitUntilCallStarted(1)
        h.enqueue(Links.r3(4))
        h.enqueue(Links.r3(5))
        h.opener.resume(1)
        await h.coordinator.waitUntilIdle()

        #expect(h.loader.count == 2)
        #expect(h.opener.urls == (1...5).map { Links.r3($0).absoluteString })
    }

    @Test func configIsReadPerItem() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r4: b("Profile 7")])
        h.opener.suspendedCalls = [1]
        h.coordinator.enqueue((1...3).map(Links.r4), source: .external)
        await h.opener.waitUntilCallStarted(1)
        try h.config.update { $0.setBinding(b("Profile 8"), for: .r4) }
        h.opener.resume(1)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Profile 7", "Profile 8", "Profile 8"])
    }

    @Test func unfinishedCountIncludesTheInFlightItem() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.opener.suspendedCalls = [1]
        h.enqueue(Links.r3(1))
        await h.opener.waitUntilCallStarted(1)
        #expect(h.coordinator.unfinishedCount == 1)
        #expect(h.coordinator.pending.items.isEmpty)
        h.opener.resume(1)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.unfinishedCount == 0)
    }

    @Test func recentIsANewestFirstRingBufferOfTwenty() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.coordinator.enqueue((1...25).map(Links.r3), source: .external)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.recent.count == RoutingCoordinator.recentCapacity)
        #expect(h.coordinator.recent.first == .opened(host: "github.com", rule: .r3, directory: "Default"))
    }

    // MARK: Retry

    @Test func retryAfterCatalogBecomesAvailableLaunches() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        try h.bind(allBound)
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        #expect(item.kind == .needsProfile(.catalogUnavailable(.notFound("/x/Local State"))))

        h.loader.state = .loaded(Fixture.validCatalog())
        try h.coordinator.retry(id: item.id)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Default"])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func retryKeepsIdAndSeq() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        try h.bind(allBound)
        h.enqueue(Links.r4(1), Links.r3(2))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.pendingItem(Links.r3(2)))

        h.loader.state = .loaded(Fixture.validCatalog())
        h.opener.failingCalls = [1]
        try h.coordinator.retry(id: item.id)
        await h.coordinator.waitUntilIdle()
        // The R4 item was re-routed by the successful batch load too; only the retried item fails.
        #expect(h.opener.callCount == 2)
        let again = try #require(h.pendingItem(Links.r3(2)))
        #expect(again.id == item.id)
        #expect(again.seq == item.seq)
        #expect(again.kind == .launchFailed(.openFailed("fake open failure")))
    }

    @Test func retryWhenTheCausePersists() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        try h.bind(allBound)
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)

        try h.coordinator.retry(id: item.id)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.count == 1)
        let again = try #require(h.coordinator.pending.items.first)
        #expect(again.id == item.id)
        #expect(again.kind == .needsProfile(.catalogUnavailable(.notFound("/x/Local State"))))
        #expect(h.opener.callCount == 0)
    }

    @Test func retryOfConfigUnavailableAfterReset() async throws {
        let h = try CoordinatorHarness(configFixture: "config-corrupt")
        defer { h.cleanup() }
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        guard case .needsProfile(.configUnavailable) = item.kind else {
            Issue.record("expected .configUnavailable, got \(item.kind)")
            return
        }

        try h.config.resetToDefaults(catalogLoader: { h.loader.load() })
        #expect(h.coordinator.pending.items == [item])
        try h.coordinator.retry(id: item.id)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Default"])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func retryNeedsAProfileChoiceForUnsetMissingAndMismatch() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        let stale = ProfileBinding(directory: "Profile 47", email: "other@example.com", displayName: "tp", matchedBy: nil)
        try h.bind([.r2: stale, .r3: b("Profile 99")])
        h.enqueue(Links.r1(1), Links.r2(2), Links.r3(3))
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        let current = try #require(Fixture.validCatalog().profile(directory: "Profile 47"))
        let expectedKinds: [PendingKind] = [
            .needsProfile(.unset),
            .needsProfile(.identityMismatch(stale, current: current)),
            .needsProfile(.missing(b("Profile 99"))),
        ]
        #expect(before.map(\.kind) == expectedKinds)
        for item in before {
            #expect(throws: PendingActionError.notApplicable) { try h.coordinator.retry(id: item.id) }
        }
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items == before)
        #expect(h.opener.callCount == 0)
    }

    @Test func retryOfAFailedLaunchThatFailsAgain() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.opener.failingCalls = [1, 2]
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)

        try h.coordinator.retry(id: item.id)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.count == 1)
        #expect(h.coordinator.pending.items.first?.id == item.id)
        #expect(h.opener.callCount == 2)
    }

    @Test func retryOfAFailedOpenOnceReusesTheChosenDirectory() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.opener.failingCalls = [1]
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)

        try h.coordinator.openOnce(id: item.id, directory: "Profile 7")
        await h.coordinator.waitUntilIdle()
        let failed = try #require(h.coordinator.pending.items.first)
        #expect(failed.kind == .launchFailed(.openFailed("fake open failure")))
        #expect(failed.lastAttempt == .resolved(directory: "Profile 7"))

        try h.coordinator.retry(id: failed.id)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Profile 7", "Profile 7"])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    // MARK: Open and remember / open once

    @Test func openAndRememberSavesLaunchesAndReroutesTheSameRule() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1), Links.r2(2), Links.r3(3), Links.r3(4))
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.count == 4)
        let target = try #require(h.pendingItem(Links.r3(1)))
        let r2Item = try #require(h.pendingItem(Links.r2(2)))

        try h.coordinator.openAndRemember(id: target.id, directory: "Profile 7")
        let saved = try #require(h.loadedConfig?.binding(for: .r3))
        #expect(saved == b("Profile 7"))
        #expect(saved.matchedBy == nil)
        #expect(ConfigStore(fileURL: h.file).load() == .loaded(try #require(h.loadedConfig)))

        await h.coordinator.waitUntilIdle()
        #expect(h.opener.urls == [Links.r3(1), Links.r3(3), Links.r3(4)].map(\.absoluteString))
        #expect(h.opener.directories == ["Profile 7", "Profile 7", "Profile 7"])
        #expect(h.coordinator.pending.items == [r2Item])
    }

    @Test func openAndRememberWhileConfigUnavailableWritesNothing() async throws {
        let h = try CoordinatorHarness(configFixture: "config-corrupt")
        defer { h.cleanup() }
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        let bytes = try Data(contentsOf: h.file)

        #expect(throws: PendingActionError.configUnavailable) {
            try h.coordinator.openAndRemember(id: item.id, directory: "Default")
        }
        await h.coordinator.waitUntilIdle()
        #expect(try Data(contentsOf: h.file) == bytes)
        #expect(h.coordinator.pending.items == [item])
        #expect(h.opener.callCount == 0)
    }

    @Test func openAndRememberWithAnUnknownDirectorySavesNothing() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        let before = h.config.state

        #expect(throws: PendingActionError.profileNotFound("Profile 99")) {
            try h.coordinator.openAndRemember(id: item.id, directory: "Profile 99")
        }
        #expect(h.config.state == before)
        #expect(h.coordinator.pending.items == [item])
    }

    @Test func openAndRememberWithUnavailableCatalogThrows() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.noProfiles))
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        #expect(throws: PendingActionError.catalogUnavailable(.noProfiles)) {
            try h.coordinator.openAndRemember(id: item.id, directory: "Default")
        }
        #expect(h.loadedConfig?.binding(for: .r3) == nil)
    }

    @Test func openAndRememberOnALaunchFailureIsNotApplicable() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.opener.failingCalls = [1]
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        #expect(throws: PendingActionError.notApplicable) {
            try h.coordinator.openAndRemember(id: item.id, directory: "Profile 7")
        }
    }

    @Test func openOnceOnConfigUnavailableLaunchesAndWritesNothing() async throws {
        let h = try CoordinatorHarness(configFixture: "config-corrupt")
        defer { h.cleanup() }
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        let bytes = try Data(contentsOf: h.file)

        try h.coordinator.openOnce(id: item.id, directory: "Profile 7")
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Profile 7"])
        #expect(h.coordinator.pending.items.isEmpty)
        #expect(try Data(contentsOf: h.file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.dir.url.path) == ["config.json"])
    }

    @Test func openOnceWhenTheDirectoryVanishesComesBackAsMissing() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)

        let without = Fixture.validCatalog().profiles.filter { $0.directory != "Profile 7" }
        h.loader.state = .loaded(ProfileCatalog(profiles: without))
        try h.coordinator.openOnce(id: item.id, directory: "Profile 7")
        await h.coordinator.waitUntilIdle()

        #expect(h.coordinator.pending.items.count == 1)
        let again = try #require(h.coordinator.pending.items.first)
        #expect(again.id == item.id)
        #expect(again.seq == item.seq)
        #expect(again.kind == .needsProfile(.missing(ProfileBinding(directory: "Profile 7", email: nil, displayName: "Profile 7", matchedBy: nil))))
        #expect(again.lastAttempt == .resolved(directory: "Profile 7"))
        #expect(h.opener.callCount == 0)
    }

    // MARK: Discard, unknown ids, ordering

    @Test func discardRemovesTheItem() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)

        try h.coordinator.discard(id: item.id)
        #expect(h.coordinator.pending.items.isEmpty)
        #expect(h.coordinator.recent.first == .discarded(rule: .r3))
        #expect(h.coordinator.unfinishedCount == 0)
    }

    @Test func unknownIdThrowsItemNotFound() throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        let id = UUID()
        #expect(throws: PendingActionError.itemNotFound) { try h.coordinator.openOnce(id: id, directory: "Default") }
        #expect(throws: PendingActionError.itemNotFound) { try h.coordinator.openAndRemember(id: id, directory: "Default") }
        #expect(throws: PendingActionError.itemNotFound) { try h.coordinator.retry(id: id) }
        #expect(throws: PendingActionError.itemNotFound) { try h.coordinator.discard(id: id) }
    }

    @Test func pendingItemsStayInSeqOrderAfterReattempts() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind(allBound)
        h.opener.failingCalls = [1, 2, 3, 4]
        h.coordinator.enqueue((1...3).map(Links.r3), source: .external)
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        #expect(before.map(\.seq) == [1, 2, 3])

        try h.coordinator.retry(id: before[0].id)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.map(\.id) == before.map(\.id))
        #expect(h.coordinator.pending.items.map(\.seq) == [1, 2, 3])
        #expect(h.opener.callCount == 4)
    }

    // MARK: Design review #1 (MEDIUM): re-route on recovery

    @Test func tM1_reroutePendingOpensFixedRuleOnly() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r3: b("Profile 99")])
        h.enqueue(Links.r3(1), Links.r2(2))
        await h.coordinator.waitUntilIdle()
        let r3Item = try #require(h.pendingItem(Links.r3(1)))
        let r2Item = try #require(h.pendingItem(Links.r2(2)))
        #expect(r3Item.kind == .needsProfile(.missing(b("Profile 99"))))
        #expect(r2Item.kind == .needsProfile(.unset))

        try h.config.update { $0.setBinding(b("Profile 7"), for: .r3) }
        h.coordinator.reroutePending(rule: .r3)
        await h.coordinator.waitUntilIdle()

        #expect(h.opener.callCount == 1)
        #expect(h.opener.directories == ["Profile 7"])
        #expect(h.opener.urls == [Links.r3(1).absoluteString])
        #expect(h.pendingItem(Links.r3(1)) == nil)
        #expect(h.coordinator.pending.items == [r2Item])
    }

    @Test func tM2_updateBindingReroutesAllPendingLinksOfTheRuleInSeqOrder() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        let urls = (1...6).map(Links.r3)
        h.coordinator.enqueue(urls, source: .external)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.count == 6)
        #expect(h.coordinator.pending.items.allSatisfy { $0.kind == .needsProfile(.unset) })

        try h.coordinator.updateBinding(rule: .r3, to: b("Profile 8"))
        #expect(h.loadedConfig?.binding(for: .r3) == b("Profile 8"))
        await h.coordinator.waitUntilIdle()

        #expect(h.opener.urls == urls.map(\.absoluteString))
        #expect(h.opener.directories == Array(repeating: "Profile 8", count: 6))
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func tM3_updateBindingToNilReroutesNothing() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r3: b("Profile 99")])
        h.enqueue(Links.r3(1), Links.r1(2))
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        #expect(before.count == 2)

        try h.coordinator.updateBinding(rule: .r3, to: nil)
        await h.coordinator.waitUntilIdle()

        #expect(h.loadedConfig?.binding(for: .r3) == nil)
        // Re-routing the R3 item would have turned it into `.unset`. (R4 is covered by
        // choosingLastActiveForR4ReroutesItsPendingLinks: nil there means last active.)
        #expect(h.coordinator.pending.items == before)
        #expect(h.opener.callCount == 0)
    }

    @Test func tM4_failedUpdateBindingReroutesNothing() async throws {
        let h = try CoordinatorHarness(configFixture: "config-corrupt")
        defer { h.cleanup() }
        h.enqueue(Links.r4(1))
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        let bytes = try Data(contentsOf: h.file)

        #expect(throws: ConfigError.writeFailed("configuration unavailable")) {
            try h.coordinator.updateBinding(rule: .r4, to: b("Profile 8"))
        }
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.callCount == 0)
        #expect(h.coordinator.pending.items == before)
        #expect(try Data(contentsOf: h.file) == bytes)
    }

    @Test func tM5_loadCatalogReroutesCatalogUnavailableItems() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        try h.bind([.r3: b("Default")])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        #expect(item.kind == .needsProfile(.catalogUnavailable(.notFound("/x/Local State"))))

        h.loader.state = .loaded(Fixture.validCatalog())
        // A non-rerouting load never re-routes.
        _ = h.coordinator.loadCatalog(reroutingBlocked: false)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items == [item])
        #expect(h.opener.callCount == 0)

        let state = h.coordinator.loadCatalog()
        #expect(state == .loaded(Fixture.validCatalog()))
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Default"])
        #expect(h.opener.urls == [Links.r3(1).absoluteString])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func tM5_reroutedItemKeepsIdAndSeq() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        try h.bind([.r3: b("Default")])
        h.enqueue(Links.r1(1), Links.r3(2))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.pendingItem(Links.r3(2)))

        h.loader.state = .loaded(Fixture.validCatalog())
        h.opener.failingCalls = [1]
        _ = h.coordinator.loadCatalog()
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Default"])
        let again = try #require(h.pendingItem(Links.r3(2)))
        #expect(again.id == item.id)
        #expect(again.seq == item.seq)
        #expect(again.kind == .launchFailed(.openFailed("fake open failure")))
        // The unset R1 item is not a catalog item and was not touched.
        #expect(h.pendingItem(Links.r1(1))?.kind == .needsProfile(.unset))
    }

    @Test func tM6_resetConfigToDefaultsReroutesConfigUnavailableItems() async throws {
        let h = try CoordinatorHarness(configFixture: "config-corrupt")
        defer { h.cleanup() }
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        guard case .needsProfile(.configUnavailable) = item.kind else {
            Issue.record("expected .configUnavailable, got \(item.kind)")
            return
        }

        try h.coordinator.resetConfigToDefaults()
        #expect(h.loadedConfig?.binding(for: .r3)?.directory == "Default")
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Default"])
        #expect(h.opener.urls == [Links.r3(1).absoluteString])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    // MARK: Final review #1: seeding re-routes `.unset` links

    @Test func firstRunUnsetLinkReroutesWhenALaterCatalogLoadSeedsItsRule() async throws {
        // Absent config.json and unreadable Local State (P-1): seeding cannot run, the link pends `.unset`.
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        #expect(h.loadedConfig == .unseededDefault)
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        #expect(item.kind == .needsProfile(.unset))

        // A non-rerouting load seeds but never launches.
        h.loader.state = .loaded(Fixture.validCatalog())
        _ = h.coordinator.loadCatalog(reroutingBlocked: false)
        await h.coordinator.waitUntilIdle()
        #expect(h.loadedConfig?.binding(for: .r3)?.directory == "Default")
        #expect(h.coordinator.pending.items == [item])
        #expect(h.opener.callCount == 0)

        // The next blocking load ("Refresh profiles") picks the bound `.unset` item up.
        _ = h.coordinator.loadCatalog()
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.callCount == 1)
        #expect(h.opener.directories == ["Default"])
        #expect(h.opener.urls == [Links.r3(1).absoluteString])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func unsetLinkOfAStillUnboundRuleStaysPendingAfterACatalogLoad() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        #expect(item.kind == .needsProfile(.unset))

        // Seeding is off (bind), so R3 stays "Not set".
        h.loader.state = .loaded(Fixture.validCatalog())
        _ = h.coordinator.loadCatalog()
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items == [item])
        #expect(h.opener.callCount == 0)
    }

    @Test func resetConfigToDefaultsReroutesUnsetLinksOfNewlySeededRules() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r1(1), Links.r3(2))
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.map(\.kind) == [.needsProfile(.unset), .needsProfile(.unset)])

        // Seeding happens only in ConfigController.resetToDefaults, after the coordinator's load.
        h.loader.seeds = false
        try h.coordinator.resetConfigToDefaults()
        #expect(h.loadedConfig?.binding(for: .r1)?.directory == "Profile 30")
        #expect(h.loadedConfig?.binding(for: .r3)?.directory == "Default")
        #expect(h.loadedConfig?.binding(for: .r4) == nil)
        await h.coordinator.waitUntilIdle()
        // The reset seeded R1 and R3, so both unset links open in seq order.
        #expect(h.opener.callCount == 2)
        #expect(h.opener.directories == ["Profile 30", "Default"])
        #expect(h.opener.urls == [Links.r1(1).absoluteString, Links.r3(2).absoluteString])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    // MARK: #13: last active Chrome profile fallback

    @Test func unsetFallbackLaunchesInLastActiveChromeWithoutPending() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r4(1))
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.requests.map(\.arguments) == [[Links.r4(1).absoluteString]])
        #expect(h.coordinator.pending.items.isEmpty)
        #expect(h.coordinator.recent == [.opened(host: "example.com", rule: .r4, directory: nil)])
    }

    @Test func unsetFallbackLaunchesWhileCatalogUnavailable() async throws {
        // Absent config.json and unreadable Local State: R4 still opens, R3 cannot.
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        #expect(h.loadedConfig == .unseededDefault)
        h.enqueue(Links.r4(1), Links.r3(2))
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.requests.map(\.arguments) == [[Links.r4(1).absoluteString]])
        #expect(h.coordinator.pending.items.count == 1)
        #expect(h.pendingItem(Links.r3(2))?.kind == .needsProfile(.unset))
    }

    @Test func choosingLastActiveForR4ReroutesItsPendingLinks() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r4: b("Profile 99")])
        let urls = (1...3).map(Links.r4)
        h.coordinator.enqueue(urls, source: .external)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.map(\.kind) == Array(repeating: .needsProfile(.missing(b("Profile 99"))), count: 3))
        #expect(h.opener.callCount == 0)

        try h.coordinator.updateBinding(rule: .r4, to: nil)
        #expect(h.loadedConfig?.binding(for: .r4) == nil)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.requests.map(\.arguments) == urls.map { [$0.absoluteString] })
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func burstWithLastActiveFallbackKeepsOrder() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r1: b("Profile 30"), .r2: b("Profile 47"), .r3: b("Default")])
        let urls = (1...8).map(Links.mixed)
        h.coordinator.enqueue(urls, source: .external)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.urls == urls.map(\.absoluteString))
        #expect(h.opener.directories == ["Profile 30", "Profile 47", "Default", "<last active>",
                                         "Profile 30", "Profile 47", "Default", "<last active>"])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    // MARK: Design review NITs

    @Test func tN3_openOnceWithUnavailableCatalogRetriesTheChosenDirectory() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.coordinator.pending.items.first)
        #expect(item.kind == .needsProfile(.unset))

        try h.coordinator.openOnce(id: item.id, directory: "Profile 7")
        await h.coordinator.waitUntilIdle()
        let blocked = try #require(h.coordinator.pending.items.first)
        #expect(blocked.id == item.id)
        #expect(blocked.kind == .needsProfile(.catalogUnavailable(.notFound("/x/Local State"))))
        #expect(blocked.lastAttempt == .resolved(directory: "Profile 7"))
        #expect(h.opener.callCount == 0)

        h.loader.state = .loaded(Fixture.validCatalog())
        try h.coordinator.retry(id: blocked.id)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Profile 7"])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func tN5_unseenAlertCountCountsRejectionsOnly() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r3: b("Default")])
        h.opener.failingCalls = [1]
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.first?.kind == .launchFailed(.openFailed("fake open failure")))
        #expect(h.coordinator.unseenAlertCount == 0)

        h.enqueue(URL(string: "ftp://github.com/x")!)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.unseenAlertCount == 1)
        #expect(h.coordinator.recent.first == .rejected(.unsupportedScheme("ftp")))

        h.coordinator.markAlertsSeen()
        #expect(h.coordinator.unseenAlertCount == 0)
        #expect(h.opener.callCount == 1)
    }
}

// MARK: #14: rule editing re-routes pending links

private let r5 = RuleID(number: 5)

private func hostDraft(_ host: String, binding: ProfileBinding? = nil) -> RuleDraft {
    RuleDraft(matchType: .host, host: host, binding: binding)
}

@MainActor
extension RoutingCoordinatorTests {
    @Test func addRuleReroutesPendingLinksItNowMatches() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        // A fixed fallback whose profile is gone: example.com links wait.
        try h.bind([.r4: b("Profile 99")])
        h.enqueue(Links.r4(1), Links.r4(2))
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        #expect(before.map(\.kind) == Array(repeating: .needsProfile(.missing(b("Profile 99"))), count: 2))

        let added = try h.coordinator.addRule(hostDraft("example.com", binding: b("Default")))
        #expect(added == r5)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.urls == [Links.r4(1).absoluteString, Links.r4(2).absoluteString])
        #expect(h.opener.directories == ["Default", "Default"])
        #expect(h.coordinator.pending.items.isEmpty)
        #expect(h.coordinator.recent.first == .opened(host: "example.com", rule: r5, directory: "Default"))
        #expect(h.loadedConfig?.ruleOrder == [.r1, .r2, .r3, r5, .fallback])
    }

    /// A new rule goes directly above the fallback, so a narrower rule for github.com only takes
    /// effect once it is moved above R3; each step re-routes the waiting links.
    @Test func addedRuleBelowABroaderRuleTakesEffectAfterMovingUp() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r1: b("Profile 30"), .r2: b("Profile 47")])
        h.enqueue(Links.r3(1), Links.r3(2))
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        #expect(before.map(\.kind) == [.needsProfile(.unset), .needsProfile(.unset)])

        try h.coordinator.addRule(RuleDraft(matchType: .hostPathPrefix, host: "github.com", pathPrefix: "/khuepm",
                                            binding: b("Default")))
        await h.coordinator.waitUntilIdle()
        #expect(h.loadedConfig.map(RuleAnalysis.issues) == [r5: .shadowed(by: .r3)])
        #expect(h.opener.callCount == 0)
        #expect(h.coordinator.pending.items.map(\.id) == before.map(\.id))

        try h.coordinator.moveRule(id: r5, by: -1)
        await h.coordinator.waitUntilIdle()
        #expect(h.loadedConfig?.ruleOrder == [.r1, .r2, r5, .r3, .fallback])
        #expect(h.opener.urls == [Links.r3(1).absoluteString, Links.r3(2).absoluteString])
        #expect(h.opener.directories == ["Default", "Default"])
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func rerouteKeepsIdAndSeqWhenTheLinkStillCannotLaunch() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let before = try #require(h.coordinator.pending.items.first)

        try h.coordinator.addRule(hostDraft("example.org"))
        await h.coordinator.waitUntilIdle()
        let after = try #require(h.coordinator.pending.items.first)
        #expect(h.coordinator.pending.items.count == 1)
        #expect(after.id == before.id)
        #expect(after.seq == before.seq)
        #expect(after.receivedAt == before.receivedAt)
        #expect(after.rule == .r3)
    }

    @Test func editRuleReroutesPending() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r3: b("Default")])
        h.enqueue(Links.r2(1))
        await h.coordinator.waitUntilIdle()
        #expect(h.pendingItem(Links.r2(1))?.kind == .needsProfile(.unset))

        try h.coordinator.updateRule(id: .r2, draft: RuleDraft(matchType: .hostPathPrefix, host: "github.com", pathPrefix: "/other/repo"))
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.urls == [Links.r2(1).absoluteString])
        #expect(h.opener.directories == ["Default"])
        #expect(h.coordinator.recent.first == .opened(host: "github.com", rule: .r3, directory: "Default"))
        #expect(h.coordinator.pending.items.isEmpty)
        #expect(h.loadedConfig?.rule(.r2)?.identity == "khue@truckerpoints.ai")
    }

    @Test func deleteRuleReroutesItsPendingLinks() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r3: b("Default")])
        h.enqueue(Links.r2(1), Links.r2(2))
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items.count == 2)

        try h.coordinator.deleteRule(id: .r2)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.urls == [Links.r2(1).absoluteString, Links.r2(2).absoluteString])
        #expect(h.opener.directories == ["Default", "Default"])
        #expect(h.coordinator.pending.items.isEmpty)
        #expect(h.loadedConfig?.ruleOrder == [.r1, .r3, .fallback])
    }

    @Test func moveRuleReroutesPending() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r3: b("Default")])
        h.enqueue(Links.r2(1))
        await h.coordinator.waitUntilIdle()

        try h.coordinator.moveRule(id: .r3, by: -1)
        await h.coordinator.waitUntilIdle()
        #expect(h.loadedConfig?.ruleOrder == [.r1, .r3, .r2, .fallback])
        #expect(h.opener.directories == ["Default"])
        #expect(h.coordinator.recent.first == .opened(host: "github.com", rule: .r3, directory: "Default"))
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func ruleChangeLeavesLaunchFailedAndCatalogUnavailableAlone() async throws {
        let failed = try CoordinatorHarness()
        defer { failed.cleanup() }
        try failed.bind(allBound)
        failed.opener.failingCalls = [1]
        failed.enqueue(Links.r1(1))
        await failed.coordinator.waitUntilIdle()
        let failedItems = failed.coordinator.pending.items
        #expect(failedItems.map(\.kind) == [.launchFailed(.openFailed("fake open failure"))])
        try failed.coordinator.addRule(hostDraft("example.org"))
        try failed.coordinator.moveRule(id: .r3, by: -1)
        await failed.coordinator.waitUntilIdle()
        #expect(failed.coordinator.pending.items == failedItems)
        #expect(failed.opener.callCount == 1)

        let unavailable = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { unavailable.cleanup() }
        try unavailable.bind([.r3: b("Default")])
        unavailable.enqueue(Links.r3(1))
        await unavailable.coordinator.waitUntilIdle()
        let unavailableItems = unavailable.coordinator.pending.items
        #expect(unavailableItems.map(\.kind) == [.needsProfile(.catalogUnavailable(.notFound("/x/Local State")))])
        try unavailable.coordinator.addRule(hostDraft("example.org"))
        await unavailable.coordinator.waitUntilIdle()
        #expect(unavailable.coordinator.pending.items == unavailableItems)
        #expect(unavailable.opener.callCount == 0)
    }

    @Test func invalidDraftWritesAndReroutesNothing() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        h.enqueue(Links.r3(1))
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        let bytes = try Data(contentsOf: h.file)
        let config = h.loadedConfig

        #expect(throws: RuleEditError.invalid([.wildcardHost])) { try h.coordinator.addRule(hostDraft("*.github.com")) }
        #expect(throws: RuleEditError.invalid([.duplicate(of: .r1)])) {
            try h.coordinator.updateRule(id: .r3, draft: hostDraft("git.fis.vn"))
        }
        #expect(throws: RuleEditError.fallbackImmutable) { try h.coordinator.deleteRule(id: .fallback) }
        #expect(throws: RuleEditError.ruleNotFound) { try h.coordinator.deleteRule(id: r5) }
        #expect(throws: RuleEditError.cannotMove) { try h.coordinator.moveRule(id: .r1, by: -1) }
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items == before)
        #expect(try Data(contentsOf: h.file) == bytes)
        #expect(h.loadedConfig == config)
    }

    @Test func ruleChangeWithConfigUnavailableThrowsAndReroutesNothing() async throws {
        let h = try CoordinatorHarness(configFixture: "config-corrupt")
        defer { h.cleanup() }
        h.enqueue(Links.r4(1))
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        guard before.count == 1, case .needsProfile(.configUnavailable)? = before.first?.kind else {
            Issue.record("expected one configUnavailable item, got \(before)")
            return
        }
        let bytes = try Data(contentsOf: h.file)

        #expect(throws: RuleEditError.configUnavailable) { try h.coordinator.addRule(hostDraft("example.org")) }
        #expect(throws: RuleEditError.configUnavailable) { try h.coordinator.updateRule(id: .r3, draft: hostDraft("example.org")) }
        #expect(throws: RuleEditError.configUnavailable) { try h.coordinator.deleteRule(id: .r3) }
        #expect(throws: RuleEditError.configUnavailable) { try h.coordinator.moveRule(id: .r3, by: -1) }
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items == before)
        #expect(h.opener.callCount == 0)
        #expect(try Data(contentsOf: h.file) == bytes)
    }

    @Test func failedSaveReroutesNothing() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([.r3: b("Default")])
        h.enqueue(Links.r2(1))
        await h.coordinator.waitUntilIdle()
        let before = h.coordinator.pending.items
        let config = h.loadedConfig
        // A read-only directory makes the atomic write fail.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: h.dir.url.path)

        do {
            try h.coordinator.deleteRule(id: .r2)
            Issue.record("expected the save to fail")
        } catch {
            guard case .saveFailed(.writeFailed) = error else {
                Issue.record("expected .saveFailed(.writeFailed), got \(error)")
                return
            }
        }
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items == before)
        #expect(h.opener.callCount == 0)
        #expect(h.loadedConfig == config)
    }

    @Test func rulesPersistAcrossRelaunch() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        try h.coordinator.addRule(RuleDraft(matchType: .hostPathPrefix, host: "GitHub.com", pathPrefix: "/Acme/App/",
                                            binding: b("Profile 8")))
        try h.coordinator.moveRule(id: r5, by: -1)
        try h.coordinator.moveRule(id: r5, by: -1)
        try h.coordinator.deleteRule(id: .r1)
        try h.coordinator.updateRule(id: .r3, draft: hostDraft("gitlab.com"))

        let relaunched = ConfigController(store: ConfigStore(fileURL: h.file))
        relaunched.load()
        guard case .loaded(let config) = relaunched.state else {
            Issue.record("expected a loaded config, got \(relaunched.state)")
            return
        }
        #expect(config == h.loadedConfig)
        #expect(config.ruleOrder == [r5, .r2, .r3, .fallback])
        #expect(config.rule(r5)?.match == .hostPathPrefix(host: "github.com", pathPrefix: "/Acme/App"))
        #expect(config.binding(for: r5)?.directory == "Profile 8")
        #expect(config.rule(.r3)?.match == .host("gitlab.com"))
        #expect(config.nextRuleNumber == 6)

        let decision = Router.decide(URL(string: "https://github.com/acme/app/pull/1")!, config: relaunched.routingConfig,
                                     catalog: .loaded(Fixture.validCatalog()))
        guard case .launch(let target, _) = decision else {
            Issue.record("expected .launch, got \(decision)")
            return
        }
        #expect(target.rule == r5)
        #expect(target.directory == "Profile 8")
    }

    @Test func openAndRememberOnDeletedRuleIsNotApplicable() async throws {
        let h = try CoordinatorHarness(catalog: .unavailable(.notFound("/x/Local State")))
        defer { h.cleanup() }
        try h.bind([.r2: b("Profile 47"), .r3: b("Default")])
        h.enqueue(Links.r2(1))
        await h.coordinator.waitUntilIdle()
        let item = try #require(h.pendingItem(Links.r2(1)))
        #expect(item.kind == .needsProfile(.catalogUnavailable(.notFound("/x/Local State"))))

        try h.coordinator.deleteRule(id: .r2)
        await h.coordinator.waitUntilIdle()
        #expect(h.coordinator.pending.items == [item])   // catalogUnavailable is left alone
        let bytes = try Data(contentsOf: h.file)

        h.loader.state = .loaded(Fixture.validCatalog())
        #expect(throws: PendingActionError.notApplicable) { try h.coordinator.openAndRemember(id: item.id, directory: "Default") }
        #expect(try Data(contentsOf: h.file) == bytes)
        #expect(throws: ConfigError.writeFailed("rule R2 no longer exists")) {
            try h.coordinator.updateBinding(rule: .r2, to: b("Default"))
        }
        #expect(try Data(contentsOf: h.file) == bytes)

        // Retry classifies the link again with the current rules: it now matches R3.
        try h.coordinator.retry(id: item.id)
        await h.coordinator.waitUntilIdle()
        #expect(h.opener.directories == ["Default"])
        #expect(h.coordinator.recent.first == .opened(host: "github.com", rule: .r3, directory: "Default"))
        #expect(h.coordinator.pending.items.isEmpty)
    }

    @Test func resetReroutesItemsOfRemovedRules() async throws {
        let h = try CoordinatorHarness()
        defer { h.cleanup() }
        try h.bind([:])
        try h.coordinator.addRule(hostDraft("example.com"))
        h.enqueue(Links.r4(1))
        await h.coordinator.waitUntilIdle()
        #expect(h.pendingItem(Links.r4(1))?.rule == r5)
        #expect(h.opener.callCount == 0)

        try h.coordinator.resetConfigToDefaults()
        await h.coordinator.waitUntilIdle()
        #expect(h.loadedConfig?.ruleOrder == [.r1, .r2, .r3, .fallback])
        #expect(h.opener.requests.map(\.arguments) == [[Links.r4(1).absoluteString]])   // last active Chrome profile
        #expect(h.coordinator.pending.items.isEmpty)
    }
}
