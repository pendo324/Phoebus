import SwiftUI
import PhoebusCore

/// The large-card layout of `PostRow`.
extension PostRow {
    /// Apollo's "Large Thumbnails" row style: title alone at top
    /// (regular weight), then a full-bleed image with no rounded
    /// corners and no horizontal padding (spanning the row's entire
    /// width, edge to edge), then a two-line footer: subreddit name
    /// alone on its own line (no "by author"), then
    /// "↑score 💬count 🕐time" on the left of the SAME row as
    /// "••• ↑ ↓" on the right. Vote arrows are inline in this meta
    /// row, not a separate stacked column.
    var largeThumbnailBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if post.stickied {
                Label("Stickied Post", systemImage: "pin.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal)
            }

            // Same subreddit-header row as the compact body.
            if showsSubredditHeader {
                HStack(spacing: 6) {
                    if showsSubredditIcon {
                        // 20pt here, not the compact row's 16pt.
                        SubredditIconView(subreddit: post.subreddit, repository: repository, size: 20)
                    }
                    Text(SubredditCapitalization.display(post.subreddit))
                        .apolloFont(size: 14, weight: .medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded(onSubredditTap))
                        .accessibilityIdentifier("feed.postRow.large.subredditHeader")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .accessibilityHidden(true)
            }

            TitleFlairLayout(titleString: titleString,
                             fontSize: ScaledSystemFont.scaled(17, style: .body, for: dynamicTypeSize),
                             bold: appearanceSettings.boldPostTitles, gap: 6, lineSpacing: 3) {
                Text(titleString)
                    // "Bold Post Titles" applies to the large row's title too.
                    .font(.system(size: ScaledSystemFont.scaled(17, style: .body, for: dynamicTypeSize),
                                  weight: appearanceSettings.boldPostTitles ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if post.over18 { NSFWTag() }
            }
                .tagFilterCover(.title, isNSFW: post.over18, isActive: coversTitle) { revealTagPart(.title) }
                .padding(.horizontal)
                // VoiceOver: the large row can't be merged whole
                // (video/gallery/link card is separately operable), so
                // the title carries the full spoken summary and the
                // subreddit header/info row below are hidden as
                // duplicates.
                .accessibilityLabel(accessibilitySummary)
                .accessibilityAddTraits(.isButton)
            // "Swipe Through Feed Galleries" (`UDKeyFeedGalleryCarousel`): when on and
            // this post is a multi-image gallery, page through its images in the feed
            // row. "Swipe Past Gallery to Navigate" is not supported: `PostRow` has no
            // access to the enclosing `ForEach`'s index.
            if post.crosspostParent != nil {
                // Apollo shows a crosspost as its card alone (below), not the original's
                // media or link.
                EmptyView()
            } else if generalSettings.feedGalleryCarousel, post.galleryImageURLs.count > 1 {
                FeedGalleryCarouselView(urls: post.galleryImageURLs, shouldBlur: nativeMediaBlur, isNSFW: post.over18)
                    .tagFilterCover(.media, isNSFW: post.over18, isActive: coversMediaByTagFilter,
                                    cornerRadius: 0) { revealTagPart(.media) }
            } else if case .video(let videoURL) = PostMediaKind.classify(post: post) {
                // A video post gets a player, not a still frame: the
                // large feed row does its own media rendering rather
                // than calling `PostMediaView` (the post-detail
                // renderer). No control panel inline besides the
                // bottom-right mute square and progress strip; full
                // transport lives in fullscreen, reached by tapping.
                MutedVideoPlayerView(
                    url: videoURL,
                    unmuteContext: .feed,
                    enablesFeedScrubber: true,
                    showsControlPanel: false,
                    // Reddit's own dimensions, so the row is the right
                    // height on the first pass instead of resizing
                    // once the HLS manifest arrives.
                    initialAspectRatio: post.media?.redditVideo?.aspectRatio.map { CGFloat($0) },
                    onRequestFullscreen: { showingFullscreenMedia = true }
                ) { video in
                    // No set height: the player self-sizes from the asset's natural aspect
                    // ratio, and pinning a height leaves an empty black box.
                    video
                        .apolloMediaFrame()
                        .tagFilterCover(.media, isNSFW: post.over18, isActive: coversMediaByTagFilter,
                                        cornerRadius: 0) { revealTagPart(.media) }
                        .overlay {
                            if nativeMediaBlur {
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Image(systemName: post.over18 ? "eye.slash.fill" : "exclamationmark.triangle.fill")
                                            .foregroundStyle(.white)
                                    }
                            }
                        }
                        .apolloMediaPager(
                            items: [.video(videoURL)],
                            isPresented: $showingFullscreenMedia,
                            votePost: post,
                            repository: repository,
                            // The PLAYER owns the taps here.
                            attachesTapGestures: false)
                }
                // Where a back-popped PiP card hands the picture back,
                // and a system PiP candidate when leaving the app.
                .environment(\.floatingPiPHome, true)
                .environment(\.floatingPiPIsGIF, post.media?.redditVideo?.isGif == true)
            } else if case .link(let linkURL) = PostMediaKind.classify(post: post),
                      linkPreviewSettings.bodyDisplayMode != .off, !nativeMediaBlur {
                // Rich Link Previews > Body covers feeds too: the link post's card in
                // place of its thumbnail.
                LinkPreviewCard(url: linkURL, context: .body,
                                fallbackImageURL: post.previewImageURL(displayWidth: 400),
                                fallbackTitle: post.title)
                    .padding(.horizontal)
            } else if let url = resolvedThumbnailURL, post.isSelf {
                // A text post's own embedded image (Text Post Thumbnails): Reborn's hero,
                // 10pt corners at the text margin; a tap opens the image rather than the
                // thread. The image fills a set box: on its own, a filled image reports
                // its full size and would widen the whole row.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .overlay { CachedAsyncImage(url: url, contentMode: .fill) }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .tagFilterCover(.media, isNSFW: post.over18, isActive: coversMediaByTagFilter,
                                    cornerRadius: 10) { revealTagPart(.media) }
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { showingFullscreenMedia = true })
                    .padding(.horizontal)
                    .apolloMediaPager(items: [.image(url)], isPresented: $showingFullscreenMedia,
                                      votePost: post, repository: repository, attachesTapGestures: false)
            } else if let url = resolvedThumbnailURL {
                CachedAsyncImage(url: url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .tagFilterCover(.media, isNSFW: post.over18, isActive: coversMediaByTagFilter,
                                    cornerRadius: 0) { revealTagPart(.media) }
                    .overlay {
                        if nativeMediaBlur {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Image(systemName: post.over18 ? "eye.slash.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(.white)
                                }
                        }
                    }
            } else if let urlString = post.url, let host = URL(string: urlString)?.host, !(post.isSelf) {
                // Apollo shows a domain/URL row for link posts with no
                // thumbnail image.
                HStack {
                    Image(systemName: "safari")
                        .foregroundStyle(.secondary)
                    Text(host.replacingOccurrences(of: "www.", with: ""))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal)
            }
            VStack(alignment: .leading, spacing: 2) {
                // A nested `Button` here never receives taps since the whole row uses a
                // plain `.onTapGesture`. Only on an aggregate feed whose header isn't
                // already showing it; inside a subreddit Apollo doesn't name it. With Show
                // Subreddit at Top off: the subreddit, larger, on the ••• / vote line, the
                // stats below it.
                if isAggregateFeed, !showsSubredditHeader {
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            if appearanceSettings.showSubredditIconsForPosts {
                                SubredditIconView(subreddit: post.subreddit, repository: repository, size: 19)
                            }
                            Text(SubredditCapitalization.display(post.subreddit))
                                .apolloFont(size: 17)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded(onSubredditTap))
                        Spacer()
                        trailingControls
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: themeColors))
                }
                // "Always Show Usernames": the author under the title where
                // the info row doesn't already lead with them.
                if appearanceSettings.alwaysShowUsernames, !showsAuthorInInfoRow {
                    HStack(spacing: 4) {
                        Text("by")
                        Text(post.author)
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded(onAuthorTap))
                        if let authorFlair = post.authorFlairText, !authorFlair.isEmpty, generalSettings.showUserFlair {
                            LinkFlairLabel(text: authorFlair, parts: nil)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(authorFlairBackgroundColor ?? Color.secondary.opacity(0.2)))
                                .foregroundStyle(authorFlairTextColor ?? .secondary)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                // The info row and vote arrows use the same stock
                // glyphs and 4pt icon->number gap as the compact row.
                // The same info row as the compact row (`infoRowStats`), so
                // the Info Row and Appearance settings apply here too.
                HStack(spacing: 10) {
                    if showsAuthorInInfoRow {
                        infoRowAuthor
                    }
                    infoRowStats
                    Spacer()
                    if !(isAggregateFeed && !showsSubredditHeader) {
                        trailingControls
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: themeColors))
            }
            .apolloFont(size: 13)
            .padding(.horizontal)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
        }
    }

    /// ••• and, with Large Posts' voting buttons on, the arrows.
    @ViewBuilder
    var trailingControls: some View {
                    moreOptionsButton
                    // The LARGE row's own key
                    // (`LargeThumbnailsShowVotingButtons`, Appearance >
                    // Large Posts), separate from the compact row's
                    // `CompactModeHideVotingButtons`.
                    if largePostsShowVotingButtons {
                        Button {
                            Task { await vote(direction: voteState == true ? 0 : 1) }
                        } label: {
                            StockIcon("inline-upvote")
                                .foregroundStyle(voteState == true ? .orange : Color.apolloIdleVoteArrow)
                        }
                        Button {
                            Task { await vote(direction: voteState == false ? 0 : -1) }
                        } label: {
                            StockIcon("inline-downvote")
                                .foregroundStyle(voteState == false ? .blue : Color.apolloIdleVoteArrow)
                        }
                    }
    }
}
