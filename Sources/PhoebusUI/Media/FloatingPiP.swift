import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
import AVFoundation
import AVKit

/// Reborn's floating in-app Picture-in-Picture ("Enable In-App PiP"): video
/// playback continues in a miniplayer as you scroll through comments.
///
/// - A playing post video scrolled out of view on the comments page keeps
///   playing in a floating card that hosts a second `AVPlayerLayer` on the
///   same `AVPlayer`; scrolling back hides the card.
/// - The card lives in its own passthrough window above the app; only the
///   card takes touches.
/// - Size is an area calibrated so a 16:9 video is half the screen wide,
///   kept across aspect ratios (min width 150, 10pt edge margin, height
///   capped at half the screen). Double-tap toggles the large (0.82)
///   footprint.
/// - Drag anywhere; a release under 250pt/s stays put, a fling projects
///   with a 0.99 deceleration rate. Dragging past an edge or a >300pt/s
///   horizontal fling tucks the card away, leaving an 18pt sliver with a
///   chevron.
/// - Pinch resizes; tap shows controls (close, settings, mute, play/pause,
///   optional skip buttons and progress strip) that hide after 3s. A GIF
///   card hides mute.
/// - Default Position is a corner or Last Position; Start Hidden tucks a
///   corner card away.
/// - Activation: All Videos, Unmuted Videos Only, All Videos & GIFs
///   (`PictureInPicturePolicy`).
/// - The card floats over forward navigation; a back-pop off its post hands
///   the picture back to the post's feed row if it's on screen, otherwise
///   closes it.
/// - "Enable PiP When Leaving App" hands the card, or an inline video that
///   could have become one, to the system PiP window.
/// - The fullscreen viewer's PiP button sends its video to the card.
@MainActor
final class FloatingPiPController: NSObject {
    static let shared = FloatingPiPController()

    // Reborn's geometry.
    static let minWidth: CGFloat = 150
    static let edgeMargin: CGFloat = 10
    static let defaultLandscapeFraction: CGFloat = 0.5
    static let largeLandscapeFraction: CGFloat = 0.82
    static let referenceAspect: CGFloat = 16.0 / 9.0
    static let stashVisibleWidth: CGFloat = 18
    static let flingVelocity: CGFloat = 250
    static let stashVelocity: CGFloat = 300
    static let controlsAutoHide: TimeInterval = 3

    private(set) var player: AVPlayer?
    private(set) var ownerID: String?
    /// The post screen that owns the card's video; its closing is a
    /// back-pop (see `floatingPiPScreenScope`).
    private(set) var ownerScreenID: UUID?
    /// A silent GIF: always loops, no mute control, and closing leaves
    /// it playing inline.
    private(set) var isGIFContent = false
    /// Sent here from the fullscreen viewer: no inline home by design, so
    /// scrolling and back-pops leave it be.
    private(set) var fromFullscreen = false
    private var aspect: CGFloat = 16.0 / 9.0
    private var window: PassthroughWindow?
    private var card: UIView?
    private var playerLayer: AVPlayerLayer?
    private var layerView: PlayerLayerView?
    private var overlay: UIView?
    private var stashHandle: UIImageView?
    private var playButton: UIButton?
    private var muteButton: UIButton?
    private var settingsButton: UIButton?
    private var closeButton: UIButton?
    private var skipBack: UIButton?
    private var skipForward: UIButton?
    private var progressTrack: UIView?
    private var progressFill: UIView?
    private var stashedSide = 0
    private var hideTimer: Timer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var pinchStartWidth: CGFloat = 0
    private var settings = PictureInPictureSettings()
    /// The card's own system-PiP controller, present only with "Enable PiP
    /// When Leaving App" on.
    private var nativePiP: AVPictureInPictureController?

    var isShowing: Bool { card?.isHidden == false }

    /// The card's own holder id for the audio session: it holds a claim
    /// while it presents an audible player, whoever showed it before.
    static let audioHolder = "pip.card"

    /// Whether the card has this player: a view letting go of it must
    /// not pause it.
    func owns(_ player: AVPlayer) -> Bool {
        isShowing && self.player === player
    }

