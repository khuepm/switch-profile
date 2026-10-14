import Foundation

/// Single owner of the in-memory configuration state and the only caller of `ConfigStore.save`.
/// Invariant: nothing is written while the state is `.unavailable`, except by `resetToDefaults`,
/// which backs the file up first.
@MainActor
public final class ConfigController {
    private let store: ConfigStore

    /// Never `.absent` after `load()`.
    public private(set) var state: ConfigState = .unavailable(.unreadable("not loaded"))

    /// Single closure, assigned only by the composition root, which fans out.
    public var onChange: (@MainActor () -> Void)?

    public init(store: ConfigStore) {
        self.store = store
    }

    public var routingConfig: RoutingConfig {
        switch state {
        case .loaded(let config): .loaded(config)
        case .unavailable(let error): .unavailable(error)
        case .absent: .unavailable(.unreadable("not loaded"))
        }
    }

    public var isWritable: Bool {
        if case .loaded = state { return true }
        return false
    }

    /// Reads the file. An absent file becomes `AppConfig.unseededDefault` in memory; nothing is written.
    public func load() {
        switch store.load() {
        case .absent:
            state = .loaded(.unseededDefault)
        case let loaded:
            state = loaded
        }
        onChange?()
    }

    /// Applies `body` to a copy, saves it, and commits it to memory only on success.
    public func update(_ body: (inout AppConfig) -> Void) throws(ConfigError) {
        guard case .loaded(var config) = state else {
            Log.config.error("Configuration write refused: configuration unavailable")
            throw .writeFailed("configuration unavailable")
        }
        body(&config)
        try store.save(config)
        state = .loaded(config)
        onChange?()
    }

    /// Seeding hook, called after every successful catalog load. Seeds once per config lifetime.
    public func catalogDidLoad(_ catalog: ProfileCatalog) {
        guard case .loaded(let config) = state, config.seedPending else { return }
        let seeded = ConfigSeeder.seed(config, catalog: catalog)
        do {
            try store.save(seeded)
        } catch {
            // Keep the unseeded config (seedPending still true); the next catalog load retries.
            Log.config.error("Saving seeded configuration failed: \(String(describing: error), privacy: .public)")
            return
        }
        state = .loaded(seeded)
        let count = RuleID.allCases.filter { config.targets[$0].binding == nil && seeded.targets[$0].binding != nil }.count
        Log.config.info("Seeded \(count, privacy: .public) of 3 rules")
        onChange?()
    }

    /// Backs the current file up, writes `AppConfig.unseededDefault`, then loads the catalog so the
    /// seeding hook runs. If the backup or the save fails, the state is unchanged and the error is thrown;
    /// a later call succeeds because a missing file is tolerated by the backup step.
    public func resetToDefaults(catalogLoader: @MainActor () -> CatalogState) throws(ConfigError) {
        try store.backupCorruptFile(now: Date())
        let fresh = AppConfig.unseededDefault
        try store.save(fresh)
        state = .loaded(fresh)
        Log.config.notice("Configuration reset to defaults")
        onChange?()
        if case .loaded(let catalog) = catalogLoader() {
            // The production loader already calls the hook; a second call is a no-op once seeded.
            catalogDidLoad(catalog)
        }
    }
}
