import Foundation
#if canImport(Combine)
import Combine
#endif

/// The awards of the threads the user has open, keyed by post or comment
/// fullname, so a late-arriving fragment updates the rows it concerns without
/// touching the comment tree. Follows `VoteStateStore`: one shared instance
/// every row observes.
@MainActor
public final class AwardStore {
    public static let shared = AwardStore()

    #if canImport(Combine)
    public let objectWillChange = ObservableObjectPublisher()
    #endif

    /// How long a thread's awards stand before opening it asks again.
    public static let lifetime: TimeInterval = 600
    /// After a failed load, how long before the thread tries again.
    public static let failureBackoff: TimeInterval = 60
    /// Threads kept at once; the oldest give up their badges.
    public static let maxThreads = 8

    private struct ThreadState {
        var ids: Set<String> = []
        var loadedAt: Date?
        var failedAt: Date?
        var isLoading = false
    }

    private var badges: [String: AwardBadge] = [:]
    /// Things a fragment listed, with or without awards: a listed thing
    /// without a badge is known to have none, an unlisted one is unknown.
    private var listed: Set<String> = []
    private var threads: [String: ThreadState] = [:]
    private var order: [String] = []

    private init() {}

    private func changed() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }

    public func badge(for thingID: String) -> AwardBadge? { badges[thingID] }

    /// Whether to request `thread`'s awards now: not while a request is out,
    /// not within the lifetime of the last answer or the backoff after a
    /// failure, unless `force`. A true answer marks the thread as loading.
    public func beginLoad(thread: String, force: Bool = false, now: Date = Date()) -> Bool {
        var state = threads[thread] ?? ThreadState()
        guard !state.isLoading else { return false }
        if !force {
            if let loadedAt = state.loadedAt, now.timeIntervalSince(loadedAt) < Self.lifetime { return false }
            if let failedAt = state.failedAt, now.timeIntervalSince(failedAt) < Self.failureBackoff { return false }
        }
        state.isLoading = true
        threads[thread] = state
        order.removeAll { $0 == thread }
        order.append(thread)
        evictOldThreads()
        return true
    }

    /// The answer to a load `beginLoad` allowed. `replacing` swaps the
    /// thread's awards for `found`; otherwise `found` is added to them.
    public func finishLoad(thread: String, found: AwardHTML.Fragment, replacing: Bool, now: Date = Date()) {
        guard var state = threads[thread] else { return }
        if replacing { forget(state.ids); state.ids = [] }
        absorb(found, into: &state)
        state.isLoading = false
        state.loadedAt = now
        state.failedAt = nil
        threads[thread] = state
        changed()
    }

    /// A load that gave nothing usable. Rows keep what they had.
    public func failLoad(thread: String, now: Date = Date()) {
        guard var state = threads[thread] else { return }
        state.isLoading = false
        state.failedAt = now
        threads[thread] = state
    }

    /// Adds the awards of comments loaded later (a "more comments" stub).
    public func merge(_ found: AwardHTML.Fragment, thread: String) {
        guard !found.listed.isEmpty, var state = threads[thread] else { return }
        absorb(found, into: &state)
        threads[thread] = state
        changed()
    }

    private func absorb(_ found: AwardHTML.Fragment, into state: inout ThreadState) {
        for (id, badge) in found.badges { badges[id] = badge }
        for id in found.listed where found.badges[id] == nil { badges[id] = nil }
        listed.formUnion(found.listed)
        state.ids.formUnion(found.listed)
    }

    private func forget(_ ids: Set<String>) {
        for id in ids { badges[id] = nil }
        listed.subtract(ids)
    }

    /// The user gave `award`: a row Reddit's listing already counted shows it
    /// at once, without a refetch. A thing the listing never covered (a post,
    /// a comment past the first page) has no known count to add to, so it
    /// keeps showing nothing rather than a wrong total.
    public func recordGiven(_ award: AwardOrderResult, to thingID: String) {
        guard listed.contains(thingID) else { return }
        let current = badges[thingID]
            ?? AwardBadge(thingID: thingID, count: 0, awardID: nil, iconURL: nil, hasPaidAward: false)
        badges[thingID] = current.givingAward(award)
        changed()
    }

    private func evictOldThreads() {
        guard order.count > Self.maxThreads else { return }
        defer { changed() }
        while order.count > Self.maxThreads {
            let oldest = order.removeFirst()
            forget(threads[oldest]?.ids ?? [])
            threads[oldest] = nil
        }
    }
}
