import SwiftUI
import PhoebusCore

/// Multireddit list. Each multireddit opens its feed through `SettingsLink`, so
/// the push lands in the tab's path and the page swipes see it.
public struct MultiredditListScreen: View {
    let repository: RedditRepository

    @State private var multireddits: [RedditMultireddit] = []
    @State private var errorMessage: String?
    /// See `InboxScreen.isLoading`: avoids claiming there are no multireddits while
    /// they are still loading.
    @State private var isLoading = false
    @State private var editingMultireddit: RedditMultireddit?
    @State private var editedDisplayName = ""
    @State private var editedDescription = ""
    @State private var isSavingEdit = false
    /// Add/remove-subreddit flow, beyond the rename/description sheet below.
    @State private var managingSubredditsMultireddit: RedditMultireddit?
    /// `SubredditSectionsSettings.hideMultiredditDescriptions`: when on, the subtitle
    /// falls back to the subreddit count, as in the Subreddits root list.
    @Setting(SubredditSectionsSettingsStore.storage) private var sectionsSettings

    public init(repository: RedditRepository) {
        self.repository = repository
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if multireddits.isEmpty && errorMessage == nil && isLoading {
                ApolloLoadingCell()
                    .listRowSeparator(.hidden)
            } else if multireddits.isEmpty && errorMessage == nil {
                Text("No multireddits yet. Create one on reddit.com to see it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(multireddits) { multi in
                SettingsLink {
                    FeedScreen(multireddit: multi, repository: repository)
                } label: {
                    VStack(alignment: .leading) {
                        Text(multi.displayName).font(.headline)
                        if let subtitle = multiredditSubtitle(multi) {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // Reborn's in-app multireddit renaming and descriptions.
                .swipeActions(edge: .trailing) {
                    Button {
                        editedDisplayName = multi.displayName
                        // The current description, not an empty box: `updateMultireddit` PUTs a full
                        // model, so saving a blank editor would wipe it.
                        editedDescription = multi.descriptionMarkdown ?? ""
                        editingMultireddit = multi
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                    Button {
                        managingSubredditsMultireddit = multi
                    } label: {
                        Label("Subreddits", systemImage: "list.bullet")
                    }
                    .tint(.green)
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Multireddits")
        .task { await load() }
        .onAppear {
        }
        .refreshable { await load() }
        .sheet(item: $managingSubredditsMultireddit) { multi in
            NavigationStack {
                MultiredditSubredditsScreen(multireddit: multi, repository: repository) {
                    managingSubredditsMultireddit = nil
                    Task { await load() }
                }
            }
        }
        .sheet(item: $editingMultireddit) { multi in
            NavigationStack {
                List {
                    Section("Name") {
                        TextField("Display Name", text: $editedDisplayName)
                    }
                    Section("Description") {
                        TextEditor(text: $editedDescription)
                            .frame(minHeight: 100)
                    }
                }
                .apolloFlatListAppearance()
                .navigationTitle("Edit Multireddit")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingMultireddit = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await saveEdit(multi) }
                        }
                        .disabled(isSavingEdit || editedDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func load() async {
        if multireddits.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            multireddits = try await repository.fetchMultireddits()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// Same subtitle logic as `SubredditsRootScreen.multiredditSubtitle`; both call
    /// `RedditMultireddit.subtitle(hideDescriptions:fallback:)`.
    private func multiredditSubtitle(_ multi: RedditMultireddit) -> String? {
        multi.subtitle(hideDescriptions: sectionsSettings.hideMultiredditDescriptions, fallback: "\(multi.subreddits.count) subreddits")
    }

    private func saveEdit(_ multi: RedditMultireddit) async {
        isSavingEdit = true
        defer { isSavingEdit = false }
        do {
            try await repository.updateMultireddit(
                path: multi.path,
                displayName: editedDisplayName,
                descriptionMarkdown: editedDescription,
                subredditNames: multi.subreddits.map(\.name)
            )
            editingMultireddit = nil
            await load()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
