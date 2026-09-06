import SwiftUI
import PhoebusCore

/// Apollo's saved-item corner wedge.
///
/// See `SavedIndicator` for the shape's geometry; this draws the shape rather
/// than shipping artwork.
public struct SavedIndicatorShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Uses the smaller dimension so the wedge keeps its 45-degree hypotenuse
        // in a non-square rect.
        let size = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.maxX - size, y: rect.maxY - size)
        let points = SavedIndicator.points(size: size).map {
            CGPoint(x: origin.x + $0.x, y: origin.y + $0.y)
        }

        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// Drop-in corner badge marking a saved post or comment.
///
/// Tinted with the save color (`SwipeAction.save.tintColor`, green) rather
/// than flat black, matching the Save swipe action and bookmark button.
public struct SavedIndicatorBadge: View {
    private let size: SavedIndicator.Size

    public init(size: SavedIndicator.Size = .regular) {
        self.size = size
    }

    public var body: some View {
        SavedIndicatorShape()
            .fill(Color.green)
            .frame(width: size.points, height: size.points)
            .allowsHitTesting(false)
            .accessibilityLabel("Saved")
    }
}
