import SwiftUI

extension EdgeInsets {
    static var zero: EdgeInsets { EdgeInsets() }

    var negated: EdgeInsets {
        EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing)
    }
}

extension CGRect {
    func expanded(by insets: EdgeInsets) -> CGRect {
        guard !isNull else { return self }
        return CGRect(x: minX - insets.leading, y: minY - insets.top,
                      width: width + insets.leading + insets.trailing,
                      height: height + insets.top + insets.bottom)
    }
}

extension View {
    /// Grows the tap area by `insets`. Attach the gesture (or wrap in the
    /// Button or Menu) after this, then `.hitAreaLayout(insets)` so the
    /// layout doesn't move.
    func hitArea(_ insets: EdgeInsets) -> some View {
        padding(insets).contentShape(Rectangle())
    }

    /// Takes back the room `hitArea` added, so the control lays out at its
    /// drawn size.
    func hitAreaLayout(_ insets: EdgeInsets) -> some View {
        padding(insets.negated)
    }
}
