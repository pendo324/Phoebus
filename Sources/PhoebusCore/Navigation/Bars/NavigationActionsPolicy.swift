import Foundation

/// Reborn's collapsible Liquid Glass navigation actions (#1035, #1047): a
/// screen with more than one action shows one "•••" pill that expands in
/// place and collapses on the first scroll, a back-swipe, or when the app
/// resigns active.
///
/// Every action is rendered as its own `ToolbarItem` here, so no pill is shown.
///
/// Constants:
///   - fewer than two actionable items stay inline.
///   - spring: mass 1, stiffness 644, damping ratio 0.78, duration 0.36.
public enum NavigationActionsPolicy {
    /// Expand/collapse duration.
    public static let animationDuration: TimeInterval = 0.36

    /// Spring mass.
    public static let springMass: Double = 1

    /// Spring stiffness.
    public static let springStiffness: Double = 644

    /// Damping ratio; the coefficient is `2 * ratio * sqrt(stiffness)` for unit mass.
    public static let springDampingRatio: Double = 0.78

    /// The damping coefficient.
    public static var springDamping: Double {
        2 * springDampingRatio * springStiffness.squareRoot()
    }

    /// Whether a screen's trailing actions should collapse into a single
    /// pill: fewer than two actionable items (not hidden, with an action or
    /// menu) stay inline.
    public static func shouldCollapse(actionableCount: Int) -> Bool {
        actionableCount >= 2
    }

    /// Why an expanded group re-collapsed.
    public enum CollapseReason: Sendable, Equatable {
        /// Any pan on a scroll view under this screen.
        case scrolled
        /// The interactive pop gesture began.
        case backGesture
        /// The app resigned active.
        case resignActive
        /// An action inside the expanded group was chosen.
        case actionTapped
    }

    /// Whether the collapse should animate. Scrolling animates; the back
    /// gesture and resigning active do not, so the spring never runs during
    /// an interactive transition or a snapshot.
    public static func animatesCollapse(for reason: CollapseReason) -> Bool {
        switch reason {
        case .scrolled, .actionTapped: return true
        case .backGesture, .resignActive: return false
        }
    }
}
