import SwiftUI
import PhoebusCore

/// The subreddit header above the feed.
extension FeedScreen {
    /// Reborn "Subreddit Layout" header band at the top of a subreddit's
    /// feed. New/Immersive gets a taller banner with the join button
    /// overlaid; Classic/Compact is a flat, low-profile row. Both
    /// densities honor the same three band toggles.
    /// The community's title and member count joined with "  ·  ", either
    /// alone when the other is missing. Returns nil when neither exists.
    func headerSubtitle(_ info: RedditSubreddit) -> String? {
        // Apollo suppresses a title identical to the subreddit name -
        // it would just repeat the row above.
        let title = info.title.caseInsensitiveCompare(info.displayName) == .orderedSame ? "" : info.title
        let members = info.subscribers.map(\.apolloMemberCount)
        switch (title.isEmpty, members) {
        case (false, .some(let m)): return "\(title)  ·  \(m)"
        case (false, .none): return title
        case (true, .some(let m)): return m
        case (true, .none): return nil
        }
    }

    /// The header's name: the nav title's casing (Apollo's capitalization
    /// table) when it names the same subreddit, else Reddit's own
    /// `display_name`.
    func headerDisplayName(_ info: RedditSubreddit) -> String {
        let navigationName = SubredditCapitalization.display(subreddit)
        return navigationName.caseInsensitiveCompare(info.displayName) == .orderedSame
            ? navigationName : SubredditCapitalization.display(info.displayName)
    }

    func subredditLayoutHeader(_ info: RedditSubreddit) -> some View {
        let immersive = subredditLayoutSettings.subredditHeaderImmersive
        // Whether a banner will actually render, distinct from whether the
        // user enabled banners: Reddit returns `banner_background_image: ""`
        // for none, and `URL(string: "")` is nil. The `.padding(.top, -20)`
        // pull-up below must use the same expression.
        let officialBannerURL = info.headerBannerURL
        // Only where members may set their own flair (`can_assign_user_flair`).
        let showsFlairButton = subredditLayoutSettings.subredditShowUserFlairButton && info.canAssignUserFlair == true
        let showsActions = showsFlairButton
            || subredditLayoutSettings.subredditShowSidebarButton
            || subredditLayoutSettings.subredditShowJoinButton
        // A custom banner (Reborn #266) counts as a banner too.
        let customBanner = SubredditCustomArtStore.shared.image(for: subreddit, kind: .banner)
        let bannerURL: URL? = subredditLayoutSettings.subredditShowBanner ? officialBannerURL : nil
        let hasBanner = subredditLayoutSettings.subredditShowBanner && (bannerURL != nil || customBanner != nil)
        // The subreddit banner is 104pt, shorter than the profile's 150pt.
        // Immersive keeps the profile height.
        let bannerHeight: CGFloat = !hasBanner
            ? 0
            : CGFloat(immersive
                ? IdentityHeaderLayout.profileBannerHeight
                : IdentityHeaderLayout.subredditBannerHeight)
        // Centred, with the avatar straddling the banner's bottom
        // edge. Shared with the profile header; see
        // `IdentityHeaderLayout` for the ported constants.
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // The banner band. Zero height when there is none, so
                // the avatar's own 14pt floor takes over.
                if hasBanner {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: bannerHeight)
                        .background {
                            if let customBanner {
                                Image(uiImage: customBanner).resizable().scaledToFill()
                            } else if let bannerURL {
                                CachedAsyncImage(url: bannerURL, contentMode: .fill)
                            }
                        }
                        .clipped()
                        // Reborn #266: tap views, long-press offers
                        // Choose Photo / Remove Custom Banner.
                        .subredditArtOptions(subreddit, kind: .banner, viewURL: officialBannerURL)
                } else {
                    Color.clear.frame(height: 0)
                }

