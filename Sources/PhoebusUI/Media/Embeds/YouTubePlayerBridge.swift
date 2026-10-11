import Combine
import SwiftUI
import UIKit
import WebKit
import PhoebusCore

/// One YouTube video's player: the IFrame Player API page in a web view,
/// driven from Swift and exposed as a `VideoTransport`, so the app's own
/// control panel, scrub bar and mute button run it as they run an `AVPlayer`.
/// A script in the embed frame (`YouTubeEmbed.frameScript`) controls the
/// `<video>` element and reports its events, which are the source of truth for
/// state, time, rate and sound; the IFrame API is the loader and the fallback
/// while that script hasn't found the element.
///
/// The inline post, the floating PiP card and the fullscreen viewer show the
/// same bridge: the web view moves between their host views (`register`)
/// instead of reloading, so playback carries on.
@MainActor
final class YouTubePlayerBridge: NSObject, ObservableObject, VideoTransport {
    enum HostRole { case inline, card, fullscreen }

    /// The player page is 16:9; every host shows the picture at this ratio.
    static let aspectRatio: CGFloat = 16.0 / 9.0

    let videoID: String
    let webView: WKWebView
    /// Changes when the controls need to redraw, not with every time report.
    @Published private(set) var status = YouTubePlayback.Status()
    /// The video can't play inline (removed, private, embedding disabled).
    var onUnplayable: (() -> Void)?

    private let startSeconds: Int
    private var playback = YouTubePlayback()
    private var isPageReady = false
    private(set) var hasLoadedPage = false
    private var pending: [YouTubeEmbed.Command] = [.mute]
    private var intendedMuted = true
    private var intendedRate: Double?
    /// The embed frame that reported its video, which commands are run in.
    private var videoFrame: WKFrameInfo?
    /// Until then a pause the player reports after a move is undone at once.
    private var resumeUntil: TimeInterval = 0
    /// Bumped by every play or pause request, so a delayed check after a
    /// move can tell the user has since decided otherwise.
    private var intent = 0
    private weak var inlineHost: YouTubeWebHostView?
    private weak var cardHost: YouTubeWebHostView?
    private weak var fullscreenHost: YouTubeWebHostView?
    private var sessionObserver: AnyCancellable?

