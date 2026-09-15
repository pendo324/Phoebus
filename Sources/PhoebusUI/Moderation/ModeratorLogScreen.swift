import SwiftUI
import PhoebusCore

/// Moderator log: a subreddit's moderation action history, paginated, with
/// filters by action and by moderator and a "Clear Filters" option.
public struct ModeratorLogScreen: View {
    let subreddit: String
    let repository: RedditRepository

    @State private var entries: [ModeratorLogEntry] = []
    @State private var errorMessage: String?
    @State private var afterCursor: String?
    @State private var isLoadingMore = false
    @State private var reachedEnd = false
    @State private var actionTypeFilter: String?
    @State private var moderatorFilter: String?

    public init(subreddit: String, repository: RedditRepository) {
        self.subreddit = subreddit
        self.repository = repository
    }

    /// Reddit `type` query values for `/about/log`, matching the categories its web
    /// UI exposes.
    private static let actionTypes: [(label: String, value: String)] = [
        ("Remove Link", "removelink"),
        ("Approve Link", "approvelink"),
        ("Remove Comment", "removecomment"),
        ("Approve Comment", "approvecomment"),
        ("Ban User", "banuser"),
        ("Unban User", "unbanuser"),
        ("Spam Link", "spamlink"),
        ("Spam Comment", "spamcomment"),
        ("Sticky", "sticky"),
        ("Distinguish", "distinguish"),
        ("Wiki Revise", "wikirevise"),
    ]

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let actionTypeFilter {
                filterChip("Action: \(actionTypeFilter)") { self.actionTypeFilter = nil }
            }
            if let moderatorFilter {
                filterChip("Mod: u/\(moderatorFilter)") { self.moderatorFilter = nil }
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.headline)
                        Spacer()
                        Text(entry.created, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("by u/\(entry.mod)").font(.caption).foregroundStyle(.secondary)
                    if let target = entry.targetAuthor {
                        Text("target: u/\(target)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let details = entry.details, !details.isEmpty {
                        Text(details).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .onAppear {
                    // Loads the next page once the second-to-last row appears.
                    if entry.id == entries.dropLast().last?.id {
                        Task { await loadMore() }
                    }
                }
            }
            if isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        // Empty-state casing follows "Mod Queue is empty".
        .overlay {
            if entries.isEmpty && errorMessage == nil && !isLoadingMore {
                Text("No moderator actions yet.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Mod Log: r/\(subreddit)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Menu("Filter by Action") {
                        ForEach(Self.actionTypes, id: \.value) { option in
                            Button(option.label) {
                                actionTypeFilter = option.value
                                Task { await reload() }
                            }
                        }
                    }
                    Button("Filter by Moderator…") {
                        // Apollo populates this from the subreddit's moderator list rather than free
                        // text. No text-entry sheet is wired here, so the entry is present but inert.
                    }
                    if actionTypeFilter != nil || moderatorFilter != nil {
                        Button("Clear Filters", role: .destructive) {
                            actionTypeFilter = nil
                            moderatorFilter = nil
                            Task { await reload() }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    .accessibilityLabel("Filter")
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func filterChip(_ label: String, onClear: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Button("Clear", action: onClear).font(.caption)
        }
    }

    private func reload() async {
        entries = []
        afterCursor = nil
        reachedEnd = false
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.fetchModeratorLog(subreddit: subreddit, after: afterCursor, actionType: actionTypeFilter, moderator: moderatorFilter)
            entries.append(contentsOf: page.entries)
            afterCursor = page.after
            if page.after == nil { reachedEnd = true }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