    private let lastCenterXKey = "PictureInPictureLastCenterX"
    private let lastCenterYKey = "PictureInPictureLastCenterY"
    private let areaKey = "PictureInPictureAreaFraction"
    private let stashKey = "PictureInPictureLastStashSide"

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        // Queued to main: a setting saved by a background refresh (the
        // block list, the mature-media pref) posts off the main thread,
        // and this controller is main-actor.
        NotificationCenter.default.addObserver(forName: .apolloSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateArmingTimer() }
        }
        updateArmingTimer()
    }

    /// System PiP must already be armed, with its session claimed and the
    /// controller ready, when the app leaves: arming in willResignActive is too
    /// late to start. A light poll keeps it armed, only while system PiP is
    /// switched on.
    private var armingTimer: Timer?

    private func updateArmingTimer() {
        let wanted = PictureInPictureSettingsStore.load().systemEnabled
        guard wanted != (armingTimer != nil) else { return }
        armingTimer?.invalidate()
        armingTimer = nil
        guard wanted else {
            InlineSystemPiP.disarmAll()
            return
        }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { FloatingPiPController.shared.refreshSystemPiP() }
        }
        RunLoop.main.add(timer, forMode: .common)
        armingTimer = timer
    }

    /// Keeps exactly one system PiP source armed: the card when it shows,
    /// else the best inline candidate.
    func refreshSystemPiP() {
        guard UIApplication.shared.applicationState == .active else { return }
        if isShowing, nativePiP != nil, let player, player.timeControlStatus != .paused {
            InlineSystemPiP.disarmAll()
            SystemPiPAudio.claim(muted: player.isMuted || isGIFContent)
            return
        }
        InlineSystemPiP.armBestCandidate(cardIsShowing: isShowing)
    }

    // MARK: Activation

    /// Whether a video scrolled away should hand over to the card.
    static func shouldActivate(settings: PictureInPictureSettings, isPlaying: Bool, isMuted: Bool, isGIF: Bool) -> Bool {
        PictureInPicturePolicy.shouldActivate(settings: settings, isPlaying: isPlaying, isMuted: isMuted, isSilent: isGIF)
    }

    /// Whether the item is known to have no sound. Only a progressive file
    /// whose tracks are loaded can say so: an HLS stream (how Reddit and
    /// Streamable serve video) carries its audio muxed into the segments and
    /// lists no audio track, so reading that as silent would keep every such
    /// video out of Unmuted Only and All Videos. Unknown means "has sound";
    /// GIFs are marked silent by their call site.
    static func isKnownSilent(_ player: AVPlayer) -> Bool {
        guard let item = player.currentItem, item.status == .readyToPlay,
              let asset = item.asset as? AVURLAsset,
              asset.url.pathExtension.lowercased() != "m3u8" else { return false }
        let tracks = item.tracks.compactMap { $0.assetTrack?.mediaType }
        return !tracks.isEmpty && !tracks.contains(.audio)
    }

    func show(player: AVPlayer, owner: String, aspectRatio: CGFloat, isGIF: Bool = false,
              screenID: UUID? = nil, fromFullscreen: Bool = false) {
        settings = PictureInPictureSettingsStore.load()
        if ownerID != owner || self.player !== player { stopObserving() }
        self.player = player
        ownerID = owner
        ownerScreenID = screenID
        isGIFContent = isGIF
        self.fromFullscreen = fromFullscreen
        // The view that showed this player lets go of its claim as it
        // leaves; an audible card needs its own.
        if !player.isMuted { VideoAudioSession.claim(Self.audioHolder) }
        aspect = max(0.1, aspectRatio)
        buildIfNeeded()
        guard let card, let window else { return }
        if playerLayer?.player !== player { installPlayerLayer(in: card) }
        playerLayer?.player = player
        if card.isHidden {
            let size = spawnSize()
            card.bounds = CGRect(origin: .zero, size: size)
            placeAtSpawn(size: size)
            card.isHidden = false
            card.alpha = 0
            card.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            UIView.animate(withDuration: 0.25) {
                card.alpha = 1
                card.transform = .identity
            }
        }
        window.isHidden = false
        setupNativePiP()
        startObserving()
        syncControls()
    }

    /// The inline video is visible again: hand the picture back, still
    /// playing.
    func hide(owner: String) {
        guard ownerID == owner, !fromFullscreen, let card, !card.isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: { card.alpha = 0 }) { _ in
            self.teardown()
        }
    }

    /// A fullscreen-origin card whose video's feed row came on screen.
    /// The card plays its own player, so the row's live one wins and the
    /// card closes (Reborn's same-post dedupe).
    func restoreFullscreenCard(toHome owner: String) {
        guard fromFullscreen, ownerID == owner, isShowing else { return }
        close()
    }

    /// Close button: stop playback and dismiss. A GIF is left playing inline
    /// since it's silent and loops.
    func close() {
        // A fullscreen-origin card's player is its own: nothing inline
        // shows it, so it always stops.
        if let player, !isGIFContent || fromFullscreen {
            player.pause()
            player.isMuted = true
        }
        teardown()
    }

    /// The fullscreen viewer took the card's own player: it owns playback
    /// now, so the card goes without stopping it.
    func yield(to player: AVPlayer, url: URL) {
        guard isShowing else { return }
        if self.player === player { teardown(); return }
        // The viewer reopened on a fullscreen-origin card's video, which
        // plays on its own player: close the card rather than play twice.
        if fromFullscreen, ownerID == url.absoluteString { close() }
    }

    /// The card's post screen closed. Forward navigation keeps the
    /// screen alive, so this only fires on a back-pop; give the feed a
    /// beat to lay out, then restore into its row or close.
    func screenClosed(_ screenID: UUID) {
        guard isShowing, ownerScreenID == screenID, let owner = ownerID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard self.isShowing, self.ownerID == owner else { return }
            switch PictureInPicturePolicy.backPop(homeVisible: FloatingPiPHomes.isVisible(owner),
                                                  fromFullscreen: self.fromFullscreen) {
            case .restoreInline: self.hide(owner: owner)
            case .close: self.close()
            case .keep: break
            }
        }
    }

    /// Inline looping is the card's call while it presents: Loop Videos off
    /// stops a video at its end.
    func suppressesInlineLoop(for player: AVPlayer) -> Bool {
        isShowing && self.player === player
            && !PictureInPicturePolicy.loops(isGIF: isGIFContent, settings: settings)
    }

    private func teardown() {
        stopObserving()
        destroyNativePiP()
        hideControls()
        card?.isHidden = true
        card?.alpha = 1
        card?.transform = .identity
        window?.isHidden = true
        playerLayer?.player = nil
        player = nil
        ownerID = nil
        ownerScreenID = nil
        isGIFContent = false
        fromFullscreen = false
        VideoAudioSession.release(Self.audioHolder)
    }

    // MARK: System PiP

    /// "Enable PiP When Leaving App": the card's layer gets a system PiP
    /// controller that starts on its own when the app backgrounds.
    private func setupNativePiP() {
        guard settings.systemEnabled, AVPictureInPictureController.isPictureInPictureSupported(),
              nativePiP == nil, let playerLayer else { return }
        let controller = AVPictureInPictureController(playerLayer: playerLayer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        controller?.delegate = self
        nativePiP = controller
    }

    private func destroyNativePiP() {
        if nativePiP?.isPictureInPictureActive == true { nativePiP?.stopPictureInPicture() }
        nativePiP = nil
    }

    /// System PiP needs an active Playback session to start, even for a muted
    /// card; a muted one mixes so it never stops other apps' audio.
    @objc private func willResignActive() {
        refreshSystemPiP()
    }

    // MARK: Geometry

    private var bounds: CGRect { window?.bounds ?? UIScreen.main.bounds }
    private var insets: UIEdgeInsets { window?.safeAreaInsets ?? .zero }

    func cardSize(forWidth width: CGFloat) -> CGSize {
        Self.cardSize(forWidth: width, aspect: aspect, bounds: bounds.size)
    }

    static func cardSize(forWidth width: CGFloat, aspect: CGFloat, bounds: CGSize) -> CGSize {
        let aspect = max(aspect, 0.1)
        let maxWidth = bounds.width - 2 * edgeMargin
        var w = max(minWidth, min(maxWidth, width))
        var h = w / aspect
        let maxHeight = bounds.height * 0.5
        if h > maxHeight {
            h = maxHeight
            w = max(minWidth, min(maxWidth, h * aspect))
        }
        return CGSize(width: w, height: h)
    }

    static func area(forLandscapeFraction fraction: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let w = screenWidth * fraction
        return w * (w / referenceAspect)
    }

    private func cardSize(forArea area: CGFloat) -> CGSize {
        guard area > 0 else { return cardSize(forWidth: Self.minWidth) }
        return cardSize(forWidth: sqrt(area * aspect))
    }

    private func spawnSize() -> CGSize {
        if settings.startPosition == .lastPosition {
            let fraction = CGFloat(UserDefaults.standard.float(forKey: areaKey))
            if fraction > 0.0001 { return cardSize(forArea: fraction * bounds.width * bounds.width) }
        }
        return cardSize(forArea: Self.area(forLandscapeFraction: Self.defaultLandscapeFraction, screenWidth: bounds.width))
    }

    private func cornerCenter(_ corner: Int, size: CGSize) -> CGPoint {
        let left = insets.left + Self.edgeMargin + size.width / 2
        let right = bounds.width - insets.right - Self.edgeMargin - size.width / 2
        let top = insets.top + Self.edgeMargin + size.height / 2
        let bottom = bounds.height - insets.bottom - Self.edgeMargin - size.height / 2
        switch corner {
        case 0: return CGPoint(x: left, y: top)
        case 1: return CGPoint(x: right, y: top)
        case 2: return CGPoint(x: left, y: bottom)
        default: return CGPoint(x: right, y: bottom)
        }
    }

    private func clamped(_ center: CGPoint, size: CGSize) -> CGPoint {
        let minX = insets.left + Self.edgeMargin + size.width / 2
        let maxX = max(minX, bounds.width - insets.right - Self.edgeMargin - size.width / 2)
        let minY = insets.top + Self.edgeMargin + size.height / 2
        let maxY = max(minY, bounds.height - insets.bottom - Self.edgeMargin - size.height / 2)
        return CGPoint(x: min(maxX, max(minX, center.x)), y: min(maxY, max(minY, center.y)))
    }

    private func placeAtSpawn(size: CGSize) {
        guard let card else { return }
        stashedSide = 0
        if settings.startPosition == .lastPosition, UserDefaults.standard.object(forKey: lastCenterXKey) != nil {
            let c = CGPoint(x: CGFloat(UserDefaults.standard.double(forKey: lastCenterXKey)) * bounds.width,
                            y: CGFloat(UserDefaults.standard.double(forKey: lastCenterYKey)) * bounds.height)
            card.center = clamped(c, size: size)
            let side = UserDefaults.standard.integer(forKey: stashKey)
            if side != 0 { stash(side, animated: false) } else { updateStashHandle() }
            return
        }
        card.center = cornerCenter(settings.startPosition.rawValue, size: size)
        if settings.startHidden {
            stash(settings.startPosition == .topLeft || settings.startPosition == .bottomLeft ? -1 : 1, animated: false)
        } else {
            updateStashHandle()
        }
    }

    private func persistPosition() {
        guard let card, bounds.width > 1, bounds.height > 1 else { return }
        UserDefaults.standard.set(Double(card.center.x / bounds.width), forKey: lastCenterXKey)
        UserDefaults.standard.set(Double(card.center.y / bounds.height), forKey: lastCenterYKey)
        UserDefaults.standard.set(stashedSide, forKey: stashKey)
    }

    private func persistArea() {
        guard let card, bounds.width > 1 else { return }
        UserDefaults.standard.set(Float(card.bounds.width * card.bounds.height / (bounds.width * bounds.width)), forKey: areaKey)
    }

    /// WWDC18 projection with Reborn's fast 0.99 rate.
    static func projectedOffset(_ velocity: CGFloat) -> CGFloat {
        let rate: CGFloat = 0.99
        return (velocity / 1000) * rate / (1 - rate)
    }

    // MARK: Stash

    private func stash(_ side: Int, animated: Bool) {
        guard let card else { return }
        stashedSide = side
        hideControls()
        let size = card.bounds.size
        var y = card.center.y - size.height / 2
        y = max(insets.top + Self.edgeMargin, min(bounds.height - insets.bottom - Self.edgeMargin - size.height, y))
        let x = side < 0 ? Self.stashVisibleWidth - size.width : bounds.width - Self.stashVisibleWidth
        let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        updateStashHandle()
        if animated {
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) { card.frame = frame }
        } else {
            card.frame = frame
        }
        persistPosition()
    }

    private func unstash() {
        guard let card, stashedSide != 0 else { return }
        stashedSide = 0
        updateStashHandle()
        let target = clamped(card.center, size: card.bounds.size)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) { card.center = target }
        persistPosition()
    }

    private func updateStashHandle() {
        guard let card, let handle = stashHandle else { return }
        guard stashedSide != 0 else { handle.isHidden = true; return }
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        handle.image = UIImage(systemName: stashedSide < 0 ? "chevron.compact.right" : "chevron.compact.left", withConfiguration: config)
        let x = stashedSide < 0 ? card.bounds.width - Self.stashVisibleWidth : 0
        handle.frame = CGRect(x: x, y: 0, width: Self.stashVisibleWidth, height: card.bounds.height)
        handle.isHidden = false
        card.bringSubviewToFront(handle)
    }

    // MARK: Build

    private func buildIfNeeded() {
        guard card == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false

        let card = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 112))
        card.backgroundColor = .black
        card.layer.cornerRadius = 12
        card.layer.masksToBounds = true
        card.layer.borderWidth = 0.5
        card.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        card.isHidden = true
        card.accessibilityIdentifier = "pip.card"

        installPlayerLayer(in: card)

        let overlay = OverlayView(frame: card.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor(white: 0, alpha: 0.35)
        overlay.isHidden = true
        overlay.onLayout = { [weak self] in self?.layoutControls() }
        card.addSubview(overlay)
        self.overlay = overlay

        func button(_ symbol: String, _ size: CGFloat, _ action: Selector, _ label: String) -> UIButton {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)), for: .normal)
            b.tintColor = .white
            b.addTarget(self, action: action, for: .touchUpInside)
            b.accessibilityLabel = label
            overlay.addSubview(b)
            return b
        }
        let track = UIView()
        track.backgroundColor = UIColor(white: 1, alpha: 0.35)
        track.layer.cornerRadius = 1.5
        track.layer.masksToBounds = true
        track.isUserInteractionEnabled = false
        let fill = UIView()
        fill.backgroundColor = .white
        track.addSubview(fill)
        overlay.insertSubview(track, at: 0)
        progressTrack = track
        progressFill = fill
        playButton = button("pause.fill", 26, #selector(playPauseTapped), "Play or pause")
        skipBack = button("gobackward.10", 20, #selector(skipBackTapped), "Skip back")
        skipForward = button("goforward.10", 20, #selector(skipForwardTapped), "Skip forward")
        closeButton = button("xmark", 14, #selector(closeTapped), "Close")
        // The gear opens Picture in Picture settings.
        settingsButton = button("gearshape.fill", 14, #selector(settingsTapped), "Picture in Picture Settings")
        muteButton = button("speaker.slash.fill", 14, #selector(muteTapped), "Mute")

        let handle = UIImageView()
        handle.tintColor = .white
        handle.contentMode = .center
        handle.backgroundColor = UIColor(white: 0, alpha: 0.35)
        handle.isHidden = true
        card.addSubview(handle)
        stashHandle = handle

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        card.addGestureRecognizer(tap)
        card.addGestureRecognizer(doubleTap)
        card.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        card.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))

        root.view.addSubview(card)
        window.interactiveView = card
        self.window = window
        self.card = card
    }

    /// A fresh layer for each new player: reusing one layer across players
    /// draws black after a fullscreen hand-off.
    private func installPlayerLayer(in card: UIView) {
        destroyNativePiP()
        layerView?.playerLayer.player = nil
        layerView?.removeFromSuperview()
        let view = PlayerLayerView(frame: card.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.playerLayer.videoGravity = .resizeAspectFill
        view.isUserInteractionEnabled = false
        card.insertSubview(view, at: 0)
        layerView = view
        playerLayer = view.playerLayer
    }

    /// Lays out the overlay controls.
    private func layoutControls() {
        guard let overlay, let playButton else { return }
        let w = overlay.bounds.width, h = overlay.bounds.height
        guard w > 1, h > 1 else { return }
        closeButton?.frame = CGRect(x: 6, y: 6, width: 34, height: 34)
        // The gear rides the same top band as close and mute.
        settingsButton?.frame = CGRect(x: 44, y: 6, width: 34, height: 34)
        muteButton?.frame = CGRect(x: w - 40, y: 6, width: 34, height: 34)
        // A silent GIF has no audio to toggle.
        muteButton?.isHidden = isGIFContent
        progressTrack?.frame = CGRect(x: 10, y: h - 9, width: w - 20, height: 3)
        progressTrack?.isHidden = !settings.progressBar
        let compact = h < 120
        var pp: CGFloat = (settings.skipButtons && compact) ? 44 : 52
        let skip: CGFloat = compact ? 36 : 40
        var showSkips = settings.skipButtons
        var rowY = h / 2
        var offset = pp / 2 + 8 + skip / 2
        if showSkips {
            rowY = max(rowY, 42 + skip / 2)
            offset = min(offset, w / 2 - 6 - skip / 2)
            if rowY > h - 4 - pp / 2 || offset < pp / 2 + 2 + skip / 2 {
                showSkips = false; pp = 52; rowY = h / 2
            }
        }
        playButton.frame = CGRect(x: w / 2 - pp / 2, y: rowY - pp / 2, width: pp, height: pp)
        skipBack?.isHidden = !showSkips
        skipForward?.isHidden = !showSkips
        skipBack?.frame = CGRect(x: w / 2 - offset - skip / 2, y: rowY - skip / 2, width: skip, height: skip)
        skipForward?.frame = CGRect(x: w / 2 + offset - skip / 2, y: rowY - skip / 2, width: skip, height: skip)
        updateProgress()
    }

    private func syncControls() {
        guard let player else { return }
        let playing = player.timeControlStatus != .paused
        playButton?.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)), for: .normal)
        muteButton?.setImage(UIImage(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        muteButton?.isHidden = isGIFContent
        let secs = settings.skipSeconds
        let medium = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        skipBack?.setImage(UIImage(systemName: "gobackward.\(secs)", withConfiguration: medium) ?? UIImage(systemName: "gobackward", withConfiguration: medium), for: .normal)
        skipForward?.setImage(UIImage(systemName: "goforward.\(secs)", withConfiguration: medium) ?? UIImage(systemName: "goforward", withConfiguration: medium), for: .normal)
    }

    private func updateProgress() {
        guard let player, let track = progressTrack, let fill = progressFill,
              let item = player.currentItem, item.duration.isNumeric, item.duration.seconds > 0 else { return }
        let fraction = max(0, min(1, player.currentTime().seconds / item.duration.seconds))
        fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * fraction, height: track.bounds.height)
    }

    // MARK: Observation

    private func startObserving() {
        guard let player, timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateProgress()
                self?.syncControls()
            }
        }
        // Loop Videos (default on); GIFs always loop.
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShowing,
                      PictureInPicturePolicy.loops(isGIF: self.isGIFContent, settings: self.settings) else { return }
                self.player?.seek(to: .zero)
                self.player?.play()
            }
        }
    }

    private func stopObserving() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    // MARK: Actions

    private func showControls() {
        overlay?.isHidden = false
        syncControls()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.controlsAutoHide, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideControls() }
        }
    }

    private func hideControls() {
        overlay?.isHidden = true
        hideTimer?.invalidate()
        hideTimer = nil
    }

    @objc private func handleTap() {
        if stashedSide != 0 { unstash(); return }
        if overlay?.isHidden == true { showControls() } else { hideControls() }
    }

    @objc private func handleDoubleTap() {
        guard let card, stashedSide == 0 else { return }
        hideControls()
        let current = card.bounds.width * card.bounds.height
        let small = Self.area(forLandscapeFraction: Self.defaultLandscapeFraction, screenWidth: bounds.width)
        let large = Self.area(forLandscapeFraction: Self.largeLandscapeFraction, screenWidth: bounds.width)
        let size = cardSize(forArea: abs(current - small) < abs(current - large) ? large : small)
        // Anchor to the nearest corner so a docked card grows inward.
        let old = card.frame
        let x = old.midX > bounds.width / 2 ? old.maxX - size.width : old.minX
        let y = old.midY > bounds.height / 2 ? old.maxY - size.height : old.minY
        let target = clamped(CGPoint(x: x + size.width / 2, y: y + size.height / 2), size: size)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            card.bounds = CGRect(origin: .zero, size: size)
            card.center = target
        }
        persistArea()
        persistPosition()
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let card, let container = card.superview else { return }
        switch pan.state {
        case .changed:
            let t = pan.translation(in: container)
            card.center = CGPoint(x: card.center.x + t.x, y: card.center.y + t.y)
            pan.setTranslation(.zero, in: container)
        case .ended, .cancelled:
            let v = pan.velocity(in: container)
            let speed = hypot(v.x, v.y)
            var projected = card.center
            if speed >= Self.flingVelocity {
                projected.x += Self.projectedOffset(v.x)
                projected.y += Self.projectedOffset(v.y)
            }
            let horizontalFling = abs(v.x) > Self.stashVelocity && abs(v.x) > abs(v.y)
            if stashedSide != 0 {
                let stillOff = stashedSide < 0 ? projected.x < 0 : projected.x > bounds.width
                if stillOff { stash(stashedSide, animated: true); return }
                stashedSide = 0
                updateStashHandle()
            } else if card.center.x < 0 || (projected.x < 0 && horizontalFling && v.x < 0) {
                stash(-1, animated: true); return
            } else if card.center.x > bounds.width || (projected.x > bounds.width && horizontalFling && v.x > 0) {
                stash(1, animated: true); return
            }
            let target = clamped(projected, size: card.bounds.size)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) { card.center = target }
            persistPosition()
        default:
            break
        }
    }

    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        guard let card, stashedSide == 0 else { return }
        switch pinch.state {
        case .began:
            pinchStartWidth = card.bounds.width
        case .changed:
            let size = cardSize(forWidth: pinchStartWidth * pinch.scale)
            let c = card.center
            card.bounds = CGRect(origin: .zero, size: size)
            card.center = c
        case .ended, .cancelled:
            persistArea()
            let target = clamped(card.center, size: card.bounds.size)
            UIView.animate(withDuration: 0.25) { card.center = target }
            persistPosition()
        default:
            break
        }
    }

    @objc private func playPauseTapped() {
        guard let player else { return }
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
        syncControls()
        showControls()
    }

    @objc private func muteTapped() {
        guard let player else { return }
        if player.isMuted { VideoAudioSession.claim(Self.audioHolder) }
        player.isMuted.toggle()
        if player.isMuted { VideoAudioSession.release(Self.audioHolder) }
        syncControls()
        showControls()
    }

    @objc private func settingsTapped() {
        NotificationCenter.default.post(name: .apolloOpenSettingsRoute, object: "picture-in-picture")
        showControls()
    }

    @objc private func skipBackTapped() { skip(by: -Double(settings.skipSeconds)) }
    @objc private func skipForwardTapped() { skip(by: Double(settings.skipSeconds)) }

    private func skip(by seconds: Double) {
        guard let player else { return }
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        showControls()
    }

    @objc private func closeTapped() { close() }

    // MARK: Views

    final class PassthroughWindow: UIWindow {
        weak var interactiveView: UIView?
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let view = interactiveView, !view.isHidden,
                  view.frame.contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class OverlayView: UIView {
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }
}

