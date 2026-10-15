import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Filters: what Phoebus hides. Client-side content filters
/// (subreddit/keyword/author/domain) applied to feed listings, Reborn's
/// subreddit-specific filters and Tag Filters, and Apollo's blocked users,
/// with the post and comment rules as drill-downs.
public struct FiltersSettingsScreen: View {
    @State private var filters: [ContentFilter] = ContentFilterStore.load()
    @State private var showingAdd = false
    @State private var addKind: FilterKind = .keyword
    @Setting(PostFilterStore.storage) private var postRules
    @State private var showingAddSpecific = false
    @State private var newSpecific = ""
    @State private var showingAddWord = false
    @State private var newWord = ""
    @State private var resImportAlert: RESImportAlert?
    @Setting(BlockedUsersStore.storage) private var blockedStore
    private var blockedCount: Int { _ = blockedStore; return BlockedUsersStore.names().count }
    @Setting(UserTags.self) private var userTags
    @Setting(GeneralSettingsStore.storage) private var general

    public init() {}

    public var body: some View {
        List {
            // Apollo's three sections with all-caps headers ("FILTERED
            // SUBREDDITS" / "FILTERED KEYWORDS" / "BLOCKED USERS"), each with its
            // own footer. Order: Filtered Keywords (+ "Add Keyword"), Filtered
            // Subreddits (+ "Add Subreddit"), the rules, an untitled "Blocked
            // Users ›" (Phoebus's "User Tags ›" follows it), then Reborn's
            // spliced Subreddit-Specific Filters (+ "Add Subreddit...") and Filter
            // Subreddits by Name (+ "Add Word...") sections, and Tag Filters.
            keywordsSection
            subredditsSection
            rulesSection
            blockedUsersSection
            userTagsSection
            AuthorDomainFiltersSection(filters: $filters)
            subredditSpecificSection
            filterByNameSection
            TagFilterSections()
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.filters.title)
        .navigationBarTitleDisplayModeIfAvailable()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Plain text "Add" bar button, not a "+" icon.
                Button("Add") {
                    showingAdd = true
                }
                // Long-pressing the "Add Subreddit" button offers to
                // import a Reddit Enhancement Suite filteReddit export
                // from the clipboard.
                .onLongPressGesture {
                    importFromClipboard()
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                AddFilterScreen(initialKind: addKind) { newFilter in
                    filters.append(newFilter)
                    ContentFilterStore.save(filters)
                    showingAdd = false
                }
            }
        }
        .alert(item: $resImportAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    private var subredditsSection: some View {
        Section {
            let subredditFilters = filters.filter { $0.kind == .subreddit }
            ForEach(subredditFilters) { filter in
                // A static "Add Subreddit" row follows this ForEach,
                // so these dynamic rows keep their hairline.
                Text(filter.value).apolloPlainSettingsRowInsets()
            }
            .onDelete { indexSet in
                delete(kind: .subreddit, at: indexSet)
            }
            Button("Add Subreddit") { addKind = .subreddit; showingAdd = true }
                .foregroundStyle(Color.apolloAccent)
                .apolloSearchRow("Add Subreddit", lastBeforeFooter: true)
        } header: {
            Text("Filtered Subreddits")
                .apolloSectionHeader()
        } footer: {
            Text("Exclude these subreddits from \u{201c}All Posts\u{201d} and \u{201c}Popular\u{201d}.")
                    .apolloSectionFooter()
        }
    }

    private var keywordsSection: some View {
        Section {
            let keywordFilters = filters.filter { $0.kind == .keyword }
            ForEach(keywordFilters) { filter in
                Text(filter.value).apolloPlainSettingsRowInsets()
            }
            .onDelete { indexSet in
                delete(kind: .keyword, at: indexSet)
            }
            Button("Add Keyword") { addKind = .keyword; showingAdd = true }
                .foregroundStyle(Color.apolloAccent)
                .apolloSearchRow("Add Keyword", lastBeforeFooter: true)
        } header: {
            Text("Filtered Keywords")
                .apolloSectionHeader()
        } footer: {
            Text("Exclude posts containing these keywords in title, link, or flair.")
                    .apolloSectionFooter()
        }
    }

    /// Phoebus's rules, which match more than a word or a name.
    private var rulesSection: some View {
        Section {
            SettingsDrillDownRow(destination: .postRules)
            SettingsDrillDownRow(destination: .commentFilters, lastBeforeFooter: true)
        } header: {
            Text("Rules")
                .apolloSectionHeader()
        } footer: {
            Text("Hide posts by score, awards or title, and comments by score, words or author.")
                .apolloSectionFooter()
        }
    }

    private var blockedUsersSection: some View {
        Section {
            SettingsDrillDownRow(destination: .blockedUsers, value: "\(blockedCount)")
            // Phoebus's own: whether a blocked user's comments vanish or fold up.
            ApolloSettingsPicker("Blocked Users' Comments", selection: $general.hideBlockedUserComments,
                                 options: [false, true],
                                 display: { $0 ? "Hide" : "Collapse" })
                .apolloSearchRow("Blocked Users' Comments", lastBeforeFooter: true) // search: item "Blocked Users"
        } footer: {
            Text("Exclude posts and communication from these users.")
                    .apolloSectionFooter()
        }
    }

    /// Phoebus-only user tags, next to the other per-user list.
    private var userTagsSection: some View {
        Section {
            SettingsDrillDownRow(destination: .userTags, value: "\(userTags.byUser.count)", lastBeforeFooter: true)
        } footer: {
            Text("Your own labels on users, shown after their names.")
                    .apolloSectionFooter()
        }
    }

    // Reborn's two spliced sections.
    private var subredditSpecificSection: some View {
        Section {
            ForEach(postRules.subreddits.keys.sorted(), id: \.self) { sub in
                SettingsLink {
                    SubredditFilterDetailScreen(subreddit: sub, rules: $postRules.binding) {}
                } label: {
                    HStack {
                        Text("r/\(sub)")
                        Spacer()
                        Text("\(postRules.subreddits[sub]?.ruleCount ?? 0)").foregroundStyle(.secondary)
                    }
                }
                .apolloPlainSettingsRowInsets()
            }
            .onDelete { offsets in
                let keys = postRules.subreddits.keys.sorted()
                for index in offsets { $postRules.update { $0.subreddits.removeValue(forKey: keys[index]) } }
            }
            Button("Add Subreddit...") { showingAddSpecific = true }
                .foregroundStyle(Color.apolloAccent)
                .apolloSearchRow("Add Subreddit...", lastBeforeFooter: true)
        } header: {
            Text("Subreddit-Specific Filters")
                .apolloSectionHeader()
        } footer: {
            Text("Hide posts in a specific subreddit by title keyword or post flair. Tap a subreddit to configure. Applies on this device.")
                    .apolloSectionFooter()
        }
        .alert("Add Subreddit", isPresented: $showingAddSpecific) {
            TextField("subreddit", text: $newSpecific)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                var v = newSpecific.trimmingCharacters(in: .whitespaces).lowercased()
                if v.hasPrefix("r/") { v.removeFirst(2) }
                guard !v.isEmpty, postRules.subreddits[v] == nil else { return }
                $postRules.update { $0.subreddits[v] = PostFilterRules.SubredditRules() }
                newSpecific = ""
            }
        }
    }

