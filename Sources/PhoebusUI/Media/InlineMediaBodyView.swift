import SwiftUI
import AVKit
import PhoebusCore
#if canImport(UIKit)
import AnimatedImage
#endif

/// Renders a single piece of inline-detected media (image/gif/video/
/// redgifs/streamable), reimplementing Apollo-Reborn's Inline
/// Media Previews: images, GIFs and videos sit in Reborn's sized box
/// (`InlineMediaFrame`); the hosted players keep their own layouts.
struct InlineMediaPreviewView: View {
    @Setting(LinkPreviewSettings.self) private var linkPreviewSettings
    let kind: InlineMediaKind
    let settings: InlineMediaSettings

    var body: some View {
        switch kind {
        case .image(let url):
            InlineImageView(url: url, settings: settings)
        case .gif(let url):
            InlineGIFView(url: url, settings: settings)
        case .video(let url):
            InlineVideoPosterView(url: url, settings: settings)
        default:
            HStack {
                if settings.alignment == .right { Spacer(minLength: 0) }
                hostedContent
                    .frame(maxWidth: settings.size.fraction * 600)
                if settings.alignment == .left { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private var alignment: Alignment {
        switch settings.alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    @ViewBuilder
    private var hostedContent: some View {
        switch kind {
        case .image, .gif, .video:
            EmptyView()
        case .redgifs(let id):
            RedGifsVideoView(gifID: id, unmuteContext: .embed)
        case .gfycat(let id):
            // Gfycat IDs resolve via the RedGifs API post-merger.
            RedGifsVideoView(gifID: id, unmuteContext: .embed)
        case .streamable(let id):
            StreamableVideoView(videoID: id, unmuteContext: .embed)
        case .imgurAlbum(let id):
            // The same album gallery the post-level classifier renders for this URL
            // shape (see `InlineMediaKind.imgurAlbum`).
            ImgurAlbumView(albumID: id)
        case .link(let url):
            LinkPreviewCard(url: url, context: .comments)
        }
    }
}

// MARK: - Reborn's inline media box

/// Remembers each media URL's shape, so a re-rendered row lays out at the
/// right size at once (Reborn keeps the same URL → ratio table).
@MainActor
enum InlineMediaRatioCache {
    private static var ratios: [URL: CGFloat] = [:]
    static func ratio(for url: URL) -> CGFloat? {
        ratios[url] ?? InlineMediaFrame.ratio(fromQueryOf: url)
    }
    static func store(_ ratio: CGFloat, for url: URL) {
        guard ratio.isFinite, ratio > 0 else { return }
        ratios[url] = ratio
    }
    /// Shapes known up front from `media_metadata`; a decoded image's own
    /// ratio (stored later) wins.
    static func seed(_ known: [String: Double]) {
        for (string, ratio) in known {
            guard let url = URL(string: string), ratios[url] == nil else { continue }
            store(CGFloat(ratio), for: url)
        }
    }
}

/// Places one piece of media in its Reborn box: sized by
/// `InlineMediaFrame`, positioned by the alignment setting, 4pt above
/// and below.
struct InlineMediaBoxLayout: Layout {
    var ratio: CGFloat
    var size: InlineMediaSize
    var alignment: InlineMediaAlignment
    var isVideo = false

    private static var screen: CGRect {
        #if canImport(UIKit)
        UIScreen.main.bounds
        #else
        CGRect(x: 0, y: 0, width: 400, height: 800)
        #endif
    }

    private func frame(width: CGFloat) -> InlineMediaFrame {
        .fit(ratio: ratio, rowWidth: width, screenHeight: Self.screen.height, size: size, isVideo: isVideo)
    }

    private func rowWidth(_ proposal: ProposedViewSize) -> CGFloat {
        if let width = proposal.width, width.isFinite, width > 0 { return width }
        return Self.screen.width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = rowWidth(proposal)
        return CGSize(width: width, height: frame(width: width).height + 2 * InlineMediaFrame.verticalInset)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let box = frame(width: bounds.width)
        let slack = max(0, bounds.width - box.width)
        let x: CGFloat
        switch alignment {
        case .left: x = 0
        case .right: x = slack
        case .center: x = slack / 2
        }
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + InlineMediaFrame.verticalInset),
                          proposal: ProposedViewSize(width: box.width, height: box.height))
        }
    }
}

/// The box's clipping and outline: 8pt corners, and Reborn's hairline
/// only when the media is letterboxed inside a box of another shape.
private struct InlineMediaChrome: ViewModifier {
    let ratio: CGFloat
    let settings: InlineMediaSettings
    var isVideo = false

    func body(content: Content) -> some View {
        let letterboxed = InlineMediaFrame.fit(ratio: ratio, rowWidth: 1000, screenHeight: 100_000,
                                               size: .large, isVideo: isVideo).isLetterboxed
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: InlineMediaFrame.cornerRadius))
            .overlay {
                if letterboxed {
                    RoundedRectangle(cornerRadius: InlineMediaFrame.cornerRadius)
                        .strokeBorder(Color(.separator), lineWidth: 0.75)
                }
            }
    }
}

