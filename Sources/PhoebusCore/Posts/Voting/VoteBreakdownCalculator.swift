import Foundation

/// A client-side vote-count *estimate*, following Apollo-Reborn's vote-insight feature.
///
/// The formula:
/// ```
/// upvotes   = P * score / (2P - 1)
/// downvotes = upvotes - score
/// ```
/// where `P` is the *displayed* (already-rounded) upvote percentage as a
/// 0-1 proportion. Constraints:
/// - `displayedPercent` (0-100 scale) must be between 60 and 100 inclusive.
///   The cutoff is not symmetric around 50%: a comment at 20% upvoted never
///   gets an estimate.
/// - `score` must be strictly positive; otherwise the reason shown is
///   "Upvote and downvote totals are not shown when the score is zero or
///   negative...".
/// - The denominator `2P - 1` is then positive (`P >= 0.6` implies
///   `2P - 1 >= 0.2 > 0`).
///
/// Reborn's comment estimate additionally uses an authenticated
/// Comment-Insights scrape for an upvote count. This type covers the
/// post-level, public-API-only computation.
public enum VoteBreakdownCalculator {
    public struct Breakdown: Sendable, Equatable {
        public let upvotes: Int
        public let downvotes: Int
    }

    /// Cutoff: `displayedPercent < 60 || displayedPercent > 100 || score <= 0`
    /// rejects the estimate. Expressed as a 0-1 proportion to match `upvoteRatio`.
    private static let minimumReliableRatio = 0.6

    /// Returns `nil` when `upvoteRatio` is unavailable, below the 60%
    /// reliability cutoff, or `score` isn't strictly positive.
    public static func breakdown(score: Int, upvoteRatio: Double?) -> Breakdown? {
        guard let upvoteRatio, upvoteRatio <= 1 else { return nil }
        guard upvoteRatio >= minimumReliableRatio else { return nil }
        guard score > 0 else { return nil }
        let denominator = 2 * upvoteRatio - 1
        guard denominator > 0 else { return nil }
        let upvotesDouble = Double(score) * upvoteRatio / denominator
        let upvotes = Int(upvotesDouble.rounded())
        let downvotes = upvotes - score
        guard upvotes >= 0, downvotes >= 0 else { return nil }
        return Breakdown(upvotes: upvotes, downvotes: downvotes)
    }
}
