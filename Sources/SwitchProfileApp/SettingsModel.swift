import AppKit
import SwitchProfileCore

/// The inline rule editor's fields.
struct RuleDraftState: Equatable {
    /// nil while adding a new rule.
    var editing: RuleID?
    var matchType: RuleMatchType
    var host: String
    var pathPrefix: String
    /// Profile for a new rule (nil: not set). Editing keeps the row's profile picker instead.
    var directory: String?
}

/// State and actions of the Settings window. All decisions are delegated to Core; every binding
/// write goes through `RoutingCoordinator.updateBinding(rule:to:)`, and every rule add, edit, delete
/// or move through the coordinator's rule operations, so pending links re-route.
@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var configState: ConfigState
    @Published private(set) var catalog: CatalogState = .unavailable(.notFound("not loaded yet"))
    @Published private(set) var statuses: [RuleID: TargetStatus] = [:]
    @Published private(set) var defaultBrowser: DefaultBrowserService.Status
    /// Per-rule inline messages (Detect results, save errors).
    @Published private(set) var ruleMessages: [RuleID: String] = [:]
    @Published private(set) var defaultBrowserMessage: String?
    @Published private(set) var recordMessage: String?
    @Published private(set) var isAwaitingConfirmation = false
    @Published private(set) var configMessage: String?
    /// Duplicate and shadowing warnings per rule (`RuleAnalysis`).
    @Published private(set) var ruleIssues: [RuleID: RuleIssue] = [:]
    /// The one rule being added or edited inline; nil when no editor is open.
    @Published var draft: RuleDraftState? {
        didSet { if showsDraftErrors { draftErrors = validation(of: draft)?.errors ?? [] } }
    }
    /// Shown under the editor's fields once Save was pressed; recomputed on every later change.
    @Published private(set) var draftErrors: [RuleFieldError] = []
    /// A save error that is not a field error (configuration unavailable, write failed).
    @Published private(set) var draftMessage: String?

    private let configController: ConfigController
    private let coordinator: RoutingCoordinator
    private let defaultBrowserService: DefaultBrowserService
    /// The same confirmation flow as the menu item; returns true to proceed.
    private let confirmReset: @MainActor () -> Bool
    /// Asks before deleting a rule (id, description); returns true to delete.
    private let confirmDeleteRule: @MainActor (RuleID, String) -> Bool
    private var showsDraftErrors = false

    /// NIT #8: while a `setDefaultApplication` call is in flight, notification re-reads may only report success.
    private var setCallInFlight = false
    /// Per attempt: the https call is made at most once.
    private var httpsRequested = false

    init(configController: ConfigController, coordinator: RoutingCoordinator,
         defaultBrowserService: DefaultBrowserService, confirmReset: @escaping @MainActor () -> Bool,
         confirmDeleteRule: @escaping @MainActor (RuleID, String) -> Bool) {
        self.configController = configController
        self.coordinator = coordinator
        self.defaultBrowserService = defaultBrowserService
        self.confirmReset = confirmReset
        self.confirmDeleteRule = confirmDeleteRule
        configState = configController.state
        defaultBrowser = defaultBrowserService.status()
    }

    // MARK: Derived state

    var config: AppConfig? {
        if case .loaded(let config) = configState { return config }
        return nil
    }

    var isConfigWritable: Bool { config != nil }

    /// Set while Chrome profiles are unavailable; unseeded rules then report `.unset` for this reason.
    var catalogError: LocalStateError? {
        if case .unavailable(let error) = catalog { return error }
        return nil
    }

    var catalogProfiles: [ChromeProfile] {
        if case .loaded(let catalog) = catalog { return catalog.profiles }
        return []
    }

    func boundDirectory(_ rule: RuleID) -> String? {
        config?.binding(for: rule)?.directory
    }

    /// The rules above the fallback; the built-in ones while the configuration is unavailable
    /// (shown disabled, as routing then uses them).
    var userRules: [RuleID] {
        (config ?? .unseededDefault).rules.map(\.id)
    }

    /// The saved previous browser, when its app still exists.
    var restorableBrowser: DefaultBrowserRecord? {
        guard let record = config?.previousDefaultBrowser,
              FileManager.default.fileExists(atPath: record.path) else { return nil }
        return record
    }

    // MARK: Loading

    /// Window open and Refresh: loads the catalog (through the coordinator) and recomputes.
    func reload() {
        catalog = coordinator.loadCatalog()
        refresh()
    }

    /// Recomputes from the held catalog; never loads (NIT #6).
    func refresh() {
        configState = configController.state
        if let config {
            statuses = ConfigValidator.status(config: config, catalog: catalog)
            ruleIssues = RuleAnalysis.issues(config)
        } else {
            statuses = [:]
            ruleIssues = [:]
        }
        // An edited rule that no longer exists (or a config that became unavailable) closes the editor.
        if let editing = draft?.editing, config?.rule(editing) == nil {
            cancelDraft()
        } else if draft != nil, config == nil {
            cancelDraft()
        }
        defaultBrowser = defaultBrowserService.status()
    }

    // MARK: Rule list (#14)

    func beginAdd() {
        startDraft(RuleDraftState(editing: nil, matchType: .host, host: "", pathPrefix: "", directory: nil))
    }

    func beginEdit(_ rule: RuleID) {
        guard let existing = config?.rule(rule) else { return }
        startDraft(RuleDraftState(editing: rule, matchType: existing.match.type, host: existing.match.host,
                                  pathPrefix: existing.match.pathPrefix ?? "", directory: nil))
    }

    func cancelDraft() {
        showsDraftErrors = false
        draft = nil
        draftErrors = []
        draftMessage = nil
    }

    /// Validates through the coordinator, which saves and re-routes waiting links on success.
    func saveDraft() {
        guard let draft else { return }
        draftMessage = nil
        var ruleDraft = RuleDraft(matchType: draft.matchType, host: draft.host, pathPrefix: draft.pathPrefix)
        if draft.editing == nil, let directory = draft.directory {
            guard case .loaded(let catalog) = catalog, let profile = catalog.profile(directory: directory) else {
                draftMessage = "Profile '\(directory)' no longer exists – press Refresh"
                return
            }
            ruleDraft.binding = ProfileBinding(profile: profile, matchedBy: nil)
        }
        do throws(RuleEditError) {
            if let editing = draft.editing {
                try coordinator.updateRule(id: editing, draft: ruleDraft)
            } else {
                try coordinator.addRule(ruleDraft)
            }
            cancelDraft()
        } catch {
            if case .invalid(let errors) = error {
                showsDraftErrors = true
                draftErrors = errors
            } else {
                Log.ui.notice("Saving a rule failed: \(String(describing: error), privacy: .public)")
                draftMessage = UIText.ruleEditError(error)
            }
        }
        refresh()
    }

    func deleteRule(_ rule: RuleID) {
        ruleMessages[rule] = nil
        guard confirmDeleteRule(rule, UIText.ruleDescription(rule, config: config)) else { return }
        do throws(RuleEditError) {
            try coordinator.deleteRule(id: rule)
        } catch {
            Log.ui.notice("Deleting \(rule.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            ruleMessages[rule] = UIText.ruleEditError(error)
        }
        refresh()
    }

    /// `offset` -1 moves the rule up, +1 down.
    func moveRule(_ rule: RuleID, by offset: Int) {
        ruleMessages[rule] = nil
        do throws(RuleEditError) {
            try coordinator.moveRule(id: rule, by: offset)
        } catch {
            Log.ui.notice("Moving \(rule.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            ruleMessages[rule] = UIText.ruleEditError(error)
        }
        refresh()
    }

    /// Starting another edit or add discards the unsaved draft.
    private func startDraft(_ state: RuleDraftState) {
        cancelDraft()
        draft = state
    }

    private func validation(of state: RuleDraftState?) -> RuleValidation? {
        guard let state, let config else { return nil }
        let ruleDraft = RuleDraft(matchType: state.matchType, host: state.host, pathPrefix: state.pathPrefix)
        return RuleValidator.validate(ruleDraft, existing: config.rules, editing: state.editing)
    }

    // MARK: Routing rules

    func select(rule: RuleID, directory: String?) {
        guard directory != boundDirectory(rule) else { return }
        ruleMessages[rule] = nil
        guard let directory else {
            write(rule: rule, binding: nil)
            return
        }
        guard case .loaded(let catalog) = catalog, let profile = catalog.profile(directory: directory) else {
            ruleMessages[rule] = "Profile '\(directory)' no longer exists – press Refresh"
            return
        }
        write(rule: rule, binding: ProfileBinding(profile: profile, matchedBy: nil))
    }

    func detect(rule: RuleID) {
        ruleMessages[rule] = nil
        guard let identity = config?.identity(for: rule) else { return }
        catalog = coordinator.loadCatalog()
        guard case .loaded(let profiles) = catalog else {
            refresh()
            if case .unavailable(let error) = catalog { ruleMessages[rule] = UIText.catalogError(error) }
            return
        }
        switch ProfileResolver.resolve(identity: identity, in: profiles) {
        case .unique(let profile, _):
            write(rule: rule, binding: ProfileBinding(profile: profile, matchedBy: nil))
            if ruleMessages[rule] == nil { ruleMessages[rule] = "Detected \(UIText.profileLabel(profile))" }
        case .ambiguous(let candidates):
            refresh()
            let list = candidates.map(UIText.profileLabel).joined(separator: "; ")
            ruleMessages[rule] = "Several profiles match '\(identity)': \(list). Choose one."
        case .notFound:
            refresh()
            ruleMessages[rule] = "No profile matches '\(identity)'"
        }
    }

    /// "Confirm" and "Use '<name>' (now <email>)".
    func confirmBinding(rule: RuleID) {
        ruleMessages[rule] = nil
        guard let status = statuses[rule], let binding = ConfigValidator.confirmedBinding(for: status) else { return }
        write(rule: rule, binding: binding)
    }

    private func write(rule: RuleID, binding: ProfileBinding?) {
        do throws(ConfigError) {
            try coordinator.updateBinding(rule: rule, to: binding)
        } catch {
            Log.ui.notice("Saving the \(rule.rawValue, privacy: .public) binding failed: \(String(describing: error), privacy: .public)")
            ruleMessages[rule] = "Could not save: \(UIText.configError(error))"
        }
        refresh()
    }

    func resetToDefaults() {
        guard confirmReset() else { return }
        configMessage = nil
        do throws(ConfigError) {
            try coordinator.resetConfigToDefaults()
        } catch {
            configMessage = "Reset failed: \(UIText.configError(error))"
        }
        reload()
    }

    // MARK: Default browser (design §8.4)

    func setAsDefault() {
        guard !setCallInFlight else { return }
        httpsRequested = false
        defaultBrowserMessage = nil
        recordMessage = nil

        // 1. Record the previous default, only when it is another browser.
        if case .other(_, let bundleID, let url) = defaultBrowserService.handler(scheme: "http") {
            if configController.isWritable {
                do throws(ConfigError) {
                    try configController.update {
                        $0.previousDefaultBrowser = DefaultBrowserRecord(bundleIdentifier: bundleID, path: url.path)
                    }
                } catch {
                    recordMessage = "Previous browser not recorded: \(UIText.configError(error))"
                }
            } else {
                recordMessage = "Previous browser not recorded because the configuration is invalid"
            }
        }

        // 2. Ask macOS; the re-read status is the source of truth.
        isAwaitingConfirmation = true
        setCallInFlight = true
        Task { @MainActor in
            var failure: (any Error)?
            do {
                try await defaultBrowserService.setDefault(scheme: "http")
            } catch {
                failure = error
            }
            // 3. https only once http is ours, so no second dialog stacks on the first.
            let afterHTTP = defaultBrowserService.status()
            if failure == nil, afterHTTP.http == .thisApp, afterHTTP.https != .thisApp, !httpsRequested {
                httpsRequested = true
                do {
                    try await defaultBrowserService.setDefault(scheme: "https")
                } catch {
                    failure = error
                }
            }
            setCallInFlight = false
            // 4. Only this post-await re-read may report "not changed".
            refresh()
            if defaultBrowser.isDefault {
                finishAwaiting("Switch Profile is the default browser")
            } else if let failure {
                Log.ui.notice("Setting the default browser failed: \(failure.localizedDescription, privacy: .public)")
                finishAwaiting("Default browser was not changed: \(failure.localizedDescription)")
            }
        }
    }

    /// Re-read on app activation and Settings becoming key (step 5).
    func defaultBrowserStatusMayHaveChanged() {
        refresh()
        guard isAwaitingConfirmation else { return }
        if defaultBrowser.isDefault {
            finishAwaiting("Switch Profile is the default browser")
            return
        }
        if defaultBrowser.http == .thisApp, defaultBrowser.https != .thisApp, !httpsRequested {
            httpsRequested = true
            setCallInFlight = true
            Task { @MainActor in
                var failure: (any Error)?
                do {
                    try await defaultBrowserService.setDefault(scheme: "https")
                } catch {
                    failure = error
                }
                setCallInFlight = false
                refresh()
                if defaultBrowser.isDefault {
                    finishAwaiting("Switch Profile is the default browser")
                } else if let failure {
                    finishAwaiting("Default browser was not changed: \(failure.localizedDescription)")
                }
            }
            return
        }
        // NIT #8: while a call is in flight a re-read may only report success.
        guard !setCallInFlight else { return }
        Log.ui.notice("Default browser was not changed")
        finishAwaiting("Default browser was not changed")
    }

    func restorePrevious() {
        guard let record = restorableBrowser, !setCallInFlight else { return }
        let application = URL(fileURLWithPath: record.path)
        defaultBrowserMessage = nil
        setCallInFlight = true
        Task { @MainActor in
            var failure: (any Error)?
            do {
                for scheme in DefaultBrowserService.schemes {
                    try await defaultBrowserService.setDefault(scheme: scheme, application: application)
                }
            } catch {
                failure = error
            }
            setCallInFlight = false
            let restored = DefaultBrowserService.schemes.allSatisfy { defaultBrowserService.isHandler(application, scheme: $0) }
            if restored {
                if configController.isWritable {
                    do throws(ConfigError) {
                        try configController.update { $0.previousDefaultBrowser = nil }
                    } catch {
                        recordMessage = "Could not clear the saved browser: \(UIText.configError(error))"
                    }
                }
                defaultBrowserMessage = "Restored \(DefaultBrowserService.displayName(of: application)) as the default browser"
            } else if let failure {
                defaultBrowserMessage = "Default browser was not changed: \(failure.localizedDescription)"
            } else {
                defaultBrowserMessage = "Default browser was not changed"
            }
            refresh()
        }
    }

    private func finishAwaiting(_ message: String) {
        isAwaitingConfirmation = false
        defaultBrowserMessage = message
    }
}
