import SwiftUI
import AVKit
import UIKit
import PhoebusCore

/// Gallery View's own fullscreen pager, opened from a grid tile.
///
/// Separate from `MediaPagerScreen`: Reborn's Gallery has its own
/// fullscreen viewer with different chrome ("Done" button, running
/// "N / M" counter, bottom info card).
public struct GalleryImageViewerScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let tiles: [GalleryTile]
    let startIndex: Int
    let repository: RedditRepository
    /// Leaves the gallery for the real post; called from the info card.
    var onOpenPost: ((RedditPost) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.apolloTheme) private var apolloTheme
    @State private var selection: Int
    /// A video page opens with chrome hidden; still pictures keep it up.
    @State private var chromeVisible = true
    @State private var didApplyInitialChrome = false
    /// Live vertical offset while the dismiss pan drags, so the pager
    /// visibly follows the finger, matching Reborn's dismiss pan.
    @State private var dismissDragOffset: CGFloat = 0
    /// True while the dismiss pan is dragging; drives background dim.
    @State private var isDismissDragging = false
    /// Hold-and-drag scrub: press and slide anywhere on a video page
    /// to scrub. Arms on long-press begin, commits only once the drag
    /// clears a small slop.
    @State private var gestureScrubActive = false
    @State private var gestureScrubStartX: CGFloat = 0
    @State private var gestureScrubStartTime: Double = 0
    @State private var gestureScrubWasPlaying = false
    /// The info card swipes away sideways; hidden state is per item.
    @State private var infoHiddenForItem = false
    /// Every page's player, keyed by index (not just "the current
    /// one"), since a neighbour can build its player before becoming
    /// current. Held unobserved so registration can't rebuild the
    /// `TabView` mid-gesture.
    @State private var registry = GalleryPlayerRegistry()
    @State private var holdingForSpeed = false
    @State private var holdSpeedRestoreRate: Float = 1
    /// Survives the transport bar's rebuilds; see `bottomStack`. Not
    /// observed by this screen, so its 4Hz ticks don't re-render the
    /// `TabView` mid-drag.
    @State private var transportClock: GalleryTransportClock

    private var currentPlayer: AVPlayer? { registry.players[selection] }
    /// Post whose comments are open as a sheet over the still-live
    /// media. An upward flick opens comments, gated on Reborn's
    /// `SwipeUpForComments` key (default YES).
    @State private var commentsPost: RedditPost?
    @Environment(\.openURL) private var openURL
    @State private var saveToast: String?

    private func saveCurrentImage() async {
        guard let tile = currentTile else { return }
        let url = tile.galleryMediaID != nil ? tile.fullResolutionURL : (GalleryPostMedia.fullResolutionURL(for: tile.post) ?? tile.fullResolutionURL)
        saveToast = "Saving…"
        do {
            _ = try await AlbumImageSaver.saveAll(urls: [url], useApolloAlbum: generalSettings.saveToApolloAlbum)
            saveToast = "Saved to your photo library."
        } catch {
            saveToast = error.localizedDescription
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saveToast = nil
    }

    private func saveCurrentVideo() async {
        guard let post = currentPost else { return }
        let url = PostMediaKind.downloadableVideoURL(for: post) ?? currentTile?.videoURL
        guard let url else { return }
        saveToast = "Saving…"
        do {
            try await VideoDownloadService.downloadAndSave(videoURL: url)
            saveToast = "Saved to your photo library."
        } catch {
            saveToast = error.localizedDescription
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saveToast = nil
    }


    public init(tiles: [GalleryTile],
                startIndex: Int,
                repository: RedditRepository,
                onOpenPost: ((RedditPost) -> Void)? = nil) {
        self.tiles = tiles
        self.startIndex = startIndex
        self.repository = repository
        self.onOpenPost = onOpenPost
        _selection = State(initialValue: startIndex)
        // Created once per viewer; unobserved so 4Hz ticks don't re-render this screen.
        _transportClock = State(initialValue: GalleryTransportClock())
    }

    private static let topInset: CGFloat = 12
    private static let bottomInset: CGFloat = 16
    private static let sideInset: CGFloat = 16
    private static let controlHeight: CGFloat = 36
    private static let controlGap: CGFloat = 8
    private static let doneWidth: CGFloat = 74
    private static let counterWidth: CGFloat = 88
    private static let infoCornerRadius: CGFloat = 14
    private static let infoMaxWidth: CGFloat = 460
    private static let videoBarHeight: CGFloat = 44
    /// The card sits 8pt above the transport bar.
    private static let infoToBarGap: CGFloat = 8

    private var currentPost: RedditPost? {
        guard selection >= 0, selection < tiles.count else { return nil }
        return tiles[selection].post
    }

    private var currentTile: GalleryTile? {
        guard selection >= 0, selection < tiles.count else { return nil }
        return tiles[selection]
    }

    private var currentIsVideo: Bool {
        guard let currentPost else { return false }
        return GalleryPostMedia.kind(for: currentPost) != .photo
    }

    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedGallery) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        ZStack {
            // Darkens as the dismiss drag progresses, matching Reborn's dim curve.
            Color.black.opacity(1.0 - dismissDragProgress * 0.65)
                .ignoresSafeArea()

            // A UIKit paging collection view, not a `TabView`: a `TabView`
            // rebuilds its whole page strip on any state change, which can park
            // pages between two videos mid-swipe. See `GalleryPager`.
            GalleryPager(count: tiles.count, selection: $selection) { index in
                let tile = tiles[index]
                GalleryViewerPage(
                        tile: tile,
                        isCurrent: index == selection,
                        // Recorded per index, not filtered to current: a page
                        // builds its player while still a neighbour.
                        onPlayerReady: { player, url in
                            registry.record(player: player,
                                            url: url.absoluteString,
                                            at: index,
                                            isCurrent: index == selection)
                            // Only the current page adopts the shared unmute;
                            // a neighbour would otherwise become briefly audible.
                            player.isMuted =
                                (index == selection)
                                ? GalleryMuteStore.isMuted : true
                            // A resolver page can register after the swipe
                            // that made it current, so sync here too.
                            if index == selection { syncPlayback() }
                        },
                        // No per-page tap: the container recognizer owns it, and a per-page
                        // tap would double-toggle the chrome.
                        onSurfaceTapped: nil,
                        // No per-page vertical swipe; the viewer owns one
                        // pan above the pager (`swipeCatcher`), Reborn's shape too.
                        onVerticalSwipe: nil)
            }
            .ignoresSafeArea()
            .offset(y: dismissDragOffset)
            // The swipe lives on a transparent layer above the `TabView`:
            // a gesture on the page content never fires because the
            // TabView's own scroll view claims the drag first. See
            // `GalleryVerticalSwipeCatcher`.
            swipeCatcher

            chrome
        }
        .statusBarHiddenIfAvailable()
        // Nothing should keep playing after the viewer closes; a SwiftUI
        // page keeps its player alive until ARC frees it otherwise.
        .onDisappear {
            VideoPlayerCache.shared.pauseAll()
            VideoAudioSession.releaseAll()
        }
        // A sheet over the still-live media, not a push, matching Reborn's own comments pane.
        .sheet(item: $commentsPost) { post in
            NavigationStack {
                CommentTreeScreen(subreddit: post.subreddit,
                                  postID: post.id,
                                  repository: repository)
            }
            // Themed background when Reduce Transparency or a gallery theme
            // is active, glass otherwise, matching Reborn's own comments pane.
            .presentationBackgroundIfThemed(apolloTheme.color(.background))
            .presentationDetentsIfAvailable()
        }
        // Free players outside Reborn's prefetch window (current page +/- 1).
        // `onDisappear` can't do this since a `TabView` keeps all pages
        // mounted. Deferred past the swipe settling so eviction doesn't
        // rewrite `@State` mid-flight and stall the pager.
        .task(id: selection) {
            // Asserted immediately: a video should start as its page lands.
            syncPlayback()
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            evictDistantPlayers()
        }
        .task(id: registry.generation) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            evictDistantPlayers()
        }
        .onChange(of: selection) { _ in
            // Hidden state is per item, so paging brings the card back.
            infoHiddenForItem = false
            registry.selectionChanged(to: selection)
            applyChromeForCurrentItem(animated: false)
        }
        .onAppear {
            guard !didApplyInitialChrome else { return }
            didApplyInitialChrome = true
            applyChromeForCurrentItem(animated: false)
        }
    }

    /// Up opens comments (Reborn's `SwipeUpForComments`, default YES),
    /// down dismisses. Dismissal uses a distance-OR-velocity commit
    /// rule so a fast short flick still registers.
    private func handleVerticalSwipe(verticalDistance dy: CGFloat, horizontalDistance dx: CGFloat, verticalVelocity vy: CGFloat = 0) {
        guard abs(dy) > abs(dx) else { return }
        if dy < 0 {
            guard generalSettings.swipeUpForComments else { return }
            guard -dy >= Self.upwardCommentsDistance else { return }
            if let currentPost { commentsPost = currentPost }
        } else if dy >= Self.dismissDistance || vy >= Self.dismissVelocity {
            dismiss()
        }
    }

    private static let upwardCommentsDistance: CGFloat = 72
    private static let dismissDistance: CGFloat = 120
    private static let dismissVelocity: CGFloat = 850

    /// Background dim progress, normalized 0...1 over the dismiss distance.
    private var dismissDragProgress: CGFloat {
        guard isDismissDragging else { return 0 }
        return min(abs(dismissDragOffset) / 400, 1)
    }

    /// A transparent layer that owns the vertical swipe, since the
    /// `TabView` beneath won't let its pages have it. Horizontal drags
    /// are not claimed so the pager's own paging still works: the
    /// gesture only commits when more vertical than horizontal.
    private var swipeCatcher: some View {
        // A UIKit pan recognizer, not a SwiftUI `DragGesture`: a
        // `DragGesture` claims every drag with no hook to decline after
        // starting, which breaks left-right paging.
        GalleryVerticalSwipeCatcher(
            onTap: {
                withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
            },
            // Live, every `.changed`, so the pager/background follow the finger.
            onDismissPanChanged: { dy in
                isDismissDragging = true
                dismissDragOffset = dy
            },
            onVerticalSwipeEnded: { dy, dx, vy in
                isDismissDragging = false
                handleVerticalSwipe(verticalDistance: dy, horizontalDistance: dx, verticalVelocity: vy)
                // Snap back only for the "let go, stayed" case; dismiss() above
                // already tears the screen down on commit.
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    dismissDragOffset = 0
                }
            },
            onDismissPanCancelled: {
                isDismissDragging = false
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    dismissDragOffset = 0
                }
            },
            // Hold-and-drag scrub; nil on a still so the catcher never arms.
            scrubDuration: { currentIsVideo ? (currentPlayer?.currentItem?.duration).flatMap { $0.isNumeric && $0.seconds.isFinite && $0.seconds > 0 ? $0.seconds : nil } : nil },
            onScrubBegan: {
                guard let player = currentPlayer else { return 0 }
                gestureScrubWasPlaying = player.rate > 0
                let seconds = player.currentTime().seconds
                gestureScrubStartTime = (seconds.isFinite && seconds >= 0) ? seconds : 0
                gestureScrubActive = true
                transportClock.isScrubbing = true
                transportClock.scrubTime = gestureScrubStartTime
                player.pause()
                Haptics.selection()
                return gestureScrubStartTime
            },
            onScrubChanged: { fraction, duration in
                guard gestureScrubActive else { return }
                let target = max(0, min(duration, gestureScrubStartTime + fraction * duration))
                transportClock.scrubTime = target
                currentPlayer?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            },
            onScrubEnded: {
                guard gestureScrubActive else { return }
                gestureScrubActive = false
                transportClock.isScrubbing = false
                let resume = gestureScrubWasPlaying
                let target = transportClock.scrubTime
                guard let player = currentPlayer else { return }
                player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                    guard finished, resume else { return }
                    DispatchQueue.main.async { player.play() }
                }
            },
            onHoldForSpeed: { holding in
                guard let player = currentPlayer, VideoHoldSpeedStore.load().isEnabled else { return }
                if holding {
                    holdSpeedRestoreRate = player.rate == 0 ? 1 : player.rate
                    player.rate = VideoHoldSpeedStore.load().holdSpeed
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.15)) { holdingForSpeed = true }
                } else {
                    player.rate = holdSpeedRestoreRate
                    withAnimation(.easeInOut(duration: 0.15)) { holdingForSpeed = false }
                }
            },
            chromeRegions: { chromeVisible ? chromeTouchRegions : [] })
            .overlay {
                if holdingForSpeed {
                    GeometryReader { geo in
                        Text(VideoHoldSpeedStore.load().holdSpeed.formatted() + "\u{00D7}")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .position(x: geo.size.width * 5 / 6, y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
            }
            // A `UIViewRepresentable` has no intrinsic size; without
            // this the view is 0x0 and its recognizers never see a
            // touch at all.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .accessibilityIdentifier("galleryViewer.surface")
    }

    /// The rects the chrome occupies, in window coordinates.
    @State private var chromeTouchRegions: [CGRect] = []

    /// Every live player takes the shared mute state, so unmuting one
    /// page carries to the next, but only the current page is audible.
    private func applyMuteToAllPlayers() {
        let muted = GalleryMuteStore.isMuted
        for (index, player) in registry.players {
            player.isMuted = (index == selection) ? muted : true
        }
    }

    /// Reborn's prefetch radius: current page plus one either side.
    private static let playerRetentionRadius = 1

    /// Stops every player outside that window from decoding.
    ///
    /// ARC frees a player once its view is dropped; this only silences
    /// ones still mounted but off-screen. Matches Reborn's own sync
    /// pass: current page plays, every other page pauses.
    ///
    /// The player view starts on `.task(id:)`, which can land after
    /// eviction pauses it. Re-asserting play for the current page here
    /// removes that ordering dependency, matching Reborn's own re-sync.
    private func syncPlayback() {
        // Every other page is stopped and silenced first, immediately.
        // `evictDistantPlayers` only pauses players outside the
        // prefetch radius; the sync pass here is unconditional.
        for (index, player) in registry.players where index != selection {
            player.pause()
            player.isMuted = true
        }
        guard let current = registry.players[selection] else { return }
        // The current page always gets the shared mute state back,
        // regardless of autoplay: `pauseAllExcept` above mutes every
        // other player, and this un-mutes the one page that should be.
        current.isMuted = GalleryMuteStore.isMuted
        guard VideoAutoplayPolicy.shouldAutoplay(
            mode: generalSettings.autoplayMode) else { return }
        if current.rate == 0 {
            current.play()
        }
    }

    private func evictDistantPlayers() {
        // Nothing to pause until the current page has registered its
        // own URL: a resolver page registers only after its async
        // lookup lands, so the current page can be briefly absent.
        guard let currentURL = registry.urls[selection] else { return }
        var keep: Set<String> = [currentURL]
        for index in registry.players.keys
        where abs(index - selection) <= Self.playerRetentionRadius {
            if let url = registry.urls[index] {
                keep.insert(url)
            }
        }
        VideoPlayerCache.shared.pauseAllExcept(keep)
        // Re-assert the current page, since the pause above would otherwise silence it.
        syncPlayback()
    }

    /// A video page opens with the chrome down; a still picture keeps
    /// it up.
    private func applyChromeForCurrentItem(animated: Bool) {
        guard currentIsVideo else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = false }
        } else {
            chromeVisible = false
        }
    }

    @ViewBuilder
    private var chrome: some View {
        VStack(spacing: 0) {
            topRow
            Spacer(minLength: 0)
            bottomStack
        }
        .padding(.horizontal, Self.sideInset)
        .padding(.top, Self.topInset)
        .padding(.bottom, Self.bottomInset)
        // Fades out the instant a dismiss drag starts, independent of
        // `chromeVisible`, matching Reborn's own dismiss-begin case.
        .opacity((chromeVisible && !isDismissDragging) ? 1 : 0)
        // Hiding the chrome also stops it taking touches.
        .allowsHitTesting(chromeVisible && !isDismissDragging)
    }

    private var topRow: some View {
        HStack(spacing: Self.controlGap) {
            // "Done", not an X (the post pager uses an X).
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.doneWidth, height: Self.controlHeight)
            }
            .background(chromeCapsule)
            .accessibilityIdentifier("galleryViewer.done")

            Spacer(minLength: 0)

            // "N / M" over the whole loaded feed, not just this post's
            // own gallery: a running position rather than restarting at
            // every batch boundary.
            Text("\(selection + 1) / \(tiles.count)")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: Self.counterWidth, height: Self.controlHeight)
                .background(chromeCapsule)
                .accessibilityIdentifier("galleryViewer.counter")

            // Only shown while a video/GIF page is up.
            if currentIsVideo {
                Button {
                    // One flag for the whole viewer, persisted and
                    // applied to every page's player. See `GalleryMuteStore`.
                    GalleryMuteStore.isMuted.toggle()
                    transportClock.isMuted = GalleryMuteStore.isMuted
                    applyMuteToAllPlayers()
                    if GalleryMuteStore.isMuted {
                        VideoAudioSession.release("gallery.viewer")
                    } else {
                        VideoAudioSession.claim("gallery.viewer")
                    }
                } label: {
                    // Its own view, so the clock's ticks redraw this glyph, not the whole screen.
                    GalleryMuteGlyph(clock: transportClock)
                        // Square, so the capsule renders as a circle.
                        .frame(width: Self.controlHeight, height: Self.controlHeight)
                }
                .background(chromeCapsule)
                .accessibilityIdentifier("galleryViewer.mute")
            }

            if let currentPost, let urlString = currentPost.url, let url = URL(string: urlString) {
                // Reborn's menu (5-6 items depending on media kind):
                // Save Video/Image, Share Video/Image Link, Share Post
                // Link, Open Post, Show/Hide Info.
                Menu {
                    if currentIsVideo {
                        Button {
                            Task { await saveCurrentVideo() }
                        } label: {
                            Label("Save Video", systemImage: "square.and.arrow.down")
                        }
                        if let videoURL = PostMediaKind.downloadableVideoURL(for: currentPost) ?? currentTile?.videoURL {
                            ShareLink(item: videoURL) {
                                Label("Share Video Link", systemImage: "link")
                            }
                        }
                    } else {
                        Button {
                            Task { await saveCurrentImage() }
                        } label: {
                            Label("Save Image", systemImage: "square.and.arrow.down")
                        }
                        let imageURL = currentTile?.galleryMediaID != nil ? currentTile?.fullResolutionURL : GalleryPostMedia.fullResolutionURL(for: currentPost)
                        if let imageURL {
                            ShareLink(item: imageURL) {
                                Label("Share Image Link", systemImage: "link")
                            }
                        }
                    }
                    ShareLink(item: url) {
                        Label("Share Post Link", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        dismiss()
                        onOpenPost?(currentPost)
                    } label: {
                        Label("Open Post", systemImage: "arrow.up.forward.square")
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { infoHiddenForItem.toggle() }
                    } label: {
                        Label(infoHiddenForItem ? "Show Info" : "Hide Info", systemImage: infoHiddenForItem ? "info.circle" : "info.circle.fill")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.white)
                        .frame(width: Self.controlHeight, height: Self.controlHeight)
                    .accessibilityLabel("Share")
                }
                .background(chromeCapsule)
                .accessibilityIdentifier("galleryViewer.share")
            }
        }
        // Only the bands carrying controls are refused, not the whole
        // chrome (its `VStack` spans the screen via `Spacer`).
        .measuredChromeRegion(index: 0, into: $chromeTouchRegions)
    }

    @ViewBuilder
    private var bottomStack: some View {
        VStack(alignment: .leading, spacing: Self.infoToBarGap) {
            if let saveToast {
                Text(saveToast)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .accessibilityIdentifier("galleryViewer.saveToast")
            }
            if let currentPost, !infoHiddenForItem {
                infoCard(for: currentPost, tile: currentTile)
            }
            // Shown for any video page, player or not, matching Reborn:
            // renders 0:00 with controls disabled until ready.
            if currentIsVideo {
                // The clock lives in an object owned by this screen,
                // not the bar's own `@State`, so a rebuild (paging,
                // chrome toggles, player registration) doesn't discard it.
                GalleryTransportBarHost(registry: registry,
                                        clock: transportClock)
                    .frame(height: Self.videoBarHeight)
                    .background(chromeCapsule)
                    .accessibilityIdentifier("galleryViewer.transport")
            }
        }
        // The transport takes the full width; only the card is capped.
        .frame(maxWidth: .infinity, alignment: .leading)
        .measuredChromeRegion(index: 1, into: $chromeTouchRegions)
    }

    private func infoCard(for post: RedditPost, tile: GalleryTile?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(post.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(subtitle(for: post, tile: tile))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: Self.infoMaxWidth, alignment: .leading)
        .background(
            // Glass on iOS 26, translucent black otherwise, matching
            // Reborn's own branch. Flat black is invisible over the
            // viewer's letterbox; a material still reads as a card.
            RoundedRectangle(cornerRadius: Self.infoCornerRadius, style: .continuous)
                .fill(.clear)
                .background(GalleryChromeMaterial())
                .clipShape(RoundedRectangle(cornerRadius: Self.infoCornerRadius, style: .continuous))
        )
        // Tapping it leaves the gallery for the post.
        .onTapGesture {
            dismiss()
            onOpenPost?(post)
        }
        // It swipes away sideways since vertical is spoken for
        // (swipe-to-close), so this takes horizontal.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { infoHiddenForItem = true }
                }
        )
        .accessibilityHint("Swipe sideways to hide")
        .accessibilityIdentifier("galleryViewer.infoCard")
    }

    /// `u/author · r/subreddit`, joined with " · ", plus
    /// "N of M in post" for a multi-image post.
    private func subtitle(for post: RedditPost, tile: GalleryTile?) -> String {
        var parts: [String] = []
        if !post.author.isEmpty { parts.append("u/\(post.author)") }
        if !post.subreddit.isEmpty { parts.append("r/\(post.subreddit)") }
        // "N of M in post": a gallery post's images are their own
        // pages, not one tile. The counter above covers the whole
        // loaded feed; this covers position within this post's own gallery.
        if let tile, tile.galleryCount > 1 {
            parts.append("\(tile.galleryIndex + 1) of \(tile.galleryCount) in post")
        }
        return parts.joined(separator: " · ")
    }

    /// Every overlay control sits on a translucent black capsule so it
    /// stays legible over an arbitrary photo.
    private var chromeCapsule: some View {
        Capsule()
            .fill(.clear)
            .background(GalleryChromeMaterial())
            .clipShape(Capsule())
    }
}

