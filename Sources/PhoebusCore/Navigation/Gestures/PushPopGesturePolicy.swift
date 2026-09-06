import Foundation

/// Apollo's push/pop swipe gate.
///
/// Lives in PhoebusCore so the arithmetic is testable on the host;
/// PhoebusUI's `UIGestureRecognizerDelegate` is a thin shell over it.
public enum PushPopGesturePolicy {
    /// `pushPopGestureLeftInset`, the back-swipe zone from the leading edge.
    /// Wider than the trailing inset since back is the more common gesture.
    public static let leftInset: Double = 70

    /// `pushPopGestureRightInset`, the forward-swipe zone from the trailing edge.
    public static let rightInset: Double = 40

    /// Rows can scroll to the very bottom edge, so a touch there could be
    /// claimed by the row recognizer before iOS's bottom-edge system-gesture
    /// zone gets it.
    public static let bottomSystemGestureInset: Double = 24

    /// The shared `1.65 <= abs(vx/vy)` horizontal-dominance test used by
    /// both edges. A ratio of 1.0 would claim ordinary diagonal scrolls.
    public static let horizontalDominance: Double = 1.65

    /// Whether a drag is horizontal enough to count, per the shared ratio test.
    public static func isHorizontalEnough(velocityX: Double, velocityY: Double) -> Bool {
        guard velocityY != 0 else { return velocityX != 0 }
        return abs(velocityX / velocityY) >= horizontalDominance
    }

    /// Whether a row swipe should begin, given the drag so far.
    /// Requires enough travel, and either translation or velocity
    /// decisively horizontal.
    public static func rowSwipeShouldBegin(
        translationX: Double, translationY: Double,
        velocityX: Double, velocityY: Double,
        minimumDistance: Double
    ) -> Bool {
        guard abs(translationX) >= minimumDistance else { return false }
        let translationHorizontal = abs(translationX) > abs(translationY) * horizontalDominance
        return translationHorizontal || isHorizontalEnough(velocityX: velocityX, velocityY: velocityY)
    }

    /// Minimum horizontal travel before a row swipe begins, matching
    /// the system's own pan slop.
    public static let rowSwipeMinimumDistance: Double = 10

    /// Reads the saved "Disable Left/Right Swipes" gesture settings, which
    /// drop the inset test entirely in favor of swipe-anywhere.
    public static var backAnywhere: Bool { NavigationGestureSettingsStore.load().disableLeftSwipeGestureActions }
    public static var forwardAnywhere: Bool { NavigationGestureSettingsStore.load().disableRightSwipeGestureActions }

    public static func shouldBeginBack(velocityX: Double, velocityY: Double, locationX: Double) -> Bool {
        shouldBeginBack(velocityX: velocityX, velocityY: velocityY, locationX: locationX, anywhere: backAnywhere)
    }

    public static func shouldBeginBack(velocityX: Double, velocityY: Double, locationX: Double, anywhere: Bool) -> Bool {
        guard velocityX > 0, anywhere || locationX <= leftInset else { return false }
        return isHorizontalEnough(velocityX: velocityX, velocityY: velocityY)
    }

    public static func shouldBeginForward(
        velocityX: Double,
        velocityY: Double,
        locationX: Double,
        viewWidth: Double
    ) -> Bool {
        shouldBeginForward(velocityX: velocityX, velocityY: velocityY, locationX: locationX,
                           viewWidth: viewWidth, anywhere: forwardAnywhere)
    }

    public static func shouldBeginForward(
        velocityX: Double,
        velocityY: Double,
        locationX: Double,
        viewWidth: Double,
        anywhere: Bool
    ) -> Bool {
        guard velocityX < 0, anywhere || viewWidth - rightInset <= locationX else { return false }
        return isHorizontalEnough(velocityX: velocityX, velocityY: velocityY)
    }

