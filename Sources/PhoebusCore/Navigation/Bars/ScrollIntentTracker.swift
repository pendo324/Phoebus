import Foundation

/// Tells a scroll the user did from a shift the list's own layout made, for
/// Hide Bars on Scroll. A lazy `List` re-estimates row heights as rows
/// realise, and a page loading swaps the footer row for new ones, so the
/// offset can jump against the finger by hundreds of points; read as a
/// direction change, that expanded a bar the user was collapsing.
///
/// While a finger is down its own travel is the direction. After it lifts the
/// content coasts one way, so only samples that keep going the same way count.
public struct ScrollIntentTracker: Sendable {
    public enum Direction: Equatable, Sendable {
        /// Content moves up the screen: the finger swept up.
        case down
        case up
    }

    /// Points of travel before a drag counts as a direction.
    public static let directionThreshold: Double = 12

    private var anchorOffset: Double
    private var anchorFinger: Double?
    private var intent: Direction?

    public init(offset: Double = 0) {
        anchorOffset = offset
    }

    /// A finger started dragging. Its travel is measured from the first sample
    /// after this: UIKit can still report the previous drag's position here.
    public mutating func begin(offset: Double) {
        anchorOffset = offset
        anchorFinger = nil
        intent = nil
    }

    /// A movement nobody dragged (scroll-to-top, jump-to-comment) or a rest.
    public mutating func rebase(offset: Double) {
        anchorOffset = offset
        anchorFinger = nil
        intent = nil
    }

    /// The direction the user scrolled, once they have gone far enough, else nil.
    /// `fingerY` is the finger's height on screen (growing as it moves down), nil
    /// when no finger is down (the content is coasting).
    public mutating func sample(offset: Double, fingerY: Double?) -> Direction? {
        if let fingerY {
            guard let anchor = anchorFinger else {
                anchorFinger = fingerY
                return nil
            }
            let travel = fingerY - anchor
            guard abs(travel) >= Self.directionThreshold else { return nil }
            anchorFinger = fingerY
            anchorOffset = offset
            intent = travel < 0 ? .down : .up
            return intent
        }
        anchorFinger = nil
        let delta = offset - anchorOffset
        guard abs(delta) >= Self.directionThreshold else { return nil }
        anchorOffset = offset
        let direction: Direction = delta > 0 ? .down : .up
        if let intent, intent != direction { return nil }
        intent = direction
        return direction
    }
}
