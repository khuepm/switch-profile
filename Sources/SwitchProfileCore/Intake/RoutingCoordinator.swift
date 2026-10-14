import Foundation

/// The only owner of the intake queue and the `PendingStore`, and the only caller of
/// `ChromeLauncher.launch`. Every launch, including user actions on pending items, goes through
/// one serial worker, so launch requests are issued strictly in queue order.
///
/// Pending actions are synchronous: they validate, mutate state, and either throw or queue work.
/// They never launch directly. Every public mutating method ends with `startDrainIfNeeded()` and
/// `sink?.coordinatorDidChange()`.
@MainActor
public final class RoutingCoordinator {
    public static let recentCapacity = 20

    private let config: ConfigController
    private let catalogLoader: @MainActor () -> CatalogState
    private let launcher: ChromeLauncher
    private let now: @Sendable () -> Date

    public weak var sink: (any RoutingEventSink)?
    public private(set) var pending = PendingStore()
    /// Newest first, at most `recentCapacity` entries.
    public private(set) var recent: [RecentEvent] = []
    /// Rejected fresh URLs since the last `markAlertsSeen()`. Launch errors do not count.
    public private(set) var unseenAlertCount = 0
    public private(set) var isReady = false

    private var queue: [QueuedURL] = []
    /// Set by the worker from dequeue until the item's outcome is applied.
    private var inFlight: QueuedURL?
    /// Exists only while draining.
    private var drainTask: Task<Void, Never>?
    private var lastTicket: UInt64 = 0
    private var lastSeq: UInt64 = 0

    public init(config: ConfigController, catalogLoader: @escaping @MainActor () -> CatalogState,
                launcher: ChromeLauncher, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.catalogLoader = catalogLoader
        self.launcher = launcher
        self.now = now
    }

    /// Links not yet finished: pending, queued, and the one being processed.
    public var unfinishedCount: Int {
        pending.items.count + queue.count + (inFlight == nil ? 0 : 1)
    }

    // MARK: Intake

    /// Appends one queue entry per URL, in array order. Only buffers until `markReady()`.
    public func enqueue(_ urls: [URL], source: URLSource) {
        for url in urls {
            lastSeq += 1
            append(id: UUID(), seq: lastSeq, url: url, source: source, rule: nil, kind: .route, receivedAt: now())
        }
        startDrainIfNeeded()
    }

    /// Starts draining; called once the configuration is loaded.
    public func markReady() {
        isReady = true
        startDrainIfNeeded()
    }

    /// Returns once the queue is empty and the worker has stopped.
    public func waitUntilIdle() async {
        while let task = drainTask {
            await task.value
        }
    }

    public func markAlertsSeen() {
        unseenAlertCount = 0
        startDrainIfNeeded()
        sink?.coordinatorDidChange()
    }

    // MARK: Catalog, configuration and re-routing (design review #1)

    /// The single catalog read used by the worker and every UI path. On a successful load with
    /// `reroutingBlocked`, every `.needsProfile(.catalogUnavailable)` item (all rules) is re-enqueued
    /// with its last attempt, and every `.needsProfile(.unset)` item whose rule now has a binding
    /// (typically just seeded by this or an earlier load) is re-enqueued as `.route`.
    /// "Check rule" passes `false`, so a preview never causes a launch.
    /// The sink is notified only when items were re-enqueued, so plain reads cause no UI fan-out.
    public func loadCatalog(reroutingBlocked: Bool = true) -> CatalogState {
        loadCatalog(reroutingBlocked: reroutingBlocked, excluding: nil)
    }

    /// Re-enqueues, in ascending `seq`, every pending item of `rule` that is
    /// `.needsProfile(.unset | .missing | .identityMismatch | .configUnavailable)` as `.route`,
    /// with the same `id`, `seq` and `rule`. `.launchFailed` and `.catalogUnavailable` are left alone.
    public func reroutePending(rule: RuleID) {
        let items = pending.items.filter { $0.rule == rule && Self.isReroutable($0.kind) }
        for item in items {
            requeue(item, kind: .route)
        }
        if !items.isEmpty {
            Log.routing.info("Re-routing \(items.count, privacy: .public) pending link(s) of \(rule.rawValue, privacy: .public)")
        }
        startDrainIfNeeded()
        sink?.coordinatorDidChange()
    }

    /// The Settings write path for bindings (`SettingsModel.select`, `detect` with a unique result,
    /// and `confirmBinding`). Saves the binding and, only on success with a non-nil binding,
    /// re-routes the rule's pending links. Choosing "Not set" or a failed save re-routes nothing.
    public func updateBinding(rule: RuleID, to binding: ProfileBinding?) throws(ConfigError) {
        try config.update { $0.targets[rule].binding = binding }
        if binding != nil {
            reroutePending(rule: rule)
        } else {
            startDrainIfNeeded()
            sink?.coordinatorDidChange()
        }
    }