    /// Whether a touch started inside iOS's own bottom system-gesture
    /// strip, left entirely to the system rather than a row swipe.
    public static func startedInBottomSystemGestureZone(
        startY: Double,
        viewHeight: Double
    ) -> Bool {
        viewHeight - bottomSystemGestureInset <= startY
    }

    // MARK: - Interactive transition

    /// The gesture completes if the drag passed the halfway point OR
    /// was flicked faster than 100pt/s, so a quick flick can navigate
    /// without dragging half the screen.
    public static let completionVelocity: Double = 100

    /// The halfway point, as a fraction of the view's width.
    public static let completionFraction: Double = 0.5

    /// `updateInteractiveTransition`'s argument: progress through the
    /// transition, clamped to 0...1.
    public static func transitionProgress(translationX: Double, viewWidth: Double) -> Double {
        guard viewWidth > 0 else { return 0 }
        return min(max(abs(translationX) / viewWidth, 0), 1)
    }

    /// Whether releasing here completes the navigation rather than
    /// springing back, per the velocity-or-distance test.
    public static func shouldComplete(
        translationX: Double,
        velocityX: Double,
        viewWidth: Double,
        isForward: Bool
    ) -> Bool {
        if isForward {
            if velocityX <= -completionVelocity { return true }
            return translationX <= viewWidth * -completionFraction
        } else {
            if velocityX >= completionVelocity { return true }
            return translationX >= viewWidth * completionFraction
        }
    }

    /// Whether a navigation gesture would claim this touch, so any
    /// competing row-level swipe must stand down. Directional: a
    /// leftward drag starting in the leading inset is not a back
    /// swipe, so the row swipe keeps it.
    public static func navigationClaimsTouch(
        startX: Double,
        velocityX: Double,
        velocityY: Double,
        viewWidth: Double
    ) -> Bool {
        if shouldBeginBack(velocityX: velocityX, velocityY: velocityY, locationX: startX) {
            return true
        }
        return shouldBeginForward(
            velocityX: velocityX,
            velocityY: velocityY,
            locationX: startX,
            viewWidth: viewWidth
        )
    }

    /// The row swipe's stand-down test, checked against both velocity
    /// and translation. Translation is checked too because the row
    /// samples raw touch points while the page swipe reads SwiftUI's
    /// smoothed velocity, so a slow edge drag could otherwise begin on
    /// the row a few samples before the page swipe claims it.
    public static func navigationClaimsRowTouch(
        startX: Double,
        translationX: Double, translationY: Double,
        velocityX: Double, velocityY: Double,
        viewWidth: Double,
        canGoBack: Bool,
        canGoForward: Bool
    ) -> Bool {
        func claims(_ x: Double, _ y: Double) -> Bool {
            if canGoBack, shouldBeginBack(velocityX: x, velocityY: y, locationX: startX) {
                return true
            }
            return canGoForward && shouldBeginForward(
                velocityX: x, velocityY: y, locationX: startX, viewWidth: viewWidth
            )
        }
        return claims(velocityX, velocityY) || claims(translationX, translationY)
    }

    // MARK: - Scroll exclusivity

    /// How far a drag may travel vertically before it counts as a
    /// scroll and can no longer become a horizontal gesture. Matches
    /// UIKit's own pan slop (~10pt).
    public static let scrollCommitDistance: Double = 10

    /// How far a scroll view's content must actually have followed the
    /// finger before a horizontal gesture treats the screen as
    /// scrolling. Smaller than `scrollCommitDistance` since this reads
    /// the scroll view's own pan, already past UIKit's slop.
    public static let scrollStartedDistance: Double = 4

    /// Whether a drag has become a vertical scroll: moved
    /// `scrollCommitDistance` vertically without being decisively
    /// horizontal by the shared ratio.
    public static func verticallyCommitted(translationX: Double, translationY: Double) -> Bool {
        guard abs(translationY) >= scrollCommitDistance else { return false }
        return abs(translationX) < abs(translationY) * horizontalDominance
    }
}
