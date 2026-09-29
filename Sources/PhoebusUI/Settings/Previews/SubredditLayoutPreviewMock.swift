import SwiftUI
import PhoebusCore

/// Live preview mock for the Subreddit Layout settings screen: a
/// deterministic, production-shaped mock of the subreddit header, fed
/// by a static fixture rather than the live subreddit cache.
///
/// Fixture: display name "ApolloReborn", 6,300 subscribers, subscribed,
/// about text "This subreddit is for the ongoing work for the CustomAPI
/// of the Apollo Reddit Client."
///
/// The banner is drawn rather than bundled: no redistribution rights to
/// Reborn's banner artwork, so a gradient stands in, which still
/// shows the Banner switch changing the layout.
struct SubredditLayoutPreviewMock: View {
    let settings: SubredditLayoutSettings

    /// Fixture render width: the iPhone 16 Pro width.
    private static let renderWidth: CGFloat = 393
    /// Measured banner band height. The card's top IS the banner's top.
    private static let bannerHeight: CGFloat = 88
    private static let iconSide: CGFloat = 80

    /// Avatar overlaps the banner's bottom edge by this much.
    private static let avatarBannerOverlap: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, proxy.size.width / Self.renderWidth)
            content
                .frame(width: Self.renderWidth)
                .scaleEffect(scale, anchor: .top)
                .frame(width: proxy.size.width,
                       height: contentHeight * scale, alignment: .top)
        }
        .frame(height: contentHeight * 0.85)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: settings)
    }

    /// Enough height for the tallest configuration; the card clips to
    /// whatever the current one uses.
    private var contentHeight: CGFloat {
        var height: CGFloat = 12
        if isNative { return 96 }
        if settings.subredditShowBanner { height += Self.bannerHeight }
        height += Self.iconSide
        if settings.subredditShowDisplayName { height += 36 }
        if settings.subredditShowSubtitle { height += 24 }
        if settings.subredditShowJoinButton
            || settings.subredditShowSidebarButton
            || settings.subredditShowUserFlairButton { height += 47 }
        if settings.subredditShowDescription { height += 48 }
        if settings.communityHighlights != .off { height += 56 }
        return height
    }

    /// Native = Apollo's original layout with no custom header
    /// installed; shows a frozen native snapshot instead.
    private var isNative: Bool { !settings.showSubredditHeaders }

    @ViewBuilder
    private var content: some View {
        if isNative {
            nativeSnapshot
        } else {
            customHeader
        }
    }

    /// Native preview: a search pill, the plain title and a hairline.
    private var nativeSnapshot: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                Text("Search r/ApolloReborn")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemFill)))
            Text("r/ApolloReborn")
                .font(.system(size: 17, weight: .semibold))
            Divider()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var customHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if settings.subredditShowBanner {
                    LinearGradient(
                        colors: [Color(red: 0.42, green: 0.25, blue: 0.72),
                                 Color(red: 0.87, green: 0.35, blue: 0.62)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: Self.renderWidth, height: Self.bannerHeight)
                }
                // Avatar overlaps the banner's bottom edge; 14pt floor
                // when there is no banner.
                icon
                    .padding(.top, settings.subredditShowBanner
                             ? Self.bannerHeight - Self.avatarBannerOverlap : 14)
            }

            if settings.subredditShowDisplayName {
                Text("ApolloReborn")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.top, 0)
            }
            if settings.subredditShowSubtitle {
                // 6300 subscribers through the app's abbreviator, then
                // lowercased to match Reddit's own "6.3k members" copy
                // (the shared abbreviator otherwise emits "6.3K").
                Text("\(6300.apolloAbbreviated.lowercased()) members")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }

            if settings.subredditShowUserFlairButton
                || settings.subredditShowJoinButton
                || settings.subredditShowSidebarButton {
                HStack(spacing: CGFloat(SubredditLayoutSettings.actionGap)) {
                    if settings.subredditShowUserFlairButton {
                        secondaryAction("tag")
                    }
                    if settings.subredditShowJoinButton {
                        // Fixture is subscribed, so the pill reads "Joined".
                        Text("Joined")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 124, height: 35)
                            .background(Capsule().fill(Color.apolloAccent))
                    }
                    if settings.subredditShowSidebarButton {
                        secondaryAction("rectangle.righthalf.inset.filled")
                    }
                }
                .padding(.top, 12)
            }

            if settings.subredditShowDescription {
                Text("This subreddit is for the ongoing work for the CustomAPI of the Apollo Reddit Client.")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    // Near-white, not secondary gray, to match the two
                    // description lines being brighter than the members line.
                    .foregroundStyle(Color(hex: ApolloSettingsRowMetrics.titleColorHexDark))
                    .lineLimit(SubredditLayoutSettings.aboutCollapsedLines)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            if settings.communityHighlights != .off {
                communityHighlights
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var icon: some View {
        ZStack {
            Circle().fill(Color(red: 0.42, green: 0.25, blue: 0.72))
            Text("A")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: Self.iconSide, height: Self.iconSide)
        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 4))
    }

    private func secondaryAction(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: CGFloat(SubredditLayoutSettings.secondaryActionSide),
                   height: CGFloat(SubredditLayoutSettings.secondaryActionSide))
            .background(Circle().fill(Color(.tertiarySystemFill)))
    }

    /// Highlights carousel: Partial shows a trimmed strip, Full the
    /// whole carousel.
    private var communityHighlights: some View {
        HStack(spacing: 8) {
            ForEach(0..<(settings.communityHighlights == .full ? 3 : 2), id: \.self) { index in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 104, height: 44)
                    .overlay(
                        Text("Highlight \(index + 1)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .padding(.top, 12)
    }
}
