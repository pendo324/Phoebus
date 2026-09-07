import SwiftUI
import AVKit
import PhoebusCore

/// Media dispatch for a post's URL: classifies the URL as image, GIF,
/// direct video, RedGifs-hosted video, or generic link and renders
/// the appropriate view.
public enum PostMediaKind {
    case image(URL)
    case gif(URL)
    case video(URL)
    case redgifs(id: String)
    /// gfycat.com legacy links, resolved via RedGifs' API post-merger.
    case gfycat(id: String)
    case streamable(id: String)
    /// Reborn-only "sports clip" hosts; see `SportsClipHost`.
    case sportsClip(pageURL: URL)
    case youtube(id: String)
    case vimeo(id: String)
    case steam(kind: SteamURLParser.ItemKind, id: String)
    case imgurAlbum(id: String)
    case gallery([URL])
    /// The URL to download for `post`, not the URL to play: playback
    /// uses the muxed HLS stream, but Save Video needs the
    /// progressive `DASH_*.mp4` to pair with `DASH_audio.mp4` and mux
    /// itself. See `RedditVideoStream.downloadURL`.
    static func downloadableVideoURL(for post: RedditPost) -> URL? {
        guard let redditVideo = post.media?.redditVideo else { return nil }
        return RedditVideoStream.downloadURL(
            hlsURL: redditVideo.hlsURL, fallbackURL: redditVideo.fallbackURL)
    }
    case none

    public static func classify(post: RedditPost) -> PostMediaKind {
        guard !post.isSelf else { return .none }

        // Multi-image gallery posts, checked before the single-media
        // branches since gallery posts' post.url points at the gallery
        // permalink, not a usable media URL.
        let galleryURLs = post.galleryImageURLs
        if !galleryURLs.isEmpty {
            return .gallery(galleryURLs)
        }

        // v.redd.it native Reddit-hosted video: the playable stream
        // URL lives in post.media.reddit_video.fallback_url, not
        // post.url (the human-facing watch page).
        if let redditVideo = post.media?.redditVideo,
           let url = RedditVideoStream.playbackURL(
                hlsURL: redditVideo.hlsURL,
                fallbackURL: redditVideo.fallbackURL,
                isGif: redditVideo.isGif) {
            // HLS, not `fallback_url`: Reddit stores v.redd.it audio
            // as a separate track, so `fallback_url` alone plays silently.
            return .video(url)
        }

        guard let urlString = post.url, let url = URL(string: urlString) else {
            return .none
        }

        if url.host?.contains("redgifs.com") == true, let id = RedGifsClient.extractID(from: url) {
            return .redgifs(id: id)
        }

        if url.host?.contains("gfycat.com") == true, let id = GfycatURLParser.extractID(from: url) {
            return .gfycat(id: id)
        }

        if url.host?.contains("streamable.com") == true, let id = StreamableClient.extractID(from: url) {
            return .streamable(id: id)
        }

        if SportsClipHost.matches(url) {
            return .sportsClip(pageURL: url)
        }

        if let id = YouTubeURLParser.extractVideoID(from: url) {
            return .youtube(id: id)
        }

        if let id = VimeoURLParser.extractVideoID(from: url) {
            return .vimeo(id: id)
        }

        // i.imgflip.com/<id> or imgflip.com/i/<id>.
        if let id = ImgflipURLParser.extractID(from: url), let imageURL = ImgflipURLParser.imageURL(forID: id) {
            return .image(imageURL)
        }

        // "Deep linking support for Steam": a Steam store link opens the native app.
        if let (kind, id) = SteamURLParser.extractItem(from: url) {
            return .steam(kind: kind, id: id)
        }

        // "Fully working Imgur integration": an imgur.com/a/<id> or
        // /gallery/<id> link renders as a gallery. A direct
        // i.imgur.com/<id>.jpg needs no API call and is handled by
        // the plain extension checks below.
        if let albumID = ImgurClient.extractAlbumID(from: url) {
            return .imgurAlbum(id: albumID)
        }

        let lower = urlString.lowercased()
        if lower.hasSuffix(".gif") || lower.hasSuffix(".gifv") {
            return .gif(url)
        }
        if [".mp4", ".mov", ".m3u8", ".webm"].contains(where: lower.hasSuffix) {
            return .video(url)
        }
            return .image(url)
    }
}