extension FloatingPiPController: @preconcurrency AVPictureInPictureControllerDelegate {
    /// Back from system PiP: the card is still there to take the picture.
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        SystemPiPAudio.releaseIfMixable()
    }
}

public extension Notification.Name {
    /// Opens a settings page by its Settings Shortcuts route id, on the
    /// Settings tab. `object` is the id.
    static let apolloOpenSettingsRoute = Notification.Name("ApolloOpenSettingsRoute")
}

/// The audio session system PiP needs: Playback so it can start from the
/// background, mixing when silent so someone's music keeps playing under a
/// muted clip.
@MainActor
enum SystemPiPAudio {
    private static var claimedMixable = false

    /// Idempotent: called every second while armed. An unmuted video
    /// already holds the Playback claim from its own unmute, so only the
    /// silent case needs one here.
    static func claim(muted: Bool) {
        guard !VideoAudioSession.holdsClaim, !claimedMixable else { return }
        // Any switch out of Ambient interrupts other apps' audio, mixable or not
        // (Reborn #560): with music playing, a muted video's PiP yields to it.
        guard !AVAudioSession.sharedInstance().isOtherAudioPlaying else { return }
        let resume = VideoAudioSession.pausePlaying()
        VideoAudioSession.perform { session in
            defer { DispatchQueue.main.async(execute: resume) }
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
        claimedMixable = true
    }

    static func releaseIfMixable() {
        guard claimedMixable, !VideoAudioSession.holdsClaim else { return }
        claimedMixable = false
        let resume = VideoAudioSession.pausePlaying()
        VideoAudioSession.perform { session in
            defer { DispatchQueue.main.async(execute: resume) }
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            try? session.setCategory(.ambient)
        }
    }
}

/// "Enable PiP When Leaving App" for an inline video with no card: the
/// post screen's video and feed-row videos register their on-screen layer,
/// and when the app is about to background the best candidate (playing,
/// eligible under Activate For, on screen, not under a modal) may start
/// system PiP.
@MainActor
final class InlineSystemPiP {
    private weak var layer: AVPlayerLayer?
    private weak var player: AVPlayer?
    private var isGIF = false
    /// A feed row arms only for a video the user deliberately unmuted
    /// ("In feeds, only unmuted videos can trigger it").
    private var isFeedRow = false
    private var controller: AVPictureInPictureController?

