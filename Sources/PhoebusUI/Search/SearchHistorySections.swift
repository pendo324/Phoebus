import SwiftUI
import PhoebusCore

/// A post search to push: from a recent or saved search, or the Search
/// tab's "Search Posts" row.
struct PostSearchRequest: Hashable, Identifiable {
    var query: String
    var subreddit: String = ""
    var sort: String = "relevance"
    var time: String?

    var id: String { "\(subreddit)|\(query)|\(sort)|\(time ?? "")" }

    init(query: String, subreddit: String = "", sort: String = "relevance", time: String? = nil) {
        self.query = query
        self.subreddit = subreddit
        self.sort = sort
        self.time = time
    }

    init(_ saved: SavedSearch) {
        self.init(query: saved.query, subreddit: saved.subreddit, sort: saved.sort, time: saved.time)
    }
}

/// Phoebus addition: recent queries in one scope (empty for all of
/// Reddit), newest first. Hidden while "Save Search History" is off.
struct RecentSearchesSection: View {
    @Setting(SearchHistoryStore.storage) private var history
    @Setting(SearchHistorySettings.self) private var settings
    let subreddit: String
    let onRun: (RecentSearch) -> Void

    private var entries: [RecentSearch] {
        SearchHistoryStore.lists(in: history).recent(subreddit: subreddit)
    }

    var body: some View {
        if settings.saveHistory, !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    Button {
                        onRun(entry)
                    } label: {
                        if entry.kind == .user {
                            SearchHistoryRow(title: "u/\(entry.query)", systemImage: "person.crop.circle")
                        } else {
                            SearchHistoryRow(title: entry.query, systemImage: "clock.arrow.circlepath",
                                             subtitle: entry.searchEngine == .reddit ? nil : entry.searchEngine.title)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { SearchHistoryStore.remove(entry) }
                            .accessibilityIdentifier("search.recent.delete")
                    }
                    .accessibilityIdentifier("search.recent.row.\(entry.query)")
                }
            } header: {
                HStack {
                    Text("Recent Searches").textCase(.uppercase)
                    Spacer()
                    Button("Clear", role: .destructive) { SearchHistoryStore.clearRecent(subreddit: subreddit) }
                        .foregroundStyle(.red)
                        .font(.footnote.weight(.semibold))
                        .textCase(nil)
                        .accessibilityIdentifier("search.recent.clear")
                }
            }
        }
    }
}

/// Phoebus addition: pinned searches. The Search tab lists every scope;
/// a feed's search lists only that subreddit's.
struct SavedSearchesSection: View {
    @Setting(SearchHistoryStore.storage) private var history
    /// `nil` lists every scope.
    let subreddit: String?
    let onRun: (SavedSearch) -> Void

    private var entries: [SavedSearch] {
        let saved = SearchHistoryStore.lists(in: history).saved
        guard let subreddit else { return saved }
        return saved.filter { $0.subreddit.caseInsensitiveCompare(subreddit) == .orderedSame }
    }

    var body: some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    Button {
                        onRun(entry)
                    } label: {
                        SearchHistoryRow(title: entry.query, systemImage: "star", subtitle: subtitle(for: entry))
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Remove", role: .destructive) { SearchHistoryStore.unsave(entry) }
                            .accessibilityIdentifier("search.saved.remove")
                    }
                    .accessibilityIdentifier("search.saved.row.\(entry.query)")
                }
            } header: {
                Text("Saved Searches").textCase(.uppercase)
            }
        }
    }

    private func subtitle(for entry: SavedSearch) -> String {
        var parts = [entry.subreddit.isEmpty ? "All of Reddit" : "r/\(entry.subreddit)", entry.sort.capitalized]
        if let time = entry.time, let label = FeedScreen.timeframes.first(where: { $0.value == time })?.label {
            parts.append(label)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// A Search landing row: the glyph in the accent colour, the title, an
/// optional grey subtitle, and a chevron.
private struct SearchHistoryRow: View {
    let title: String
    let systemImage: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Color.apolloAccent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ApolloSettingsChevron()
        }
        .contentShape(Rectangle())
    }
}