public struct PostMediaView: View {
    let kind: PostMediaKind
    /// When set, renders behind an interactive NSFW/spoiler blur
    /// overlay until tapped, mirroring Apollo's content warning overlay.
    let contentWarning: ContentWarning?
    @State private var showingFullscreenImage = false
    @State private var isRevealed = false
    /// The fullscreen media viewer's "jump to comments" chrome button.
    /// Optional for callers without a comment thread to jump to.
    var onJumpToComments: (() -> Void)?
    /// Post + repository context so the fullscreen viewer can show
    /// the upvote/downvote chrome.
    var votePost: RedditPost?
    var voteRepository: RedditRepository?
    /// "Double tap to upvote" on post media, taken as a parameter
    /// rather than applied by the caller as an outer modifier: an
    /// outer double-tap recognizer swallows the inner single tap that
    /// opens the fullscreen pager. Both gestures are declared on the
    /// same view; see `apolloMediaPager`.
    var onDoubleTapMedia: (() -> Void)?

    public enum ContentWarning {
        case nsfw
        case spoiler

        var label: String {
            switch self {
            case .nsfw: return "NSFW"
            case .spoiler: return "Spoiler"
            }
        }
    }

    public init(kind: PostMediaKind, contentWarning: ContentWarning? = nil, onJumpToComments: (() -> Void)? = nil, votePost: RedditPost? = nil, voteRepository: RedditRepository? = nil, onDoubleTapMedia: (() -> Void)? = nil) {
        self.kind = kind
        self.contentWarning = contentWarning
        self.onJumpToComments = onJumpToComments
        self.votePost = votePost
        self.voteRepository = voteRepository
        self.onDoubleTapMedia = onDoubleTapMedia
    }

    /// Derives the content warning from a post's spoiler/over_18
    /// flags (NSFW takes precedence when both are set). NSFW media is
    /// covered per "Blur NSFW Media" and the Tag Filters; spoilers always.
    public static func contentWarning(for post: RedditPost) -> ContentWarning? {
        if post.spoiler { return .spoiler }
        return nil
    }

    public var body: some View {
        ZStack {
            mediaContent
            if let contentWarning, !isRevealed {
                blurOverlay(for: contentWarning)
            }
        }
        // The post screen's own media: any player in it may hand over to
        // the floating PiP card (Reborn scopes PiP to the post header).
        .environment(\.floatingPiPSourceEnabled, true)
    }
    @ViewBuilder
    private var mediaContent: some View {
        switch kind {
        case .image(let url):
            CachedAsyncImage(url: url)
                .apolloMediaFrame()
                .apolloMediaPager(items: [.image(url)], isPresented: $showingFullscreenImage, votePost: votePost, repository: voteRepository, onJumpToComments: onJumpToComments, onDoubleTap: onDoubleTapMedia)
        case .gif(let url):
            AnimatedGIFView(url: url,
                            redditMP4URL: votePost?.preview?.images?.first?.variants?.mp4?.source?.url
                                .flatMap { URL(string: GalleryTile.unescaped($0)) })
                .environment(\.floatingPiPIsGIF, true)
                .apolloMediaFrame()
        case .video(let url):
            // A standalone v.redd.it/native video post reaches the
            // same fullscreen pager as an image via `.apolloMediaPager`.
            //
            // Reborn's "Unmute Videos in Comments" owns the post's own
            // video here; the feed setting never reaches it.
            //
            // The trailing closure decorates the video surface only
            // (`MutedVideoPlayerView.decorateVideo`); wrapping the
            // whole thing would letterbox the controls into the
            // media's aspect ratio and make a tap on the scrubber
            // open the fullscreen pager.
            MutedVideoPlayerView(
                url: url,
                unmuteContext: .commentsHeader,
                enablesFeedScrubber: true,
                // The post screen's own video hands off to the
                // floating PiP card when scrolled away.
                enablesFloatingPiP: true,
                showsControlPanel: false,
                initialAspectRatio: votePost?.media?.redditVideo?.aspectRatio.map { CGFloat($0) },
                onRequestFullscreen: { showingFullscreenImage = true }
            ) { video in
                video
                    .apolloMediaFrame()
                    .apolloMediaPager(items: [.video(url)], isPresented: $showingFullscreenImage, votePost: votePost, repository: voteRepository, onJumpToComments: onJumpToComments, onDoubleTap: onDoubleTapMedia,
                              // The player owns the taps here.
                              attachesTapGestures: false)
            }
            // Reddit's GIF uploads arrive as silent videos flagged is_gif.
            .environment(\.floatingPiPIsGIF, votePost?.media?.redditVideo?.isGif == true)
        case .redgifs(let id):
            RedGifsVideoView(gifID: id, unmuteContext: .commentsHeader)
        case .gfycat(let id):
            // Gfycat IDs resolve via the RedGifs API post-merger.
            RedGifsVideoView(gifID: id, unmuteContext: .commentsHeader)
        case .streamable(let id):
            StreamableVideoView(videoID: id, unmuteContext: .commentsHeader)
        case .sportsClip(let pageURL):
            SportsClipView(pageURL: pageURL)
        case .youtube(let id):
            YouTubePlayerView(videoID: id)
        case .vimeo(let id):
            VimeoPlayerView(videoID: id)
        case .steam(let kind, let id):
            SteamLinkView(kind: kind, id: id)
        case .imgurAlbum(let id):
            ImgurAlbumView(albumID: id)
        case .gallery(let urls):
            GalleryMediaView(urls: urls, onJumpToComments: onJumpToComments, votePost: votePost, voteRepository: voteRepository)
        case .none:
            EmptyView()
        }
    }

