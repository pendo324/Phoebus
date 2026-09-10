import SwiftUI
import PhoebusCore

/// Owns the loaded comment tree state, hoisted out of `CommentTreeContent`
/// and out of any lazily-rendered `List` `Section`.
///
/// A `Section` embedded in a `List` is lazy, so a `.task` inside its own
/// content never fires until it scrolls near-visible; a tall post header
/// keeps Comments below the fold forever. Loading through this externally
/// owned store, driven by a `.task` on the top-level `List` instead, avoids
/// that.
@MainActor
final class CommentTreeStore: ObservableObject {
    @Published var roots: [CommentTreeNode] = []
    /// A row the hosting list should scroll to (Parent Comment swipe).
    @Published var scrollRequest: String?
    /// Bumped per comment on every collapse toggle and folded into its row
    /// identity, so the list RELOADS the row (a new cell) the way Apollo's
    /// batch update does, instead of resizing the old one in place. See
    /// `CommentCollapseAnimation`.
    @Published var rowGeneration: [String: Int] = [:]

    /// A comment row's list identity (`.id`), which changes with each
    /// collapse toggle. Scroll to comments through this.
    func rowID(_ commentID: String) -> String {
        guard let generation = rowGeneration[commentID], generation > 0 else { return commentID }
        return "\(commentID)#\(generation)"
    }
    /// True while the first comment fetch for the current post is in
    /// flight, so the list can show a loading row instead of looking like
    /// an empty thread. Only the first fetch sets this; a cached tree is
    /// served synchronously and must not flash a spinner.
    @Published var isLoadingComments = false
    @Published var errorMessage: String?
    @Published var newCommentIDs: Set<String> = []
    /// Trailing "N more comments" stub at the root level (a sibling of
    /// the top-level comments, not nested under any of them).
    @Published var rootMoreStub: MoreStub?
    /// IDs of "more" stubs currently being resolved, so the UI can
    /// show a spinner in place of the tappable row.
    @Published var resolvingStubIDs: Set<String> = []
    /// Reborn's floating re-collapse button lets the user re-collapse the
    /// currently-scrolled-past top-level thread without scrolling back up.
    /// Tracks which top-level (depth-0) comment is the most recent one
    /// scrolled into view, updated by each top-level row's `.onAppear`.
    @Published var visibleTopLevelRootID: String?
    /// Top-level comments currently on screen, for the jump button's
    /// "next comment below the one you're reading". Not published: it
    /// is only read when the button is tapped.
    var onScreenRootIDs: Set<String> = []

    /// The top-level comment after the topmost one on screen, wrapping
    /// to the first.
    func nextRootIDForJump() -> String? {
        let ids = roots.map(\.id)
        guard !ids.isEmpty else { return nil }
        let topmost = ids.firstIndex(where: onScreenRootIDs.contains) ?? -1
        return ids[(topmost + 1) % ids.count]
    }
    /// Set when a "N more replies" marker resolves to nothing (the
    /// referenced comments were deleted server-side), so the UI can show
    /// `DeletedMoreCommentsExplanationScreen` instead of vanishing the row.
    @Published var deletedMoreStubExplanation: MoreStub?
    /// Short-lived shared cache of built comment trees, so a screen rebuilt
    /// by a forward swipe can show the comments the user was just looking
    /// at instead of blanking and refetching. See `fetch`.
    static let recentTrees = RecentCommentTreeCache()

    private var lastKey: String?
    private var lastSubreddit = ""
    private var lastPostID = ""
    private var lastSort = "confidence"
    /// Re-fetches on a 10s cadence while "Live Update" sort is active.
    /// Owned by the store, not a SwiftUI `.task` loop, so it survives
    /// `.id(sort)` churn; torn down by `stopLivePolling()`.
    private var livePollTask: Task<Void, Never>?
    /// New comment count since `liveBaselineIDs` was captured, driving the
    /// "N new comments" pill. Uses ID-set diffing rather than row-geometry
    /// walking since SwiftUI's `List` has no UIKit row geometry to inspect.
    @Published var liveNewCount = 0
    private var liveBaselineIDs: Set<String> = []
    /// Distinguishes FOLLOW (pinned to the live edge) from READ (scrolled
    /// into older comments, counting arrivals) by scroll position. SwiftUI's
    /// `List` position is observable directly, so no display link is needed.
    @Published var isAtLiveEdge = true

