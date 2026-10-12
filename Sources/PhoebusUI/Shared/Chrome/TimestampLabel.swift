import SwiftUI
import PhoebusCore

/// Reborn "Tap timestamp for creation date": a relative-time label ("2h",
/// "3d") that shows the absolute creation date and time in an alert on tap.
///
/// Uses Apollo's compact single-unit format rather than
/// `Text(date, style: .relative)`, whose long multi-unit strings wrap and
/// break feed row layouts.
public struct TimestampLabel: View {
    let date: Date
    /// Whether to draw the real clock glyph before the age.
    /// Whether to draw the clock glyph before the age. The feed info row
    /// shows one; other callers (comment byline, chat) show the age bare.
    let showsIcon: Bool
    /// Replaces the relative age (the comment byline's `CommentAgeMode`);
    /// the tap still shows `date`.
    let text: String?
    /// Adds "Edited <time>" under the creation time (Show Edited Marker).
    let edited: RedditEditedTime?
    /// How far the tap reaches past the label (see `hitArea`).
    let hitInsets: EdgeInsets
    @State private var showingAbsolute = false

    public init(_ date: Date, showsIcon: Bool = false, text: String? = nil, edited: RedditEditedTime? = nil,
                hitInsets: EdgeInsets = EdgeInsets()) {
        self.date = date
        self.showsIcon = showsIcon
        self.text = text
        self.edited = edited
        self.hitInsets = hitInsets
    }

    @ViewBuilder
    private var content: some View {
        if showsIcon {
            // HStack, not `Label`: the icon-to-number gap is 4pt, which `Label`'s
            // own spacing does not honour.
            HStack(spacing: 4) {
                StockIcon("posts-clock")
                Text(text ?? date.apolloRelativeTime)
            }
        } else {
            Text(text ?? date.apolloRelativeTime)
        }
    }

    public var body: some View {
        content
            .hitArea(hitInsets)
            .onTapGesture { showingAbsolute = true }
            .hitAreaLayout(hitInsets)
            .alert("Created", isPresented: $showingAbsolute) {
                Button("OK") {}
            } message: {
                Text(EditedMarker.appendingTimestamp(edited, to: date.formatted(date: .abbreviated, time: .shortened)) ?? "")
            }
    }
}
