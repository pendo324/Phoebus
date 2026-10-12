import SwiftUI
import PhoebusCore

/// Apollo's edited indicator: a small pencil that names the edit time on
/// tap (see `EditedMarker`). Apollo's own `comment-edited` glyph isn't
/// bundled, so this draws the SF pencil at the byline's size.
struct EditedIndicator: View {
    let edited: RedditEditedTime
    /// Off when the caller attaches its own tap (the post info row's
    /// Popup / Overlay).
    var showsDetailOnTap = true
    /// How far the tap reaches past the glyph (see `hitArea`).
    var hitInsets: EdgeInsets = .zero
    @State private var showingDetail = false

    var body: some View {
        if showsDetailOnTap {
            glyph
                .hitArea(hitInsets)
                .onTapGesture { showingDetail = true }
                .hitAreaLayout(hitInsets)
                .alert(EditedMarker.lines(edited).title, isPresented: $showingDetail) {
                    Button("OK") {}
                } message: {
                    if let message = EditedMarker.lines(edited).message { Text(message) }
                }
                .accessibilityAddTraits(.isButton)
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Image(systemName: "pencil")
            .font(.system(size: 11, weight: .semibold))
            .accessibilityLabel(EditedMarker.lines(edited).title)
    }
}
