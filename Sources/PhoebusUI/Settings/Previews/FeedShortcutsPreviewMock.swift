import SwiftUI
import PhoebusCore

/// Live preview mock for the Feed Shortcuts settings screen.
///
/// Reborn's feed shortcuts preview: the card shows the four feed
/// shortcuts as the Subreddits root will draw them, reacting live to
/// which shortcuts are visible (`visibleIndexes`), the Icon Style
/// (`iconStyle`), the Feed Layout (`layout`) and "Hide Feed
/// Descriptions" (`hideDescriptions`).
///
/// The "Popular Posts" detail is "Most popular across Reddit", the
/// wording the Subreddits root ships (`SubredditsRootScreen
/// .feedShortcutRows`); the preview reuses the root's strings so the
/// two cannot disagree.
///
/// Geometry matches the Subreddits root's `iconRow`: a 31.3pt icon
/// badge, title starting at the icon's trailing edge plus 32pt, rows on
/// a 60pt pitch (an 8pt gap between 52pt row items), inside a card with
/// 16pt padding and 8pt stack insets top and bottom.
struct FeedShortcutsPreviewMock: View {
    let settings: GeneralSettings

    /// Row metrics, shared with the Subreddits root.
    private static let iconSide: CGFloat = 31.3
    private static let iconToTitle: CGFloat = 32
    private static let rowPitch: CGFloat = 60

    /// One shortcut: row title, detail, glyph and tint.
    struct Item: Identifiable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
        let color: Color
        /// Short title used by the non-row layouts.
        let shortTitle: String
    }

    /// Home is always present, the other three follow their hide-keys.
    var items: [Item] {
        var result: [Item] = [
            Item(id: "home", title: "Home", detail: "Posts from subscriptions",
                 systemImage: "house.fill",
                 color: Color(red: 0.93, green: 0.16, blue: 0.4), shortTitle: "Home")
        ]
        if !settings.hidePopularInSubredditList {
            result.append(Item(id: "popular", title: "Popular Posts",
                               detail: "Most popular posts across Reddit",
                               systemImage: "chart.line.uptrend.xyaxis",
                               color: .blue, shortTitle: "Popular"))
        }
        if !settings.hideAllInSubredditList {
            result.append(Item(id: "all", title: "All Posts",
                               detail: "Posts across all subreddits",
                               systemImage: "tray.and.arrow.up.fill",
                               color: .green, shortTitle: "All"))
        }
        if !settings.hideModeratorInSubredditList {
            result.append(Item(id: "moderator", title: "Moderator Posts",
                               detail: "Posts from moderated subreddits",
                               systemImage: "star.fill",
                               color: .gray, shortTitle: "Moderator"))
        }
        return result
    }

    var body: some View {
        Group {
            switch settings.subredditFeedLayout {
            case .rows:
                rows
            case .sideBySide, .grid, .iconDock:
                strip
            }
        }
        // Card padding: 8pt of stack inset top and bottom.
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.25), value: items.map(\.id))
        .animation(.easeInOut(duration: 0.25), value: settings.subredditFeedIconStyle)
        .animation(.easeInOut(duration: 0.25), value: settings.subredditFeedLayout)
    }

    /// Rows layout, at the root's own metrics: a 31.3pt icon,
    /// 32pt to the title, 17pt title over a 13pt tertiary detail, on
    /// a 60pt pitch.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: Self.iconToTitle) {
                    FeedShortcutIconBadge(systemImage: item.systemImage,
                                          color: item.color,
                                          style: settings.subredditFeedIconStyle)
                        .frame(width: Self.iconSide, height: Self.iconSide)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 17))
                        if !settings.hideFeedDescriptions {
                            Text(item.detail)
                                .font(.system(size: 13))
                                // The root's tertiary #61626A, not
                                // `.secondary`.
                                .foregroundStyle(Color(hex: ApolloSettingsRowMetrics.detailColorHex))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: Self.rowPitch)
                .id(item.id)
            }
        }
    }

    /// Non-row layouts are one equal-width horizontal stack with separators
    /// between items. Icon Dock drops the titles and takes the wider 28pt
    /// horizontal inset rather than 14pt.
    private var strip: some View {
        let isDock = settings.subredditFeedLayout == .iconDock
        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 4) {
                    FeedShortcutIconBadge(systemImage: item.systemImage,
                                          color: item.color,
                                          style: settings.subredditFeedIconStyle)
                        .frame(width: 34, height: 34)
                    if !isDock {
                        Text(item.shortTitle)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .id(item.id)
                if index < items.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, isDock ? 28 : 14)
    }
}

/// The Subreddits root's shortcut icon badge, shared so the settings
/// preview draws the same view as the real list.
///
/// Icon styles: Classic (filled circle), Circle (outlined ring), Tinted
/// (bare glyph), SoftTile / SolidTile (rounded square).
struct FeedShortcutIconBadge: View {
    let systemImage: String
    let color: Color
    let style: FeedIconStyle

    var body: some View {
        switch style {
        case .classic:
            ZStack {
                Circle().fill(color)
                glyph(size: 14, color: .white)
            }
        case .circle:
            ZStack {
                Circle().stroke(color, lineWidth: 2)
                glyph(size: 14, color: color)
            }
        case .tinted:
            glyph(size: 18, color: color)
        case .softTile:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.18))
                glyph(size: 14, color: color)
            }
        case .solidTile:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(color)
                glyph(size: 14, color: .white)
            }
        }
    }

    private func glyph(size: CGFloat, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }
}