    private var filterByNameSection: some View {
        Section {
            ForEach(postRules.nameSubstrings, id: \.self) {
                Text($0).apolloPlainSettingsRowInsets()
            }
                .onDelete { offsets in
                    $postRules.update { $0.nameSubstrings.remove(atOffsets: offsets) }
                }
            Button("Add Word...") { showingAddWord = true }
                .foregroundStyle(Color.apolloAccent)
                .apolloSearchRow("Add Word...", lastBeforeFooter: true)
        } header: {
            Text("Filter Subreddits by Name")
                .apolloSectionHeader()
        } footer: {
            Text("Hide any subreddit whose name contains one of these words, in feeds and in search (e.g. 'circlejerk' hides r/carscirclejerk). Applies on this device.")
                    .apolloSectionFooter()
        }
        .alert("Add Word", isPresented: $showingAddWord) {
            TextField("word", text: $newWord)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let v = newWord.trimmingCharacters(in: .whitespaces).lowercased()
                guard !v.isEmpty, !postRules.nameSubstrings.contains(v) else { return }
                $postRules.update { $0.nameSubstrings.append(v) }
                newWord = ""
            }
        }
    }

    private func delete(kind: FilterKind, at indexSet: IndexSet) {
        let matching = filters.filter { $0.kind == kind }
        let toRemove = Set(indexSet.map { matching[$0].id })
        filters.removeAll { toRemove.contains($0.id) }
        ContentFilterStore.save(filters)
    }

    /// Matches the real Apollo copy verbatim for the empty-clipboard and
    /// invalid-format cases.
    private func importFromClipboard() {
        #if canImport(UIKit)
        let clipboardText = UIPasteboard.general.string ?? ""
        #else
        let clipboardText = ""
        #endif
        switch RESFilterImporter.parse(clipboardText) {
        case .success(let imported):
            var existingSubreddits = Set(filters.filter { $0.kind == .subreddit }.map { $0.value.lowercased() })
            var existingKeywords = Set(filters.filter { $0.kind == .keyword }.map { $0.value.lowercased() })
            var existingDomains = Set(filters.filter { $0.kind == .domain }.map { $0.value.lowercased() })
            var added = 0
            for filter in imported {
                let key = filter.value.lowercased()
                switch filter.kind {
                case .subreddit:
                    guard !existingSubreddits.contains(key) else { continue }
                    existingSubreddits.insert(key)
                case .keyword:
                    guard !existingKeywords.contains(key) else { continue }
                    existingKeywords.insert(key)
                case .domain:
                    guard !existingDomains.contains(key) else { continue }
                    existingDomains.insert(key)
                case .author:
                    break
                }
                filters.append(filter)
                added += 1
            }
            ContentFilterStore.save(filters)
            resImportAlert = RESImportAlert(title: "Reddit Enhancement Suite Filters Import", message: "Imported \(added) filter\(added == 1 ? "" : "s") from Reddit Enhancement Suite.")
        case .failure(.emptyClipboard):
            resImportAlert = RESImportAlert(title: "Reddit Enhancement Suite Filters Import", message: "Note: you currently have no text on your clipboard for Phoebus to import.")
        case .failure(.invalidOrEmpty):
            resImportAlert = RESImportAlert(title: "Reddit Enhancement Suite Filters Import", message: "The format is either invalid or there are no subreddits contained in the text.")
        }
    }
}