    init(videoID: String, startSeconds: Int) {
        self.videoID = videoID
        self.startSeconds = startSeconds
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = YouTubeAccount.dataStore
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Lets WebKit put the video in system Picture in Picture; the app's
        // own controls have no button for it.
        configuration.allowsPictureInPictureMediaPlayback = true
        // forMainFrameOnly: false so it reaches the youtube.com embed iframe.
        configuration.userContentController.addUserScript(
            WKUserScript(source: YouTubeEmbed.frameScript(captionsWanted: YouTubeCaptions.wanted), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let proxy = YouTubeScriptMessageProxy()
        configuration.userContentController.add(proxy, name: YouTubeEmbed.messageHandlerName)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        proxy.target = self
        // The page is transparent until the player paints, so the poster
        // behind it shows through while it loads. Touches go to the app's own
        // layer above, not into the player.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        webView.allowsLinkPreview = false
        sessionObserver = NotificationCenter.default.publisher(for: .youTubeSessionChanged)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.reloadForSessionChange() } }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - Page

    /// Loads the player page once, under the app's own origin
    /// (`YouTubeEmbed.origin`).
    func loadIfNeeded() {
        guard !hasLoadedPage else { return }
        loadPage(startSeconds: startSeconds)
    }

    private func loadPage(startSeconds: Int) {
        hasLoadedPage = true
        let origin = YouTubeEmbed.origin(bundleIdentifier: Bundle.main.bundleIdentifier)
        guard let html = YouTubeEmbed.html(videoID: videoID, startSeconds: startSeconds, origin: origin,
                                         captionsWanted: YouTubeCaptions.wanted) else {
            // Not a real video ID: nothing to load, so nothing will play.
            playback.apply(.error(code: 100), at: Self.now)
            publish()
            DispatchQueue.main.async { [weak self] in self?.onUnplayable?() }
            return
        }
        webView.loadHTMLString(html, baseURL: origin)
    }

    fileprivate func handle(_ body: Any, from frame: WKFrameInfo) {
        guard let message = YouTubePlayerMessage.parse(body) else { return }
        let wasPlaying = playback.isPlaying
        let attaching = !playback.hasVideoSource
        playback.apply(message, at: Self.now)
        // Until the video reports its own sound, the app's choice stands.
        if case .ready = message, !playback.hasVideoSource { playback.setMuted(intendedMuted) }
        publish()
        switch message {
        case .video(let report):
            if !frame.isMainFrame { videoFrame = frame }
            if attaching {
                send(intendedMuted ? .mute : .unMute)
                if let intendedRate { send(.setPlaybackRate(intendedRate)) }
            }
            // WebKit can pause a video whose web view was just moved to
            // another window: start it again without reloading.
            if report.type == "pause", !report.isEnded, wasPlaying, Self.now < resumeUntil { send(.play) }
        case .ready:
            isPageReady = true
            let commands = pending
            pending = []
            commands.forEach(send)
        case .error(let code) where YouTubeEmbed.isUnplayableInline(errorCode: code):
            onUnplayable?()
        default:
            break
        }
    }

    private func publish() {
        let current = playback.status
        if current != status { status = current }
    }

    private func send(_ command: YouTubeEmbed.Command) {
        guard isPageReady else {
            // Only the last of the sound commands matters.
            if command == .mute || command == .unMute { pending.removeAll { $0 == .mute || $0 == .unMute } }
            pending.append(command)
            return
        }
        run(command)
        if command == .play || command == .pause { settleRequestSoon() }
    }

    /// Runs the command on the video element in the embed frame, or through
    /// the IFrame API when there is no such frame or the element didn't take it.
    private func run(_ command: YouTubeEmbed.Command) {
        guard let frame = videoFrame else {
            webView.evaluateJavaScript(command.script, completionHandler: nil)
            return
        }
        webView.evaluateJavaScript(command.frameScript, in: frame, in: .page) { [weak self] result in
            if case .success(let handled) = result, handled as? Bool == true { return }
            if case .failure = result { self?.videoFrame = nil }
            self?.webView.evaluateJavaScript(command.script, completionHandler: nil)
        }
    }

    /// A play or pause the player never answers (an autoplay it refuses)
    /// stops showing as if it had worked.
    private func settleRequestSoon() {
        let issued = intent
        Task { @MainActor [self] in
            try? await Task.sleep(for: .seconds(3))
            guard issued == intent else { return }
            playback.settleRequest(at: Self.now)
            publish()
        }
    }

    // MARK: - Hosts

    /// A screen that shows the player. The fullscreen viewer's host takes the
    /// web view while it is up, then the floating card's, and the inline one
    /// gets it back when they close.
    func register(host: YouTubeWebHostView, role: HostRole) {
        switch role {
        case .inline: inlineHost = host
        case .card: cardHost = host
        case .fullscreen: fullscreenHost = host
        }
        host.bridge = self
        moveWebView()
    }

    func unregister(host: YouTubeWebHostView) {
        if inlineHost === host { inlineHost = nil }
        if cardHost === host { cardHost = nil }
        if fullscreenHost === host { fullscreenHost = nil }
        moveWebView()
    }

    var isFullscreenHosted: Bool { fullscreenHost != nil }
    var isCardHosted: Bool { cardHost != nil }

    private func moveWebView() {
        guard let host = fullscreenHost ?? cardHost ?? inlineHost, webView.superview !== host else { return }
        let wasPlaying = status.isPlaying && playback.playerState.isPlayingOrBuffering
        if wasPlaying { resumeUntil = Self.now + 3 }
        host.adopt(webView)
        if wasPlaying { recoverPlaybackAfterMove() }
    }

    /// A web view taken out of its window and put into another can leave its
    /// video paused. A pause the video reports meanwhile is undone at once
    /// (`handle`); if it still isn't playing after a beat, asks again, and as
    /// a last resort reloads the page at the current time.
    private func recoverPlaybackAfterMove() {
        intent &+= 1
        let moved = intent
        Task { @MainActor [self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard moved == intent, !playback.playerState.isPlayingOrBuffering else { return }
            send(.play)
            try? await Task.sleep(for: .milliseconds(1500))
            guard moved == intent, !playback.playerState.isPlayingOrBuffering else { return }
            reloadAtCurrentTime()
        }
    }

    /// A player that isn't playing starts over as the account that is signed
    /// in now; one that is playing keeps going until it next loads.
    private func reloadForSessionChange() {
        guard hasLoadedPage, !playback.playerState.isPlayingOrBuffering else { return }
        isPageReady = false
        pending = [intendedMuted ? .mute : .unMute]
        loadPage(startSeconds: Int(currentSeconds))
    }

    private func reloadAtCurrentTime() {
        let resumeAt = Int(currentSeconds)
        isPageReady = false
        videoFrame = nil
        playback.videoSourceLost()
        pending = [intendedMuted ? .mute : .unMute, .play]
        loadPage(startSeconds: resumeAt)
    }

    // MARK: - VideoTransport

    var isPlaying: Bool { status.isPlaying }
    var isMuted: Bool { status.isMuted }
    var currentSeconds: Double { playback.seconds(at: Self.now) }
    var durationSeconds: Double { status.duration }
    var playbackRate: Double { playback.rate }

    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        $status.map(\.isPlaying).removeDuplicates().receive(on: RunLoop.main).eraseToAnyPublisher()
    }

    var isMutedPublisher: AnyPublisher<Bool, Never> {
        $status.map(\.isMuted).removeDuplicates().receive(on: RunLoop.main).eraseToAnyPublisher()
    }

    func play() {
        intent &+= 1
        loadIfNeeded()
        playback.requestPlaying(true, at: Self.now)
        publish()
        send(.play)
    }

    func pause() {
        intent &+= 1
        playback.requestPlaying(false, at: Self.now)
        publish()
        send(.pause)
    }

    func setMuted(_ muted: Bool) {
        intendedMuted = muted
        // Shown at once, so quick taps toggle from what the button shows; the
        // video's own report settles it.
        playback.setMuted(muted)
        publish()
        let wasPlaying = status.isPlaying
        send(muted ? .mute : .unMute)
        // Changing the audio session for the sound can pause a playing page;
        // the frame script resumes it, and this catches a page without one.
        guard wasPlaying else { return }
        let issued = intent
        Task { @MainActor [self] in
            try? await Task.sleep(for: .milliseconds(700))
            if issued == intent, !playback.playerState.isPlayingOrBuffering { play() }
        }
    }

    func seek(to seconds: Double, scrubbing: Bool, completion: (@MainActor @Sendable () -> Void)?) {
        // The ad stays as it is; the scrub bar is not for it.
        if !status.isAd {
            playback.seek(to: seconds, at: Self.now)
            send(.seek(seconds: seconds, allowSeekAhead: !scrubbing))
        }
        // The API reports no seek completion, so a scrub that chases the
        // finger waits a beat between positions.
        guard let completion else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(scrubbing ? 200 : 100))
            completion()
        }
    }

    func setPlaybackRate(_ rate: Double) {
        intendedRate = rate
        send(.setPlaybackRate(rate))
    }

    // MARK: - Sound

    /// The video's starting sound for where it plays, from the same settings
    /// as every other video (`VideoUnmutePolicy`).
    func applyInitialSound(_ context: VideoUnmuteContext, holderID: String) {
        let muted = VideoUnmutePolicy.startsMuted(
            context, settings: GeneralSettingsStore.load(),
            feedRememberedMuted: RememberedVideoMuteStore.isMuted,
            fullscreenUnmutedThisSession: FullscreenUnmuteMemory.isUnmuted,
            alreadyAudible: !status.isMuted && status.isPlaying)
        // The audio session is claimed before unmuting: the app rests in
        // Ambient, which silences unmuted video.
        if VideoAudioSession.shouldClaim(isMuted: muted) { VideoAudioSession.claim(holderID) }
        setMuted(muted)
    }

    /// The user's own mute toggle (the control panel's button).
    func toggleMute(_ context: VideoUnmuteContext, holderID: String) {
        let muting = !status.isMuted
        soundGeneration &+= 1
        if VideoAudioSession.shouldClaim(isMuted: muting) { VideoAudioSession.claim(holderID) }
        if context == .fullscreen { FullscreenUnmuteMemory.isUnmuted = !muting }
        setMuted(muting)
        if muting { releaseSoundSoon(holderID: holderID) }
    }

    /// Bumped by every mute toggle, so a deferred release can tell it was
    /// overtaken.
    private var soundGeneration = 0

    /// Giving up the audio session pauses the page's video, so it is done
    /// once the sound has stayed off for a moment, not on every quick toggle,
    /// and the frame is told to resume through it.
    private func releaseSoundSoon(holderID: String) {
        let generation = soundGeneration
        Task { @MainActor [self] in
            try? await Task.sleep(for: .seconds(2))
            guard generation == soundGeneration, status.isMuted else { return }
            let wasPlaying = status.isPlaying
            if wasPlaying { send(.keepPlaying) }
            VideoAudioSession.release(holderID)
            guard wasPlaying else { return }
            let issued = intent
            try? await Task.sleep(for: .milliseconds(700))
            if issued == intent, generation == soundGeneration, !playback.playerState.isPlayingOrBuffering { play() }
        }
    }

    func releaseSound(holderID: String) {
        soundGeneration &+= 1
        VideoAudioSession.release(holderID)
    }
}

