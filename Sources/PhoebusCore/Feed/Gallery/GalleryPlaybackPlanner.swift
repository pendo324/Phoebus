import Foundation

/// Which Gallery View tiles may play at once. Reborn lets at most 12 play, and
/// with sports clips playing a screen can hold more than that, so tiles at least
/// half on screen claim the slots first, then the slivers at the top and bottom
/// edges (`Apollo-Reborn#1389`): a strip peeking out under the navigation bar
/// must not take a slot from a whole tile further down.
public enum GalleryPlaybackPlanner {
    /// A tile that wants to play, with its vertical extent in the grid's own
    /// space (the viewport spans `viewportMinY...viewportMaxY`).
    public struct Candidate: Equatable, Sendable {
        public let id: String
        public let minY: Double
        public let maxY: Double

        public init(id: String, minY: Double, maxY: Double) {
            self.id = id
            self.minY = minY
            self.maxY = maxY
        }
    }

    /// Candidates on screen in claim order: mostly visible first, then slivers,
    /// each group keeping the order given (top to bottom). Off-screen tiles
    /// and tiles with no height are left out.
    public static func claimOrder(_ candidates: [Candidate], viewportMinY: Double, viewportMaxY: Double) -> [String] {
        var mostly: [String] = []
        var slivers: [String] = []
        for candidate in candidates {
            let height = candidate.maxY - candidate.minY
            guard height > 0 else { continue }
            let shown = min(candidate.maxY, viewportMaxY) - max(candidate.minY, viewportMinY)
            guard shown > 0 else { continue }
            if shown * 2 >= height { mostly.append(candidate.id) } else { slivers.append(candidate.id) }
        }
        return mostly + slivers
    }

    /// The tiles that play: the first `limit` of the claim order.
    public static func playing(_ candidates: [Candidate], viewportMinY: Double, viewportMaxY: Double,
                               limit: Int = GalleryAutoplaySettings.maxPlayingTiles) -> [String] {
        Array(claimOrder(candidates, viewportMinY: viewportMinY, viewportMaxY: viewportMaxY).prefix(max(0, limit)))
    }
}
