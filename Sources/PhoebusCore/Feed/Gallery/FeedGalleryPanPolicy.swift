import Foundation

/// Reborn "Swipe Past Gallery to Navigate" (#1271): who owns a horizontal
/// pan that starts on a feed gallery, decided once as it begins. The
/// carousel keeps pans that can page it; a clearly horizontal pull past its
/// first or last image, or one starting at a screen edge where navigation
/// can act, is yielded so the row's swipe actions or the page swipe follow
/// the finger.
public enum FeedGalleryPanPolicy {
    public enum Disposition: Equatable, Sendable {
        case consume
        case yield
    }

    /// Below this, or when not horizontal, the carousel keeps the pan:
    /// giving it away is permanent for the touch.
    public static let minimumVelocity: Double = 150
    /// ~24pt physical edge plus the ~10pt of pan hysteresis UIKit has already
    /// removed from the translation.
    public static let screenEdgeWidth: Double = 34

    public static func disposition(contentOffsetX: Double, maximumOffsetX: Double,
                                   velocityX: Double, velocityY: Double,
                                   touchX: Double, viewWidth: Double,
                                   rightToLeft: Bool = false,
                                   canGoBack: Bool, canGoForward: Bool) -> Disposition {
        if maximumOffsetX <= 0.5 || abs(velocityX) < minimumVelocity || abs(velocityX) <= abs(velocityY) {
            return .consume
        }
        let atFirstPage = contentOffsetX <= 0.5
        let atLastPage = contentOffsetX >= maximumOffsetX - 0.5
        if (atFirstPage && velocityX > 0) || (atLastPage && velocityX < 0) {
            return .yield
        }
        let fromLeftEdge = touchX <= screenEdgeWidth && velocityX > 0
        let fromRightEdge = viewWidth > 0 && touchX >= viewWidth - screenEdgeWidth && velocityX < 0
        let wantsBack = rightToLeft ? fromRightEdge : fromLeftEdge
        let wantsForward = rightToLeft ? fromLeftEdge : fromRightEdge
        return (wantsBack && canGoBack) || (wantsForward && canGoForward) ? .yield : .consume
    }
}
