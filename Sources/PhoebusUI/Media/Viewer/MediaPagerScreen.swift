import SwiftUI
import AVKit
import PhoebusCore

/// One shared fullscreen chrome (close/more/jump-to-comments) across images,
/// video and multi-image galleries. `MediaPagerItem` models one page; this
/// screen pages between them with `TabView(.page)` and reports "jump to
/// comments" back to the caller.
public enum MediaPagerItem: Identifiable, Equatable {
    case image(URL)
    case video(URL)
    /// A GIF: drawn as a GIF (or its silent MP4 sibling) with only a
    /// play/pause badge, never the video transport.
    case gif(URL)

    public var id: String {
        switch self {
        case .image(let url): return "image:\(url.absoluteString)"
        case .video(let url): return "video:\(url.absoluteString)"
        case .gif(let url): return "gif:\(url.absoluteString)"
        }
    }
}

public struct MediaPagerScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let items: [MediaPagerItem]
    let startIndex: Int
    /// Post context for the vote chrome: Apollo's media viewer has
    /// upvote/downvote buttons and a score label.
    var votePost: RedditPost?
    var repository: RedditRepository?
    /// Only shown when the caller has a real comment thread to jump
    /// to (a standalone image viewer with no post context has none).
    var onJumpToComments: (() -> Void)?

    @State private var selection: Int
    @Environment(\.dismiss) private var dismiss
    @State private var saveToast: String?

    /// Only the images of this album; "Save All" saves images, and a
    /// mixed post's videos are saved by their own path.
    private var albumImageURLs: [URL] {
        items.compactMap { if case .image(let u) = $0 { return u } else { return nil } }
    }

    @State private var askingGIFFormat: URL?
    /// Follows "Download GIFs as…"; Ask Each Time asks first.
    private func saveGIF(_ url: URL, format: GIFSaveFormat? = nil) async {
        let settings = generalSettings
        if format == nil, settings.gifSaveFormat == .askEachTime {
            askingGIFFormat = url
            return
        }
        do {
            try await GIFSaveService.save(gifURL: url, format: format ?? settings.gifSaveFormat,
                                          useApolloAlbum: settings.saveToApolloAlbum)
            saveToast = "Saved"
        } catch {
            saveToast = error.localizedDescription
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saveToast = nil
    }

    private func saveImages(_ urls: [URL]) async {
        saveToast = AlbumSaveCapacity.downloadingToast(count: urls.count)
        do {
            let saved = try await AlbumImageSaver.saveAll(
                urls: urls,
                useApolloAlbum: generalSettings.saveToApolloAlbum)
            saveToast = AlbumSaveCapacity.savedToast(count: saved)
        } catch {
            saveToast = error.localizedDescription
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saveToast = nil
    }
    @Environment(\.openURL) private var openURL
    /// "Show Controls When Opened": default off, chrome is hidden
    /// until tapped, matching a fullscreen viewer's "immersive by
    /// default" convention.
    @State private var controlsVisible = GeneralSettingsStore.load().showMediaViewerControlsWhenOpened
    /// The video on the current page, handed over by the player.
    /// Apollo's fullscreen viewer has no speedometer button, so
    /// playback speed lives in the "..." menu here.
    /// Each video page's player, by page. The current page's player drives PiP
    /// and playback speed, not a pre-mounted neighbour's.
    @State private var pagePlayers: [Int: AVPlayer] = [:]
    private var currentPlayer: AVPlayer? { pagePlayers[selection] }
    /// Every player this viewer has shown, and the inline ones it muted
    /// while it's up (#1252); the latter get their sound back on close.
    @State private var viewerPlayers: [AVPlayer] = []
    @State private var silencedInline: [AVPlayer] = []
    @State private var playbackSpeed: Float = 1
    public init(items: [MediaPagerItem], startIndex: Int = 0, votePost: RedditPost? = nil, repository: RedditRepository? = nil, onJumpToComments: (() -> Void)? = nil) {
        self.items = items
        self.startIndex = startIndex
        self.votePost = votePost
        self.repository = repository
        self.onJumpToComments = onJumpToComments
        _selection = State(initialValue: startIndex)
    }

    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedMediaViewer) }
            // Download GIFs as… Ask Each Time.
            .confirmationDialog("Save GIF", isPresented: $askingGIFFormat.isPresent(), titleVisibility: .visible,
                                presenting: askingGIFFormat) { url in
                Button("Save as GIF") { Task { await saveGIF(url, format: .alwaysGIF) } }
                Button("Save as Video") { Task { await saveGIF(url, format: .alwaysVideo) } }
                Button("Cancel", role: .cancel) {}
            }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                // Keyed by index, not the item's URL-derived id: a
                // gallery may legitimately contain the same image
                // twice, and two pages sharing an id makes SwiftUI
                // unable to match `.tag(index)` against `selection`.
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    MediaPagerPageView(item: item, isCurrentPage: index == selection, albumImageURLs: albumImageURLs, controlsVisible: controlsVisible, onSurfaceTapped: {
                        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
                    }, onVerticalSwipe: { dy, dx in
                        handleVerticalSwipe(verticalDistance: dy, horizontalDistance: abs(dx))
                    }, onPlayerReady: { newPlayer, newURL in
                        pagePlayers[index] = newPlayer
                        if !viewerPlayers.contains(where: { $0 === newPlayer }) { viewerPlayers.append(newPlayer) }
                        silencedInline += VideoPlayerCache.shared.silenceAudible(except: viewerPlayers)
                        // The viewer takes the card's own player: the
                        // card goes, playback carries on here.
                        FloatingPiPController.shared.yield(to: newPlayer, url: newURL)
                    })
                        .tag(index)
                }
            }
            #if canImport(UIKit)
            // No page dots: the album position is the "N / M" counter.
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            // A page left behind stops, unless another view (the post's
            // own video) still shows the same player.
            .onChange(of: selection) { _, current in
                for (index, player) in pagePlayers where index != current && player !== pagePlayers[current] {
                    if case .video(let url) = items[safe: index],
                       VideoPlayerCache.shared.holderCount(url: url) > 1 { continue }
                    player.pause()
                }
            }
            .onAppear { FeedVideoSound.viewersShowing += 1 }
            .onDisappear {
                FeedVideoSound.viewersShowing = max(0, FeedVideoSound.viewersShowing - 1)
                // Sound back for the inline video this viewer silenced,
                // unless the video went on to an audible PiP card, which
                // owns the sound now.
                let pip = FloatingPiPController.shared
                if !(pip.isShowing && pip.player?.isMuted == false) {
                    VideoPlayerCache.shared.restoreSound(silencedInline)
                }
                silencedInline = []
                NotificationCenter.default.post(name: .apolloFullscreenViewerClosed, object: nil)
            }
            // "Show Controls When Opened": when off (default), the
            // chrome starts hidden and a single tap toggles it.
            // Placed on the background so it doesn't compete with
            // `MediaPagerPageView`'s own double-tap-to-zoom gesture.
            .onTapGesture {
                // An image or GIF page's zoom view toggles the chrome
                // itself, once it knows the tap isn't a double-tap.
                switch items[safe: selection] {
                case .image, .gif: return
                default: break
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsVisible.toggle()
                }
            }

            // Chrome as in Apollo's viewer: only the close X at the top, in the status
            // bar's space; votes, comments, share and more along the bottom.
            if controlsVisible {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                        .accessibilityLabel("Close")
                    }
                    .accessibilityIdentifier("mediaPager.close")
                    Spacer()
                    if items.count > 1 {
                        albumCounter
                    }
                }
                // The X's centre sits 45.7pt in and 26.7pt down.
                .padding(.leading, 23.7)
                .padding(.trailing, 16)
                .padding(.top, 4.7)

                Spacer()

                if let saveToast {
                    Text(saveToast)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .accessibilityIdentifier("mediaPager.saveToast")
                }
                // Upvote, score, downvote; comments and their count;
                // share; more. Centred 54.5pt above the screen's bottom.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // Always shown, as Apollo's; it opens the thread when
                    // the viewer came from one.
                    if votePost != nil || onJumpToComments != nil {
                        Button {
                            guard let onJumpToComments else { return }
                            dismiss()
                            onJumpToComments()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 21))
                                if let count = votePost?.numComments {
                                    Text(count.apolloAbbreviated)
                                        .font(.system(size: 17))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(height: 44)
                            .accessibilityLabel("Comments")
                        }
                        // Apollo's hint copy.
                        .accessibilityHint("Double tap to view comments")
                        .accessibilityIdentifier("mediaPager.jumpToComments")
                        Spacer(minLength: 0)
                    }
                    if let url = currentURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 21))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Double tap to share media")
                        .accessibilityIdentifier("mediaPager.share")
                        Spacer(minLength: 0)
                    Menu {
                        // "Save Image" always, plus "Save All N
                        // Images" for a real album.
                        if case .image(let imageURL) = items[safe: selection] {
                            Button {
                                Task { await saveImages([imageURL]) }
                            } label: {
                                Label("Save Image", systemImage: "square.and.arrow.down")
                            }
                        }
                        if case .gif(let gifURL) = items[safe: selection] {
                            Button {
                                Task { await saveGIF(gifURL) }
                            } label: {
                                Label("Save GIF", systemImage: "square.and.arrow.down")
                            }
                        }
                        // `CopyMediaLinkActivity` sets the
                        // pasteboard's URL, not a plain string.
                        Button {
                            PasteboardHelper.copy(url: url)
                        } label: {
                            Label("Copy Link", systemImage: "link")
                        }
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                        // Playback speed, for video pages only. An
                        // icon-less checked row, so UIKit draws
                        // the checkmark on the trailing edge.
                        if let currentPlayer, case .video = items[safe: selection] {
                            Section {
                                ForEach(VideoPlaybackSpeeds.all, id: \.self) { speed in
                                    Toggle(isOn: Binding(
                                        get: { speed == playbackSpeed },
                                        set: { isOn in
                                            guard isOn else { return }
                                            playbackSpeed = speed
                                            if currentPlayer.timeControlStatus == .playing {
                                                currentPlayer.rate = speed
                                            }
                                        }
                                    )) {
                                        Text(VideoPlaybackSpeeds.title(speed))
                                    }
                                }
                            }
                            .accessibilityIdentifier("mediaPager.playbackSpeedSection")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                        .accessibilityLabel("More")
                    }
                    .accessibilityIdentifier("mediaPager.more")
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 21)
                .padding(.bottom, 32.5)
            }
            // Measured from the screen's edges, not the safe area.
            .ignoresSafeArea()
            .transition(.opacity)
            }
        }
        .statusBarHiddenIfAvailable()
    }

    /// Apollo's album position, "1 / 2", at the top right: its right edge
    /// 33.7pt in and centred 24.3pt down.
    private var albumCounter: some View {
        Text("\(selection + 1) / \(items.count)")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white.opacity(0.65))
            .padding(.trailing, 17.7)
            .padding(.bottom, 4.8)
            .accessibilityLabel("\(selection + 1) of \(items.count)")
            .accessibilityIdentifier("mediaPager.counter")
    }

    /// The swipe decision, shared by the SwiftUI gesture (images) and
    /// the player's UIKit pan recognizer (video), since the player's
    /// `isUserInteractionEnabled` view swallows the drag before SwiftUI
    /// sees it; `AVPlayerLayerView.onVerticalSwipe` reports it instead.
    private func handleVerticalSwipe(verticalDistance: CGFloat, horizontalDistance: CGFloat) {
        #if canImport(UIKit)
        // A zoomed image's drag pans the image.
        guard !ZoomingScrollView.isZoomedOnScreen else { return }
        #endif
        // Mostly-vertical only, either way, so this never steals the
        // `TabView`'s horizontal paging between gallery images.
        guard abs(verticalDistance) > 60,
              abs(verticalDistance) > horizontalDistance * 1.5 else { return }
        if verticalDistance > 0 {
            // Down: leave the viewer, the standard fullscreen dismissal.
            dismiss()
        }
    }
    private var currentURL: URL? {
        switch items[safe: selection] {
        case .image(let url), .video(let url), .gif(let url): return url
        case nil: return nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// One page's content: pinch/double-tap-to-zoom for images, a
/// muted-aware `AVPlayer` for video (reusing `MutedVideoPlayerView`
/// so the pager gets the same unmute wiring every other video
/// surface already has).
private struct MediaPagerPageView: View {
    let item: MediaPagerItem
    /// Only the page on screen autoplays; the pager pre-mounts neighbours.
    var isCurrentPage: Bool = true
    /// The album's images, for the long-press menu (#1254).
    var albumImageURLs: [URL] = []
    /// Hides the floating video panel along with the viewer's own
    /// chrome, so one tap hides everything.
    var controlsVisible: Bool = true
    /// Forwarded to the video player, which owns taps on its own
    /// surface; without it a tap over a fullscreen video couldn't
    /// toggle the chrome.
    var onSurfaceTapped: (() -> Void)?
    /// Forwarded to the player, the only thing that sees a drag on a
    /// fullscreen video.
    var onVerticalSwipe: ((CGFloat, CGFloat) -> Void)?
    /// Hands the pager the player, so its "..." menu can drive
    /// playback speed since Apollo has no speedometer button here.
    var onPlayerReady: ((AVPlayer, URL) -> Void)?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    /// The fullscreen image path every tap-to-zoom image routes
    /// through (`PostMediaView`'s `.image`/`.gallery` cases both page
    /// through `MediaPagerScreen`).
    @Setting(GeneralSettings.self) private var general
    private var liveTextEnabled: Bool { general.liveTextAnalyzer }

    var body: some View {
        switch item {
        case .image(let url):
            #if canImport(UIKit)
            // UIKit's own zooming: anchored at the fingers, rubber-banded, with
            // momentum; SwiftUI's scaleEffect zoom is not smooth.
            ZoomableImageView(url: url, liveText: liveTextEnabled,
                              onSingleTap: onSurfaceTapped, onVerticalSwipe: onVerticalSwipe)
            #else
            imageContent(url: url)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnifyGesture)
                .simultaneousGesture(scale > 1 ? dragGesture : nil)
                .onTapGesture(count: 2) { toggleZoom() }
            #endif
        case .video(let url):
            // Stock "Unmute Videos When Opened" owns the viewer's sound.
            //
            // The fullscreen viewer draws its control panel edge to
            // edge: the player self-sizes to fill the container
            // (`fillsContainer`), and `showsControlPanel` with
            // `floatsControlPanel` overlays the panel rather than
            // stacking it in a `VStack` below the video.
            MutedVideoPlayerView(url: url, unmuteContext: .fullscreen, enablesHoldForSpeed: true, showsControlPanel: true, fillsContainer: true, floatsControlPanel: true, isCurrentPage: isCurrentPage, controlsVisible: controlsVisible, onSurfaceTapped: onSurfaceTapped, onVerticalSwipe: onVerticalSwipe, onPlayerReady: onPlayerReady)
                .ignoresSafeArea()
        case .gif(let url):
            FullscreenGIFPage(url: url, onSurfaceTapped: onSurfaceTapped, onVerticalSwipe: onVerticalSwipe)
        }
    }

    @ViewBuilder
    private func imageContent(url: URL) -> some View {
        #if canImport(VisionKit) && canImport(UIKit)
        if liveTextEnabled, #available(iOS 16.0, *) {
            // `LiveTextImageView` reports its own size via
            // `sizeThatFits`, so SwiftUI lays it out at the image's
            // real aspect ratio; `.aspectRatio()` alone doesn't work
            // for a view that reports no intrinsic size.
            LiveTextImageView(url: url)
        } else {
            CachedAsyncImage(url: url)
        }
        #else
        CachedAsyncImage(url: url)
        #endif
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, min(lastScale * value.magnification, 5))
            }
            .onEnded { _ in
                lastScale = scale
                if scale == 1 { offset = .zero; lastOffset = .zero }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation {
            if scale > 1 {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }
}

/// Convenience modifier: presents a unified `MediaPagerScreen` in a
/// fullscreen cover when tapped, the single presentation path every media
/// type routes through.
public extension View {
    /// - Parameter attachesTapGestures: pass `false` when the content
    ///   already owns its tap handling, which a video does
    ///   (`MutedVideoPlayerView.onRequestFullscreen`). This modifier's
    ///   `.highPriorityGesture` outranks any plain gesture inside the
    ///   content regardless of nesting depth, so leaving it attached
    ///   over a video means the outer tap wins everywhere, including
    ///   the mute badge, which should route to the player instead.
    func apolloMediaPager(items: [MediaPagerItem], startIndex: Int = 0, isPresented: Binding<Bool>, votePost: RedditPost? = nil, repository: RedditRepository? = nil, onJumpToComments: (() -> Void)? = nil, onDoubleTap: (() -> Void)? = nil, attachesTapGestures: Bool = true, isEnabled: Bool = true) -> some View {
        // The whole modifier can be off, cover included: a caller
        // that is itself a fullscreen viewer must not present a
        // second one. See `RedGifsVideoView.suppressesOwnFullscreen`.
        self
            // Skipped for content that owns its own tap handling (a
            // video does): `.highPriorityGesture` and a `Button`
            // outrank a plain gesture regardless of nesting depth.
            .modifier(MediaPagerOuterTapTargets(
                isPresented: isPresented,
                onDoubleTap: onDoubleTap,
                isEnabled: attachesTapGestures))
            .modifier(MediaPagerCover(
                items: items,
                startIndex: startIndex,
                isPresented: isPresented,
                votePost: votePost,
                repository: repository,
                onJumpToComments: onJumpToComments,
                isEnabled: isEnabled))
    }
}

/// Presents the fullscreen pager, unless the caller is already one.
/// Gating only the tap targets isn't enough: the cover is presented
/// from `isPresented`, which a caller could still set, letting a
/// gallery video open a second fullscreen view on top of the first.
struct MediaPagerCover: ViewModifier {
    let items: [MediaPagerItem]
    let startIndex: Int
    let isPresented: Binding<Bool>
    let votePost: RedditPost?
    let repository: RedditRepository?
    let onJumpToComments: (() -> Void)?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.fullScreenCoverIfAvailable(isPresented: isPresented) {
                MediaPagerScreen(items: items, startIndex: startIndex, votePost: votePost, repository: repository, onJumpToComments: onJumpToComments)
            }
        } else {
            content
        }
    }
}

