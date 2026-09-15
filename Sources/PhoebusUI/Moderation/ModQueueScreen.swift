import SwiftUI
import PhoebusCore

/// Moderator queue: reported posts and comments awaiting action, paginated, with
/// a Reports/Spam/Unmoderated filter.
public struct ModQueueScreen: View {
    let subreddit: String
    let repository: RedditRepository

    @State private var items: [ModQueueItem] = []
    @State private var errorMessage: String?
    @State private var filter: RedditRepository.ModQueueFilter = .all
    @State private var afterCursor: String?
    @State private var isLoadingMore = false
    @State private var reachedEnd = false

    public init(subreddit: String, repository: RedditRepository) {
        self.subreddit = subreddit
        self.repository = repository
    }

    /// Rows this app can open, in Apollo's order (Reborn's catalogue ids).
    private let moderatorMenuIDs = ["mod-mail", "mod-queue", "mod-log", "mod-reports", "mod-spam-queue",
                                    "mod-unmoderated", "mod-all-comments", "mod-traffic", "mod-ban-users",
                                    "mod-mute-users", "mod-rules", "mod-automoderator",
                                    "mod-approved-submitters", "mod-moderators"]

    @ViewBuilder
    private func moderatorMenuRow(_ id: String) -> some View {
        switch id {
        case "mod-mail":
            SettingsLink { ModmailListScreen(repository: repository) } label: {
                Label("Mod Mail", systemImage: "envelope.badge.shield.half.filled")
            }
        case "mod-queue": filterRow(.all, title: "Mod Queue", symbol: "tray.full")
        case "mod-reports": filterRow(.reports, title: "Reports", symbol: "flag")
        case "mod-spam-queue": filterRow(.spam, title: "Spam", symbol: "exclamationmark.shield")
        case "mod-unmoderated": filterRow(.unmoderated, title: "Unmoderated", symbol: "eye.slash")
        case "mod-log":
            SettingsLink { ModeratorLogScreen(subreddit: subreddit, repository: repository) } label: {
                Label("Mod Log", systemImage: "list.bullet.clipboard")
            }
        case "mod-all-comments":
            SettingsLink { AllSubredditCommentsScreen(subreddit: subreddit, repository: repository) } label: {
                Label("All Comments", systemImage: "text.bubble")
            }
        case "mod-traffic":
            SettingsLink { SubredditTrafficScreen(subreddit: subreddit, repository: repository) } label: {
                Label("Traffic Stats", systemImage: "chart.xyaxis.line")
            }
        case "mod-ban-users": userListRow(.banned)
        case "mod-mute-users": userListRow(.muted)
        case "mod-approved-submitters": userListRow(.approved)
        case "mod-rules":
            SettingsLink { SubredditRulesScreen(subredditName: subreddit, repository: repository) } label: {
                Label("Rules", systemImage: "list.number")
            }
        case "mod-automoderator":
            SettingsLink { AutoModeratorScreen(subreddit: subreddit, repository: repository) } label: {
                Label("AutoModerator", systemImage: "shield.lefthalf.filled")
            }
        case "mod-moderators":
            SettingsLink { SubredditModeratorsScreen(subredditName: subreddit, repository: repository) } label: {
                Label("Moderators", systemImage: "shield")
            }
        default:
            EmptyView()
        }
    }

