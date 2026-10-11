import SwiftUI
import PhoebusCore

/// "Resume Where I Left Off": records where the reader is on the way out
/// and hands the saved place back on the next cold launch. `MainTabView`
/// supplies the tab; the Posts tab's frontmost feed registers a
/// `FeedResumeContext` for the rest.
@MainActor
public final class ResumeCoordinator {
    public static let shared = ResumeCoordinator()

    /// Set when the app was opened by a link, widget, notification,
    /// quick action or Shortcut, which win over resuming.
    public var launchedFromLink = false
    /// One decision per process: an account switch rebuilds the tabs.
    private var decided = false
    /// The snapshot being rebuilt, until its feed claims it. Saves made
    /// before then (the feed not built yet, or another tab in front)
    /// write it back unchanged instead of losing it.
    private var pendingFeed: ResumeSnapshot?
    weak var currentFeed: FeedResumeContext?

    private init() {}

    /// The place to rebuild on this launch, if any. Waits a moment first,
    /// so a link delivered just after launch still wins.
    public func launchSnapshot(account: String?, hasPendingLink: () -> Bool) async -> ResumeSnapshot? {
        guard !decided else { return nil }
        decided = true
        let enabled = ResumeSettingsStore.load().resumeWhereLeftOff
        guard ResumePolicy.snapshotToRestore(ResumeStore.load(), enabled: enabled, account: account,
                                             now: Date(), openedFromLink: launchedFromLink) != nil else { return nil }
        try? await Task.sleep(nanoseconds: 400_000_000)
        let snapshot = ResumePolicy.snapshotToRestore(ResumeStore.load(), enabled: enabled, account: account, now: Date(),
                                                      openedFromLink: launchedFromLink || hasPendingLink())
        if snapshot?.feed != nil { pendingFeed = snapshot }
        return snapshot
    }

    /// The saved place for the feed that was open, handed out once.
    func claimFeed(_ destination: LastViewedSubredditStore.Destination) -> ResumeSnapshot? {
        guard let pending = pendingFeed, pending.feed == destination else { return nil }
        pendingFeed = nil
        return pending
    }

    /// The Posts tab is back at the Subreddits list.
    public func postsTabShowsRoot() {
        currentFeed = nil
    }

    /// Saves where the reader is. `force` rewrites an unchanged place too,
    /// so backgrounding refreshes its age.
    public func save(account: String?, tab: Int, force: Bool) {
        guard ResumeSettingsStore.load().resumeWhereLeftOff else { return }
        var snapshot = ResumeSnapshot(savedAt: Date(), account: account, tab: tab,
                                      feed: nil, sort: nil, topPostID: nil, openPost: nil)
        if let pendingFeed {
            snapshot.feed = pendingFeed.feed
            snapshot.sort = pendingFeed.sort
            snapshot.topPostID = pendingFeed.topPostID
            snapshot.openPost = pendingFeed.openPost
        } else if let currentFeed {
            snapshot.feed = currentFeed.destination
            snapshot.sort = currentFeed.sort
            snapshot.topPostID = currentFeed.topPostID()
            snapshot.openPost = currentFeed.openPost
        }
        ResumeStore.record(snapshot, force: force)
    }
}

/// One feed's part of the snapshot: which feed, its topmost post on
/// screen (read from UIKit, as "Remember Thread Position" reads comments)
/// and the post open on top of it.
@MainActor
final class FeedResumeContext {
    /// Rows carry markers only if the setting was on as the feed opened.
    let tracksRows = ResumeSettingsStore.load().resumeWhereLeftOff
    let tracker = ThreadScrollTracker()
    var destination: LastViewedSubredditStore.Destination = .home
    var sort = ""
    var openPost: ResumeSnapshot.OpenPost?
    weak var listing: FeedListingModel?
    var scrollProxy: ScrollViewProxy?
    private var lastTopPostID: String?
    /// From a restore until the reader's first drag, the saved post is
    /// still where they are, even if the restore fell short.
    private var restoringTopPostID: String?
    private var restoreTask: Task<Void, Never>?

    /// The topmost post on screen; the last one seen when no row is laid
    /// out (the feed is covered or not built yet).
    func topPostID() -> String? {
        if let restoringTopPostID { return restoringTopPostID }
        guard tracksRows, let listing else { return lastTopPostID }
        let onScreen = tracker.visibleRowIDs()
        guard !onScreen.isEmpty else { return lastTopPostID }
        lastTopPostID = TopVisibleRowPolicy.topmost(order: listing.posts.map(\.id), onScreen: onScreen)
        return lastTopPostID
    }

    func noteTopPost() {
        _ = topPostID()
    }

    /// Saves keep reporting `postID` while the restore looks for it.
    func holdPosition(_ postID: String) {
        restoringTopPostID = postID
        lastTopPostID = postID
        tracker.onDragBegan = { [weak self] in
            self?.restoringTopPostID = nil
            self?.restoreTask?.cancel()
        }
    }

    /// The saved post wasn't found; the feed stays at its top.
    func releasePosition() {
        restoringTopPostID = nil
        lastTopPostID = nil
    }

    /// Brings `postID` to the top: `scrollTo` gets close, the tracker
    /// steps the rest of the way. Stops as soon as the reader drags.
    func restore(to postID: String) async {
        holdPosition(postID)
        scrollProxy?.scrollTo(postID, anchor: .top)
        let order = listing?.posts.map(\.id) ?? []
        let task = Task { [weak self] in
            guard let tracker = self?.tracker else { return }
            _ = await tracker.scroll(toRow: postID, order: order) { !Task.isCancelled }
        }
        restoreTask = task
        await task.value
    }
}

private struct ResumeTracksFeedsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Feeds in this stack (the Posts tab's) take part in "Resume Where I
    /// Left Off".
    var resumeTracksFeeds: Bool {
        get { self[ResumeTracksFeedsKey.self] }
        set { self[ResumeTracksFeedsKey.self] = newValue }
    }
}

public extension View {
    /// See `ResumeCoordinator`.
    func apolloResumeTracksFeeds() -> some View {
        environment(\.resumeTracksFeeds, true)
    }
}
