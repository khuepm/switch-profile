import AppKit
import SwiftUI
import SwitchProfileCore

/// State of the pending-links window: the head item (lowest seq) and a held catalog.
@MainActor
final class ResolutionModel: ObservableObject {
    @Published private(set) var items: [PendingItem] = []
    @Published private(set) var catalog: CatalogState = .unavailable(.notFound("not loaded yet"))
    @Published var selection: String?
    @Published private(set) var actionError: String?
    @Published private(set) var isConfigWritable = false

    private let coordinator: RoutingCoordinator
    private let configController: ConfigController
    private var shownHeadID: UUID?

    init(coordinator: RoutingCoordinator, configController: ConfigController) {
        self.coordinator = coordinator
        self.configController = configController
    }

    var head: PendingItem? { items.first }

    var catalogProfiles: [ChromeProfile] {
        if case .loaded(let catalog) = catalog { return catalog.profiles }
        return []
    }

    /// Re-reads the store; loads the catalog when the head item changed.
    func update() {
        let headID = coordinator.pending.items.first?.id
        if headID != shownHeadID {
            shownHeadID = headID
            selection = nil
            actionError = nil
            if headID != nil { loadCatalog() }
        }
        items = coordinator.pending.items
        isConfigWritable = configController.isWritable
    }

    func refreshProfiles() {
        actionError = nil
        loadCatalog()
        items = coordinator.pending.items
    }

    private func loadCatalog() {
        catalog = coordinator.loadCatalog()
        if let selection, !catalogProfiles.contains(where: { $0.directory == selection }) {
            self.selection = nil
        }
    }

    // MARK: Actions

    func openOnce() {
        guard let head, let selection else { return }
        perform { () throws(PendingActionError) in try coordinator.openOnce(id: head.id, directory: selection) }
    }

    func openAndRemember() {
        guard let head, let selection else { return }
        perform { () throws(PendingActionError) in try coordinator.openAndRemember(id: head.id, directory: selection) }
    }

    func retry() {
        guard let head else { return }
        perform { () throws(PendingActionError) in try coordinator.retry(id: head.id) }
    }

    func discard() {
        guard let head else { return }
        perform { () throws(PendingActionError) in try coordinator.discard(id: head.id) }
    }

    func copyURL() {
        guard let head else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(head.url.absoluteString, forType: .string)
    }

    /// A thrown error is shown inline and the item stays the head.
    private func perform(_ action: () throws(PendingActionError) -> Void) {
        do throws(PendingActionError) {
            try action()
            actionError = nil
        } catch {
            Log.ui.notice("Pending action failed: \(String(describing: error), privacy: .public)")
            actionError = UIText.pendingActionError(error)
        }
        update()
    }

    static func canRetry(_ kind: PendingKind) -> Bool {
        switch kind {
        case .launchFailed, .needsProfile(.catalogUnavailable), .needsProfile(.configUnavailable): true
        case .needsProfile(.unset), .needsProfile(.missing), .needsProfile(.identityMismatch): false
        }
    }
}

/// The pending-links window. Created, shown and closed only by `AppDelegate.stateDidChange`
/// (and the "Pending links (N)…" menu item).
@MainActor
final class ResolutionWindowController {
    private let model: ResolutionModel
    private let window: NSWindow

    init(coordinator: RoutingCoordinator, configController: ConfigController) {
        model = ResolutionModel(coordinator: coordinator, configController: configController)
        window = NSWindow(contentViewController: NSHostingController(rootView: ResolutionView(model: model)))
        window.title = "Switch Profile – Pending Links"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 360))
        window.center()
    }

    /// Shows and activates the window only if it is not visible; otherwise re-renders the head and "1 of N".
    func showIfNeeded() {
        model.update()
        guard !window.isVisible, model.head != nil else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        model.update()
        if window.isVisible { window.orderOut(nil) }
    }
}