/// Reborn's placeholder tint while an image loads.
private let inlineMediaPlaceholder = Color(white: 0.5, opacity: 0.12)

// MARK: Images

/// An inline image: aspect-fit in its box; a tap opens the viewer.
private struct InlineImageView: View {
    let url: URL
    let settings: InlineMediaSettings
    @State private var image: PlatformImage?
    @State private var failed = false
    @State private var showingFullscreen = false

    var body: some View {
        let ratio = image.map { $0.aspectRatio } ?? InlineMediaRatioCache.ratio(for: url) ?? 9.0 / 16.0
        InlineMediaBoxLayout(ratio: ratio, size: settings.size, alignment: settings.alignment) {
            Group {
                if let image {
                    image.swiftUIImage.resizable().aspectRatio(contentMode: .fit)
                } else if failed {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    inlineMediaPlaceholder
                }
            }
            .modifier(InlineMediaChrome(ratio: ratio, settings: settings))
            .apolloMediaPager(items: [.image(url)], isPresented: $showingFullscreen)
        }
        .task(id: url) { await load() }
        .accessibilityIdentifier("comment.inlineImage")
    }

    private func load() async {
        guard image == nil else { return }
        guard let bytes = await MediaBytes.data(for: url) else {
            if !Task.isCancelled { failed = true }
            return
        }
        guard let decoded = PlatformImage(data: bytes) else {
            failed = true
            return
        }
        InlineMediaRatioCache.store(decoded.aspectRatio, for: url)
        image = decoded
    }
}

// MARK: GIFs

/// Reborn's inline GIF: Autoplay Inline GIFs decides whether it plays.
/// Tap to Play (and WiFi Only while on cellular) adds the 30pt corner
/// play/pause badge, which toggles playback in place; a tap anywhere else
/// opens the viewer. Played as the MP4 sibling when the GIF fallback
/// format is MP4, with none of the video chrome.
private struct InlineGIFView: View {
    let url: URL
    let settings: InlineMediaSettings
    /// Set once the user taps the badge; `nil` follows the setting.
    @State private var userPlaying: Bool?
    @State private var ratio: CGFloat?
    @State private var showingFullscreen = false

    var body: some View {
        let unmetered = NetworkReachability.isOnUnmeteredNetwork
        let mode = settings.autoplayMode
        let isPlaying = userPlaying ?? mode.autoplays(isUnmetered: unmetered)
        let boxRatio = ratio ?? InlineMediaRatioCache.ratio(for: url) ?? 9.0 / 16.0
        InlineMediaBoxLayout(ratio: boxRatio, size: settings.size, alignment: settings.alignment) {
            GIFSurface(url: url, isPlaying: isPlaying, onRatio: { newRatio in
                InlineMediaRatioCache.store(newRatio, for: url)
                ratio = newRatio
            })
            .modifier(InlineMediaChrome(ratio: boxRatio, settings: settings))
            .apolloMediaPager(items: [.gif(url)], isPresented: $showingFullscreen)
            .overlay(alignment: .bottomTrailing) {
                if mode.showsPlayBadge(isUnmetered: unmetered) {
                    GIFPlaybackBadge(isPlaying: isPlaying) { userPlaying = !isPlaying }
                }
            }
        }
        .accessibilityIdentifier("comment.inlineGIF")
    }
}

