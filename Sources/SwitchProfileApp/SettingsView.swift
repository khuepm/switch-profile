import SwiftUI
import SwitchProfileCore

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            defaultBrowserSection
            profilesSection
            rulesSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 600)
    }

    // MARK: 1. Default browser

    private var defaultBrowserSection: some View {
        Section("Default browser") {
            schemeLine("http", model.defaultBrowser.http)
            schemeLine("https", model.defaultBrowser.https)
            if model.isAwaitingConfirmation {
                Text("Waiting for macOS confirmation…")
            } else if let message = model.defaultBrowserMessage {
                Text(message)
            }
            if let message = model.recordMessage {
                Text(message).foregroundStyle(.secondary)
            }
            HStack {
                if !model.defaultBrowser.isDefault {
                    Button("Set as default browser…") { model.setAsDefault() }
                        .disabled(model.isAwaitingConfirmation)
                }
                if let record = model.restorableBrowser {
                    Button("Restore previous default (\(DefaultBrowserService.displayName(of: URL(fileURLWithPath: record.path))))…") {
                        model.restorePrevious()
                    }
                }
            }
            Text("Apps with embedded browsers, or apps that open a specific browser directly, bypass Switch Profile.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func schemeLine(_ scheme: String, _ handler: DefaultBrowserService.SchemeHandler) -> some View {
        LabeledContent(scheme, value: UIText.handler(handler))
        if case .otherCopy(let url) = handler {
            Text("Another copy at \(url.path) is the default; remove it.")
                .foregroundStyle(.orange)
        }
    }

    // MARK: 2. Chrome profiles

    private var profilesSection: some View {
        Section("Chrome profiles") {
            HStack {
                switch model.catalog {
                case .loaded(let catalog):
                    Text("\(catalog.profiles.count) profiles found in Chrome Local State")
                case .unavailable(let error):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CatalogMessages.unavailable(error)).foregroundStyle(.red)
                        Text(CatalogMessages.remedy(error, requester: .app))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Refresh") { model.reload() }
            }
        }
    }

    // MARK: 3. Routing rules

    private var rulesSection: some View {
        Section("Routing rules") {
            if case .unavailable(let error) = model.configState {
                HStack {
                    Text("Configuration file is invalid – Reset to defaults… to edit mappings (\(UIText.configError(error)))")
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Reset to defaults…") { model.resetToDefaults() }
                }
            }
            if let message = model.configMessage {
                Text(message).foregroundStyle(.red)
            }
            ForEach(RuleID.allCases, id: \.self) { rule in
                RuleRow(model: model, rule: rule)
            }
        }
    }
}

private struct RuleRow: View {
    @ObservedObject var model: SettingsModel
    let rule: RuleID

    private var status: TargetStatus? { model.statuses[rule] }

    /// Also true for an unseeded rule, or R4 in last-active mode, while the catalog is unavailable,
    /// so the picker never offers fixed profiles it cannot list.
    private var isCatalogUnavailable: Bool {
        switch status {
        case .catalogUnavailable?: true
        case .unset?, .lastActiveChrome?: model.catalogError != nil
        default: false
        }
    }

    /// Picker, Detect and Confirm are disabled while the config is unavailable or the row has no catalog.
    private var isDisabled: Bool { !model.isConfigWritable || isCatalogUnavailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(rule.rawValue): \(UIText.ruleDescription(rule))").font(.headline)
            Text("Identity: \(model.config?.targets[rule].identity ?? "none (choose a profile)")")
                .foregroundStyle(.secondary)
            HStack {
                Picker("Profile for \(rule.rawValue)", selection: selection) {
                    // For R4 the nil binding means "Last active Chrome profile", the default.
                    Text(rule == .r4 ? "Last active Chrome profile" : "Not set").tag(String?.none)
                    pickerTags
                }
                if rule != .r4 {
                    Button("Detect") { model.detect(rule: rule) }
                        .disabled(isDisabled || model.config?.targets[rule].identity == nil)
                }
            }
            .disabled(isDisabled)
            statusLine
            if let message = model.ruleMessages[rule] {
                Text(message).font(.footnote).textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var selection: Binding<String?> {
        Binding(get: { model.boundDirectory(rule) },
                set: { model.select(rule: rule, directory: $0) })
    }

    /// The current selection is always one of the tags, so the picker never renders blank.
    @ViewBuilder
    private var pickerTags: some View {
        switch status {
        case .catalogUnavailable?:
            if let directory = model.boundDirectory(rule) {
                Text("\(directory) (unverified)").tag(Optional(directory))
            }
        case .missing(let binding)?:
            Text("\(binding.directory) (missing)").tag(Optional(binding.directory)).disabled(true)
            catalogTags(except: nil)
        case .identityMismatch(let binding, _)?:
            // The bound directory exists in the catalog; its entry is the synthetic, disabled tag.
            Text("\(binding.directory) (account changed)").tag(Optional(binding.directory)).disabled(true)
            catalogTags(except: binding.directory)
        default:
            catalogTags(except: nil)
        }
    }

    private func catalogTags(except excluded: String?) -> some View {
        ForEach(model.catalogProfiles.filter { $0.directory != excluded }, id: \.directory) { profile in
            Text(UIText.profileLabel(profile)).tag(Optional(profile.directory))
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .ok(let profile, autoDetected: nil)?:
            Text("✓ \(profile.displayName) (\(profile.directory))")
        case .ok(_, autoDetected: let kind?)?:
            HStack {
                Text("Auto-detected: matched by \(UIText.matchKind(kind)). Confirm or choose another.")
                Button("Confirm") { model.confirmBinding(rule: rule) }
                    .disabled(isDisabled)
            }
        case .lastActiveChrome?:
            // Shown even while the catalog is unavailable: this mode does not need it.
            Text("Opens in the Chrome profile you used last, like Chrome without Switch Profile")
        case .unset?:
            if model.catalogError != nil {
                Text("Chrome profiles unavailable – see above").foregroundStyle(.secondary)
            } else {
                Text("Not set – choose a profile")
            }
        case .missing(let binding)?:
            Text("Profile '\(binding.directory)' no longer exists – choose a profile").foregroundStyle(.orange)
        case .identityMismatch(let binding, let current)?:
            VStack(alignment: .leading) {
                Text("'\(current.displayName)' (\(current.directory)) was bound to \(binding.email ?? "signed out"), and is now \(current.email ?? "signed out")")
                    .foregroundStyle(.orange)
                Button("Use '\(current.displayName)' (now \(current.email ?? "signed out"))") { model.confirmBinding(rule: rule) }
                    .disabled(!model.isConfigWritable)
            }
        case .catalogUnavailable?:
            Text("Chrome profiles unavailable – see above").foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }
}
