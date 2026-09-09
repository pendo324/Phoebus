import Foundation
#if canImport(Combine)
import Combine
#endif

/// Local vote and save state, keyed by fullname, shared by every view
/// that can change or display it.
///
/// Row state lives here rather than in per-row `@State`, so a vote made from a
/// swipe (handled by the parent), the buttons or the post screen updates
/// every view of it.
@MainActor
public final class VoteStateStore {
    public static let shared = VoteStateStore()

    /// Hand-rolled rather than `@Published`, so this type stays in
    /// PhoebusCore where its arithmetic can be smoke-tested on Linux, where
    /// Combine is unavailable.
    #if canImport(Combine)
    public let objectWillChange = ObservableObjectPublisher()
    #endif

    private func changed() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }

    /// `true` = upvoted, `false` = downvoted, `nil` = no vote.
    private var votes: [String: Bool?] = [:]
    /// Score offset relative to the server's value, so a row can show
    /// the user's own vote immediately without refetching.
    private var scoreDeltas: [String: Int] = [:]
    private var saved: [String: Bool] = [:]

    private init() {}

    // MARK: Vote

    /// The current vote, falling back to the server value when the user
    /// has not voted in this session.
    public func vote(for fullname: String, serverValue: Bool?) -> Bool? {
        if let local = votes[fullname] { return local }
        return serverValue
    }

    public func scoreDelta(for fullname: String) -> Int {
        scoreDeltas[fullname] ?? 0
    }

    /// Applies a vote locally and reports the score change, so the
    /// caller can roll it back if the network call fails.
    ///
    /// The deltas follow un-vote semantics: tapping an active
    /// direction clears the vote, and switching directly from one
    /// direction to the other moves the score by two.
    @discardableResult
    public func applyVote(fullname: String, direction: Int, serverValue: Bool?) -> Int {
        let previous = vote(for: fullname, serverValue: serverValue)
        let delta = Self.scoreDelta(from: previous, direction: direction)
        changed()
        votes[fullname] = direction == 1 ? true : (direction == -1 ? false : Bool?.none)
        scoreDeltas[fullname] = scoreDelta(for: fullname) + delta
        return delta
    }

    /// Undoes an `applyVote` whose network call failed.
    public func revertVote(fullname: String, to previous: Bool?, delta: Int) {
        changed()
        votes[fullname] = previous
        scoreDeltas[fullname] = scoreDelta(for: fullname) - delta
    }

    /// The score arithmetic, as a pure function so it can be asserted
    /// directly rather than only observed through a live network.
    public static func scoreDelta(from previous: Bool?, direction: Int) -> Int {
        switch (previous, direction) {
        case (true, 0): return -1
        case (false, 0): return 1
        case (nil, 1): return 1
        case (nil, -1): return -1
        case (false, 1): return 2
        case (true, -1): return -2
        // Re-applying the vote already held is a no-op, as is clearing
        // a vote that was never cast.
        default: return 0
        }
    }

    /// The direction a tap or swipe on `direction` should send, given
    /// what is currently held: pressing the active direction again
    /// un-votes.
    public static func toggledDirection(current: Bool?, tapped: Int) -> Int {
        if tapped == 1 { return current == true ? 0 : 1 }
        if tapped == -1 { return current == false ? 0 : -1 }
        return 0
    }

    // MARK: Save

    public func isSaved(_ fullname: String, serverValue: Bool) -> Bool {
        saved[fullname] ?? serverValue
    }

    public func setSaved(_ value: Bool, for fullname: String) {
        changed()
        saved[fullname] = value
    }

    /// Clears everything, for tests.
    public func reset() {
        changed()
        votes = [:]
        scoreDeltas = [:]
        saved = [:]
    }
}