/// Forwards the page's messages to the bridge without the web view's user
/// content controller keeping the bridge alive.
@MainActor
private final class YouTubeScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: YouTubePlayerBridge?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message.body, from: message.frameInfo)
    }
}

/// The view a screen gives the bridge's web view to live in.
final class YouTubeWebHostView: UIView {
    weak var bridge: YouTubePlayerBridge?

    private weak var adopted: WKWebView?

    func adopt(_ webView: WKWebView) {
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        adopted = webView
        // The host may not have its size yet; `layoutSubviews` follows it.
        webView.autoresizingMask = []
        webView.frame = bounds
        addSubview(webView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let adopted, adopted.superview === self, adopted.frame != bounds { adopted.frame = bounds }
    }
}

/// Where the web view shows in SwiftUI. Touches pass through: the video
/// surface's taps are the screen's own.
struct YouTubeWebSurface: UIViewRepresentable {
    let bridge: YouTubePlayerBridge
    let role: YouTubePlayerBridge.HostRole

    func makeUIView(context: Context) -> YouTubeWebHostView {
        let host = YouTubeWebHostView()
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = false
        bridge.register(host: host, role: role)
        return host
    }

    func updateUIView(_ host: YouTubeWebHostView, context: Context) {}

    static func dismantleUIView(_ host: YouTubeWebHostView, coordinator: ()) {
        host.bridge?.unregister(host: host)
    }
}

/// One bridge per video while any screen holds it, so the inline post, a
/// re-created row and the fullscreen viewer all find the same player.
/// Weak, like `VideoPlayerCache`: the views own it through their state.
@MainActor
final class YouTubePlayerRegistry {
    static let shared = YouTubePlayerRegistry()

    private final class Entry {
        weak var bridge: YouTubePlayerBridge?
        init(_ bridge: YouTubePlayerBridge) { self.bridge = bridge }
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    func bridge(for videoID: String, startSeconds: Int = 0) -> YouTubePlayerBridge {
        if let existing = entries[videoID]?.bridge { return existing }
        let bridge = YouTubePlayerBridge(videoID: videoID, startSeconds: startSeconds)
        entries = entries.filter { $0.value.bridge != nil }
        entries[videoID] = Entry(bridge)
        return bridge
    }
}