                // The avatar, centred, pulled up so it overlaps the
                // banner by `avatarOverlap`.
                SubredditIconView(
                    subreddit: subreddit,
                    repository: repository,
                    size: CGFloat(IdentityHeaderLayout.avatarDiameter)
                )
                .subredditArtOptions(subreddit, kind: .icon,
                                     viewURL: (info.communityIcon?.isEmpty == false ? info.communityIcon : info.iconImage)
                                        .flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) })
                .padding(.top, CGFloat(IdentityHeaderLayout.avatarTop(bannerHeight: Double(bannerHeight))))
            }
            // No extra bottom padding here: a ZStack sizes to the
            // union of its children, and the avatar already reports
            // `avatarTop + 96`, so adding the overhang again doubles it.

            if subredditLayoutSettings.subredditShowDisplayName {
                // The display name, not "r/name". 28pt bold.
                Text(headerDisplayName(info))
                    .font(.system(size: CGFloat(IdentityHeaderLayout.nameFontSize), weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
            if subredditLayoutSettings.subredditShowSubtitle, let subtitle = headerSubtitle(info) {
                // 15pt medium, not `.caption`.
                Text(subtitle)
                    .font(.system(size: CGFloat(IdentityHeaderLayout.subnameFontSize), weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .padding(.top, 1)
            }


            // Action cluster below the name/subtitle stack: Flair, Join and
            // Sidebar, centered in that order. Flair and Sidebar default off,
            // independent of Join, and are same-size icon-only squares.
            if showsActions {
                HStack(spacing: SubredditLayoutSettings.actionGap) {
                    Spacer(minLength: 0)
                    if showsFlairButton {
                        SubredditSecondaryActionButton(
                            systemImage: "tag",
                            accessibilityLabel: "Set User Flair"
                        ) { showingUserFlair = true }
                        .accessibilityIdentifier("feed.subredditLayoutHeader.userFlairButton")
                    }
                    if subredditLayoutSettings.subredditShowJoinButton {
                        Button {
                            Task { await toggleHeaderSubscribe() }
                        } label: {
                            // An accent pill whether joined or not, like
                            // the profile's Follow pill: 16.5pt semibold,
                            // 42pt tall, at least 148pt wide with 26pt
                            // either side of the title. Glass tints the
                            // accent at 0.62, the solid fill is 0.92.
                            Text(currentlySubscribedToHeaderSubreddit() ? "Joined" : "Join")
                                .font(.system(size: 16.5, weight: .semibold))
                                .foregroundStyle(headerJoinTextColor)
                                .padding(.horizontal, 26)
                                .frame(minWidth: 148)
                                .frame(height: 42)
                                .background(Capsule().fill(Color.apolloAccent.opacity(LiquidGlass.isEnabled ? 0.62 : 0.92)))
                                .overlay {
                                    if LiquidGlass.isEnabled {
                                        Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("feed.subredditLayoutHeader.joinButton")
                    }
                    if subredditLayoutSettings.subredditShowSidebarButton {
                        SubredditSecondaryActionButton(
                            // Fallback symbol when the bundled
                            // "option-sidebar" art is absent.
                            systemImage: "rectangle.righthalf.inset.filled",
                            accessibilityLabel: "Open Sidebar"
                        ) { showingSidebarSheet = true }
                        .accessibilityIdentifier("feed.subredditLayoutHeader.sidebarButton")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                // 10pt under the name stack, 16pt above the body.
                .padding(.top, 10)
                .padding(.bottom, SubredditLayoutSettings.actionBottomGap)
            }

            // Reborn "Description" band (`SubredditShowDescription`, default on):
            // the sidebar blurb, centred, collapsed to 3 lines with an accent
            // "more"/"less" toggle when it doesn't fit.
            if subredditLayoutSettings.subredditShowDescription,
               let description = info.publicDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                HeaderAboutText(text: description, expanded: $headerDescriptionExpanded)
                    .frame(maxWidth: CGFloat(IdentityHeaderLayout.bodyMaxWidth))
                    .padding(.horizontal, CGFloat(IdentityHeaderLayout.sideInset))
                    .padding(.top, showsActions ? 0 : 10)
                    .accessibilityIdentifier("feed.subredditLayoutHeader.description")
            }
        }
        .padding(.bottom, CGFloat(IdentityHeaderLayout.bottomPadding))
        // Zero insets so a banner can run edge-to-edge and full-bleed.
        // Pin the whole header to the row's width. Without this the
        // banner's natural wide size sets the VStack's ideal width,
        // pushing every sibling off the left edge.
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        // The feed's own surface shows through, as it does under the
        // posts; the List's default row fill is a different black.
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("feed.subredditLayoutHeader")
    }

    /// Black or white on the accent pill, by the accent's luminance.
    var headerJoinTextColor: Color {
        let hex = ThemeStore.load().accentColorHex
        guard HexContrast.needsDarkText(onHex: hex) else { return .white }
        let rgb = HexContrast.darkTextRGB
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// The header's about text: collapsed to three lines with a "more"
/// toggle only when it actually overflows.
private struct HeaderAboutText: View {
    let text: String
    @Binding var expanded: Bool
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var truncates: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        VStack(spacing: 0) {
            styled(Text(text))
                .lineLimit(expanded ? nil : SubredditLayoutSettings.aboutCollapsedLines)
                .frame(maxWidth: .infinity)
                .background(heightReader { shownHeight = $0 })
                // The uncollapsed text at the same width, unseen, to
                // tell whether the collapsed one is cut off.
                .background(
                    styled(Text(text))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .background(heightReader { fullHeight = $0 })
                        .hidden())
            if truncates || expanded {
                Text(expanded ? "less" : "more")
                    .font(.footnote)
                    .foregroundStyle(Color.apolloAccent)
                    .frame(height: 22)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard truncates || expanded else { return }
            expanded.toggle()
        }
    }

    private func styled(_ text: Text) -> some View {
        text.font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
    }

    private func heightReader(_ update: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { update(proxy.size.height) }
                .onChange(of: proxy.size.height) { _, height in update(height) }
        }
    }
}
