import AppKit
import SwitchProfileCore

/// The menu bar item: attention icon and a menu rebuilt every time it opens.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Menu actions, provided by `AppDelegate`.
    struct Actions {
        var refreshMappingAttention: @MainActor () -> Void
        /// nil hides the default-browser lines.
        var defaultBrowserSummary: @MainActor () -> (text: String, isDefault: Bool)?
        var setAsDefault: @MainActor () -> Void
        var showPending: @MainActor () -> Void
        var resetToDefaults: @MainActor () -> Void
        var openSettings: @MainActor () -> Void
    }

    private static let normalSymbol = "arrow.triangle.branch"
    private static let attentionSymbol = "exclamationmark.triangle"

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let coordinator: RoutingCoordinator
    private let configController: ConfigController
    private let actions: Actions
    private var showsAttention: Bool?

    /// Rules whose binding is missing or changed account (`AppDelegate.refreshMappingAttention`).
    var mappingAttention: [RuleID] = [] {
        didSet { refresh() }
    }

    init(coordinator: RoutingCoordinator, configController: ConfigController, actions: Actions) {
        self.coordinator = coordinator
        self.configController = configController
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refresh()
    }

    /// Icon and accessibility state.
    func refresh() {
        let attention = !coordinator.pending.items.isEmpty
            || !mappingAttention.isEmpty
            || !configController.isWritable
            || coordinator.unseenAlertCount > 0
        guard attention != showsAttention, let button = statusItem.button else { return }
        showsAttention = attention
        let description = attention ? "Switch Profile – needs attention" : "Switch Profile"
        let image = NSImage(systemSymbolName: attention ? Self.attentionSymbol : Self.normalSymbol,
                            accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        actions.refreshMappingAttention()
        // Opening the menu clears only the unseen rejection part of the attention state.
        coordinator.markAlertsSeen()
        rebuild()
    }

    // MARK: Menu

    private func rebuild() {
        menu.removeAllItems()

        if let summary = actions.defaultBrowserSummary() {
            menu.addItem(disabledItem(summary.text))
            if !summary.isDefault {
                menu.addItem(item("Set as Default Browser…", #selector(setAsDefault)))
            }
        }
        let pendingCount = coordinator.pending.items.count
        if pendingCount > 0 {
            menu.addItem(item("Pending links (\(pendingCount))…", #selector(showPending)))
        }
        if !configController.isWritable {
            menu.addItem(item("Configuration error – Reset to defaults…", #selector(resetToDefaults)))
        }
        if !mappingAttention.isEmpty {
            let rules = mappingAttention.map(\.rawValue).joined(separator: ", ")
            menu.addItem(item("Profile mapping needs attention (\(rules))…", #selector(openSettings)))
        }
        if menu.numberOfItems > 0 {
            menu.addItem(.separator())
        }

        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Recent")
        recentMenu.autoenablesItems = false
        if coordinator.recent.isEmpty {
            recentMenu.addItem(disabledItem("No recent links"))
        } else {
            for event in coordinator.recent {
                recentMenu.addItem(disabledItem(Self.describe(event)))
            }
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Switch Profile", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func setAsDefault() { actions.setAsDefault() }
    @objc private func showPending() { actions.showPending() }
    @objc private func resetToDefaults() { actions.resetToDefaults() }
    @objc private func openSettings() { actions.openSettings() }

    /// Host, rule and directory only.
    static func describe(_ event: RecentEvent) -> String {
        switch event {
        case .opened(let host, let rule, let directory):
            "\(host) → \(rule.rawValue) → \(directory ?? "last active Chrome profile")"
        case .rejected(.unsupportedScheme(let scheme)):
            "Rejected \(scheme): link"
        case .rejected(.malformed):
            "Rejected malformed link"
        case .discarded(let rule):
            "Discarded \(rule.rawValue) link"
        }
    }
}