/// The whole outer tap surface: hit shape, tap gestures and `Button`,
/// all skipped together when the content owns its own tap handling.
struct MediaPagerOuterTapTargets: ViewModifier {
    let isPresented: Binding<Bool>
    let onDoubleTap: (() -> Void)?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                // `.contentShape` first: the tap target is the
                // media's whole frame, not the rendered content
                // (which can leave transparent gaps in an `AsyncImage`).
                .contentShape(Rectangle())
                .modifier(MediaPagerTapGestures(isPresented: isPresented, onDoubleTap: onDoubleTap))
                // A real `Button` resolves through UIKit's control
                // path. Behind the media, so any control layered on
                // top keeps its touches.
                .background {
                    Button {
                        isPresented.wrappedValue = true
                    } label: {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("media.openFullscreenButton")
                    .accessibilityLabel("View fullscreen")
                }
        } else {
            content
        }
    }
}

/// The tap gestures that open the pager, as one gesture rather than
/// two competing recognizers.
///
/// Two separately attached `.highPriorityGesture`s make a single tap over a
/// video do nothing: an unconditionally registered double-tap recognizer
/// makes every single tap wait and then get discarded.
/// `.exclusively(before:)` makes them one gesture with defined precedence,
/// and where there's no double-tap handler only the single tap is attached.
struct MediaPagerTapGestures: ViewModifier {
    let isPresented: Binding<Bool>
    let onDoubleTap: (() -> Void)?