    private static var candidates: [ObjectIdentifier: InlineSystemPiP] = [:]
    private static var active: InlineSystemPiP?

    func attach(layer: AVPlayerLayer, player: AVPlayer, isGIF: Bool, isFeedRow: Bool) {
        self.layer = layer
        self.player = player
        self.isGIF = isGIF
        self.isFeedRow = isFeedRow
        guard PictureInPictureSettingsStore.load().systemEnabled,
              AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if controller == nil || controller?.playerLayer !== layer {
            controller = AVPictureInPictureController(playerLayer: layer)
            controller?.canStartPictureInPictureAutomaticallyFromInline = false
        }
        Self.candidates[ObjectIdentifier(self)] = self
    }

    func detach() {
        Self.candidates[ObjectIdentifier(self)] = nil
        // Mid-PiP the window keeps going; it tears down when it stops.
        if controller?.isPictureInPictureActive != true { controller = nil }
    }

    static func disarmAll() {
        guard active != nil else { return }
        for candidate in candidates.values { candidate.controller?.canStartPictureInPictureAutomaticallyFromInline = false }
        active = nil
        SystemPiPAudio.releaseIfMixable()
    }

    static func armBestCandidate(cardIsShowing: Bool) {
        let settings = PictureInPictureSettingsStore.load()
        guard settings.systemEnabled, !cardIsShowing else { disarmAll(); return }
        let best = candidates.values
            .compactMap { candidate -> (InlineSystemPiP, CGFloat)? in
                guard let player = candidate.player, let visible = candidate.visibleFraction(),
                      // Deliberately audible: unmuted, with the session actually claimed for
                      // its sound.
                      !candidate.isFeedRow || (!player.isMuted && VideoAudioSession.holdsClaim),
                      PictureInPicturePolicy.armsSystemPiP(
                        settings: settings, isPlaying: player.timeControlStatus != .paused,
                        isMuted: player.isMuted,
                        isSilent: candidate.isGIF || FloatingPiPController.isKnownSilent(player)) else { return nil }
                return (candidate, visible)
            }
            .max { $0.1 < $1.1 }?.0
        guard let best, let player = best.player else { disarmAll(); return }
        if active !== best {
            disarmAll()
            best.controller?.canStartPictureInPictureAutomaticallyFromInline = true
            active = best
        }
        SystemPiPAudio.claim(muted: player.isMuted || best.isGIF)
    }

