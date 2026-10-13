import AppKit
import SwitchProfileCore

/// Composition root and the single consumer of coordinator and configuration change events.
/// It is the only assigner of `coordinator.sink` and `configController.onChange`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, RoutingEventSink {
    private let configController: ConfigController
    private let coordinator: RoutingCoordinator
    /// What every consumer other than the coordinator uses, so catalog recovery re-routes pending links.
    private let catalogLoader: @MainActor () -> CatalogState

    private var statusItemController: StatusItemController?
    private var isRefreshingAttention = false
    private var terminationSource: (any DispatchSourceSignal)?

    override init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configController = ConfigController(store: ConfigStore(fileURL: AppPaths.configFile(home: home)))

        // The single raw catalog loader, given only to the coordinator.
        let localState = ChromePaths.localState(home: home)
        let rawCatalogLoader: @MainActor () -> CatalogState = { [configController] in
            let state: CatalogState
            // Inside a closure, a plain `do` infers `any Error`; `do throws(...)` is required.
            do throws(LocalStateError) { state = .loaded(try LocalStateLoader.load(from: localState)) }
            catch { state = .unavailable(error) }
            if case .loaded(let catalog) = state { configController.catalogDidLoad(catalog) }   // seeding hook
            return state
        }

        let opener = WorkspaceApplicationOpener()
        let launcher = ChromeLauncher(locator: opener, opener: opener,
                                      ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.khuepm.switchprofile")
        let coordinator = RoutingCoordinator(config: configController, catalogLoader: rawCatalogLoader, launcher: launcher)

        self.configController = configController
        self.coordinator = coordinator
        self.catalogLoader = { [coordinator] in coordinator.loadCatalog() }
        super.init()
    }

    // MARK: NSApplicationDelegate

    /// AppKit turns GURL Apple events into this call, on cold launch too (possibly before
    /// `applicationDidFinishLaunching`); the coordinator buffers until `markReady()`.
    func application(_ application: NSApplication, open urls: [URL]) {
        coordinator.enqueue(urls, source: .external)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationSignalHandler()
        // 1. An absent file becomes the in-memory unseeded default; nothing is written.
        configController.load()
        // 2. Status item and the event fan-out.
        statusItemController = StatusItemController(
            coordinator: coordinator,
            configController: configController,
            actions: StatusItemController.Actions(
                refreshMappingAttention: { [weak self] in self?.refreshMappingAttention() },
                defaultBrowserSummary: { nil },
                setAsDefault: {},
                showPending: {},
                resetToDefaults: {},
                openSettings: {}
            )
        )
        coordinator.sink = self
        configController.onChange = { [weak self] in self?.stateDidChange(configChanged: true) }
        // 3. Start draining; the first batch's catalog load seeds the config if needed.
        coordinator.markReady()
        // 4. Launch-time mapping check.
        refreshMappingAttention()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = coordinator.unfinishedCount
        guard count > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count == 1
            ? "1 link has not been opened and will be discarded"
            : "\(count) links have not been opened and will be discarded"
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: Event fan-out

    func coordinatorDidChange() {
        stateDidChange(configChanged: false)
    }

    private func stateDidChange(configChanged: Bool) {
        // 0. Render the new attention state after a configuration change.
        if configChanged { refreshMappingAttention() }
        // 1. Icon and attention state.
        statusItemController?.refresh()
    }

    /// Flags rules whose binding is missing or changed account, without waiting for a URL.
    private func refreshMappingAttention() {
        // The catalog load can seed, which saves and fires onChange, which calls this again.
        guard !isRefreshingAttention else { return }
        guard case .loaded = configController.state else {
            statusItemController?.mappingAttention = []
            return
        }
        isRefreshingAttention = true
        defer { isRefreshingAttention = false }
        let catalog = catalogLoader()
        // Re-read: the load may have seeded.
        guard case .loaded(let config) = configController.state else {
            statusItemController?.mappingAttention = []
            return
        }
        let attention = ConfigValidator.needsAttention(ConfigValidator.status(config: config, catalog: catalog))
        if attention != statusItemController?.mappingAttention {
            Log.profiles.notice("Profile mapping attention: \(attention.map(\.rawValue).joined(separator: ","), privacy: .public)")
        }
        statusItemController?.mappingAttention = attention
    }

    // MARK: SIGTERM

    /// Lets `pkill -TERM` quit through `NSApp.terminate`, which keeps the unfinished-links alert.
    private func installTerminationSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                Log.ui.notice("SIGTERM received; terminating")
                NSApp.terminate(nil)
            }
        }
        source.resume()
        terminationSource = source
    }
}