    /// "Reset to defaults…" for the menu and Settings. On success every
    /// `.needsProfile(.configUnavailable)` item (all rules) is re-enqueued with its last attempt, and
    /// every `.needsProfile(.unset)` item whose rule the reset seeded is re-enqueued as `.route`.
    public func resetConfigToDefaults() throws(ConfigError) {
        try config.resetToDefaults(catalogLoader: { self.loadCatalog() })
        let items = pending.items.filter {
            if case .needsProfile(.configUnavailable) = $0.kind { return true }
            return isBoundUnset($0)
        }
        for item in items {
            requeue(item, kind: isBoundUnset(item) ? .route : item.lastAttempt)
        }
        startDrainIfNeeded()
        sink?.coordinatorDidChange()
    }

    // MARK: Pending actions

    /// Allowed for any pending item; writes nothing. Re-enqueues the item at the tail with `directory`.
    public func openOnce(id: UUID, directory: String) throws(PendingActionError) {
        guard let item = pending.item(id: id) else { throw .itemNotFound }
        requeue(item, kind: .resolved(directory: directory))
        startDrainIfNeeded()
        sink?.coordinatorDidChange()
    }

    /// Saves `directory` as the rule's binding, opens the item with it, and re-routes the rule's
    /// other pending links. Nothing is written unless every check passes.
    public func openAndRemember(id: UUID, directory: String) throws(PendingActionError) {
        // 1. Exists and needs a profile.
        guard let item = pending.item(id: id) else { throw .itemNotFound }
        guard case .needsProfile = item.kind else { throw .notApplicable }
        // 2. Configuration writable.
        guard config.isWritable else { throw .configUnavailable }
        // 3. Fresh catalog containing the directory. This item is excluded from catalog re-routing
        //    so it cannot be queued twice.
        let catalog: ProfileCatalog
        switch loadCatalog(reroutingBlocked: true, excluding: item.id) {
        case .unavailable(let error): throw .catalogUnavailable(error)
        case .loaded(let loaded): catalog = loaded
        }
        guard let profile = catalog.profile(directory: directory) else { throw .profileNotFound(directory) }
        // 4. Save.
        do throws(ConfigError) {
            try config.update { $0.targets[item.rule].binding = ProfileBinding(profile: profile, matchedBy: nil) }
        } catch {
            throw .saveFailed(error)
        }
        // 5. Open this item with the chosen directory, then re-route the rule's other links.
        requeue(item, kind: .resolved(directory: directory))
        reroutePending(rule: item.rule)
    }

    /// Repeats the last attempt of a `.launchFailed`, `.catalogUnavailable` or `.configUnavailable`
    /// item. Kinds that need a profile choice throw `.notApplicable`.
    public func retry(id: UUID) throws(PendingActionError) {
        guard let item = pending.item(id: id) else { throw .itemNotFound }
        switch item.kind {
        case .launchFailed, .needsProfile(.catalogUnavailable), .needsProfile(.configUnavailable):
            break
        case .needsProfile(.unset), .needsProfile(.missing), .needsProfile(.identityMismatch):
            throw .notApplicable
        }
        requeue(item, kind: item.lastAttempt)
        startDrainIfNeeded()
        sink?.coordinatorDidChange()
    }

    public func discard(id: UUID) throws(PendingActionError) {
        guard let item = pending.remove(id: id) else { throw .itemNotFound }
        record(.discarded(rule: item.rule))
        Log.routing.notice("Discarded a pending link of \(item.rule.rawValue, privacy: .public)")
        startDrainIfNeeded()
        sink?.coordinatorDidChange()
    }

    // MARK: Worker

    private func startDrainIfNeeded() {
        guard isReady, drainTask == nil, !queue.isEmpty else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        var catalog = loadCatalog()
        var batchEnd = lastTicket
        while !queue.isEmpty {
            let item = queue.removeFirst()
            inFlight = item
            // Exact "per batch" rule: anything appended after the last load triggers a fresh one.
            if item.ticket > batchEnd {
                catalog = loadCatalog()
                batchEnd = lastTicket
            }
            await process(item, catalog: catalog)
            inFlight = nil
            sink?.coordinatorDidChange()
        }
        // No suspension point between the empty check and this line, so no enqueue can fall into the gap.
        drainTask = nil
    }