    /// How much of the video is on screen, or nil when it's off screen or
    /// covered by a modal (the fullscreen viewer owns its own session).
    private func visibleFraction() -> CGFloat? {
        guard let layer, let window = UIKitTree.keyWindow,
              window.rootViewController?.presentedViewController == nil else { return nil }
        // A screen covered by a push is taken out of the window; its layer
        // no longer reaches the window's.
        var ancestor = layer.superlayer
        while let current = ancestor, current !== window.layer { ancestor = current.superlayer }
        guard ancestor != nil else { return nil }
        let frame = layer.convert(layer.bounds, to: window.layer)
        let visible = frame.intersection(window.bounds)
        guard !visible.isNull, frame.height > 0 else { return nil }
        let fraction = visible.height / frame.height
        return fraction >= 0.5 ? fraction : nil
    }
}

/// Where each feed-row video is on screen, keyed by URL, so a back-pop
/// can hand the card's picture back to its row.
@MainActor
enum FloatingPiPHomes {
    private static var visible: [String: Bool] = [:]

    static func report(_ owner: String, frame: CGRect, topLimit: CGFloat) {
        let screen = UIScreen.main.bounds
        let isVisible = frame.width > 1 && frame.midY > topLimit && frame.midY < screen.height
        visible[owner] = isVisible
        // A card sent from the fullscreen viewer floats over feeds with no home
        // of its own; once its video's row is on screen, never show it twice:
        // hand it back.
        if isVisible { FloatingPiPController.shared.restoreFullscreenCard(toHome: owner) }
    }

