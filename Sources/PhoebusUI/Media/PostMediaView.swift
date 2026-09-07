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
