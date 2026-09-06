import SwiftUI
import PhoebusCore

/// Apollo's Subreddits-list section header: a tinted uppercase label
/// followed by a rule that fades out to the right.
///
/// - label in the accent blue, 19pt from the leading edge, caption size
/// - 2pt rule fading from solid to transparent, left to right
///
/// SwiftUI's stock `Section` header is grey, sentence case and has no
/// rule, so it cannot be restyled into this.
public struct ApolloSubredditSectionHeader: View {
    @Setting(SubredditSectionsSettings.self) private var subredditSectionsSettings
    let title: String
    /// Reborn's "Subreddit List Enhancements" + "Modern Subreddit
    /// Dividers" (`SubredditSectionsSettings.usesModernDividers`). Reborn
    /// only styles the header when both are on; otherwise the list keeps
    /// stock Apollo's plain grey section band.
    private var modern: Bool { subredditSectionsSettings.usesModernDividers }

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        if modern { modernBody } else { classicBody }
    }

    /// Stock Apollo's section band: a secondary-coloured title on a
    /// faint fill.
    private var classicBody: some View {
        HStack(spacing: 0) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 19)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .textCase(nil)
        .listRowInsets(EdgeInsets())
        .accessibilityIdentifier("subreddits.sectionHeader.\(title)")
    }

    private var modernBody: some View {
        HStack(spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            // Fades to clear; the right end blends into the list background.
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 2)
        }
        .padding(.leading, 19)
        // The rule runs under the index letters, stopping 3pt short of the
        // edge. The header zeroes its row insets, so it does not inherit the
        // list's trailing safe-area padding and spans the full width itself.
        .padding(.trailing, 3)
        .padding(.vertical, 6)
        // Opaque, so a pinned header covers the rows scrolling under it.
        .background(Color(uiColor: RowHighlight.surface))
        .textCase(nil)  // SwiftUI upper-cases headers itself; the label already is.
        .listRowInsets(EdgeInsets())
        .accessibilityIdentifier("subreddits.sectionHeader.\(title)")
    }
}
