import Foundation

/// Where a fresh URL came from (informational). Re-enqueued pending items are queued as `.external`.
public enum URLSource: Sendable {
    /// Delivered by macOS (`application(_:open:)`).
    case external
    /// "Open test link" in Settings.
    case test
}

/// What one attempt does with a URL; also what Retry repeats.
public enum AttemptKind: Equatable, Sendable {
    /// Classify and route through the current configuration.
    case route
    /// Launch with a profile the user chose ("Open once" / "Open and use").
    case resolved(directory: String)
}

/// One entry of the coordinator's intake queue.
struct QueuedURL: Sendable {
    /// Monotonic per append (including re-enqueues); used only for batching.
    let ticket: UInt64
    /// Receipt order; assigned once at first enqueue and kept forever.
    let seq: UInt64
    /// Assigned once at first enqueue; becomes `PendingItem.id`.
    let id: UUID
    let url: URL
    let source: URLSource
    /// nil for fresh URLs; set for re-enqueued pending items.
    let rule: RuleID?
    let kind: AttemptKind
    /// First receipt time; kept through re-enqueues.
    let receivedAt: Date
}

public enum PendingKind: Equatable, Sendable {
    case needsProfile(ProfileIssue)
    case launchFailed(LaunchError)
}

/// A URL that could not be opened and waits for a user action.
public struct PendingItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let seq: UInt64
    public let url: URL
    public let rule: RuleID
    public let kind: PendingKind
    /// What Retry repeats.
    public let lastAttempt: AttemptKind
    public let receivedAt: Date

    public init(id: UUID, seq: UInt64, url: URL, rule: RuleID, kind: PendingKind, lastAttempt: AttemptKind, receivedAt: Date) {
        self.id = id
        self.seq = seq
        self.url = url
        self.rule = rule
        self.kind = kind
        self.lastAttempt = lastAttempt
        self.receivedAt = receivedAt
    }
}

/// Pending items, owned by `RoutingCoordinator`.
public struct PendingStore: Equatable, Sendable {
    /// Always sorted by `seq` ascending.
    public private(set) var items: [PendingItem] = []

    init() {}

    /// Replaces the item with the same id, otherwise inserts it in `seq` order.
    mutating func upsert(_ item: PendingItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            let index = items.firstIndex { $0.seq > item.seq } ?? items.endIndex
            items.insert(item, at: index)
        }
    }

    @discardableResult
    mutating func remove(id: UUID) -> PendingItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    func item(id: UUID) -> PendingItem? {
        items.first { $0.id == id }
    }
}

public enum RecentEvent: Equatable, Sendable {
    case opened(host: String, rule: RuleID, directory: String)
    case rejected(Rejection)
    case discarded(rule: RuleID)
}

/// Notified after every coordinator state change; the UI re-reads `pending` and `recent`.
public protocol RoutingEventSink: AnyObject {
    @MainActor func coordinatorDidChange()
}

public enum PendingActionError: Error, Equatable, Sendable {
    case itemNotFound
    case notApplicable
    case configUnavailable
    case profileNotFound(String)
    case catalogUnavailable(LocalStateError)
    case saveFailed(ConfigError)
}
