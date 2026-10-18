import SwiftUI
import SwitchProfileCore

struct ResolutionView: View {
    @ObservedObject var model: ResolutionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let head = model.head {
                content(head)
            } else {
                Text("No pending links")
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 300, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(_ head: PendingItem) -> some View {
        Text("1 of \(model.items.count)").font(.headline)
        Text(head.url.absoluteString)
            .textSelection(.enabled)
            .lineLimit(4)
            .truncationMode(.middle)
        Text("\(head.rule.rawValue) (\(UIText.ruleDescription(head.rule, config: model.config))): \(UIText.pendingKind(head.kind, rule: head.rule))")
            .foregroundStyle(.secondary)

        HStack {
            Picker("Profile", selection: $model.selection) {
                if model.catalogProfiles.isEmpty {
                    Text(placeholder).tag(String?.none)
                } else {
                    Text("Choose a profile").tag(String?.none)
                    ForEach(model.catalogProfiles, id: \.directory) { profile in
                        Text(UIText.profileLabel(profile)).tag(Optional(profile.directory))
                    }
                }
            }
            .disabled(model.catalogProfiles.isEmpty)
            Button("Refresh profiles") { model.refreshProfiles() }
        }
        if case .unavailable(let error) = model.catalog {
            Text(UIText.catalogError(error)).font(.footnote).foregroundStyle(.secondary)
        }

        HStack {
            Button("Open once") { model.openOnce() }
                .disabled(model.selection == nil)
            if model.canRemember(head) {
                Button(head.rule == .fallback ? "Open and use as fallback" : "Open and use for \(head.rule.rawValue)") {
                    model.openAndRemember()
                }
                .disabled(model.selection == nil)
            }
            if ResolutionModel.canRetry(head.kind) {
                Button("Retry") { model.retry() }
            }
        }
        HStack {
            Button("Copy URL") { model.copyURL() }
            Button("Discard") { model.discard() }
        }
        if let error = model.actionError {
            Text(error).foregroundStyle(.red).textSelection(.enabled)
        }
    }

    private var placeholder: String {
        if case .unavailable = model.catalog { return "No Chrome profiles available" }
        return "No profiles"
    }
}