    func body(content: Content) -> some View {
        if let onDoubleTap {
            content.highPriorityGesture(
                TapGesture(count: 2).onEnded { onDoubleTap() }
                    .exclusively(before: TapGesture().onEnded { isPresented.wrappedValue = true })
            )
        } else {
            content.highPriorityGesture(
                TapGesture().onEnded { isPresented.wrappedValue = true })
        }
    }
}

/// A GIF in the viewer, as Reborn shows it: the GIF fitted to the screen,
/// playing, with the small play/pause badge in its corner and no video
/// controls. A tap elsewhere toggles the viewer's chrome.
private struct FullscreenGIFPage: View {
    let url: URL
    var onSurfaceTapped: (() -> Void)?
    var onVerticalSwipe: ((CGFloat, CGFloat) -> Void)?
    @State private var isPlaying = true
    @State private var ratio: CGFloat?

    var body: some View {
        #if canImport(UIKit)
        // Pinch, double-tap and long-press as an image's page.
        ZoomableGIFView(url: url, isPlaying: isPlaying,
                        onSingleTap: onSurfaceTapped, onVerticalSwipe: onVerticalSwipe,
                        onRatio: { newRatio in DispatchQueue.main.async { ratio = newRatio } })
            // On the GIF's own bottom-right corner at its fitted size.
            .overlay {
                GeometryReader { geo in
                    let boxRatio = ratio ?? 9.0 / 16.0
                    let width = min(geo.size.width, geo.size.height / boxRatio)
                    Color.clear
                        .frame(width: width, height: width * boxRatio)
                        .overlay(alignment: .bottomTrailing) {
                            GIFPlaybackBadge(isPlaying: isPlaying) { isPlaying.toggle() }
                        }
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .accessibilityIdentifier("mediaPager.gif")
        #else
        GIFSurface(url: url, isPlaying: isPlaying)
        #endif
    }
}
