import Foundation

/// Which side a row drag belongs to, whether that side is on, and which action
/// releasing the drag performs. Pure so it can be asserted without dragging a
/// real row; `ProgressiveSwipeRowModifier` asks it both while revealing and on
/// release, so a side that is turned off never reveals and never fires.
public enum SwipeRowPolicy {
    /// The slot side, not the finger's travel: Left is revealed by a rightward
    /// drag (leading actions), Right by a leftward one.
    public enum Side: Sendable, CaseIterable {
        case left
        case right

        public var title: String { self == .left ? "Left" : "Right" }
    }

    public static func side(forDrag translation: Double) -> Side? {
        translation > 0 ? .left : (translation < 0 ? .right : nil)
    }

    /// Whether a drag towards `side` reveals its actions. Disable Left/Right
    /// Swipes hands that drag to swipe-anywhere page navigation, and a side
    /// whose two slots are both None has nothing to reveal.
    public static func isActive(_ side: Side, settings: SwipeActionSettings, navigation: NavigationGestureSettings) -> Bool {
        switch side {
        case .left:
            return (settings.leftShort != .none || settings.leftLong != .none) && !navigation.disableLeftSwipeGestureActions
        case .right:
            return (settings.rightShort != .none || settings.rightLong != .none) && !navigation.disableRightSwipeGestureActions
        }
    }

    /// The action releasing a drag of `translation` points would perform, or nil
    /// when it performs nothing: short of the commit point, towards a side that
    /// is off, or onto a slot set to None.
    public static func action(forDrag translation: Double, settings: SwipeActionSettings,
                              navigation: NavigationGestureSettings,
                              width: Double = SwipeCommitPolicy.referenceWidth) -> SwipeAction? {
        guard let side = side(forDrag: translation),
              isActive(side, settings: settings, navigation: navigation),
              SwipeCommitPolicy.commits(distance: abs(translation), width: width) else { return nil }
        let long = SwipeCommitPolicy.isLong(distance: abs(translation),
                                            fraction: navigation.longSwipeTriggerPoint.fraction, width: width)
        let action: SwipeAction
        switch side {
        case .left: action = long ? settings.leftLong : settings.leftShort
        case .right: action = long ? settings.rightLong : settings.rightShort
        }
        return action == .none ? nil : action
    }
}
