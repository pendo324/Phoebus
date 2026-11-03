import Foundation

/// Reborn's Community Highlights Back/Forward swipe (#1577): who owns a
/// horizontal pan that starts on the carousel. With the first card in view a
/// Back swipe has nothing left to reveal and would only rubber-band, so the
/// page swipe takes it; the same for a Forward swipe at the last card. Anywhere
/// in between the carousel scrolls, so one swipe brings it back to the first
/// card and the next goes Back.
public enum CommunityHighlightsPanPolicy {
    /// Whether the carousel should refuse this pan so the page swipe follows the
    /// finger. `edgeSlack` is the carousel's side padding: an end counts once
    /// its card is fully in view, and a free scroll often rests a few points
    /// short of the limit.
    public static func yieldsToNavigation(
        contentOffsetX: Double, maximumOffsetX: Double, edgeSlack: Double,
        velocityX: Double, velocityY: Double,
        touchX: Double, viewWidth: Double,
        navigationEnabled: Bool, backAnywhere: Bool, forwardAnywhere: Bool,
        canGoBack: Bool, canGoForward: Bool
    ) -> Bool {
        guard navigationEnabled else { return false }
        let atStart = contentOffsetX <= edgeSlack + 0.5
        let atEnd = contentOffsetX >= max(0, maximumOffsetX) - edgeSlack - 0.5
        if atStart, canGoBack,
           PushPopGesturePolicy.shouldBeginBack(velocityX: velocityX, velocityY: velocityY,
                                                locationX: touchX, anywhere: backAnywhere) {
            return true
        }
        return atEnd && canGoForward
            && PushPopGesturePolicy.shouldBeginForward(velocityX: velocityX, velocityY: velocityY,
                                                       locationX: touchX, viewWidth: viewWidth,
                                                       anywhere: forwardAnywhere)
    }
}