    /// Reborn "Deleted Comments" archive-recovery cache, keyed by comment fullname.
    /// Populated lazily, once per post, only when recovery is active for this
    /// thread (global Always mode, or a Passive per-thread override).
    @Published var archivedComments: [String: ArchivedComment] = [:]
    /// Reborn "Passive (Per-Thread)" override, toggled from the "..." menu's
    /// Show/Hide Deleted Comments shortcut when the global mode is Passive.
    /// In-memory only, scoped to this store's lifetime.
    @Published var passiveThreadOverrideEnabled = false
    /// Fullnames the user has tapped to reveal under Tap-to-Reveal mode.
    /// Per-thread, in-memory only.
    @Published var revealedFullnames: Set<String> = []
    private var archiveFetchedForPostID: String?

    /// True when deleted/removed comment recovery is active for this
    /// thread: global Always mode, or Passive mode with this thread's
    /// override on.
    var deletedCommentsRecoveryActive: Bool {
        switch DeletedCommentsSettingsStore.load().mode {
        case .alwaysShow: return true
        case .passive: return passiveThreadOverrideEnabled
        case .off: return false
        }
    }

    /// Fetches the Arctic Shift archive for this post once recovery is
    /// active. Safe to call repeatedly; only fetches once per postID, and
    /// a transient failure clears the marker so a retry (e.g. pull to
    /// refresh) can happen.
    ///
    /// The archived copy to show in place of `comment`, or nil. Applies
    /// only to a comment whose live body is Reddit's deleted/removed
    /// placeholder.
    nonisolated static func archivedCopy(
        for comment: RedditComment,
        recoveryActive: Bool,
        archive: [String: ArchivedComment]
    ) -> ArchivedComment? {
        guard recoveryActive,
              DeletedCommentsClassifier.bodyLooksDeletedOrRemoved(comment.body) else { return nil }
        return archive[comment.name]?.classified(byCurrentBody: comment.body)
    }

    func fetchArchivedCommentsIfNeeded(postID: String) async {
        guard deletedCommentsRecoveryActive, archiveFetchedForPostID != postID else { return }
        archiveFetchedForPostID = postID
        do {
            archivedComments = try await ArcticShiftClient.fetchArchivedComments(linkFullname: "t3_\(postID)")
        } catch {
            archiveFetchedForPostID = nil
        }
    }

    /// Comments "..." menu "Show/Hide Deleted Comments" shortcut: a plain
    /// global toggle when Passive mode is off, or a per-thread override
    /// when Passive mode is on.
    func toggleDeletedCommentsShortcut(postID: String) async {
        let settings = DeletedCommentsSettingsStore.load()
        if settings.mode == .passive {
            passiveThreadOverrideEnabled.toggle()
            if passiveThreadOverrideEnabled {
                await fetchArchivedCommentsIfNeeded(postID: postID)
            }
        } else {
            // Off or Always: plain global toggle.
            let updated = DeletedCommentsSettingsStore.storage.update {
                $0.mode = settings.mode == .alwaysShow ? .off : .alwaysShow
            }
            if updated.mode == .alwaysShow {
                archiveFetchedForPostID = nil
                await fetchArchivedCommentsIfNeeded(postID: postID)
            }
        }
    }

    /// Un-hides one recovered comment's body under Tap-to-Reveal mode.
    func revealComment(_ fullname: String) {
        revealedFullnames.insert(fullname)
    }

