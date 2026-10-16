import SwiftUI
import PhoebusCore

/// "Give Award" for a post or comment: the awards Reddit offers for it
/// (free ones, and paid ones out of the user's own Gold), an anonymous toggle
/// and a confirmation before any Gold is spent. Gold is never bought here.
public struct AwardPickerScreen: View {
    let thingID: String
    let repository: RedditRepository
    let onComplete: () -> Void

    @State private var dialog: AwardDialog?
    @State private var selectedID: String?
    @State private var isAnonymous = false
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var confirmingPaid = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(thingID: String, repository: RedditRepository, onComplete: @escaping () -> Void) {
        self.thingID = thingID
        self.repository = repository
        self.onComplete = onComplete
    }

    private var selected: AwardCatalogueEntry? {
        dialog?.catalogue.first { $0.id == selectedID }
    }

    private var canGive: Bool {
        guard let selected, let dialog, !isSubmitting else { return false }
        return dialog.canAfford(selected) != false
    }

    public var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                            .accessibilityIdentifier("awards.picker.error")
                    }
                }
                if let dialog {
                    let free = dialog.catalogue.filter(\.isFree)
                    let paid = dialog.catalogue.filter { !$0.isFree }
                    if !free.isEmpty {
                        Section {
                            ForEach(free) { row($0, dialog: dialog) }
                        } header: {
                            Text("Free").apolloSectionHeader()
                        }
                    }
                    if !paid.isEmpty {
                        Section {
                            ForEach(paid) { row($0, dialog: dialog) }
                        } header: {
                            Text("Gold").apolloSectionHeader()
                        } footer: {
                            Text(goldFooter(dialog)).apolloSectionFooter()
                        }
                    }
                    Section {
                        Toggle("Give Anonymously", isOn: $isAnonymous)
                            .accessibilityIdentifier("awards.picker.anonymous")
                    }
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if errorMessage == nil {
                    Text("Reddit offered no awards for this.").foregroundStyle(.secondary)
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Give Award")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("awards.picker.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Give") { giveTapped() }
                        .disabled(!canGive)
                        .accessibilityIdentifier("awards.picker.give")
                }
            }
            .confirmationDialog(confirmTitle, isPresented: $confirmingPaid, titleVisibility: .visible) {
                Button("Give for \(selected?.goldPrice ?? 0) Gold") { Task { await give() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This spends Gold you already have.")
            }
        }
        .task { await load() }
    }

    private var confirmTitle: String {
        guard let selected else { return "Give Award" }
        return "Give \(selected.name) for \(selected.goldPrice) Gold?"
    }

    private func goldFooter(_ dialog: AwardDialog) -> String {
        if let balance = dialog.goldBalance {
            return "You have \(balance.formatted()) Gold. Phoebus doesn't sell Gold."
        }
        return "Paid awards use Gold you already have, and Reddit refuses them if you don't have enough. Phoebus doesn't sell Gold."
    }

    private func row(_ entry: AwardCatalogueEntry, dialog: AwardDialog) -> some View {
        let affordable = dialog.canAfford(entry) != false
        return Button {
            selectedID = entry.id
        } label: {
            HStack(spacing: 12) {
                CachedAsyncImage(url: entry.iconURL, downsampleTarget: .pixelWidth(40, scale: 3))
                    .frame(width: 40, height: 40)
                    .opacity(affordable ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    if !affordable {
                        Text("Not enough Gold")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(entry.isFree ? "Free" : "\(entry.goldPrice) Gold")
                    .foregroundStyle(.secondary)
                if selectedID == entry.id {
                    Image(systemName: "checkmark").foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
        .accessibilityIdentifier("awards.picker.row.\(entry.id)")
    }

    private func giveTapped() {
        guard let selected else { return }
        if selected.isFree {
            Task { await give() }
        } else {
            confirmingPaid = true
        }
    }

    private func give() async {
        guard let selected else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let result = try await repository.giveAward(thingID: thingID, awardID: selected.id, isAnonymous: isAnonymous)
            AwardStore.shared.recordGiven(result, to: thingID)
            onComplete()
            dismiss()
        } catch {
            errorMessage = "Couldn't give the award: \(error.localizedDescription)"
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dialog = try await repository.awardDialog(thingID: thingID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