    private func blurOverlay(for warning: ContentWarning) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(maxHeight: 400)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: warning == .nsfw ? "eye.slash.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                    Text("Tap to reveal \(warning.label)")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { isRevealed = true }
            }
    }
}

/// Inline gallery for multi-image posts: Apollo's three-thumbnail mosaic
/// with an "N IMAGES" badge, tapped to open the fullscreen pager.
///
/// It is not a swipeable `TabView`, which would claim vertical drags with
/// any horizontal component from the enclosing list. Swiping between images
/// happens in the fullscreen pager.
struct GalleryMediaView: View {
    let urls: [URL]
    var onJumpToComments: (() -> Void)?
    var votePost: RedditPost?
    var voteRepository: RedditRepository?
    /// "Double tap to upvote" on post media, taken as a parameter for
    /// the same reason as `PostMediaView.onDoubleTapMedia`.
    var onDoubleTapMedia: (() -> Void)?
    /// The tapped thumbnail's index, and the presentation trigger.
    ///
    /// Item-based rather than a separate Bool + index: setting both in the same
    /// tap presents the cover with the previous index, since SwiftUI evaluates
    /// the sheet content before the state change lands.
    @State private var fullscreenStart: FullscreenStart?

    private struct FullscreenStart: Identifiable {
        let id: Int
    }

    /// Apollo's native album mosaic is 16:9.
    private static let mosaicAspectRatio: CGFloat = 16.0 / 9.0

    /// The real mosaic's 2pt gutter between tiles.
    private static let gutter: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let gutter = Self.gutter
            let height = geometry.size.height
            // Two images split the width evenly; with three, the first is
            // a square and the other two stack evenly beside it.
            let leftWidth = switch urls.count {
            case 1: width
            case 2: (width - gutter) / 2
            default: min(height, width)
            }
            let rightWidth = width - leftWidth - gutter

            HStack(spacing: gutter) {
                thumbnail(at: 0)
                    .frame(width: leftWidth, height: height)

                if urls.count > 1 {
                    VStack(spacing: gutter) {
                        if urls.count == 2 {
                            thumbnail(at: 1)
                                .frame(width: rightWidth, height: height)
                        } else {
                            let tileHeight = (height - gutter) / 2
                            thumbnail(at: 1)
                                .frame(width: rightWidth, height: tileHeight)
                            thumbnail(at: 2)
                                .frame(width: rightWidth, height: tileHeight)
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            // The count badge sits bottom-right, reading "N IMAGES".
            .overlay(alignment: .bottomTrailing) {
                if urls.count > 1 {
                    Text("\(urls.count) IMAGES")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.black.opacity(0.75))
                        )
                        .padding(8)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("gallery.counter")
                }
            }
        }
        .aspectRatio(Self.mosaicAspectRatio, contentMode: .fit)
        .fullScreenCoverIfAvailable(item: $fullscreenStart) { start in
            // Seeds the initial page from the tapped thumbnail's index.
            MediaPagerScreen(items: urls.map { .image($0) }, startIndex: start.id, votePost: votePost, repository: voteRepository, onJumpToComments: onJumpToComments)
        }
    }

    /// One mosaic tile. Tapping it opens the fullscreen pager at that image.
    ///
    /// `.clipped()` with a fill content mode crops thumbnails to their
    /// slot rather than letterboxing each one.
    @ViewBuilder
    private func thumbnail(at index: Int) -> some View {
        if index < urls.count {
            // A Button, not `.onTapGesture`: inside a `List` row the row's own tap
            // handling wins over a plain tap gesture, so per-tile taps never arrive.
            Button {
                fullscreenStart = FullscreenStart(id: index)
            } label: {
                Color.clear
                    .overlay(
                        CachedAsyncImage(url: urls[index])
                            .scaledToFill()
                    )
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gallery.thumbnail.\(index)")
        }
    }
}
/// Sizes a resolved video: `apolloMediaFrame`'s capped inline box
/// normally, or the whole container inside a fullscreen viewer.
private struct ResolvedVideoFrame: ViewModifier {
    let fillsContainer: Bool

