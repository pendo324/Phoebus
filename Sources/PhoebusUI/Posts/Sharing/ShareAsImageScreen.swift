import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Renders a post as a shareable card image (title/subreddit/author/score), with
/// Apollo's hideable-field options: Include Post Details / Hide Usernames /
/// Watermark. "Include Post Details" shows or hides the whole
/// subreddit+author+score/comment block, distinct from "Hide Usernames" (byline
/// only). Rows are plain flat rows on the dark background, the header reads
/// "Preview" with a circular gray X close button, and a full-width blue Share
/// button is pinned near the bottom.
public struct ShareAsImageScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let post: RedditPost
    /// The comment being shared, when this is a comment share.
    let comment: RedditComment?
    /// Ancestors of `comment`, nearest parent last.
    let availableParents: [RedditComment]
    let repository: RedditRepository

    @State private var includePostDetails = true
    @State private var includePostTextPollOrImage = true
    @State private var hideUsernames = UserDefaults.standard.bool(forKey: "HideUsernamesByDefaultInShareAsImage")
    @State private var hideSubreddit = UserDefaults.standard.bool(forKey: "HideSubredditsByDefaultInShareAsImage")
    @State private var showWatermark = true

    // Reborn "Share as Video" (#380): a video post's card gets a toggle that exports
    // an MP4 with the card as a static backdrop and the post's video playing inside
    // the media region. Default off, as in Reborn.
    /// Backs the comment-share "Parent Comments" stepper.
    @State private var parentComments = 0
    /// Reborn's "Link" menu (#1278): the permalink that rides alongside the image or
    /// video, so Messages and Mail attach it too. Read in `.onAppear`, since which
    /// choices exist depends on whether a comment is shared.
    @State private var linkMode: ShareLinkMode = .none
    @State private var shareAsVideo = false
    @State private var isExportingVideo = false
    @State private var exportedVideoURL: URL?
    @State private var exportError: String?
    @State private var presentingShareSheet = false
    /// The post's own picture, which the card carries. Loaded async because the card
    /// cannot block on the network.
    @State private var postImage: Image?
    @State private var postImageAspect: CGFloat?
    /// Pre-loaded author avatars for the card (see `ShareCardView.avatars`).
    @State private var avatars: [String: Image] = [:]
    /// Images linked in the shared comments, by comment id.
    @State private var commentImages: [String: [ShareCardImageLoader.Result]] = [:]
    @State private var includeCommentImages = UserDefaults.standard.object(forKey: "ApolloShareIncludeCommentImages") as? Bool ?? true
    /// The card's natural size, measured so the preview can scale it to
    /// fit a fixed box instead of pushing the options around.
    @State private var cardSize: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var videoURL: URL? {
        guard case .video(let url) = PostMediaKind.classify(post: post) else { return nil }
        // The downloadable rendition: an HLS playlist cannot be muxed
        // with the DASH audio track, only an MP4 can.
        return PostMediaKind.downloadableVideoURL(for: post) ?? url
    }

    /// The active theme's compiled tokens. Read explicitly rather than via
    /// `\.apolloTheme`, since the card is also rendered detached by `ImageRenderer`,
    /// which does not inherit the environment; otherwise preview and export could
    /// disagree.
    private var themeColors: ApolloThemeColors {
        let theme = ThemeStore.load()
        let compiled = ThemeAppearance.compiledTheme(for: theme)
        // Without a gallery theme the card follows the system appearance.
        let dark = compiled == nil ? colorScheme == .dark : theme.isDark
        return ApolloThemeColors(compiled: compiled, mode: dark ? .dark : .light)
    }

    public init(
        post: RedditPost,
        comment: RedditComment? = nil,
        availableParents: [RedditComment] = [],
        repository: RedditRepository
    ) {
        self.post = post
        self.comment = comment
        self.availableParents = availableParents
        self.repository = repository
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Preview")
                    .font(.headline)
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        .accessibilityLabel("Close")
                    }
                    .padding(.trailing)
                }
            }
            .padding(.top)
            .padding(.bottom, 8)

            // Apollo's preview is a fixed box the card snapshot scales
            // into, so adding parent comments or toggling details shrinks
            // the preview rather than moving the options.
            GeometryReader { box in
                let scale = cardSize.width > 0 && cardSize.height > 0
                    ? min(1, box.size.width / cardSize.width, box.size.height / cardSize.height)
                    : 1
                cardPreview
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .scaleEffect(scale)
                    .frame(width: box.size.width, height: box.size.height)
            }
            .padding()
            .frame(maxHeight: .infinity)

            // Apollo's row order: Parent Comments, Post Details, Post Text, Hide Usernames,
            // Hide Subreddit, Watermark; Reborn adds Include Link under Watermark.
            VStack(spacing: 0) {
                if comment != nil, !availableParents.isEmpty {
                    Stepper(
                        "Parent Comments: \(parentComments)",
                        value: $parentComments,
                        in: 0...availableParents.count
                    )
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("shareAsImage.parentCommentsStepper")
                }
                Toggle("Include Post Details", isOn: $includePostDetails)
                    .padding(.vertical, 10)
                if ShareCardView.bodyText(of: post) != nil || postImage != nil {
                    Toggle("Include Post Text", isOn: $includePostTextPollOrImage)
                        .padding(.vertical, 10)
                }
                if hasCommentImages {
                    Toggle("Include Images", isOn: $includeCommentImages)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier("shareAsImage.includeImagesToggle")
                        .onChange(of: includeCommentImages) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "ApolloShareIncludeCommentImages")
                        }
                }
                Toggle("Hide Usernames", isOn: $hideUsernames)
                    .padding(.vertical, 10)
                Toggle("Hide Subreddit", isOn: $hideSubreddit)
                    .padding(.vertical, 10)
                Toggle("Watermark", isOn: $showWatermark)
                    .padding(.vertical, 10)
                HStack {
                    Text("Link")
                    Spacer()
                    Menu {
                        ForEach(ShareLinkMode.options(hasComment: comment != nil), id: \.self) { mode in
                            Button {
                                linkMode = mode
                                ShareLinkMode.write(mode)
                            } label: {
                                if mode == linkMode {
                                    Label(mode.title, systemImage: "checkmark")
                                } else {
                                    Text(mode.title)
                                }
                            }
                        }
                    } label: {
                        // The theme accent, as the toggles (#1278 "Use theme accent for share link menu").
                        Text(linkMode.title)
                            .foregroundStyle(.tint)
                    }
                    .accessibilityIdentifier("shareAsImage.linkMenu")
                }
                .padding(.vertical, 10)
                .onAppear { linkMode = ShareLinkMode.read(hasComment: comment != nil) }
                if videoURL != nil {
                    Toggle("Share as Video", isOn: $shareAsVideo)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier("shareAsImage.shareAsVideoToggle")
                }
            }
            .padding(.horizontal)
            .fixedSize(horizontal: false, vertical: true)

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            shareControl
                .padding()
        }
        .task { await loadPostImage() }
        .task { await loadAvatars() }
        .task { await loadCommentImages() }
        #if canImport(UIKit)
        .sheet(isPresented: $exportedVideoURL.isPresent()) {
            if let exportedVideoURL {
                // The chosen link rides with the video too (#1278).
                ActivityShareSheet(items: [exportedVideoURL] + (linkURL.map { [$0] } ?? []))
            }
        }
        .sheet(isPresented: $presentingShareSheet) {
            ActivityShareSheet(items: shareItems) { completed in
                presentingShareSheet = false
                // Only a completed share closes the preview; cancelling leaves it up so the
                // options can be adjusted and tried again.
                if completed { dismiss() }
            }
        }
        #endif
    }

    @ViewBuilder
    private var shareControl: some View {
        #if canImport(UIKit)
        if shareAsVideo, let videoURL {
            Button {
                exportShareVideo(videoURL: videoURL)
            } label: {
                shareButtonLabel(isExportingVideo ? "Exporting…" : "Share")
            }
            .disabled(isExportingVideo)
            .accessibilityIdentifier("shareAsImage.shareButton")
        } else {
            // An ActivityShareSheet rather than ShareLink: "Include
            // Link" needs a second item alongside the image, and the
            // sheet must dismiss only on a completed share, not a
            // cancelled one.
            Button {
                presentingShareSheet = true
            } label: {
                shareButtonLabel("Share")
            }
            .accessibilityIdentifier("shareAsImage.shareButton")
        }
        #else
        ShareLink(
            item: renderCardImage(),
            preview: SharePreview("Post from r/\(post.subreddit)", image: renderCardImage())
        ) {
            shareButtonLabel("Share")
        }
        #endif
    }

    #if canImport(UIKit)
    /// The share sheet's items. With "Include Link" on, the permalink
    /// rides alongside the image so Messages and Mail attach both.
    private var shareItems: [Any] {
        var items: [Any] = []
        let renderer = ImageRenderer(content: cardContent)
        // 4x of the 320pt card gives a 1280px-wide image, so text stays
        // sharp when the photo is viewed full screen or zoomed.
        renderer.scale = 4
        if let uiImage = renderer.uiImage { items.append(uiImage) }
        if let linkURL { items.append(linkURL) }
        return items
    }
    #endif

    private func shareButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.apolloAccent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    #if canImport(UIKit)
    /// Reborn suppresses the native image-only share and shows progress while it
    /// builds the MP4 asynchronously; this surfaces a failure inline rather than
    /// silently switching modes.
    private func exportShareVideo(videoURL: URL) {
        exportError = nil
        isExportingVideo = true
        let renderer = ImageRenderer(content: cardContent.frame(width: 360))
        renderer.scale = 3
        guard let cardImage = renderer.uiImage else {
            isExportingVideo = false
            exportError = "Couldn't render the card."
            return
        }
        // Media region: the bottom slice of the card where a
        // poster/GIF normally sits.
        let mediaRect = CGRect(x: 0, y: 0.55, width: 1, height: 0.45)
        Task {
            do {
                let url = try await ShareVideoExportService.export(videoURL: videoURL, cardImage: cardImage, mediaRect: mediaRect)
                await MainActor.run {
                    isExportingVideo = false
                    exportedVideoURL = url
                }
            } catch {
                await MainActor.run {
                    isExportingVideo = false
                    exportError = error.localizedDescription
                }
            }
        }
    }
    #endif

    /// The card's picture, and for a gallery Reborn's collage rather than stock
    /// Apollo's fallback link card.
    private func loadPostImage() async {
        #if canImport(UIKit)
        guard postImage == nil else { return }
        var urls: [URL]
        switch PostMediaKind.classify(post: post) {
        case .image(let url): urls = [url]
        case .gallery(let galleryURLs): urls = galleryURLs
        default:
            // A gallery does not always classify as `.gallery` (a
            // reddit.com-hosted one can fall through), so fall back to
            // the post's own gallery URLs before giving up.
            urls = post.galleryImageURLs
        }

        // A LINK post has no direct image URL but has Reddit's own
        // preview ladder, already used as the feed thumbnail. A SELF
        // post can embed images via `media_metadata`, which
        // `derivedSelfPostThumbnailURL` already extracts. Preview
        // first, since it's the higher resolution of the two.
        if urls.isEmpty {
            // The card's own content width at 3x, so the chosen rung
            // is not upscaled.
            if let preview = post.previewImageURL(displayWidth: 320) {
                urls = [preview]
            } else if let inline = post.derivedSelfPostThumbnailURL {
                urls = [inline]
            } else if let thumbnail = post.thumbnail,
                      thumbnail.hasPrefix("http"),
                      let url = URL(string: thumbnail.replacingOccurrences(of: "&amp;", with: "&")) {
                // Last resort: Reddit's 140px thumbnail. `thumbnail`
                // is also the sentinel strings
                // "self"/"default"/"nsfw" on posts with none, hence
                // the http check.
                urls = [url]
            }
        }
        guard !urls.isEmpty else { return }
        if let result = await ShareCardImageLoader.load(urls: urls) {
            postImage = result.image
            postImageAspect = result.aspect
        }
        #endif
    }

    private var cardOptions: ShareCardView.Options {
        var options = ShareCardView.Options()
        options.includePostDetails = includePostDetails
        options.includePostTextPollOrImage = includePostTextPollOrImage
        options.hideUsernames = hideUsernames
        options.hideSubreddit = hideSubreddit
        options.includeWatermark = showWatermark
        options.parentComments = parentComments
        options.includeCommentImages = includeCommentImages
        return options
    }

    /// The link the Link menu picked, if any.
    private var linkURL: URL? {
        linkMode.url(post: post.shareURL(), comment: comment?.shareURL())
    }

    @ViewBuilder
    private var cardPreview: some View {
        cardContent
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { cardSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in cardSize = size }
            })
    }

    /// Whether any shared comment links an image, which is when the
    /// Include Images row is offered.
    private var hasCommentImages: Bool {
        guard let comment else { return false }
        let shown = [comment.id] + availableParents.suffix(parentComments).map(\.id)
        return shown.contains { commentImages[$0] != nil }
    }

    /// Loads the images linked in the shared comment and its parents,
    /// ahead of time, so the exported image includes them.
    private func loadCommentImages() async {
        #if canImport(UIKit)
        var all = availableParents
        if let comment { all.append(comment) }
        for c in all {
            let urls: [URL] = InlineMediaDetector.detect(in: c.body).compactMap { kind in
                switch kind {
                case .image(let url), .gif(let url): return url
                default: return nil
                }
            }
            var loaded: [ShareCardImageLoader.Result] = []
            for url in urls.prefix(4) {
                if let result = await ShareCardImageLoader.load(urls: [url]) { loaded.append(result) }
            }
            if !loaded.isEmpty { commentImages[c.id] = loaded }
        }
        #endif
    }

    /// Loads avatars for every author on the card when "Show User
    /// Profile Pictures" is on, reusing the app's avatar cache.
    private func loadAvatars() async {
        #if canImport(UIKit)
        guard generalSettings.showUserProfilePictures else { return }
        var names = [post.author] + availableParents.map(\.author)
        if let comment { names.append(comment.author) }
        for name in Set(names) where name != "[deleted]" && !name.isEmpty {
            var urlString = await AvatarCache.shared.cachedURL(for: name)
            if urlString == nil, !(await AvatarCache.shared.hasFreshEntry(for: name)) {
                urlString = try? await repository.fetchUserProfile(username: name).iconImage
                await AvatarCache.shared.store(url: urlString, for: name)
            }
            guard let urlString, let url = URL(string: urlString.replacingOccurrences(of: "&amp;", with: "&")),
                  let data = await MediaBytes.data(for: url),
                  let image = UIImage(data: data) else { continue }
            avatars[name] = Image(uiImage: image)
        }
        #endif
    }

    private var cardContent: some View {
        ShareCardView(
            post: post,
            comment: comment,
            parents: Array(availableParents.suffix(parentComments)),
            options: cardOptions,
            colors: themeColors,
            postImage: postImage,
            postImageAspect: postImageAspect,
            avatars: avatars,
            commentImages: commentImages,
            depthColors: CommentsThemeStore.effectiveHexes(theme: ThemeStore.load()).map(Color.init(hex:))
        )
    }

    /// Renders the card view to a static image, mirroring Apollo's
    /// share-as-image export. Uses SwiftUI's `ImageRenderer` (iOS 16+)
    /// rather than a manual `UIGraphicsImageRenderer` snapshot, since
    /// it captures the SwiftUI view tree directly.
    private func renderCardImage() -> Image {
        let renderer = ImageRenderer(content: cardContent.frame(width: 360))
        #if canImport(UIKit)
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        #endif
        return Image(systemName: "photo")
    }
}
