import SwiftUI
import PhoebusCore

/// The feed's title quick-switcher: a "Subreddits" sheet with a focused
/// search field and the favorites, or local and Reddit matches while typing.
/// Return goes to the typed name.
///
/// Reborn "Subreddit Switcher Sheet" (#1313). It replaces the in-nav-bar
/// field and floating results list with a native sheet; the sheet scrolls on
/// its own and never reaches the feed's Hide Bars on Scroll.
public struct SubredditSwitcherSheet: View {
    let repository: RedditRepository
    /// The subreddit the feed is showing, checkmarked in the list.
    let current: String
    let onSelect: (String) -> Void
    let onDone: () -> Void

    @Environment(\.apolloTheme) private var apolloTheme
    @State private var query = ""
    @State private var fieldFocused = false
    @State private var favorites: [String]
    @State private var local: [String]
    @State private var remote: [String] = []
    @State private var lastError: String?

    public init(
        repository: RedditRepository,
        current: String,
        onSelect: @escaping (String) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.repository = repository
        self.current = current
        self.onSelect = onSelect
        self.onDone = onDone
        // Synchronous so the favorites are in the first frame. The cached
        // lists are the Subreddits root's own, refreshed behind it.
        let cached = SubredditListCache.load(for: FavoriteSubredditsAccountContext.currentUsernameProvider() ?? "")
        let known = ((cached?.subscriptions ?? []) + (cached?.moderated ?? [])).map(\.displayName)
        _local = State(initialValue: known)
        _favorites = State(initialValue: SubredditSwitcherResults.favoriteNames(
            ordered: FavoriteSubredditsStore.loadOrdered(),
            known: known,
            storedName: FavoriteSubredditsStore.displayName(for:),
            sortAlphabetically: FavoriteSubredditsStore.sortAlphabetically
        ))
    }

    private var sections: [SubredditSwitcherSection] {
        SubredditSwitcherResults.sections(query: query, favorites: favorites, local: local, remote: remote)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    searchField
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(sections) { section in
                    if let title = section.title {
                        Section {
                            rows(section.names)
                        } header: {
                            Text(title).apolloSectionHeader()
                        }
                    } else {
                        Section { rows(section.names) }
                    }
                }
                if let lastError, sections.isEmpty {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .apolloCardRowFill()
                        .accessibilityIdentifier("subredditSwitcher.error")
                }
            }
            .apolloSettingsListAppearance()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Subreddits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                        .accessibilityIdentifier("subredditSwitcher.done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: query) { await loadRemote(for: query) }
        .task {
            // The sheet must be on screen before it takes input, or the
            // keyboard is dropped.
            try? await Task.sleep(nanoseconds: 80_000_000)
            fieldFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            GlassSearchTextField(
                text: $query,
                placeholder: "Subreddit",
                isFocused: $fieldFocused,
                onSubmit: { if let name = SubredditSwitcherResults.destination(for: query) { onSelect(name) } },
                returnKeyType: .go
            )
            .accessibilityIdentifier("subredditSwitcher.textField")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
                .accessibilityIdentifier("subredditSwitcher.clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        // Flattened first: the focused field paints its own fill over the capsule otherwise.
        .compositingGroup()
        .background(Capsule().fill(apolloTheme.color(.tertiaryFill) ?? Color.secondary.opacity(0.12)))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func rows(_ names: [String]) -> some View {
        ForEach(names, id: \.self) { name in
            Button {
                onSelect(name)
            } label: {
                HStack {
                    boldedPrefixText(name)
                    Spacer()
                    if name.caseInsensitiveCompare(current) == .orderedSame {
                        Image(systemName: "checkmark")
                            .foregroundStyle(apolloTheme.color(.accent) ?? .accentColor)
                    }
                }
                .apolloFullRowTapTarget()
            }
            .buttonStyle(.plain)
            .apolloCardRowFill()
            .accessibilityIdentifier("subredditSwitcher.row.\(name)")
        }
    }

    /// `name` with the matched part bold and the rest secondary, as the
    /// results list it replaces drew them.
    private func boldedPrefixText(_ name: String) -> Text {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let range = name.range(of: trimmed, options: [.caseInsensitive]) else {
            return Text(name)
        }
        return Text(String(name[name.startIndex..<range.lowerBound])).foregroundStyle(.secondary)
            + Text(String(name[range])).fontWeight(.semibold)
            + Text(String(name[range.upperBound...])).foregroundStyle(.secondary)
    }

    /// Keystroke debounce. `.task(id:)` cancels the previous task on every
    /// change, so only the last keystroke in a burst issues a request.
    private static let debounceInterval = Duration.milliseconds(300)

    private func loadRemote(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= SubredditSwitcherResults.minimumRemoteQueryLength else {
            remote = []
            lastError = nil
            return
        }
        do {
            try await Task.sleep(for: Self.debounceInterval)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        do {
            let data = try await repository.autocompleteSubreddits(query: trimmed, limit: 8)
            let listing = try await RedditListing.decodedInBackground(from: data)
            let names = await listing.childrenInBackground(RedditSubreddit.self).map(\.displayName)
            guard !Task.isCancelled else { return }
            let rules = PostFilterStore.load()
            remote = names.filter { !rules.hidesSubredditName($0) }
            lastError = nil
        } catch {
            // A cancelled request is the normal debounce path, not a failure.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            lastError = UserFacingError.message(for: error)
        }
    }
}