/// A transparent layer whose pan recognizer only begins on a mostly
/// vertical drag, leaving horizontal drags to the pager underneath.
///
/// A SwiftUI `DragGesture` can't decline after claiming a touch, which
/// breaks left/right paging; this follows Reborn's arbitration.
private struct GalleryVerticalSwipeCatcher: UIViewRepresentable {
    var onTap: () -> Void
    /// Fired on every `.changed`, dy only, driving the live-follow offset/dim.
    var onDismissPanChanged: (CGFloat) -> Void
    /// Fired once on `.ended`, with the full translation and y-velocity,
    /// so the caller can apply Reborn's distance-OR-velocity commit rule.
    var onVerticalSwipeEnded: (CGFloat, CGFloat, CGFloat) -> Void
    /// Fired on `.cancelled`/`.failed` when a system gesture steals the
    /// touch before `.ended`, so the live offset can still spring back.
    var onDismissPanCancelled: () -> Void
    /// The current page's video duration, or nil for a still. The
    /// scrub recognizer refuses to arm at all in that case.
    var scrubDuration: () -> Double?
    /// Fired once, when the scrub commits (past the movement slop).
    /// Returns the player's current position, which becomes the scrub's zero point.
    var onScrubBegan: () -> Double
    /// Fired on every scrub `.changed`, with drag fraction of screen
    /// width (matching the transport bar's own slider scale) and duration.
    var onScrubChanged: (CGFloat, Double) -> Void
    var onScrubEnded: () -> Void
    /// Hold for Video Speed: a press resting on the right third (true on
    /// start, false on lift).
    var onHoldForSpeed: (Bool) -> Void = { _ in }
    /// See `Coordinator.chromeRegions`.
    var chromeRegions: () -> [CGRect]