    func body(content: Content) -> some View {
        if fillsContainer {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content.apolloMediaFrame()
        }
    }
}

/// Resolves a RedGifs ID to its playable video URL via RedGifsClient's
/// keyless temp-token OAuth flow, then plays it inline.
struct RedGifsVideoView: View {
    let gifID: String
    /// Defaults to `.feed` (post's own top-level media);
    /// `InlineMediaPreviewView` passes `.comments` for a RedGifs ID
    /// embedded within a comment's body.
    var unmuteContext: MutedVideoPlayerView.UnmuteContext = .feed
    @State private var resolvedURL: URL?
    @State private var errorMessage: String?
    /// Suppresses this view's own fullscreen destination, for a caller that is
    /// already a fullscreen viewer (`GalleryImageViewerScreen`): a second viewer
    /// would stack on the first. The gallery viewer's own tap toggles chrome, so
    /// it owns the tap and the player must not.
    var suppressesOwnFullscreen: Bool = false
    /// Hands the resolved `AVPlayer` up to a fullscreen viewer that
    /// draws its own transport bar, e.g. `GalleryImageViewerScreen`.
    var onPlayerReady: ((AVPlayer, URL) -> Void)?

    /// Forwarded to the player so only the page on screen decodes.
    /// See `MutedVideoPlayerView.isCurrentPage`.
    var isCurrentPage: Bool?

    /// Opens the fullscreen viewer, and the state backing it. Every
    /// resolver-backed host (RedGifs, Gfycat, Streamable, sports clip)
    /// plays through `MutedVideoPlayerView` and needs this destination
    /// wired, or its only control is the mute badge.
    @State private var showingFullscreen = false

    var body: some View {
        Group {
            if let resolvedURL {
                MutedVideoPlayerView(
                    url: resolvedURL,
                    unmuteContext: unmuteContext,
                    enablesFeedScrubber: !suppressesOwnFullscreen,
                    // No destination when the caller is fullscreen already: the viewer's own tap keeps toggling chrome.
                    onRequestFullscreen: suppressesOwnFullscreen ? nil : { showingFullscreen = true },
                    fillsContainer: suppressesOwnFullscreen,
                    // The viewer draws the transport bar and mute button; this player draws no chrome.
                    hostedByFullscreenViewer: suppressesOwnFullscreen,
                    isCurrentPage: isCurrentPage,
                    onPlayerReady: onPlayerReady)
                    .modifier(ResolvedVideoFrame(fillsContainer: suppressesOwnFullscreen))
                    .apolloMediaPager(items: [.video(resolvedURL)], isPresented: $showingFullscreen,
                                      // The player owns the taps.
                                      attachesTapGestures: false,
                                      isEnabled: !suppressesOwnFullscreen)
            } else if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxHeight: 200)
            }
        }
        .task {
            do {
                resolvedURL = try await RedGifsClient.shared.resolvePlayableURL(forID: gifID)
            } catch {
                errorMessage = "Couldn't load RedGifs video"
            }
        }
    }
}

extension RedGifsClient {
    /// Shared instance so the temp-token cache persists across every
    /// RedGifs video shown in a scroll session, avoiding a fresh OAuth
    /// round-trip per post.
    public static let shared = RedGifsClient()
}

/// Resolves a Streamable video ID to its playable video URL via
/// Streamable's public keyless video-info endpoint, then plays it inline.
struct StreamableVideoView: View {
    let videoID: String
    /// See `RedGifsVideoView.unmuteContext` for the feed-vs-comments split.
    var unmuteContext: MutedVideoPlayerView.UnmuteContext = .feed
    @State private var resolvedURL: URL?
    @State private var errorMessage: String?
    /// Suppresses this view's own fullscreen destination, for a caller that is
    /// already a fullscreen viewer (`GalleryImageViewerScreen`): a second viewer
    /// would stack on the first. The gallery viewer's own tap toggles chrome, so
    /// it owns the tap and the player must not.
    var suppressesOwnFullscreen: Bool = false
    /// Hands the resolved `AVPlayer` up to a fullscreen viewer that
    /// draws its own transport bar, e.g. `GalleryImageViewerScreen`.
    var onPlayerReady: ((AVPlayer, URL) -> Void)?

    /// Forwarded to the player so only the page on screen decodes.
    /// See `MutedVideoPlayerView.isCurrentPage`.
    var isCurrentPage: Bool?

