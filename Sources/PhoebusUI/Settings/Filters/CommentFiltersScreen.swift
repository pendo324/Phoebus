import SwiftUI
import PhoebusCore

/// "Comment Rules" (`Settings → Filters → Comment Rules`): named filters that hide
/// or collapse comments by score, words or author. Phoebus's own; neither
/// Apollo nor Reborn filters comments beyond blocked users.
struct CommentFiltersScreen: View {
    @Setting(CommentFilterStore.storage) private var filters
    @State private var editing: CommentFilter?

    var body: some View {
        List {
            Section {
                ForEach(filters) { filter in
                    Button { editing = filter } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(filter.name)
                                .foregroundStyle(Color.primary)
                            Text(Self.summary(filter))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("commentFilters.filter.\(filter.name)")
                    .apolloPlainSettingsRowInsets()
                }
                .onDelete { offsets in
                    $filters.update { $0.remove(atOffsets: offsets) }
                }
                Button("Add Comment Filter...") { editing = CommentFilter() }
                    .foregroundStyle(Color.apolloAccent)
                    .accessibilityIdentifier("commentFilters.add")
                    .apolloPlainSettingsRowInsets(rule: false)
            } footer: {
                Text("Hide or collapse comments by score, words or author. Your own comments and a comment you open from a link are never filtered.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Comment Rules")
        .accessibilityIdentifier("commentFilters.screen")
        .toolbar {
            if !filters.isEmpty {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .sheet(item: $editing) { filter in
            NavigationStack {
                CommentFilterEditorScreen(filter: filter, onCancel: { editing = nil }) { saved in
                    $filters.update { list in
                        if let index = list.firstIndex(where: { $0.id == saved.id }) {
                            list[index] = saved
                        } else {
                            list.append(saved)
                        }
                    }
                    editing = nil
                }
            }
        }
    }

    /// One line under the filter's name: what it matches and what it does.
    static func summary(_ filter: CommentFilter) -> String {
        var parts: [String] = []
        if let min = filter.minScore { parts.append("score ≥ \(min)") }
        if let max = filter.maxScore { parts.append("score ≤ \(max)") }
        if !filter.excludedWords.isEmpty { parts.append("\(filter.excludedWords.count) word\(filter.excludedWords.count == 1 ? "" : "s")") }
        if !filter.excludedUsers.isEmpty { parts.append("\(filter.excludedUsers.count) user\(filter.excludedUsers.count == 1 ? "" : "s")") }
        parts.append(filter.displayMode.displayName)
        parts.append(filter.subreddits.isEmpty ? "everywhere" : filter.subreddits.map { "r/\($0)" }.joined(separator: ", "))
        return parts.joined(separator: " · ")
    }
}

/// Edits one comment filter as a draft, written back only on Save.
struct CommentFilterEditorScreen: View {
    let onCancel: () -> Void
    let onSave: (CommentFilter) -> Void

    @State private var draft: CommentFilter
    @State private var minScoreText: String
    @State private var maxScoreText: String
    @State private var adding: Kind?
    @State private var newValue = ""

    private enum Kind: Identifiable {
        case word, user, subreddit
        var id: Self { self }
    }

    init(filter: CommentFilter, onCancel: @escaping () -> Void, onSave: @escaping (CommentFilter) -> Void) {
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: filter)
        _minScoreText = State(initialValue: filter.minScore.map(String.init) ?? "")
        _maxScoreText = State(initialValue: filter.maxScore.map(String.init) ?? "")
    }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $draft.name)
                    .accessibilityIdentifier("commentFilterEditor.name")
                    .apolloPlainSettingsRowInsets()
            } header: {
                Text("Name").apolloSectionHeader()
            }

            Section {
                scoreField("Minimum Score", text: $minScoreText, identifier: "commentFilterEditor.minScore")
                scoreField("Maximum Score", text: $maxScoreText, identifier: "commentFilterEditor.maxScore")
            } header: {
                Text("Score").apolloSectionHeader()
            } footer: {
                Text("Comments scoring below the minimum or above the maximum are filtered. Leave empty for no limit. Comments with hidden scores and pinned comments are not filtered by score.")
                    .apolloSectionFooter()
            }

            listSection(title: "Words", values: draft.excludedWords, display: { $0 },
                        addTitle: "Add Word...", kind: .word,
                        footer: "Comments containing any of these words or phrases are filtered (not case-sensitive; \u{201c}spoil\u{201d} also matches \u{201c}spoiler\u{201d}).") {
                draft.excludedWords.remove(atOffsets: $0)
            }

            listSection(title: "Users", values: draft.excludedUsers, display: { "u/\($0)" },
                        addTitle: "Add User...", kind: .user,
                        footer: "Comments by these users are filtered.") {
                draft.excludedUsers.remove(atOffsets: $0)
            }

            Section {
                ApolloSettingsPicker("Display Mode", selection: $draft.displayMode,
                                     options: CommentFilter.DisplayMode.allCases,
                                     display: { $0.displayName })
                    .accessibilityIdentifier("commentFilterEditor.displayMode")
                    .apolloPlainSettingsRowInsets()
            } footer: {
                Text("Hide removes a filtered comment and its replies. Collapse starts it collapsed with the reason shown.")
                    .apolloSectionFooter()
            }

            listSection(title: "Subreddits", values: draft.subreddits, display: { "r/\($0)" },
                        addTitle: "Add Subreddit...", kind: .subreddit,
                        footer: "Leave empty to apply in every subreddit.") {
                draft.subreddits.remove(atOffsets: $0)
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle(draft.name.isEmpty ? "Comment Filter" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("commentFilterEditor.screen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("commentFilterEditor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(finished) }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("commentFilterEditor.save")
            }
        }
        .alert(alertTitle, isPresented: $adding.isPresent()) {
            TextField(adding == .word ? "spoiler" : adding == .user ? "username" : "subreddit", text: $newValue)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("commentFilterEditor.newValue")
            Button("Cancel", role: .cancel) { newValue = "" }
            Button("Add") { add() }
                .accessibilityIdentifier("commentFilterEditor.addConfirm")
        }
    }