    func makeUIView(context: Context) -> UIView {
        // Recognizers go on an ancestor of the pager, not this view itself:
        // `hitTest` below returns nil so this view is never the hit view, and
        // UIKit only consults recognizers on the hit view and its ancestors.
        // `AncestorGestureHost` installs them at the top of this screen's
        // hierarchy while the pager still owns the touch.
        let view = AncestorGestureHost()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        // The pager still needs the touch when this one declines, and
        // cancelling would swallow it.
        pan.cancelsTouchesInView = false

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false

        // Hold-and-drag scrub. `minimumPressDuration` is set low
        // (0.05s, not the UIKit default 0.5s) so the recognizer is
        // "armed on touch-down, committed on slop" rather than timed,
        // matching Reborn's own scrub gate.
        let scrub = UILongPressGestureRecognizer(target: context.coordinator,
                                                  action: #selector(Coordinator.handleScrub(_:)))
        scrub.minimumPressDuration = 0.05
        scrub.delegate = context.coordinator
        scrub.cancelsTouchesInView = false

        view.recognizers = [pan, tap, scrub]
        context.coordinator.apply(onTap: onTap,
                                  onDismissPanChanged: onDismissPanChanged,
                                  onVerticalSwipeEnded: onVerticalSwipeEnded,
                                  onDismissPanCancelled: onDismissPanCancelled,
                                  scrubDuration: scrubDuration,
                                  onScrubBegan: onScrubBegan,
                                  onScrubChanged: onScrubChanged,
                                  onScrubEnded: onScrubEnded,
                                  onHoldForSpeed: onHoldForSpeed)
        context.coordinator.chromeRegions = chromeRegions
        return view
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        (view as? AncestorGestureHost)?.detach()
    }

    func updateUIView(_ view: UIView, context: Context) {
        // Re-captured each update, or the recognizers call into a
        // stale view's bindings.
        context.coordinator.apply(onTap: onTap,
                                  onDismissPanChanged: onDismissPanChanged,
                                  onVerticalSwipeEnded: onVerticalSwipeEnded,
                                  onDismissPanCancelled: onDismissPanCancelled,
                                  scrubDuration: scrubDuration,
                                  onScrubBegan: onScrubBegan,
                                  onScrubChanged: onScrubChanged,
                                  onScrubEnded: onScrubEnded,
                                  onHoldForSpeed: onHoldForSpeed)
        context.coordinator.chromeRegions = chromeRegions
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var onTap: (() -> Void)?
        private var onDismissPanChanged: ((CGFloat) -> Void)?
        private var onVerticalSwipeEnded: ((CGFloat, CGFloat, CGFloat) -> Void)?
        private var onDismissPanCancelled: (() -> Void)?
        private var scrubDuration: (() -> Double?)?
        private var onScrubBegan: (() -> Double)?
        private var onHoldForSpeed: ((Bool) -> Void)?
        private var holdForSpeedTimer: DispatchWorkItem?
        private var holdingForSpeed = false
        private var onScrubChanged: ((CGFloat, Double) -> Void)?
        private var onScrubEnded: (() -> Void)?
        /// The zero-point the current scrub started from, and whether
        /// it has committed past the slop.
        private var scrubStartX: CGFloat = 0
        private var scrubActive = false
        /// The chrome's rects, in window coordinates. Empty while the
        /// chrome is hidden, so a tap anywhere brings it back.
        var chromeRegions: () -> [CGRect] = { [] }

        func apply(onTap: @escaping () -> Void,
                   onDismissPanChanged: @escaping (CGFloat) -> Void,
                   onVerticalSwipeEnded: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
                   onDismissPanCancelled: @escaping () -> Void,
                   scrubDuration: @escaping () -> Double?,
                   onScrubBegan: @escaping () -> Double,
                   onScrubChanged: @escaping (CGFloat, Double) -> Void,
                   onScrubEnded: @escaping () -> Void,
                   onHoldForSpeed: @escaping (Bool) -> Void) {
            self.onHoldForSpeed = onHoldForSpeed
            self.onTap = onTap
            self.onDismissPanChanged = onDismissPanChanged
            self.onVerticalSwipeEnded = onVerticalSwipeEnded
            self.onDismissPanCancelled = onDismissPanCancelled
            self.scrubDuration = scrubDuration
            self.onScrubBegan = onScrubBegan
            self.onScrubChanged = onScrubChanged
            self.onScrubEnded = onScrubEnded
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            onTap?()
        }

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            // Live tracking on every `.changed`, matching Reborn's
            // own dismiss pan, so a real commit threshold can be felt
            // out before releasing.
            //
            // No `scrollEnabled` toggling here: declining simultaneity
            // with the pager (see `shouldRecognizeSimultaneouslyWith`)
            // means UIKit never starts both on one touch.
            guard let view = sender.view else { return }
            let translation = sender.translation(in: view)
            switch sender.state {
            case .changed:
                onDismissPanChanged?(translation.y)
            case .ended:
                let velocity = sender.velocity(in: view).y
                onVerticalSwipeEnded?(translation.y, translation.x, velocity)
            case .cancelled, .failed:
                onDismissPanCancelled?()
            default:
                break
            }
        }

        /// Hold-and-drag scrub: arm on touch-down, commit past a 12pt
        /// horizontal slop, drive the scrub by the finger's absolute fraction
        /// of screen width (not a relative delta), matching the transport
        /// bar's slider scale.
        ///
        /// On `.began`, every `UIScrollView` under this view (the ancestor
        /// host, containing the pager) is disabled before the pager's pan can
        /// claim the touch. Relying on gesture priority would let the pager's
        /// smaller built-in threshold briefly change pages before the scrub
        /// commits.
        @objc func handleScrub(_ sender: UILongPressGestureRecognizer) {
            guard let view = sender.view else { return }
            switch sender.state {
            case .began:
                scrubStartX = sender.location(in: view).x
                scrubActive = false
                // The gallery's touches all reach this recognizer, so Hold
                // for Video Speed lives here: resting on the right third for
                // a moment, before any scrub.
                if scrubDuration?() != nil, scrubStartX > view.bounds.width * 2 / 3 {
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, !self.scrubActive else { return }
                        self.holdingForSpeed = true
                        self.onHoldForSpeed?(true)
                    }
                    holdForSpeedTimer = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                }
                Self.setScrollViewsEnabled(false, in: view)
                // Safety net: guarantees paging is never left disabled
                // forever if this recognizer never reaches a terminal
                // state (e.g. a system alert or multi-finger conflict).
                scrubWatchdogGeneration &+= 1
                let generation = scrubWatchdogGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak view] in
                    guard let self, let view, self.scrubWatchdogGeneration == generation else { return }
                    Self.setScrollViewsEnabled(true, in: view)
                }
            case .changed:
                guard let duration = scrubDuration?(), duration > 0 else { return }
                let x = sender.location(in: view).x
                let deltaX = x - scrubStartX
                if holdingForSpeed { return }
                if !scrubActive {
                    guard abs(deltaX) >= 12 else { return }
                    holdForSpeedTimer?.cancel()
                    scrubActive = true
                    _ = onScrubBegan?()
                }
                let width = max(view.bounds.width, 1)
                onScrubChanged?(deltaX / width, duration)
            case .ended, .cancelled, .failed:
                holdForSpeedTimer?.cancel()
                holdForSpeedTimer = nil
                if holdingForSpeed {
                    holdingForSpeed = false
                    onHoldForSpeed?(false)
                }
                if scrubActive { onScrubEnded?() }
                scrubActive = false
                scrubWatchdogGeneration &+= 1
                Self.setScrollViewsEnabled(true, in: view)
            default:
                break
            }
        }

        /// Invalidates the `.began` watchdog once a real terminal state arrives.
        private var scrubWatchdogGeneration = 0

        /// Walks the view tree toggling every `UIScrollView`'s
        /// `isScrollEnabled`. `UICollectionView` is a subclass, so
        /// this reaches the gallery pager's collection view.
        private static func setScrollViewsEnabled(_ enabled: Bool, in root: UIView) {
            for scrollView in UIKitTree.scrollViews(in: root) {
                scrollView.isScrollEnabled = enabled
            }
        }

        /// Never claim a touch that began on the chrome.
        ///
        /// This view passes touches through (hit-test returns nil),
        /// but its recognizers still see every touch along the chain,
        /// so a tap on the mute/share button would also toggle the chrome.
        /// so this can refuse those touches while the chrome is up,
        /// matching Reborn's region-based resolution of the same conflict.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view,
                  let window = view.window
            else { return true }
            // A zoomed image's drag pans the image, not the viewer.
            if !(gestureRecognizer is UITapGestureRecognizer), ZoomingScrollView.isZoomedOnScreen { return false }
            let point = touch.location(in: window)
            return !chromeRegions().contains { $0.contains(point) }
        }

        /// Decline a horizontal drag so the pager keeps it, matching
        /// Reborn's own velocity test. Only applies to the dismiss
        /// pan; the scrub, a `UILongPressGestureRecognizer`, is always
        /// eligible to start and instead refuses to commit until its
        /// own horizontal slop clears.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            // Two fingers are a pinch.
            guard pan.numberOfTouches < 2 else { return false }
            let velocity = pan.velocity(in: view)
            return abs(velocity.y) > abs(velocity.x)
        }

        /// Simultaneous with everything except the pager's own scroll
        /// view and the scrub recognizer once it has committed.
        ///
        /// Recognizing alongside the paging scroll view lets one drag drive
        /// both, carrying a flick past the next page; declining simultaneity
        /// means UIKit picks one per touch, a single continuous move.
        ///
        /// The dismiss pan and the scrub long-press must not both
        /// drive the same touch once the scrub has committed, matching
        /// Reborn's rule that a hold-scrub owns the drag. Before commit
        /// the two stay simultaneous so the long-press can observe
        /// every touch live, as Reborn's own dismiss pan does.
        /// The chrome tap waits for an image's double-tap to fail, so a
        /// double-tap zooms without toggling the chrome twice.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UITapGestureRecognizer && other === (other.view as? ZoomingScrollView)?.doubleTap
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            let isPanVsScrub =
                (gestureRecognizer is UIPanGestureRecognizer && other is UILongPressGestureRecognizer)
                || (gestureRecognizer is UILongPressGestureRecognizer && other is UIPanGestureRecognizer)
            if isPanVsScrub { return !scrubActive }
            return !((other.view as? UIScrollView)?.isPagingEnabled ?? false)
        }
    }
}