    /// Opens the fullscreen viewer, and the state backing it. Every
    /// resolver-backed host (RedGifs, Gfycat, Streamable, sports clip)
    /// plays through `MutedVideoPlayerView` and needs this destination
    /// wired, or its only control is the mute badge.
    @State private var showingFullscreen = false

    var body: some View {
        Group {
            if let resolvedURL {
                MutedVideoPlayerView(
                    url: resolvedURL,
                    unmuteContext: unmuteContext,
                    enablesFeedScrubber: !suppressesOwnFullscreen,
                    // No destination when the caller is fullscreen already: the viewer's own tap keeps toggling chrome.
                    onRequestFullscreen: suppressesOwnFullscreen ? nil : { showingFullscreen = true },
                    fillsContainer: suppressesOwnFullscreen,
                    // The viewer draws the transport bar and mute button; this player draws no chrome.
                    hostedByFullscreenViewer: suppressesOwnFullscreen,
                    isCurrentPage: isCurrentPage,
                    onPlayerReady: onPlayerReady)
                    .modifier(ResolvedVideoFrame(fillsContainer: suppressesOwnFullscreen))
                    .apolloMediaPager(items: [.video(resolvedURL)], isPresented: $showingFullscreen,
                                      // The player owns the taps.
                                      attachesTapGestures: false,
                                      isEnabled: !suppressesOwnFullscreen)
            } else if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxHeight: 200)
            }
        }
        .task {
            do {
                resolvedURL = try await StreamableClient.shared.resolvePlayableURL(forID: videoID)
            } catch {
                errorMessage = "Couldn't load Streamable video"
            }
        }
    }
}

extension StreamableClient {
    public static let shared = StreamableClient()
}

/// Resolves a "sports clip" host share page (see `SportsClipHost`)
/// to a playable video URL via a generic OpenGraph `og:video` scrape,
/// falling back to a plain tappable link on failure.
struct SportsClipView: View {
    let pageURL: URL
    @State private var resolvedURL: URL?
    @State private var failed = false
    /// Suppresses this view's own fullscreen destination, for a caller that is
    /// already a fullscreen viewer (`GalleryImageViewerScreen`): a second viewer
    /// would stack on the first. The gallery viewer's own tap toggles chrome, so
    /// it owns the tap and the player must not.
    var suppressesOwnFullscreen: Bool = false
    /// Hands the resolved `AVPlayer` up to a fullscreen viewer that
    /// draws its own transport bar, e.g. `GalleryImageViewerScreen`.
    var onPlayerReady: ((AVPlayer, URL) -> Void)?

    /// Forwarded to the player so only the page on screen decodes.
    /// See `MutedVideoPlayerView.isCurrentPage`.
    var isCurrentPage: Bool?

    /// Opens the fullscreen viewer, and the state backing it. Every
    /// resolver-backed host (RedGifs, Gfycat, Streamable, sports clip)
    /// plays through `MutedVideoPlayerView` and needs this destination
    /// wired, or its only control is the mute badge.
    @State private var showingFullscreen = false

    var body: some View {
        Group {
            if let resolvedURL {
                MutedVideoPlayerView(
                    url: resolvedURL,
                    enablesFeedScrubber: !suppressesOwnFullscreen,
                    onRequestFullscreen: suppressesOwnFullscreen ? nil : { showingFullscreen = true },
                    fillsContainer: suppressesOwnFullscreen,
                    // The viewer draws the transport bar and mute button; this player draws no chrome.
                    hostedByFullscreenViewer: suppressesOwnFullscreen,
                    isCurrentPage: isCurrentPage,
                    onPlayerReady: onPlayerReady)
                    .modifier(ResolvedVideoFrame(fillsContainer: suppressesOwnFullscreen))
                    .apolloMediaPager(items: [.video(resolvedURL)], isPresented: $showingFullscreen,
                                      // The player owns the taps.
                                      attachesTapGestures: false,
                                      isEnabled: !suppressesOwnFullscreen)
            } else if failed {
                Button(pageURL.absoluteString) {
                    #if canImport(UIKit)
                    UIApplication.shared.open(pageURL)
                    #endif
                }
                .font(.footnote)
            } else {
                ProgressView()
                    .frame(maxHeight: 200)
            }
        }
    }
}

// MARK: - Media frame

extension View {
    /// The standard frame for a post's media: capped height, and
    /// centred when the media is narrower than the row.
    /// `.frame(maxHeight: 400)` alone leaves a scaled-down portrait
    /// image at the leading edge; `maxWidth: .infinity` centres it.
    func apolloMediaFrame() -> some View {
        frame(maxWidth: .infinity, maxHeight: 400)
    }
}