/// Reborn's 30pt GIF badge: a dark translucent disc with a white ring,
/// showing play while paused and pause while playing, 6pt in from the
/// corner. Its hit area is 44pt.
struct GIFPlaybackBadge: View {
    let isPlaying: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Circle().fill(.black.opacity(0.45))
                    .shadow(color: .black.opacity(0.55), radius: 1.5)
                Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                if isPlaying {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1).frame(width: 3, height: 11)
                        RoundedRectangle(cornerRadius: 1).frame(width: 3, height: 11)
                    }
                    .foregroundStyle(.white)
                } else {
                    PlayTriangle().fill(.white)
                        .frame(width: 10, height: 12)
                        .offset(x: 1.25)
                }
            }
            .padding(1.5)
            .frame(width: 30, height: 30)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The 30pt badge sits 6pt in from the corner; its 44pt hit area
        // reaches 7pt further out.
        .padding([.trailing, .bottom], -1)
        .accessibilityLabel(isPlaying ? "Pause GIF" : "Play GIF")
        .accessibilityIdentifier("gif.playbackBadge")
    }
}

/// A right-pointing triangle filling its frame.
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Draws a GIF, playing or held on its first frame. Uses the MP4 sibling
/// under the "Preferred GIF Fallback Format: MP4" setting (smoother and
/// far lighter than decoding the GIF), falling back to the GIF itself
/// when that file won't play.
struct GIFSurface: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let url: URL
    let isPlaying: Bool
    var onRatio: (CGFloat) -> Void = { _ in }
    @State private var mp4Failed = false

    private var mp4URL: URL? {
        guard !mp4Failed, generalSettings.preferredGIFFallbackFormat == .mp4 else { return nil }
        if let transcode = GIFTranscodes.mp4(forGIF: url.absoluteString) { return URL(string: transcode) }
        return GIFURLHelpers.mp4SiblingURL(for: url)
    }

    var body: some View {
        #if canImport(UIKit)
        if let mp4URL {
            LoopingSilentVideo(url: mp4URL, isPlaying: isPlaying, onRatio: onRatio,
                               onFailure: { mp4Failed = true })
        } else {
            AnimatedGIFData(url: url, isPlaying: isPlaying, onRatio: onRatio)
        }
        #else
        CachedAsyncImage(url: url)
        #endif
    }
}

#if canImport(UIKit)
/// A muted, looping video with no controls at all: the GIF surface.
struct LoopingSilentVideo: View {
    let url: URL
    let isPlaying: Bool
    var onRatio: (CGFloat) -> Void
    var onFailure: () -> Void
    @State private var player: AVPlayer
    @State private var holderID = "gif." + UUID().uuidString

    init(url: URL, isPlaying: Bool, onRatio: @escaping (CGFloat) -> Void, onFailure: @escaping () -> Void) {
        self.url = url
        self.isPlaying = isPlaying
        self.onRatio = onRatio
        self.onFailure = onFailure
        _player = State(initialValue: VideoPlayerCache.shared.player(for: url) { AVPlayer(url: url) })
    }

    var body: some View {
        AVPlayerLayerView(player: player)
            .onAppear {
                VideoPlayerCache.shared.show(url: url, holder: holderID)
                player.isMuted = true
                player.actionAtItemEnd = .none
                if isPlaying { player.play() }
            }
            .onChange(of: isPlaying) { _, playing in
                if playing { player.play() } else { player.pause() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime,
                                                            object: player.currentItem)) { _ in
                player.seek(to: .zero)
                if isPlaying { player.play() }
            }
            .onDisappear {
                VideoPlayerCache.shared.release(url: url, holder: holderID)
                if !VideoPlayerCache.shared.isStillHeld(url: url) { player.pause() }
            }
            .task(id: url) {
                guard let item = player.currentItem else { return }
                if let track = try? await item.asset.loadTracks(withMediaType: .video).first,
                   let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0 {
                    onRatio(size.height / size.width)
                } else if !Task.isCancelled {
                    onFailure()
                }
            }
    }
}

/// The GIF file itself: animated while playing, its first frame when held.
private struct AnimatedGIFData: View {
    let url: URL
    let isPlaying: Bool
    var onRatio: (CGFloat) -> Void
    @State private var animated: AnimatedImage?
    @State private var still: PlatformImage?