private extension View {
    /// Reports this view's window rect into `regions[index]`, so the
    /// swipe catcher can refuse touches that land on it.
    func measuredChromeRegion(index: Int, into regions: Binding<[CGRect]>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { Self.store(proxy.frame(in: .global), at: index, into: regions) }
                    .onChange(of: proxy.frame(in: .global)) { rect in
                        Self.store(rect, at: index, into: regions)
                    }
            }
        }
    }

    static func store(_ rect: CGRect, at index: Int, into regions: Binding<[CGRect]>) {
        var value = regions.wrappedValue
        while value.count <= index { value.append(.zero) }
        guard value[index] != rect else { return }
        value[index] = rect
        regions.wrappedValue = value
    }
}

/// The mute button's glyph, isolated so the transport clock's 4Hz
/// ticks redraw only this and not the whole viewer.
private struct GalleryMuteGlyph: View {
    @ObservedObject var clock: GalleryTransportClock

    var body: some View {
        Image(systemName: clock.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .foregroundStyle(.white)
    }
}

/// The chrome's backing material.
///
/// Reborn backs every pill and the info card with a glass effect on
/// newer OS versions, and older builds fall back to translucent
/// black, which is what stays legible over an arbitrary photo. A dark
/// system material is the closest public equivalent, and unlike
/// SwiftUI's `.ultraThinMaterial` it does not pick up the app's
/// accent tint, which would turn the video panel purple.
private struct GalleryChromeMaterial: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {}
}

