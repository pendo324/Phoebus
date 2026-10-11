import SwiftUI
#if canImport(UIKit)
import UIKit

/// A screen's "I have unsaved changes" flag, found by the page swipes. Phoebus's
/// page swipe pops the navigation controller itself, so a SwiftUI dismiss
/// confirmation never sees it; a back swipe over a screen with one of these
/// dirty asks through `onAttempt` instead of popping.
final class UnsavedChangesProbe: UIView {
    var isDirty = false
    var onAttempt: () -> Void = {}
}

private struct UnsavedChangesAnchor: UIViewRepresentable {
    let isDirty: Bool
    let onAttempt: () -> Void

    func makeUIView(context: Context) -> UnsavedChangesProbe {
        let probe = UnsavedChangesProbe(frame: .zero)
        probe.isUserInteractionEnabled = false
        probe.isHidden = true
        return probe
    }

    func updateUIView(_ probe: UnsavedChangesProbe, context: Context) {
        probe.isDirty = isDirty
        probe.onAttempt = onAttempt
    }
}

extension UINavigationController {
    /// The dirty probe on the screen on top, if it has edits a pop would lose.
    func apolloUnsavedChangesProbe() -> UnsavedChangesProbe? {
        guard let root = topViewController?.view else { return nil }
        return UIKitTree.firstDescendant(of: UnsavedChangesProbe.self, in: root) { $0.isDirty }
    }
}

/// Reads `dismiss` here, in a leaf, rather than in the screen that uses the dialog.
private struct DiscardChangesDialog: ViewModifier {
    let isDirty: Bool
    let message: String
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .apolloConfirmsDiscard(isDirty: isDirty) { asking = true }
            .confirmationDialog("Discard Changes?", isPresented: $asking, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    onDiscard()
                    dismiss()
                }
                .accessibilityIdentifier("discardChanges.discard")
                Button("Keep Editing", role: .cancel) {}
                    .accessibilityIdentifier("discardChanges.keepEditing")
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// Marks this screen as holding unsaved changes while `isDirty`: a back page
    /// swipe (also the tab bar's) then calls `onAttempt`, which shows the
    /// screen's own discard confirmation, instead of popping. Forward swipes
    /// are unaffected.
    func apolloConfirmsDiscard(isDirty: Bool, onAttempt: @escaping () -> Void) -> some View {
        background(
            UnsavedChangesAnchor(isDirty: isDirty, onAttempt: onAttempt)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    /// The same, with the standard "Discard Changes?" dialog: Discard runs
    /// `onDiscard` and leaves the screen, Keep Editing stays.
    func apolloConfirmsDiscard(isDirty: Bool, message: String, onDiscard: @escaping () -> Void) -> some View {
        modifier(DiscardChangesDialog(isDirty: isDirty, message: message, onDiscard: onDiscard))
    }
}
#else
extension View {
    func apolloConfirmsDiscard(isDirty: Bool, onAttempt: @escaping () -> Void) -> some View { self }
    func apolloConfirmsDiscard(isDirty: Bool, message: String, onDiscard: @escaping () -> Void) -> some View { self }
}
#endif