    var body: some View {
        Group {
            if let animated, isPlaying {
                AnimatedImagePlayer(image: animated, contentMode: .fit)
            } else if let still {
                still.swiftUIImage.resizable().aspectRatio(contentMode: .fit)
            } else {
                inlineMediaPlaceholder
            }
        }
        .task(id: url) {
            if let bytes = await MediaBytes.data(for: url) { apply(bytes) }
        }
    }

    private func apply(_ bytes: Data) {
        animated = AnimatedImage(gif: bytes, withConfiguration: .fullQuality)
        still = PlatformImage(data: bytes)
        if let still { onRatio(still.aspectRatio) }
    }
}
#endif

// MARK: Videos

/// Reborn's inline video: a still poster with the 72pt centred play
/// circle; a tap opens the full player.
private struct InlineVideoPosterView: View {
    let url: URL
    let settings: InlineMediaSettings
    @State private var showingFullscreen = false
    @State private var ratio: CGFloat?

    var body: some View {
        let boxRatio = ratio ?? InlineMediaRatioCache.ratio(for: url) ?? 9.0 / 16.0
        InlineMediaBoxLayout(ratio: boxRatio, size: settings.size, alignment: settings.alignment, isVideo: true) {
            VideoPosterFrame(url: url, onRatio: { newRatio in
                InlineMediaRatioCache.store(newRatio, for: url)
                ratio = newRatio
            })
            .background(Color.black)
            .overlay { RebornPlayCircle().allowsHitTesting(false) }
            .modifier(InlineMediaChrome(ratio: boxRatio, settings: settings, isVideo: true))
            .apolloMediaPager(items: [.video(url)], isPresented: $showingFullscreen)
        }
        .accessibilityIdentifier("comment.inlineVideo")
    }
}

/// Reborn's video play circle: a 72pt translucent black disc with a soft
/// shadow, a 2.5pt white ring and a white triangle.
struct RebornPlayCircle: View {
    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.45))
                .shadow(color: .black.opacity(0.55), radius: 3)
            Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2.5)
                .padding(1)
            PlayTriangle().fill(.white)
                .frame(width: 29, height: 34)
                .offset(x: 4)
        }
        .frame(width: 65, height: 65)
        .frame(width: 72, height: 72)
    }
}

/// The video's first frame, decoded once as a still image rather than a
/// paused `AVPlayer` per poster, which would hold a hardware decoder for as
/// long as the row exists.
private struct VideoPosterFrame: View {
    let url: URL
    var onRatio: (CGFloat) -> Void
    @State private var frame: PlatformImage?

    var body: some View {
        ZStack {
            Color.black
            if let frame {
                frame.swiftUIImage.resizable().aspectRatio(contentMode: .fit)
            }
        }
        .task(id: url) {
            guard let still = await Self.firstFrame(of: url) else { return }
            frame = still.image
            if still.ratio > 0 { onRatio(still.ratio) }
        }
    }

    /// Height / width after the track's rotation, and the frame itself.
    private static func firstFrame(of url: URL) async -> (image: PlatformImage, ratio: CGFloat)? {
        #if canImport(UIKit)
        var source = url
        if url.pathExtension.lowercased() == "m3u8" {
            guard let file = await VideoDownloader.resolvePosterURL(forRedditVideo: url) else { return nil }
            source = file
        }
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        guard let (cgImage, _) = try? await generator.image(at: .zero) else { return nil }
        let image = UIImage(cgImage: cgImage)
        let ratio = image.size.width > 0 ? image.size.height / image.size.width : 0
        return (PlatformImage(uiImage: image), ratio)
        #else
        return nil
        #endif
    }
}

/// Wraps a post/comment body: renders the markdown text, then any
/// inline-detected media found within it (Reborn's Inline Media Previews).
/// When `InlineMediaSettings.enabled` is false, it is plain
/// `Text(RedditMarkdown.render(body))`.
public struct InlineMediaBodyView: View {
    @Setting(InlineMediaSettings.self) private var inlineMediaSettings
    /// Which real toggle governs this body.
    ///
    /// Reborn treats message media as its OWN setting
    /// (`EnableChatMedia`) rather than a sub-option of the
    /// post/comment one, so the two contexts read different keys.
    public enum Context {
        case postsAndComments
        case messages
    }