extension View {
    /// Paints the sheet in the user's theme background, on the same
    /// rule Reborn uses to choose between glass and Apollo's stock
    /// opaque backgrounds: glass is skipped entirely under Reduce
    /// Transparency.
    ///
    /// A gallery theme counts too: the point of picking one is that
    /// screens adopt it, and a glass pane over the media ignores it
    /// entirely.
    /// `nil` leaves the system default rather than forcing black.
    @ViewBuilder
    func presentationBackgroundIfThemed(_ color: Color?) -> some View {
        if #available(iOS 16.4, *), let color {
            self.presentationBackground(color)
        } else {
            self
        }
    }
}

/// One page: a still image, or a video that plays inline.
///
/// Takes the flattened `GalleryTile`, not a bare `RedditPost`: a
/// gallery post's 2nd..Nth images have no representation as a
/// `RedditPost` at all, only as entries inside one post's
/// `media_metadata`. A gallery tile always renders as a still, since
/// Gallery View's own gallery-image tiles are always image/animated
/// image, never video; a non-gallery tile falls through to the same
/// post-level `PostMediaKind` classification the post pager uses.
private struct GalleryViewerPage: View {
    let tile: GalleryTile
    let isCurrent: Bool
    var onPlayerReady: ((AVPlayer, URL) -> Void)?
    var onSurfaceTapped: (() -> Void)?
    var onVerticalSwipe: ((CGFloat, CGFloat) -> Void)?