    /// The queue's own views switch the list in place.
    private func filterRow(_ option: RedditRepository.ModQueueFilter, title: String, symbol: String) -> some View {
        Button {
            filter = option
            Task { await reload() }
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    private func userListRow(_ kind: ModeratorUsersScreen.UserListKind) -> some View {
        SettingsLink {
            ModeratorUsersScreen(subreddit: subreddit, repository: repository, kind: kind)
        } label: {
            Label(kind.title, systemImage: ApolloMenuIcon.symbol(kind.apolloIconName, fallback: "person.2.slash"))
        }
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if items.isEmpty && errorMessage == nil && !isLoadingMore {
                Text("Mod Queue is empty").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                ModQueueRow(item: item, repository: repository, subreddit: subreddit) {
                    items.removeAll { $0.id == item.id }
                }
                .onAppear {
                    if item.id == items.dropLast().last?.id {
                        Task { await loadMore() }
                    }
                }
            }
            if isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Mod Queue: r/\(subreddit)")
        // Apollo's back/forward page swipes.
        .apolloForwardSwipe()
        .toolbar {
            // The filter is a toolbar menu: every segmented control in Apollo has exactly
            // two items, so a 4-item one is not a shape it uses.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Icon-less checked row: a `Toggle`, not a checkmark image.
                    // SwiftUI maps a toggle inside a `Menu` onto `UIAction.state`,
                    // which UIKit draws as a checkmark on the trailing edge. A
                    // checkmark image lands in the leading icon slot: wrong edge.
                    ForEach(RedditRepository.ModQueueFilter.allCases, id: \.self) { option in
                        Toggle(isOn: Binding(
                            get: { filter == option },
                            set: { isOn in
                                guard isOn else { return }
                                filter = option
                                Task { await reload() }
                            }
                        )) {
                            Text(option.label)
                        }
                    }
                } label: {
                    Image(systemName: ApolloMenuIcon.symbol(
                        "option-filter-funnel", fallback: "line.3.horizontal.decrease.circle"))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Subreddit moderator menu, arranged by the Action Menus layout (Reborn #1131,
                // `moderator-subreddit`).
                Menu {
                    ForEach(ActionMenuLayoutStore.arrange(moderatorMenuIDs, for: .moderatorSubreddit), id: \.self) { id in
                        moderatorMenuRow(id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More")
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        items = []
        afterCursor = nil
        reachedEnd = false
        await loadMore()
    }

    private func loadMore() async {
        // Clears a failure from a previous attempt.
        errorMessage = nil
        guard !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let listing = try await repository.fetchModQueue(subreddit: subreddit, filter: filter, after: afterCursor)
            let newItems = listing.data.children.compactMap { child in
                ModQueueItem(kind: child.kind, raw: child.data.raw)
            }
            items.append(contentsOf: newItems)
            afterCursor = listing.data.after
            if listing.data.after == nil { reachedEnd = true }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

struct ModQueueRow: View {
    let item: ModQueueItem
    let repository: RedditRepository
    let subreddit: String
    let onHandled: () -> Void
    @State private var isProcessing = false
    /// Removal reasons picker: the subreddit's canned reasons, shown when removing
    /// content.
    @State private var removalReasons: [RedditRemovalReason] = []
    @State private var showingReasonPicker = false
    @State private var pendingReason: RedditRemovalReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.kind == "t3" ? "Post" : "Comment")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                Text("u/\(item.author)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if item.numReports > 0 {
                    Label("\(item.numReports)", systemImage: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Text(item.title).font(.headline)
            if !item.body.isEmpty {
                Text(item.body).font(.body).lineLimit(3)
            }
            // Shows the actual report reasons, not just a count.
            if !item.userReportReasons.isEmpty || !item.modReportReasons.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(item.userReportReasons, id: \.reason) { report in
                        Label("\(report.reason) (\(report.count))", systemImage: "person.fill.questionmark")
                    }
                    ForEach(item.modReportReasons, id: \.reason) { report in
                        Label("\(report.reason) — u/\(report.moderator)", systemImage: "shield.fill")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.orange)
            }
            HStack(spacing: 16) {
                Button {
                    Task { await handle { try await repository.approve(fullname: item.fullname) } }
                } label: {
                    Label("Approve", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    Task { await presentRemovalReasonsOrRemove(isSpam: false) }
                } label: {
                    Label("Remove", systemImage: "xmark.circle")
                }
                Button(role: .destructive) {
                    Task { await handle { try await repository.remove(fullname: item.fullname, isSpam: true) } }
                } label: {
                    Label("Spam", systemImage: "trash")
                }
                // Ignore Reports (`/api/ignore_reports`).
                Button {
                    Task { await handle { try await repository.ignoreReports(fullname: item.fullname) } }
                } label: {
                    Label("Ignore Reports", systemImage: "flag.slash")
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .disabled(isProcessing)
        }
        .padding(.vertical, 4)
        .confirmationDialog("Removal Reason", isPresented: $showingReasonPicker, titleVisibility: .visible) {
            ForEach(removalReasons) { reason in
                Button(reason.title) { pendingReason = reason }
            }
            Button("Remove Without Reason") {
                Task { await handle { try await repository.remove(fullname: item.fullname, isSpam: false) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $pendingReason) { reason in
            RemovalReasonNotifySheet(reason: reason, isComment: item.kind == "t1") { notify, message, modNote in
                await handle {
                    try await repository.remove(fullname: item.fullname, isSpam: false)
                    try await repository.applyRemovalReason(fullname: item.fullname, reasonID: reason.id, modNote: modNote)
                    if let notify {
                        try await repository.sendRemovalMessage(fullname: item.fullname, kind: notify,
                                                                title: reason.title, message: message)
                    }
                }
            }
        }
    }

    /// Fetches the subreddit's configured removal reasons
    /// (`api/v1/{subreddit}/removal_reasons`) and prompts for one if any exist;
    /// otherwise removes directly.
    private func presentRemovalReasonsOrRemove(isSpam: Bool) async {
        guard !isSpam else {
            await handle { try await repository.remove(fullname: item.fullname, isSpam: true) }
            return
        }
        if let fetched = try? await repository.fetchRemovalReasons(subreddit: subreddit), !fetched.isEmpty {
            removalReasons = fetched
            showingReasonPicker = true
        } else {
            await handle { try await repository.remove(fullname: item.fullname, isSpam: false) }
        }
    }

    private func handle(_ action: () async throws -> Void) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await action()
            onHandled()
        } catch {
            // Leave item in place so the moderator can retry.
        }
    }
}

/// Apollo's removal-reason follow-up: the editable reason message, "Notify user
/// via…" (Public Sticky / Reply, Reborn's "from Subreddit" variant, Mod Mail from
/// Subreddit, Mod Mail from You, or none) and the optional private mod note.
struct RemovalReasonNotifySheet: View {
    let reason: RedditRemovalReason
    let isComment: Bool
    let onSubmit: (RemovalNotifyKind?, String, String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var message: String
    @State private var modNote = ""
    @State private var notify: RemovalNotifyKind? = .publicReply
    @State private var isSubmitting = false

    init(reason: RedditRemovalReason, isComment: Bool,
         onSubmit: @escaping (RemovalNotifyKind?, String, String) async -> Void) {
        self.reason = reason
        self.isComment = isComment
        self.onSubmit = onSubmit
        _message = State(initialValue: reason.message)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Message") {
                    TextEditor(text: $message).frame(minHeight: 120)
                }
                Section("Notify user via…") {
                    ForEach(RemovalNotifyKind.allCases, id: \.self) { kind in
                        notifyRow(kind.title(forComment: isComment), kind)
                    }
                    notifyRow("Don't Notify", nil)
                }
                Section("Private Mod Note (Optional)") {
                    TextField("Mod note", text: $modNote)
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle(reason.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remove") {
                        isSubmitting = true
                        Task {
                            await onSubmit(notify, message, modNote)
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func notifyRow(_ title: String, _ kind: RemovalNotifyKind?) -> some View {
        Button {
            notify = kind
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if notify == kind { Image(systemName: "checkmark").foregroundStyle(Color.apolloAccent) }
            }
        }
    }
}