    let body_: String
    let lineLimit: Int?
    let context: Context
    /// The comment's or post's `media_metadata`, when the caller has it.
    let mediaMetadata: [String: GalleryMediaItem]?
    /// Which Rich Link Previews mode the body's link cards follow: a self
    /// post's or a comment's.
    let linkContext: LinkPreviewContext
    /// Off where Apollo draws no link cards: a profile's comment rows.
    let showsLinkCards: Bool

    public init(_ body: String, lineLimit: Int? = nil, context: Context = .postsAndComments,
                mediaMetadata: [String: GalleryMediaItem]? = nil, linkContext: LinkPreviewContext = .comments,
                showsLinkCards: Bool = true) {
        self.showsLinkCards = showsLinkCards
        self.body_ = body
        self.lineLimit = lineLimit
        self.context = context
        self.mediaMetadata = mediaMetadata
        self.linkContext = linkContext
    }

    public var body: some View {
        let settings = inlineMediaSettings
        let isEnabled = context == .messages ? settings.enabledInMessages : settings.enabled
        let (text, attachments) = InlineMediaBodyMemo.layout(body_, isEnabled: isEnabled, mediaMetadata: mediaMetadata)
        // Apollo puts a card under a comment or self post for each link
        // in it (not in truncated previews or messages), stacked after the
        // text with the inline media in the order the links appear; with
        // two or more, Reborn draws the ordinary cards compact.
        let showsCards = context == .postsAndComments && lineLimit == nil && showsLinkCards
        let shown = showsCards ? attachments : attachments.filter { if case .media = $0 { return true } else { return false } }
        let cardCount = shown.filter { if case .link = $0 { return true } else { return false } }.count
        VStack(alignment: .leading, spacing: 4) {
            if !text.isEmpty {
                BulkTranslatedText(text, lineLimit: lineLimit)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, attachment in
                switch attachment {
                case .media(let kind):
                    InlineMediaPreviewView(kind: kind, settings: settings)
                case .link(let url):
                    LinkPreviewCard(url: url, context: linkContext, forceCompact: cardCount > 1)
                        .padding(.top, 4)
                }
            }
        }
    }
}

/// One thing drawn under a body's text.
enum InlineBodyAttachment: Equatable {
    case media(InlineMediaKind)
    case link(URL)
}

/// The text and media an inline body resolves to, computed once per body
/// rather than on every render: detection runs a regex over the whole
/// body, and a vote or a settings change re-renders every row.
@MainActor
private enum InlineMediaBodyMemo {
    private struct Key: Hashable {
        let body: String
        let isEnabled: Bool
        let imageURLs: [String: String]
    }
    private static var entries: [Key: (text: String, attachments: [InlineBodyAttachment])] = [:]
    private static let limit = 500

    static func layout(_ body: String, isEnabled: Bool,
                       mediaMetadata: [String: GalleryMediaItem]?) -> (text: String, attachments: [InlineBodyAttachment]) {
        let imageURLs = RedditMediaTokens.imageURLs(from: mediaMetadata)
        let key = Key(body: body, isEnabled: isEnabled, imageURLs: imageURLs)
        if let hit = entries[key] { return hit }
        InlineMediaRatioCache.seed(RedditMediaTokens.ratios(from: mediaMetadata))
        let expanded = RedditMediaTokens.expand(body, imageURLs: imageURLs)
        let media = isEnabled ? InlineMediaDetector.detect(in: body, imageURLs: imageURLs) : []
        // A line that is only a drawn image/GIF (a bare link or Reddit's
        // `![gif](giphy|…)` token) is replaced by the media itself; with
        // previews off, a token still reads as its link rather than raw
        // markdown.
        let text = media.isEmpty ? expanded : ShareCardFormatting.removingImageOnlyLines(expanded)
        // Media and link cards in the order their links appear; each link
        // gets one card, each media link every time it appears.
        var attachments: [InlineBodyAttachment] = []
        var seenLinks = Set<String>()
        for url in LinkCardDetector.urls(in: expanded) {
            if let kind = InlineMediaDetector.classify(url) {
                if isEnabled { attachments.append(.media(kind)) }
            } else if seenLinks.insert(url.absoluteString.lowercased()).inserted {
                attachments.append(.link(url))
            }
        }
        // Anything the media scan found that the link scan didn't goes last.
        for kind in media where !attachments.contains(.media(kind)) {
            attachments.append(.media(kind))
        }
        if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
        entries[key] = (text, attachments)
        return (text, attachments)
    }
}