    private func process(_ item: QueuedURL, catalog: CatalogState) async {
        let decision = decide(item, catalog: catalog)
        switch decision {
        case .launch(let target, _):
            do throws(LaunchError) {
                try await launcher.launch(target)
                record(.opened(host: target.url.host() ?? "", rule: target.rule, directory: target.directory))
                Log.routing.info("Opened \(target.rule.rawValue, privacy: .public) link for host \(target.url.host() ?? "", privacy: .private)")
            } catch {
                pending.upsert(pendingItem(item, rule: target.rule, kind: .launchFailed(error)))
                Log.routing.error("Launch failed for \(target.rule.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        case .needsProfile(_, let rule, let issue, _):
            pending.upsert(pendingItem(item, rule: rule, kind: .needsProfile(issue)))
            Log.routing.notice("Link of \(rule.rawValue, privacy: .public) is pending: \(Self.issueName(issue), privacy: .public)")
        case .rejected(_, let rejection):
            record(.rejected(rejection))
            // A pending item cannot be rejected (it was classified already); only fresh URLs count.
            if item.rule == nil { unseenAlertCount += 1 }
            Log.routing.notice("Rejected a link: \(String(describing: rejection), privacy: .public)")
        }
    }

    private func decide(_ item: QueuedURL, catalog: CatalogState) -> RoutingDecision {
        guard case .resolved(let directory) = item.kind, let rule = item.rule else {
            // Configuration is read per item.
            return Router.decide(item.url, config: config.routingConfig, catalog: catalog)
        }
        let explanation = "\(rule.rawValue): chosen profile \(directory)"
        switch catalog {
        case .unavailable(let error):
            return .needsProfile(url: item.url, rule: rule, issue: .catalogUnavailable(error), explanation: explanation)
        case .loaded(let profiles) where profiles.profile(directory: directory) == nil:
            let binding = ProfileBinding(directory: directory, email: nil, displayName: directory, matchedBy: nil)
            return .needsProfile(url: item.url, rule: rule, issue: .missing(binding), explanation: explanation)
        case .loaded:
            return .launch(LaunchTarget(url: item.url, rule: rule, directory: directory), explanation: explanation)
        }
    }

    // MARK: Helpers

    private func loadCatalog(reroutingBlocked: Bool, excluding excluded: UUID?) -> CatalogState {
        let state = catalogLoader()
        guard reroutingBlocked, case .loaded = state else { return state }
        // State-based, not a before/after diff: a seed during a `reroutingBlocked: false` load is
        // picked up here on the next load. A bound rule never routes back to `.unset`, so no loop.
        let items = pending.items.filter {
            guard $0.id != excluded else { return false }
            if case .needsProfile(.catalogUnavailable) = $0.kind { return true }
            return isBoundUnset($0)
        }
        guard !items.isEmpty else { return state }
        for item in items {
            requeue(item, kind: isBoundUnset(item) ? .route : item.lastAttempt)
        }
        Log.routing.info("Chrome profiles loaded; re-routing \(items.count, privacy: .public) pending link(s)")
        startDrainIfNeeded()
        sink?.coordinatorDidChange()
        return state
    }

    /// Removes a pending item and appends it at the tail with the same id, seq, rule and source time.
    private func requeue(_ item: PendingItem, kind: AttemptKind) {
        pending.remove(id: item.id)
        append(id: item.id, seq: item.seq, url: item.url, source: .external, rule: item.rule, kind: kind,
               receivedAt: item.receivedAt)
    }

    private func append(id: UUID, seq: UInt64, url: URL, source: URLSource, rule: RuleID?, kind: AttemptKind, receivedAt: Date) {
        lastTicket += 1
        queue.append(QueuedURL(ticket: lastTicket, seq: seq, id: id, url: url, source: source, rule: rule,
                               kind: kind, receivedAt: receivedAt))
    }

    private func pendingItem(_ item: QueuedURL, rule: RuleID, kind: PendingKind) -> PendingItem {
        // NIT #3: record what was attempted, so Retry repeats an "Open once" choice.
        PendingItem(id: item.id, seq: item.seq, url: item.url, rule: rule, kind: kind,
                    lastAttempt: item.kind, receivedAt: item.receivedAt)
    }

    private func record(_ event: RecentEvent) {
        recent.insert(event, at: 0)
        if recent.count > Self.recentCapacity {
            recent.removeLast(recent.count - Self.recentCapacity)
        }
    }

    /// A `.needsProfile(.unset)` item whose rule has a binding in the current configuration,
    /// e.g. after first-run seeding ran on a later successful catalog load.
    private func isBoundUnset(_ item: PendingItem) -> Bool {
        guard case .needsProfile(.unset) = item.kind, case .loaded(let current) = config.routingConfig else { return false }
        return current.targets[item.rule].binding != nil
    }

    private static func isReroutable(_ kind: PendingKind) -> Bool {
        switch kind {
        case .needsProfile(.unset), .needsProfile(.missing), .needsProfile(.identityMismatch),
             .needsProfile(.configUnavailable):
            true
        case .needsProfile(.catalogUnavailable), .launchFailed:
            false
        }
    }

    private static func issueName(_ issue: ProfileIssue) -> String {
        switch issue {
        case .unset: "unset"
        case .missing(let binding): "missing \(binding.directory)"
        case .identityMismatch(let binding, _): "identity mismatch \(binding.directory)"
        case .catalogUnavailable: "catalog unavailable"
        case .configUnavailable: "configuration unavailable"
        }
    }
}