    static func remove(_ owner: String) { visible[owner] = nil }

    static func isVisible(_ owner: String) -> Bool { visible[owner] == true }
}

/// Watches an inline video's frame and hands it to the floating card when
/// it scrolls under the navigation bar or off the bottom while playing,
/// and takes it back when it returns.
struct FloatingPiPSource: ViewModifier {
    let player: AVPlayer
    let owner: String
    let aspectRatio: CGFloat
    var isGIF = false
    var screenID: UUID?
    @State private var probe = NavigationBarProbe.Box()
    /// Whether the last frame was scrolled away. The hand-over is decided
    /// when that changes, not on every scroll frame: each evaluation read
    /// the PiP settings and probed the item's tracks.
    @State private var wasOffScreen: Bool?

    func body(content: Content) -> some View {
        content
            .background(NavigationBarProbe(box: probe).frame(width: 0, height: 0))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                evaluate(frame)
            }
    }

    private func evaluate(_ frame: CGRect) {
        let screen = UIScreen.main.bounds
        let offScreen = frame.midY < probe.topLimit || frame.midY > screen.height || frame.width < 1
        guard offScreen != wasOffScreen else { return }
        wasOffScreen = offScreen
        let controller = FloatingPiPController.shared
        if offScreen {
            guard !controller.isShowing || controller.ownerID != owner else { return }
            let settings = PictureInPictureSettingsStore.load()
            let silent = isGIF || FloatingPiPController.isKnownSilent(player)
            guard FloatingPiPController.shouldActivate(settings: settings,
                                                       isPlaying: player.timeControlStatus != .paused,
                                                       isMuted: player.isMuted, isGIF: silent) else { return }
            controller.show(player: player, owner: owner, aspectRatio: aspectRatio,
                            isGIF: silent, screenID: screenID)
        } else {
            controller.hide(owner: owner)
        }
    }
}