private struct RESImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}


struct AddFilterScreen: View {
    @State private var kind: FilterKind
    init(initialKind: FilterKind = .subreddit, onAdd: @escaping (ContentFilter) -> Void) {
        _kind = State(initialValue: initialKind)
        self.onAdd = onAdd
    }
    @State private var value = ""
    let onAdd: (ContentFilter) -> Void

    var body: some View {
        List {
            ApolloSettingsPicker("Filter Type", selection: $kind,
                                 options: FilterKind.allCases.map { $0 },
                                 display: { $0.displayName })
                    .apolloSearchRow("Filter Type")
            TextField(placeholder, text: $value)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                // Placeholder changes with the filter kind, so this is
                // geometry only rather than a search target.
                .apolloPlainSettingsRowInsets()
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Add Filter")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    onAdd(ContentFilter(kind: kind, value: value.trimmingCharacters(in: .whitespaces)))
                }
                .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var placeholder: String {
        switch kind {
        case .subreddit: return "e.g. politics (without r/)"
        case .keyword: return "e.g. spoiler"
        case .author: return "e.g. username (without u/)"
        case .domain: return "e.g. example.com"
        }
    }
}


/// Phoebus's own author and domain filters, which Apollo's Blocked Users
/// list doesn't hold.
struct AuthorDomainFiltersSection: View {
    @Binding var filters: [ContentFilter]

    var body: some View {
        let local = filters.filter { $0.kind == .author || $0.kind == .domain }
        if !local.isEmpty {
            Section {
                ForEach(local) { filter in
                    HStack {
                        Text(filter.value)
                        Spacer()
                        Text(filter.kind == .domain ? "Domain" : "Author")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .apolloPlainSettingsRowInsets()
                }
                .onDelete { indexSet in
                    let toRemove = Set(local.enumerated().filter { indexSet.contains($0.offset) }.map(\.element.id))
                    filters.removeAll { toRemove.contains($0.id) }
                    ContentFilterStore.save(filters)
                }
            } header: {
                Text("Filtered Authors & Domains")
                    .apolloSectionHeader()
            } footer: {
                Text("Exclude posts by these authors or linking to these domains.")
                    .apolloSectionFooter()
            }
        }
    }
}
