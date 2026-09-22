import SwiftUI
import PhoebusCore

/// Reborn's post-level vote-count estimate, shown on tap/long-press of a
/// post's score. Upvote and downvote counts are estimated from the public
/// `score` and `upvote_ratio` (see `VoteBreakdownCalculator`). Comment-level
/// insights need an authenticated scrape and are out of scope.
struct VoteBreakdownView: View {
    let score: Int
    let upvoteRatio: Double?

    private var displayedPercent: Int? {
        guard let upvoteRatio else { return nil }
        return Int((upvoteRatio * 100).rounded())
    }

    var body: some View {
        let percent = displayedPercent
        VStack(alignment: .leading, spacing: 8) {
            if let percent {
                Text("\(percent)% Upvoted")
                    .font(.headline)
            }
            if let breakdown = VoteBreakdownCalculator.breakdown(score: score, upvoteRatio: upvoteRatio) {
                Label("~\(breakdown.upvotes) upvotes", systemImage: "arrow.up")
                    .foregroundStyle(.orange)
                Label("~\(breakdown.downvotes) downvotes", systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                if let percent {
                    Text("~\(percent):\(100 - percent) upvote to downvote ratio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Counts are approximate because Reddit rounds the upvote percentage and fuzzes the displayed score.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if score <= 0 {
                // Distinct reason string for this case.
                Text("Upvote and downvote totals are not shown when the score is zero or negative because Reddit does not expose enough information to estimate them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Reason string for the sub-60% case.
                Text("Upvote and downvote totals are not shown below 60% because they become inaccurate as the upvote percentage approaches 50%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 200)
    }
}