/// Reports a feed-row video's position for back-pop restore.
struct FloatingPiPHome: ViewModifier {
    let owner: String
    @State private var probe = NavigationBarProbe.Box()

    func body(content: Content) -> some View {
        content
            .background(NavigationBarProbe(box: probe).frame(width: 0, height: 0))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                FloatingPiPHomes.report(owner, frame: frame, topLimit: probe.topLimit)
            }
            .onDisappear { FloatingPiPHomes.remove(owner) }
    }
}

/// Finds the navigation bar over a video through the video's own view
/// controller, for Apollo's midpoint test: the video counts as scrolled
/// away once its centre passes under the bar's bottom edge.
struct NavigationBarProbe: UIViewRepresentable {
    @MainActor
    final class Box {
        weak var view: UIView?

        /// The bar's bottom in window coordinates, or the status bar plus
        /// a standard bar when there is none.
        var topLimit: CGFloat {
            guard let view, let window = view.window else { return 100 }
            if let bar = view.owningViewController()?.navigationController?.navigationBar,
               !bar.isHidden, bar.window != nil {
                return bar.convert(bar.bounds, to: window).maxY
            }
            return window.safeAreaInsets.top + 44
        }
    }

    let box: Box

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        box.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { box.view = view }
}

/// Lives exactly as long as a post screen: SwiftUI keeps it through
/// forward pushes and releases it when the screen is popped, which is
/// the back-pop the card has to answer.
@MainActor
final class FloatingPiPScreenLifetime: ObservableObject {
    let id = UUID()
    deinit {
        let id = self.id
        Task { @MainActor in FloatingPiPController.shared.screenClosed(id) }
    }
}

