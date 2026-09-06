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
    @State private var showingAbsolute = false

    public init(_ date: Date, showsIcon: Bool = false) {
        self.date = date
        self.showsIcon = showsIcon
    }

    @ViewBuilder
    private var content: some View {
        if showsIcon {
            // HStack, not `Label`: the icon-to-number gap is 4pt, which `Label`'s
            // own spacing does not honour.
            HStack(spacing: 4) {
                StockIcon("posts-clock")
                Text(date.apolloRelativeTime)
            }
        } else {
            Text(date.apolloRelativeTime)
        }
    }

    public var body: some View {
        content
            .onTapGesture { showingAbsolute = true }
            .alert("Created", isPresented: $showingAbsolute) {
                Button("OK") {}
            } message: {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            }
    }
}
