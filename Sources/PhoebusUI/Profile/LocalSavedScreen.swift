import SwiftUI
import PhoebusCore

/// Phoebus-only "Kept Locally" (Local Saved): items saved in the app that
/// Reddit no longer lists in Saved, from their local snapshots (see
/// `LocalSavedStore`). A removed comment's body comes back from the
/// archive when the Deleted Comments setting allows archive lookups.
struct LocalSavedScreen: View {
    let username: String
    let repository: RedditRepository

    @Setting(DeletedCommentsSettings.self) private var deletedComments
    @Environment(\.apolloTheme) private var apolloTheme
    @Environment(\.colorScheme) private var colorScheme

    @State private var records: [LocalSavedRecord] = []
    @State private var statuses: [String: LocalSavedLiveStatus] = [:]
    @State private var archived: [String: ArchivedComment] = [:]
    @State private var archiveRequested: Set<String> = []
    @State private var isChecking = false
    @State private var checkMessage: String?
    @State private var openingFullname: String?
    @State private var errorMessage: String?
    @State private var selectedPost: RedditPost?
    @State private var selectedComment: ProfileListingView.CommentLink?

    var body: some View {
        List {
            Section {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if records.isEmpty {
                    Text("Nothing kept locally")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("localSaved.emptyState")
                }
                ForEach(records) { record in
                    row(record)
                        .contentShape(Rectangle())
                        .onTapGesture { Task { await open(record) } }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                forget(record)
                            } label: {
                                Label("Forget", systemImage: "trash")
                            }
                            .accessibilityIdentifier("localSaved.forget.\(record.fullname)")
                        }
                        .accessibilityIdentifier("localSaved.row.\(record.fullname)")
                }
            } footer: {
                Text(checkMessage ?? "Items you saved in Phoebus that Reddit no longer lists in your Saved, usually because they were removed or deleted.")
                    .apolloSectionFooter()
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Kept Locally")
        .apolloForwardSwipe()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await checkForMissing() }
                } label: {
                    if isChecking {
                        ProgressView()
                    } else {
                        Text("Check for Missing")
                    }
                }
                .disabled(isChecking)
                .accessibilityIdentifier("localSaved.checkForMissing")
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            PostDetailScreen(post: post, repository: repository)
        }
        .apolloTracksForwardNavigation($selectedPost)
        .navigationDestination(item: $selectedComment) { link in
            CommentTreeScreen(subreddit: link.subreddit, postID: link.postID,
                              repository: repository, focusedCommentID: link.commentID)
        }
        .apolloTracksForwardNavigation($selectedComment)
        .onReceive(NotificationCenter.default.publisher(for: .localSavedChanged)) { _ in reload() }
        .task {
            reload()
            await loadStatuses()
        }
        .accessibilityIdentifier("localSaved.screen")
    }

    @ViewBuilder
    private func row(_ record: LocalSavedRecord) -> some View {
        let status = statuses[record.fullname]
        HStack(alignment: .top, spacing: 10) {
            if let thumbnail = record.thumbnail, let url = URL(string: thumbnail) {
                CachedAsyncImage(url: url, contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 4) {
                if record.kind == .post {
                    Text(record.title)
                        .apolloFont(size: 15, weight: .medium)
                        .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                        .lineLimit(3)
                } else {
                    commentBody(record, status: status)
                    if !record.title.isEmpty {
                        Text(record.title)
                            .apolloFont(size: 13)
                            .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                            .lineLimit(2)
                    }
                }
                HStack(spacing: 6) {
                    if !record.subreddit.isEmpty {
                        Text("r/\(SubredditCapitalization.display(record.subreddit))")
                    }
                    if !record.author.isEmpty {
                        Text("u/\(record.author)")
                    }
                    Text("Saved \(record.savedAt.apolloRelativeTime)")
                }
                .apolloFont(size: 12)
                .foregroundStyle(Color.apolloTertiaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let status {
                    StatusBadge(label: status.label)
                        .accessibilityIdentifier("localSaved.badge.\(record.fullname)")
                }
                if openingFullname == record.fullname {
                    ProgressView()
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func commentBody(_ record: LocalSavedRecord, status: LocalSavedLiveStatus?) -> some View {
        if let recovered = archived[record.fullname] {
            let reason: DeletedCommentReason = status == .deleted ? .userDeleted : recovered.reason
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label("Recovered from archive", systemImage: "clock.arrow.circlepath")
                        .apolloFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                    Spacer(minLength: 0)
                    DeletedReasonChip(label: reason.displayLabel)
                }
                Text(recovered.body)
                    .apolloFont(size: 15)
                    .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                    .lineLimit(8)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(DeletedCommentHighlight.color(for: reason)))
            .accessibilityIdentifier("localSaved.recovered.\(record.fullname)")
        } else {
            Text(record.snippet.isEmpty ? "Comment" : record.snippet)
                .apolloFont(size: 15)
                .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                .lineLimit(5)
            if status?.bodyIsGone == true || status == .unavailable,
               deletedComments.mode == .off, !archiveRequested.contains(record.fullname) {
                Button("Show Original Comment") {
                    Task { await recover([record.fullname]) }
                }
                .apolloFont(size: 13, weight: .semibold)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("localSaved.showOriginal.\(record.fullname)")
            }
        }
    }

    private func reload() {
        guard let account = LocalSavedStore.currentAccount else { records = []; return }
        records = LocalSavedStore.keptLocally(account: account)
    }

    /// Badges from Reddit's current copies; gone comment bodies then come
    /// from the archive, automatically unless Deleted Comments is off.
    private func loadStatuses() async {
        let missing = records.map(\.fullname).filter { statuses[$0] == nil }
        guard !missing.isEmpty, let live = try? await repository.fetchInfoItems(fullnames: missing) else { return }
        for fullname in missing {
            statuses[fullname] = LocalSavedLiveStatus.classify(live[fullname])
        }
        guard deletedComments.mode != .off else { return }
        let gone = records.filter { $0.kind == .comment && (statuses[$0.fullname]?.bodyIsGone == true || statuses[$0.fullname] == .unavailable) }
        await recover(gone.map(\.fullname))
    }

    private func recover(_ fullnames: [String]) async {
        let wanted = fullnames.filter { !archiveRequested.contains($0) }
        guard !wanted.isEmpty else { return }
        archiveRequested.formUnion(wanted)
        if let found = try? await ArcticShiftClient.fetchArchivedComments(ids: wanted) {
            archived.merge(found) { _, new in new }
        }
    }

    private func checkForMissing() async {
        guard let account = LocalSavedStore.currentAccount else { return }
        isChecking = true
        defer { isChecking = false }
        let startedAt = Date()
        let wanted = Set(LocalSavedStore.load(account: account).map(\.fullname))
        do {
            let walk = try await repository.walkSavedListing(username: username, wanted: wanted)
            LocalSavedStore.reconcile(present: walk.present, listingComplete: walk.complete,
                                      listingStartedAt: startedAt, account: account)
            reload()
            checkMessage = walk.complete
                ? "Checked your Saved: \(records.count) kept locally."
                : "Your Saved is longer than Reddit lists, so items past its end can't be checked."
            await loadStatuses()
        } catch {
            checkMessage = "Couldn't check your Saved. \(UserFacingError.message(for: error))"
        }
    }

    private func forget(_ record: LocalSavedRecord) {
        guard let account = LocalSavedStore.currentAccount else { return }
        LocalSavedStore.remove(fullname: record.fullname, account: account)
    }

    private func open(_ record: LocalSavedRecord) async {
        errorMessage = nil
        if let commentID = record.commentID {
            selectedComment = ProfileListingView.CommentLink(subreddit: record.subreddit, postID: record.postID,
                                                             commentID: commentID)
            return
        }
        openingFullname = record.fullname
        defer { openingFullname = nil }
        do {
            selectedPost = try await repository.fetchPost(subreddit: record.subreddit, postID: record.postID)
        } catch {
            errorMessage = "Couldn't load the post. It may no longer exist."
        }
    }
}

private struct StatusBadge: View {
    let label: String

    var body: some View {
        Text(label.uppercased())
            .apolloFont(size: 11, weight: .semibold)
            .foregroundStyle(Color(red: 0.42, green: 0.06, blue: 0.06))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(red: 1.0, green: 0.66, blue: 0.64)))
            .fixedSize()
    }
}