    private var post: RedditPost { tile.post }

    var body: some View {
        pageGestures(pageContent)
    }

    @ViewBuilder
    private var pageContent: some View {
        // A flattened gallery image is always a still (see this type's doc comment).
        if tile.galleryMediaID != nil {
            stillImage
        } else {
            nonGalleryPageContent
        }
    }

    @ViewBuilder
    private var nonGalleryPageContent: some View {
        // Full resolution, not the grid's thumbnail. Every non-video
        // kind (RedGifs, Streamable, gfycat, sports clips) resolves
        // its stream asynchronously via the same resolver views the
        // post screen uses.
        switch PostMediaKind.classify(post: post) {
        case .video(let url):
            videoPlayer(url: url)
        case .gif(let url):
            // A GIF-as-mp4 plays; a real animated .gif animates
            // through the image path instead.
            if url.pathExtension.lowercased() == "gif" {
                stillImage
            } else {
                videoPlayer(url: url)
            }
        case .redgifs(let id), .gfycat(let id):
            // No fullscreen of its own: this screen is fullscreen.
            RedGifsVideoView(gifID: id, unmuteContext: .fullscreen,
                             suppressesOwnFullscreen: true,
                             onPlayerReady: onPlayerReady,
                             isCurrentPage: isCurrent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .streamable(let id):
            StreamableVideoView(videoID: id, unmuteContext: .fullscreen,
                                suppressesOwnFullscreen: true,
                                onPlayerReady: onPlayerReady,
                                isCurrentPage: isCurrent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sportsClip(let pageURL):
            SportsClipView(pageURL: pageURL, suppressesOwnFullscreen: true,
                           onPlayerReady: onPlayerReady,
                           isCurrentPage: isCurrent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            stillImage
        }
    }

    /// The gestures belong to the whole page, not just the drawn
    /// media, so a letterboxed photo's black background is still tappable.
    fileprivate func pageGestures<V: View>(_ content: V) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Neither tap nor drag lives here: with the container pan
            // firing, a tap here would double-toggle chrome. Reborn
            // attaches one tap and one pan to the container, nothing
            // to the cell.
            //
            // A `.highPriorityGesture(DragGesture)` here would outrank
            // the pager's scroll view, letting a paging drag be
            // claimed mid-flight and parking the page between two videos.
    }

    private func videoPlayer(url: URL) -> some View {
        MutedVideoPlayerView(
            url: url,
            unmuteContext: .fullscreen,
            // Hold for Video Speed is the screen's own scrub recognizer
            // here (`onHoldForSpeed`): the player's never gets the touch.
            initialAspectRatio: post.media?.redditVideo?.aspectRatio.map { CGFloat($0) },
            fillsContainer: true,
            // The viewer draws its own transport bar, so the player must not add one...
            floatsControlPanel: false,
            // ...and must draw no inline chrome either: the speedometer
            // and mute badge are gated on `floatsControlPanel`, which
            // the post pager sets and this screen does not.
            hostedByFullscreenViewer: true,
            isCurrentPage: isCurrent,
            onSurfaceTapped: onSurfaceTapped,
            onVerticalSwipe: onVerticalSwipe,
            onPlayerReady: onPlayerReady)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var stillImage: some View {
        // Full resolution, not the grid's thumbnail; falls back to the
        // post-level lookup for a non-gallery tile.
        if let url = tile.galleryMediaID != nil ? tile.fullResolutionURL : GalleryPostMedia.fullResolutionURL(for: post) {
            // Pinch and double-tap zoom, as the post viewer's. The tap and
            // dismiss pan stay with the screen's own recognizers.
            ZoomableImageView(url: url, liveText: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.black
        }
    }

}

/// The viewer's own transport bar.
///
/// Its layout is Reborn's, not `VideoControlPanel`'s: play/pause,
/// back-15, forward-15, elapsed time, scrubber, duration, one row, 44pt tall.
///
/// The transport bar's playback state, a class rather than `@State`
/// since the bar is rebuilt by every render of the viewer, and a
/// rebuilt view resets `@State` to its initial value, dropping the
/// elapsed time the periodic observer had just written.
@MainActor
final class GalleryTransportClock: ObservableObject {
    @Published var isPlaying = true
    /// The current player's mute state, refreshed by the periodic
    /// observer so the chrome's glyph cannot drift from the video.
    @Published var isMuted = GalleryMuteStore.isMuted
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isScrubbing = false
    @Published var scrubTime: Double = 0
    /// The observer and the exact player it was added to: AVPlayer
    /// can't remove an observer added by a different player instance,
    /// and this clock can outlive the player it started observing.
    var timeObserver: Any?
    weak var observedPlayer: AVPlayer?
}

private struct GalleryVideoTransportBar: View {
    /// Optional: the bar appears with the page while the stream may
    /// still be resolving. Reborn renders exactly this state: zeroed
    /// times, controls disabled.
    let player: AVPlayer?

    /// Owned by the screen, so a rebuild of this view cannot reset it.
    @ObservedObject var clock: GalleryTransportClock

    private static let buttonSize: CGFloat = 36
    private static let buttonGap: CGFloat = 2
    private static let edgePadding: CGFloat = 8
    private static let timeWidth: CGFloat = 44
    private static let skipSeconds: Double = 15

    var body: some View {
        HStack(spacing: 0) {
            Button {
                guard let player else { return }
                // Assert the intent and let the periodic observer
                // confirm it a quarter-second later: reading
                // `player.rate` right after `play()` is unreliable
                // (not yet taken effect), and toggling `clock.isPlaying`
                // straight from that would make the glyph disagree with the
                // video on a stall or loop restart.
                if player.rate > 0 {
                    player.pause()
                    clock.isPlaying = false
                } else {
                    player.play()
                    clock.isPlaying = true
                }
            } label: {
                Image(systemName: clock.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                .accessibilityLabel(clock.isPlaying ? "Pause" : "Play")
            }
            .disabled(player == nil)
            .accessibilityIdentifier("galleryViewer.playPause")
            .padding(.trailing, Self.buttonGap)

            Button { skip(by: -Self.skipSeconds) } label: {
                Image(systemName: "gobackward.15")
                    .foregroundStyle(.white)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                .accessibilityLabel("Back 15 Seconds")
            }
            .disabled(player == nil)
            .accessibilityIdentifier("galleryViewer.back15")
            .padding(.trailing, Self.buttonGap)

            Button { skip(by: Self.skipSeconds) } label: {
                Image(systemName: "goforward.15")
                    .foregroundStyle(.white)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                .accessibilityLabel("Forward 15 Seconds")
            }
            .disabled(player == nil)
            .accessibilityIdentifier("galleryViewer.forward15")

            if let player {
                // Read every frame, so the time moves with the video and
                // follows a hold-and-drag scrub at once.
                VideoLiveTime(player: player) { seconds in
                    timeAndScrubber(clock.isScrubbing ? clock.scrubTime : seconds, player: player)
                }
            } else {
                timeAndScrubber(0, player: nil)
            }

            Text(Self.timeString(clock.duration))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: Self.timeWidth)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, Self.edgePadding)
        // `.task(id:)`, not `onAppear`/`onDisappear`: this view is
        // rebuilt by every render of the viewer, and onDisappear from
        // one rebuild would remove the observer the next had just added.
        .task(id: player.map(ObjectIdentifier.init)) {
            startObserving()
        }
    }

    /// One row: `VideoLiveTime` would otherwise stack the two.
    private func timeAndScrubber(_ shown: Double, player: AVPlayer?) -> some View {
        HStack(spacing: 0) {
        Text(Self.timeString(shown))
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: Self.timeWidth)
            .padding(.leading, 6)

        Slider(
            value: Binding(
                get: { shown },
                set: {
                    clock.scrubTime = $0
                    if let player { VideoScrubSession.shared(for: player).scrub(to: $0) }
                }
            ),
            in: 0...max(clock.duration, 0.1),
            onEditingChanged: { editing in
                if editing { clock.scrubTime = shown }
                clock.isScrubbing = editing
                if !editing, let player {
                    VideoScrubSession.shared(for: player).end(at: clock.scrubTime)
                }
            }
        )
        .tint(.white)
        // The slider needs a player and a known clock.duration.
        .disabled(player == nil || clock.duration <= 0)
        .padding(.horizontal, 6)
        .accessibilityIdentifier("galleryViewer.scrubber")
        }
    }

    private func skip(by seconds: Double) {
        guard let player else { return }
        let target = max(0, min(clock.duration, clock.currentTime + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func startObserving() {
        guard let player else { return }
        // Never stack two observers on one player, and never leave the
        // previous player's observer behind.
        stopObserving()
        clock.observedPlayer = player
        clock.isPlaying = player.rate > 0
        clock.timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            clock.currentTime = time.seconds
            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite, itemDuration > 0 {
                clock.duration = itemDuration
            }
            clock.isPlaying = player.rate > 0
            // Reconcile the mute glyph from the player, four times a
            // second, for the same reason play/pause reads `rate`:
            // anything that changes `isMuted` without going through
            // the button would otherwise leave the icon lying.
            if clock.isMuted != player.isMuted {
                clock.isMuted = player.isMuted
            }
        }
    }

    private func stopObserving() {
        // Removed from the player that added it. Using `player` here
        // would crash because the clock can outlive individual players.
        if let observer = clock.timeObserver, let owner = clock.observedPlayer {
            owner.removeTimeObserver(observer)
        }
        clock.timeObserver = nil
        clock.observedPlayer = nil
    }

    /// Delegates to `PhoebusCore` so the smoke test exercises the real
    /// formatter.
    static func timeString(_ seconds: Double) -> String {
        GalleryTimeFormat.string(seconds)
    }
}


/// Every page's player, by index.
///
/// A reference type the screen holds without observing, so recording a
/// player, which happens while the page is still a neighbour during
/// the drag that is paging towards it, cannot rebuild the `TabView`
/// mid-gesture and leave it parked between two pages.
@MainActor
final class GalleryPlayerRegistry: ObservableObject {
    private(set) var players: [Int: AVPlayer] = [:]
    /// The URL each page ended up playing, which is the cache's key.
    /// Recorded separately because a resolver view settles on its URL
    /// only after an async lookup.
    private(set) var urls: [Int: String] = [:]
    /// Bumped on every registration, so the screen can still schedule
    /// eviction with `.task(id:)` without observing the dictionaries.
    private(set) var generation = 0
    /// The only published value: the current page's player, which the
    /// transport bar binds to. Published because the bar must pick up
    /// a resolver's player when it arrives after the swipe.
    @Published private(set) var currentPlayer: AVPlayer?

    func record(player: AVPlayer, url: String, at index: Int, isCurrent: Bool) {
        players[index] = player
        urls[index] = url
        generation &+= 1
        if isCurrent { currentPlayer = player }
    }

    /// Called when the page settles, since `currentPlayer` is
    /// otherwise only refreshed by a registration.
    func selectionChanged(to index: Int) {
        currentPlayer = players[index]
    }
}

/// Observes the registry so the transport bar can rebind, without the
/// viewer itself observing it.
private struct GalleryTransportBarHost: View {
    @ObservedObject var registry: GalleryPlayerRegistry
    @ObservedObject var clock: GalleryTransportClock

    var body: some View {
        GalleryVideoTransportBar(player: registry.currentPlayer, clock: clock)
    }
}
