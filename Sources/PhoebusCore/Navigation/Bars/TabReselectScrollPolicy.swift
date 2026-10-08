import Foundation

/// What re-tapping a tab does to the visible screen. Reborn #1153 (scroll
/// to the top before going back a page) and "Fix Posts tab scroll-to-top and
/// preserve return position" (#1360): the jump to the top is the same one a
/// status-bar tap performs, so it saves the reading position, and a tap while
/// that jump is still running is ignored.
public enum TabReselectScrollPolicy {
    public enum Action: Equatable, Sendable {
        /// A jump to the top is already running: change nothing.
        case ignore
        /// Scroll to the top, saving the reading position.
        case scrollToTop
        /// Already at the top: go back one page.
        case popPage
        /// Already at the top of a root screen.
        case atRoot
    }

    /// Points of slack below the true top that still count as "at the top".
    public static let topTolerance: Double = 1

    /// `offsetY`/`topY` are the scroll view's content offset and its resting
    /// top offset (`-adjustedContentInset.top`); `offsetY` is nil when the
    /// screen has no scrollable list.
    public static func action(
        offsetY: Double?, topY: Double, jumpInFlight: Bool, canPop: Bool
    ) -> Action {
        // An intermediate frame of the jump may already be at the top; it
        // must not pop the page early or replace the saved spot.
        if jumpInFlight { return .ignore }
        if let offsetY, offsetY > topY + topTolerance { return .scrollToTop }
        return canPop ? .popPage : .atRoot
    }
}