    private var alertTitle: String {
        switch adding {
        case .word: return "Add Word"
        case .user: return "Add User"
        case .subreddit, nil: return "Add Subreddit"
        }
    }

    private func scoreField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField("None", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .accessibilityIdentifier(identifier)
        }
        .apolloPlainSettingsRowInsets()
    }

    private func listSection(title: String, values: [String], display: @escaping (String) -> String,
                             addTitle: String, kind: Kind, footer: String,
                             onDelete: @escaping (IndexSet) -> Void) -> some View {
        Section {
            ForEach(values, id: \.self) {
                Text(display($0)).apolloPlainSettingsRowInsets()
            }
            .onDelete(perform: onDelete)
            Button(addTitle) { adding = kind }
                .foregroundStyle(Color.apolloAccent)
                .accessibilityIdentifier("commentFilterEditor.add.\(kind)")
                .apolloPlainSettingsRowInsets(rule: false)
        } header: {
            Text(title).apolloSectionHeader()
        } footer: {
            Text(footer).apolloSectionFooter()
        }
    }

    private func add() {
        let kind = adding
        let raw = newValue
        newValue = ""
        switch kind {
        case .word:
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty, !draft.excludedWords.contains(value) else { return }
            draft.excludedWords.append(value)
        case .user:
            let value = CommentFilter.normalizedUsername(raw)
            guard !value.isEmpty,
                  !draft.excludedUsers.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
            draft.excludedUsers.append(value)
        case .subreddit:
            let value = CommentFilter.normalizedSubreddit(raw)
            guard !value.isEmpty, !draft.subreddits.contains(value) else { return }
            draft.subreddits.append(value)
        case nil:
            return
        }
    }

    /// The draft with its name trimmed and score fields parsed; a field that
    /// isn't a whole number means no limit.
    private var finished: CommentFilter {
        var filter = draft
        filter.name = filter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        filter.minScore = Int(minScoreText.trimmingCharacters(in: .whitespaces))
        filter.maxScore = Int(maxScoreText.trimmingCharacters(in: .whitespaces))
        return filter
    }
}
