import Foundation

/// Reborn "Hide Bars on Scroll" navigation reveals (#1349): a push, pop or
/// stack replacement brings back a tab bar (and, with Hide Header on Scroll,
/// the header) that scrolling had hidden, with the same animation as a
/// scroll-up reveal. A bar a screen hides on purpose stays hidden.
public enum TabBarNavigationRevealPolicy {
    public struct Decision: Equatable, Sendable {
        /// Bring the scroll-hidden bars back and reset the scroll policy.
        public let reveal: Bool
        /// UIKit's own minimize (Left/Right) only expands by switching its
        /// behavior off, so it needs that nudge on top of `reveal`.
        public let expandNativeMinimize: Bool
    }

    /// Hide styles 0 (Left) and 1 (Right) use UIKit's own minimize; Fade
    /// (2) and Down (3) animate the bar themselves.
    public static func usesNativeMinimize(hideStyle: Int) -> Bool {
        hideStyle <= 1
    }

    /// - Parameters:
    ///   - barsHidden: scrolling currently has the bars hidden.
    ///   - tabBarHiddenByScreen: the tab bar is hidden for a pushed screen
    ///     (the `hidesBottomBarWhenPushed` case), not by scrolling.
    public static func decide(hideBarsOnScroll: Bool, hideStyle: Int, barsHidden: Bool,
                              tabBarHiddenByScreen: Bool) -> Decision {
        guard hideBarsOnScroll, barsHidden else {
            return Decision(reveal: false, expandNativeMinimize: false)
        }
        return Decision(reveal: true,
                        expandNativeMinimize: usesNativeMinimize(hideStyle: hideStyle) && !tabBarHiddenByScreen)
    }
}
