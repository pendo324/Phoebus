import SwiftUI
import PhoebusCore

/// Apollo's end-of-feed cell.
///
/// See `ReachedEndCopy` for the strings and the visit-count selection rule.
/// This renders the message only; Apollo's dino artwork is not included.
public struct ReachedEndView: View {
    /// Apollo's own belief that there is nothing further to load for
    /// this listing, rather than merely the end of the current page.
    private let likelyReachedEndOfLoadablePosts: Bool

    /// Resolved once, at appear, so scrolling past the row does not
    /// keep re-rolling the beast's line or re-counting the visit.
    @State private var message: String = ""

    public init(likelyReachedEndOfLoadablePosts: Bool) {
        self.likelyReachedEndOfLoadablePosts = likelyReachedEndOfLoadablePosts
    }

    public var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        // Apollo's accessibility label/hint, verbatim.
        .accessibilityLabel(ReachedEndCopy.accessibilityLabel)
        .accessibilityHint(ReachedEndCopy.accessibilityHint)
        .accessibilityIdentifier("feed.reachedEnd")
        .onAppear {
            guard message.isEmpty else { return }
            // The counter increments as the cell is built and the beast's line is
            // chosen from the incremented value, so the first time the end is reached
            // the count reads 1 and the "great to meet another soul" line plays.
            let visitCount = ReachedEndVisitCounter.recordVisit()
            message = ReachedEndCopy.message(
                likelyReachedEndOfLoadablePosts: likelyReachedEndOfLoadablePosts,
                visitCount: visitCount
            )
        }
    }
}

/// Persists the real `EndsOfRedditsReached3` visit counter.
public enum ReachedEndVisitCounter {
    /// Increments and returns the new count, matching the real cell's
    /// own read-then-write-plus-one in its initializer.
    @discardableResult
    public static func recordVisit(defaults: UserDefaults = .standard) -> Int {
        let next = defaults.integer(forKey: ReachedEndCopy.visitCountKey) + 1
        defaults.set(next, forKey: ReachedEndCopy.visitCountKey)
        return next
    }

    public static func currentCount(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: ReachedEndCopy.visitCountKey)
    }
}