    /// Fetches once per unique (postID, sort) unless `force` is set
    /// (used after posting a reply, when `roots` must be refreshed
    /// even though the key hasn't changed).
    func fetch(subreddit: String, postID: String, sort: String, repository: RedditRepository, force: Bool = false) async {
        let key = "\(postID)-\(sort)"
        if !force, key == lastKey, !roots.isEmpty {
            // Back from a pushed screen: the disappear stopped Live's
            // polling, and nothing else restarts it.
            if sort == "live", livePollTask == nil {
                startLivePolling(subreddit: subreddit, postID: postID, repository: repository)
            }
            return
        }
        // A forward-swipe navigation rebuilds `PostDetailScreen`, which owns
        // this store as a fresh `@StateObject`, so the guard above cannot
        // help there. This short-lived shared cache serves the previous
        // tree instead of blanking to a spinner and refetching.
        if !force, let cached = Self.recentTrees.value(for: key) {
            lastKey = key
            lastSubreddit = subreddit
            lastPostID = postID
            lastSort = sort
            roots = cached.roots
            rootMoreStub = cached.moreStub
            errorMessage = nil
            // Refresh the entry's age on use, so a post the user keeps
            // returning to stays cached rather than falling off the window.
            Self.recentTrees.touch(key: key)
            return
        }
        lastKey = key
        lastSubreddit = subreddit
        lastPostID = postID
        lastSort = sort
        // Only while there is nothing to show; a re-sort or refresh keeps
        // existing comments on screen until the new ones arrive.
        if roots.isEmpty { isLoadingComments = true }
        defer { isLoadingComments = false }
        do {
            let data = try await repository.fetchComments(subreddit: subreddit, postID: postID, sort: sort)
            let general = GeneralSettingsStore.load()
            guard let built = try await CommentTreeBuilder.parseCommentsResponseInBackground(
                data, postID: postID, autoCollapse: general.autoCollapseChildComments,
                autoCollapsePinned: general.autoCollapsePinnedComments,
                autoCollapseAutoModerator: general.autoCollapseAutoModeratorComments) else {
                errorMessage = "Unexpected response shape"
                return
            }
            roots = built.roots.applyingBlockedUsers(blockedAuthors(), hide: GeneralSettingsStore.load().hideBlockedUserComments)
            rootMoreStub = built.moreStub
            Self.recentTrees.store(key: key, roots: roots, moreStub: built.moreStub)
            if GeneralSettingsStore.load().showUserProfilePictures {
                // Every author's picture in one request per 100 (#1220).
                let authors = roots.flatMap { $0.flattenedAll() }.compactMap { node in
                    node.comment.authorFullname.map { (username: node.comment.author, fullname: $0) }
                }
                await AvatarCache.shared.prefetch(authors: authors, repository: repository)
            }
            let allIDs = roots.flatMap { $0.allIDs() }
            newCommentIDs = NewCommentsTracker.newCommentIDs(postID: postID, currentIDs: allIDs)
            NewCommentsTracker.markSeen(postID: postID, commentIDs: allIDs)
            // Also snapshot the post's total comment count for the feed
            // row's unread badge. Reborn's "Recently Read" feature key:
            // `PostCommentsSnapshots`.
            if let total = built.postCommentCount {
                NewCommentsTracker.recordCommentCount(postID: postID, count: total)
            }
            errorMessage = nil
            if sort == "live" {
                liveBaselineIDs = Set(allIDs)
                liveNewCount = 0
                startLivePolling(subreddit: subreddit, postID: postID, repository: repository)
            } else {
                stopLivePolling()
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// Re-fetches on Reborn's 10s cadence while "Live" sort is active: merges in
    /// place when at the live edge (FOLLOW), or just updates the new-arrivals count
    /// for the pill (READ).
    private func startLivePolling(subreddit: String, postID: String, repository: RedditRepository) {
        livePollTask?.cancel()
        livePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.pollLiveUpdate(subreddit: subreddit, postID: postID, repository: repository)
            }
        }
    }

    func stopLivePolling() {
        livePollTask?.cancel()
        livePollTask = nil
    }

    private func pollLiveUpdate(subreddit: String, postID: String, repository: RedditRepository) async {
        guard lastSort == "live", lastPostID == postID else { return }
        do {
            let data = try await repository.fetchComments(subreddit: subreddit, postID: postID, sort: "live")
            let general = GeneralSettingsStore.load()
            guard let built = try await CommentTreeBuilder.parseCommentsResponseInBackground(
                data, postID: postID, autoCollapse: general.autoCollapseChildComments,
                autoCollapsePinned: general.autoCollapsePinnedComments,
                autoCollapseAutoModerator: general.autoCollapseAutoModeratorComments),
                  lastSort == "live", lastPostID == postID else { return }
            let allIDs = built.roots.flatMap { $0.allIDs() }
            let freshIDs = Set(allIDs).subtracting(liveBaselineIDs)
            guard !freshIDs.isEmpty else { return }

            // "Follow New Live Comments" toggle: when disabled, the whole
            // FOLLOW mechanism is off and new arrivals aren't reflected
            // until the user manually reselects Live sort.
            if isAtLiveEdge && GeneralSettingsStore.load().liveCommentsFollow {
                // FOLLOW: adopt the new snapshot so newest comments
                // appear at top and older ones slide down.
                roots = built.roots.applyingBlockedUsers(blockedAuthors(), hide: GeneralSettingsStore.load().hideBlockedUserComments)
                rootMoreStub = built.moreStub
                newCommentIDs = freshIDs
                NewCommentsTracker.markSeen(postID: postID, commentIDs: allIDs)
                liveBaselineIDs = Set(allIDs)
                liveNewCount = 0
            } else if GeneralSettingsStore.load().liveCommentsFollow {
                // READ: never touch `roots` out from under the user, only
                // grow the pill count. Only surfaced when "Follow New Live
                // Comments" is on.
                liveNewCount = freshIDs.count
            } else {
                // Off: stock Apollo's own live tick, which merges up to the
                // 20 newest new top-level comments in at the top.
                let existing = Set(roots.map(\.id))
                let fresh = built.roots.filter { freshIDs.contains($0.id) && !existing.contains($0.id) }.prefix(20)
                guard !fresh.isEmpty else { return }
                let merged = Array(fresh).applyingBlockedUsers(blockedAuthors(), hide: general.hideBlockedUserComments)
                roots = merged + roots
                newCommentIDs = Set(fresh.flatMap { $0.allIDs() })
                liveBaselineIDs.formUnion(fresh.flatMap { $0.allIDs() })
            }
        } catch {
            // A transient poll failure isn't worth surfacing as a hard
            // error over the whole thread - the next tick retries.
        }
    }

    /// Called by the live pill's tap: jump back to the newest comments and re-arm
    /// FOLLOW mode.
    func jumpToLiveEdge(subreddit: String, postID: String, repository: RedditRepository) async {
        isAtLiveEdge = true
        liveNewCount = 0
        await pollLiveUpdate(subreddit: subreddit, postID: postID, repository: repository)
    }


    /// The account's Reddit blocks plus Filters & Blocks author filters
    /// (lowercased), for `HideBlockedUserComments`.
    private func blockedAuthors() -> Set<String> {
        BlockedUsersStore.lowercasedNames().union(
            ContentFilterStore.load().filter { $0.kind == .author }.map { $0.value.lowercased() })
    }

    /// Collapses or expands every comment's children at once.
    /// Backs the post menu's "Collapse Child Comments" row.
    func setAllChildrenCollapsed(_ collapsed: Bool) {
        CommentCollapseAnimation.perform(revealsRow: false) {
            roots = roots.map { $0.settingChildrenCollapsed(collapsed) }
        }
    }

    /// See `CommentCollapseAnimation` for Apollo's row animation.
    /// Reborn #1196: a just-posted comment fades into the thread at the top of its
    /// parent instead of the whole thread reloading. Returns false when the parent
    /// is not loaded, so the caller refetches.
    @discardableResult
    func insertPosted(_ comment: RedditComment, parentFullname: String) -> Bool {
        if parentFullname.hasPrefix("t3_") {
            withAnimation(.easeOut(duration: 0.3)) {
                roots.insert(CommentTreeNode(comment: comment, depth: 0), at: 0)
            }
            return true
        }
        for (index, root) in roots.enumerated() {
            if let updated = root.inserting(reply: comment, under: parentFullname) {
                withAnimation(.easeOut(duration: 0.3)) { roots[index] = updated }
                return true
            }
        }
        return false
    }

    func toggleCollapse(_ node: CommentTreeNode) {
        CommentCollapseAnimation.perform {
            rowGeneration[node.id, default: 0] += 1
            roots = roots.map { $0.togglingCollapse(id: node.id) }
        }
    }

    /// Resolves a "more replies" stub (nested, or the root-level
    /// `rootMoreStub`) by fetching its children via `/api/morechildren`
    /// and splicing them into the tree in place. See `MoreStub`'s doc
    /// comment for why truncated threads need this.
    func resolveMoreStub(_ stub: MoreStub, repository: RedditRepository) async {
        resolvingStubIDs.insert(stub.id)
        defer { resolvingStubIDs.remove(stub.id) }
        // Reddit's depth-limit continuation ("Continue thread\u{2026}")
        // has no child ids to resolve, so `/api/morechildren` cannot
        // answer it. The tree has to be re-requested rooted at the
        // parent comment. See `MoreStub.isContinueThread`.
        if stub.isContinueThread {
            await resolveContinueThread(stub, repository: repository)
            return
        }
        do {
            let things = try await repository.fetchMoreChildren(linkFullname: "t3_\(lastPostID)", childIDs: stub.children, sort: lastSort)
            let built = CommentTreeBuilder.buildResolved(from: things, stub: stub, autoCollapse: false, autoCollapsePinned: false)
            // A "more" marker whose referenced comments were deleted
            // server-side resolves to zero real comments and no nested
            // stub either; show `DeletedMoreCommentsExplanationScreen`
            // rather than silently vanishing the row. Only trip this for
            // a truly empty result (`built.moreStub` != nil means there
            // was real data, just further paginated).
            if built.roots.isEmpty && built.moreStub == nil {
                deletedMoreStubExplanation = stub
                if rootMoreStub?.id == stub.id {
                    rootMoreStub = nil
                } else {
                    roots = roots.map { $0.resolvingMoreStub(stubID: stub.id, with: []) }
                }
                return
            }
            if rootMoreStub?.id == stub.id {
                roots.append(contentsOf: built.roots.applyingBlockedUsers(blockedAuthors(), hide: GeneralSettingsStore.load().hideBlockedUserComments))
                rootMoreStub = built.moreStub
            } else {
                roots = roots.map { $0.resolvingMoreStub(stubID: stub.id, with: built.roots.applyingBlockedUsers(blockedAuthors(), hide: GeneralSettingsStore.load().hideBlockedUserComments)) }
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// Resolves a "Continue thread\u{2026}" stub by re-fetching the tree rooted at
    /// its parent comment and splicing the newly revealed replies in where the stub
    /// sat, so threads deeper than Reddit's response depth limit don't end early.
    private func resolveContinueThread(_ stub: MoreStub, repository: RedditRepository) async {
        // `parentID` is a fullname like `t1_abc123`; the endpoint wants
        // the bare id.
        let commentID = stub.parentID.hasPrefix("t1_")
            ? String(stub.parentID.dropFirst(3))
            : stub.parentID
        do {
            let data = try await repository.fetchCommentThread(
                subreddit: lastSubreddit,
                postID: lastPostID,
                commentID: commentID,
                sort: lastSort
            )
            // Same response shape as a normal comments fetch.
            guard let built = try await CommentTreeBuilder.parseCommentsResponseInBackground(
                data, postID: lastPostID) else {
                errorMessage = "Unexpected response shape"
                return
            }
            // The refetch returns the parent comment itself as its root,
            // with the next depth-limit's worth of replies underneath.
            // Only the replies belong in the tree; the parent is already
            // on screen.
            let revealed = built.roots.first?.children ?? []
            guard !revealed.isEmpty else {
                // Nothing came back: the same genuinely-empty case the
                // id-based stubs already explain to the user.
                deletedMoreStubExplanation = stub
                roots = roots.map { $0.resolvingMoreStub(stubID: stub.id, with: []) }
                return
            }
            roots = roots.map {
                $0.resolvingMoreStub(stubID: stub.id,
                                     with: revealed.applyingBlockedUsers(blockedAuthors(), hide: GeneralSettingsStore.load().hideBlockedUserComments))
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// Holds recently built comment trees for a few seconds, to survive a
/// view rebuild - see `CommentTreeStore.fetch`.
@MainActor
final class RecentCommentTreeCache {
    private struct Entry {
        let roots: [CommentTreeNode]
        let moreStub: MoreStub?
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]

    func value(for key: String) -> (roots: [CommentTreeNode], moreStub: MoreStub?)? {
        guard let entry = entries[key] else { return nil }
        guard RecentEntryPolicy.isFresh(age: Date().timeIntervalSince(entry.storedAt)) else {
            entries[key] = nil
            return nil
        }
        return (entry.roots, entry.moreStub)
    }

    /// Resets an entry's age, so a post the user keeps returning to
    /// stays cached for as long as they keep returning to it.
    func touch(key: String) {
        guard let entry = entries[key] else { return }
        entries[key] = Entry(roots: entry.roots, moreStub: entry.moreStub, storedAt: Date())
    }

    func store(key: String, roots: [CommentTreeNode], moreStub: MoreStub?) {
        entries[key] = Entry(roots: roots, moreStub: moreStub, storedAt: Date())
        let now = Date()
        let ages = entries.mapValues { now.timeIntervalSince($0.storedAt) }
        for key in RecentEntryPolicy.keysToEvict(agesByKey: ages) {
            entries[key] = nil
        }
    }
}
