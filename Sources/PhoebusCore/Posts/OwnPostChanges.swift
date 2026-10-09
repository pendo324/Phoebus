import Foundation
#if canImport(Combine)
import Combine
#endif

/// What this device changed on a post (an edited body, a deletion, comments
/// it added), keyed by fullname, so a thread opened again from a feed row that
/// still holds the old copy shows the change.
///
/// Like `VoteStateStore`, it lives outside any view: the screen that made the
/// change is gone by the time the thread is reopened.
@MainActor
public final class OwnPostChanges {
    public static let shared = OwnPostChanges()

    /// Hand-rolled rather than `@Published`; see `VoteStateStore`.
    #if canImport(Combine)
    public let objectWillChange = ObservableObjectPublisher()
    #endif

    private func changed() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }

    /// A comment count this device set, and the count Reddit reported when it
    /// did. It applies only while Reddit still reports that count: once the
    /// listing moves on, Reddit's number includes the change (or supersedes it).
    private struct PendingCount {
        let count: Int
        let basis: Int
    }

    private var bodies: [String: String] = [:]
    private var deleted: Set<String> = []
    private var observedCounts: [String: Int] = [:]
    private var pendingCounts: [String: PendingCount] = [:]

    private init() {}

    // MARK: Edit and delete

    public func recordEdit(fullname: String, body: String) {
        changed()
        bodies[fullname] = body
    }

    public func recordDeletion(fullname: String) {
        changed()
        deleted.insert(fullname)
    }

    public func isDeleted(_ fullname: String) -> Bool {
        deleted.contains(fullname)
    }

    // MARK: Comment count

    /// Reddit's comment count for the post, as the latest thread fetch saw it.
    public func observeCommentCount(fullname: String, count: Int) {
        guard observedCounts[fullname] != count else { return }
        changed()
        observedCounts[fullname] = count
    }

    /// Adds `delta` to the count the thread shows. `listed` is the count of
    /// the copy of the post the screen was opened with.
    public func recordCommentChange(fullname: String, listed: Int, delta: Int) {
        let basis = observedCounts[fullname] ?? listed
        let shown = commentCount(for: fullname, listed: listed)
        changed()
        pendingCounts[fullname] = PendingCount(count: max(shown + delta, 0), basis: basis)
    }

    /// The count to show: Reddit's latest, plus this device's own changes
    /// while Reddit has not caught up with them.
    public func commentCount(for fullname: String, listed: Int) -> Int {
        let reported = observedCounts[fullname] ?? listed
        if let pending = pendingCounts[fullname], pending.basis == reported { return pending.count }
        return reported
    }

    // MARK: Applying

    /// The post with this device's changes laid over it.
    public func apply(to post: RedditPost) -> RedditPost {
        var result = post
        if let body = bodies[post.name] { result.selftext = body }
        result.numComments = commentCount(for: post.name, listed: post.numComments)
        return result
    }

    /// Clears everything, for tests.
    public func reset() {
        changed()
        bodies = [:]
        deleted = []
        observedCounts = [:]
        pendingCounts = [:]
    }
}
