import Foundation

/// The measuring half, kept separate so the arithmetic is testable
/// without a live `UINavigationBar`.
public enum NavigationBarGeometry {
    /// Horizontal padding of the title capsule.
    public static let capsuleHorizontalPadding: CGFloat = 14
    /// Spacing between title buttons.
    public static let titleButtonSpacing: CGFloat = 8

    /// Centring arithmetic, isolated from UIKit. Returns how far the title
    /// should move from the bar midpoint; `nil` means do not centre (either
    /// edge missing).
    public static func offset(
        barWidth: CGFloat,
        leadingSafeArea: CGFloat,
        leftLimit: CGFloat,
        rightLimit: CGFloat,
        hasTrailingActions: Bool
    ) -> CGFloat? {
        // Centre between actual controls, never an empty edge.
        guard hasTrailingActions else { return nil }
        guard leftLimit > leadingSafeArea + 0.5 else { return nil }
        guard rightLimit > leftLimit else { return nil }
        let center = (leftLimit + rightLimit) / 2
        return center - barWidth / 2
    }

    /// The maximum width the title may occupy once centred.
    public static func maximumContentWidth(
        leftLimit: CGFloat,
        rightLimit: CGFloat
    ) -> CGFloat {
        max(0, rightLimit - leftLimit - 2 * (capsuleHorizontalPadding + titleButtonSpacing))
    }

}