private struct FloatingPiPScreenScope: ViewModifier {
    @StateObject private var lifetime = FloatingPiPScreenLifetime()

    func body(content: Content) -> some View {
        content.environment(\.floatingPiPScreenID, lifetime.id)
    }
}

extension View {
    /// Reborn's in-app PiP source (see `FloatingPiPController`).
    func floatingPiPSource(player: AVPlayer, owner: String, aspectRatio: CGFloat,
                           isGIF: Bool = false, screenID: UUID? = nil) -> some View {
        modifier(FloatingPiPSource(player: player, owner: owner, aspectRatio: aspectRatio,
                                   isGIF: isGIF, screenID: screenID))
    }

    /// Marks a post screen, so closing it resolves the card as a back-pop.
    func floatingPiPScreenScope() -> some View {
        modifier(FloatingPiPScreenScope())
    }
}
#else
extension View {
    func floatingPiPScreenScope() -> some View { self }
}
#endif

private struct FloatingPiPScreenIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct FloatingPiPSourceEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FloatingPiPIsGIFKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FloatingPiPHomeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The post screen hosting this view (`floatingPiPScreenScope`).
    var floatingPiPScreenID: UUID? {
        get { self[FloatingPiPScreenIDKey.self] }
        set { self[FloatingPiPScreenIDKey.self] = newValue }
    }

    /// Set on the post screen's own media: any inline player in it (a
    /// Reddit video, Streamable and friends, a GIF played as MP4) may hand
    /// over to the card. Comment-body media stays out, as in Reborn.
    var floatingPiPSourceEnabled: Bool {
        get { self[FloatingPiPSourceEnabledKey.self] }
        set { self[FloatingPiPSourceEnabledKey.self] = newValue }
    }

    /// The player inside is a GIF (silent, always loops).
    var floatingPiPIsGIF: Bool {
        get { self[FloatingPiPIsGIFKey.self] }
        set { self[FloatingPiPIsGIFKey.self] = newValue }
    }

    /// A feed row's video: a back-pop's home, and a system PiP candidate.
    var floatingPiPHome: Bool {
        get { self[FloatingPiPHomeKey.self] }
        set { self[FloatingPiPHomeKey.self] = newValue }
    }
}
