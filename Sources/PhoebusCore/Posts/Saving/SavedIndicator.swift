import Foundation

/// Geometry of Apollo's saved-post/comment corner indicator: a right
/// triangle filling one half of a square, with the right angle at the
/// **bottom-right** corner and the hypotenuse running from the top-right
/// down to the bottom-left. Apollo draws it from a flat template asset in
/// two sizes and tints it at draw time.
public enum SavedIndicator {
    /// Point size of `saved-triangle`, used on post cells.
    public static let regularSize: CGFloat = 24

    /// Point size of `saved-triangle-small`, used on the denser comment cells.
    public static let smallSize: CGFloat = 18

    /// Which of the two sizes a given cell uses.
    public enum Size: Sendable {
        /// `saved-triangle` (24pt).
        case regular
        /// `saved-triangle-small` (18pt).
        case small

        public var points: CGFloat {
            switch self {
            case .regular: return SavedIndicator.regularSize
            case .small: return SavedIndicator.smallSize
            }
        }

        /// The asset name this case corresponds to. Kept for traceability; the
        /// shape is drawn rather than shipping Apollo's artwork.
        public var assetName: String {
            switch self {
            case .regular: return "saved-triangle"
            case .small: return "saved-triangle-small"
            }
        }
    }

    /// The wedge's three corners within a `size`x`size` box, in UIKit/SwiftUI
    /// coordinates (origin top-left).
    ///
    /// Returned in drawing order starting at the right angle.
    public static func points(size: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: size, y: size),   // right angle: bottom-right
            CGPoint(x: size, y: 0),      // up the trailing edge
            CGPoint(x: 0, y: size)       // along the bottom edge
        ]
    }
}
