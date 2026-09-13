import Foundation

/// Decides which swipe action a completed drag performs.
///
/// Pure so the threshold ordering can be asserted without dragging a real
/// row. The long threshold must lie beyond the commit point, otherwise
/// every committing swipe fires the long action.
public enum SwipeCommitPolicy {
    /// Distance at which releasing performs the short action: 60pt.
    ///
    /// Measured from Apollo: the action icon reaches full opacity, stops
    /// riding the row's edge and pops at 60pt revealed width on both sides;
    /// the long action's colour replaces the short one's at 120pt.
    ///
    /// Fixed points rather than a fraction of the width: the parking point
    /// is twice the icon's 30pt edge inset, which does not scale with the screen.
    public static let shortThreshold: Double = 60

    /// Width does not matter; see `shortThreshold`.
    public static func commitThreshold(width: Double) -> Double { shortThreshold }

    /// Fallback width, used only when the caller has no real width.
    public static let referenceWidth: Double = 393

    /// The default-width convenience.
    public static var commitThreshold: Double { shortThreshold }

    /// Where the short action gives way to the long one.
    ///
    /// Always beyond `commitThreshold`. At the default ("Normal", 0.5) this
    /// is 120pt; Early/Late move it to 96/144pt.
    public static func longThreshold(fraction: Double, width: Double = referenceWidth) -> Double {
        let commit = commitThreshold(width: width)
        return commit + commit * 2 * fraction
    }

    /// Whether a drag of `distance` commits at all.
    public static func commits(distance: Double, width: Double = referenceWidth) -> Bool {
        distance >= commitThreshold(width: width)
    }

    /// Whether a committing drag performs the long action.
    public static func isLong(distance: Double, fraction: Double, width: Double = referenceWidth) -> Bool {
        distance >= longThreshold(fraction: fraction, width: width)
    }
}
