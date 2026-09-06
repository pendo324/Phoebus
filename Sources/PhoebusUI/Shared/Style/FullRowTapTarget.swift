import SwiftUI

/// Makes a `List` row's entire width tappable, not just its label.
///
/// Rows built as `Button { ... } label: { HStack { Text(...); Spacer();
/// ... } }` with `.buttonStyle(.plain)` only respond where the label
/// draws, since a `Spacer()` contributes no hit-testable content.
/// `.contentShape(Rectangle())` gives the row a full-bounds hit area; it
/// must be applied to the Button's label (inside the button) so the
/// shape defines what the button considers tappable.
public extension View {
    /// Apply to a Button's label content to make the whole row tappable.
    func apolloFullRowTapTarget() -> some View {
        contentShape(Rectangle())
    }
}
