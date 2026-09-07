import SwiftUI
import AVKit
import UIKit
import PhoebusCore

/// Apollo's real video control panel: two rows (controls, then
/// scrubber) in portrait; one row in landscape with a different
/// control order.
public struct VideoControlPanel: View {
    let player: AVPlayer
    /// Landscape uses `landscapeHeight`: one row instead of two, with
    /// a different order (skip/play/skip, times, scrubber, then
    /// AirPlay and mute trailing).
    let isLandscape: Bool

    @State private var isPlaying = false
    @State private var isMuted: Bool
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var timeObserver: Any?
    /// Apollo's `showsRouteButton` flag: the AirPlay button is conditional on a
    /// route being available (`AVRouteDetector`), not always shown.
    @State private var showsRouteButton = false
    @State private var routeDetector: AVRouteDetector?
    @State private var routeObserver: NSObjectProtocol?

    /// Apollo's skip amount.
    static let skipSeconds: Double = 15

    /// The host's own mute toggle, so the panel's button claims the audio
    /// session and records the user's choice the same way the badge does.
    let onToggleMute: (() -> Void)?

    public init(player: AVPlayer, isLandscape: Bool = false, onToggleMute: (() -> Void)? = nil) {
        self.player = player
        self.isLandscape = isLandscape
        self.onToggleMute = onToggleMute
        _isMuted = State(initialValue: player.isMuted)
        // Known at once when the item has loaded, so the bar's first frame is
        // already in proportion.
        let known = player.currentItem?.duration.seconds ?? 0
        _duration = State(initialValue: known.isFinite && known > 0 ? known : 0)
        let now = player.currentTime().seconds
        _currentTime = State(initialValue: now.isFinite && now > 0 ? now : 0)
        _isPlaying = State(initialValue: player.rate != 0)
    }

    public var body: some View {
        Group {
            if isLandscape {
                landscapeRow
            } else {
                portraitRows
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255))
        )
        .onAppear { startObserving(); startRouteDetection() }
        .onDisappear { stopObserving(); stopRouteDetection() }
        .accessibilityIdentifier("video.controlPanel")
    }

    // MARK: - Layouts

    /// Apollo's panel: 103pt tall in #141414 with 15pt corners. Controls row
    /// centred 30.8pt from the top (AirPlay centre 34.7pt in, mute 36.7pt from the
    /// right, the 15s/play/15s trio 50pt apart); scrubber row centred 77.2pt down,
    /// its track 67pt in from either label's outer edge.
    enum Metrics {
        static let cornerRadius: CGFloat = 15
        static let height: CGFloat = 103
        static let controlsTop: CGFloat = 16.8
        static let controlsHeight: CGFloat = 28
        static let rowGap: CGFloat = 23.9
        static let scrubberHeight: CGFloat = 17
        static let controlsLeading: CGFloat = 20.7
        static let controlsTrailing: CGFloat = 22.7
        static let trioSpacing: CGFloat = 20
        static let trioSlot: CGFloat = 30
        static let scrubberLeading: CGFloat = 23
        static let scrubberTrailing: CGFloat = 26
        static let leadingLabelWidth: CGFloat = 44
        static let trailingLabelWidth: CGFloat = 41
    }

    private var portraitRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    if showsRouteButton { airPlayButton } else { Color.clear }
                }
                .frame(width: 28, height: 28)
                Spacer(minLength: 0)
                HStack(spacing: Metrics.trioSpacing) {
                    back15Button.frame(width: Metrics.trioSlot)
                    playPauseButton.frame(width: Metrics.trioSlot)
                    forward15Button.frame(width: Metrics.trioSlot)
                }
                Spacer(minLength: 0)
                muteUnmuteButton.frame(width: 28, height: 28)
            }
            .padding(.leading, Metrics.controlsLeading)
            .padding(.trailing, Metrics.controlsTrailing)
            .frame(height: Metrics.controlsHeight)
            .padding(.top, Metrics.controlsTop)
            scrubberRow
                .padding(.leading, Metrics.scrubberLeading)
                .padding(.trailing, Metrics.scrubberTrailing)
                .frame(height: Metrics.scrubberHeight)
                .padding(.top, Metrics.rowGap)
            Spacer(minLength: 0)
        }
        .frame(height: Metrics.height)
    }

    private var landscapeRow: some View {
        HStack(spacing: 16) {
            back15Button
            playPauseButton
            forward15Button
            scrubberRow
            if showsRouteButton { airPlayButton }
            muteUnmuteButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var scrubberRow: some View {
        // Read every frame, so the labels and the bar move with the
        // video and follow a scrub from anywhere at once.
        VideoLiveTime(player: player) { seconds in
            let shown = isScrubbing ? scrubTime : seconds
            HStack(spacing: 0) {
                Text(Self.timeLabel(shown))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: Metrics.leadingLabelWidth, alignment: .leading)
                    .accessibilityIdentifier("video.currentTimeLabel")
                timeSlider(shown)
                // Apollo counts down the time remaining here, unsigned.
                Text(Self.timeLabel(max(0, duration - shown)))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: Metrics.trailingLabelWidth, alignment: .trailing)
                    .accessibilityIdentifier("video.timeRemainingLabel")
            }
            // Never animated: the panel fading in must not slide the
            // thumb across from wherever it was last drawn.
            .transaction { $0.animation = nil }
        }
    }

    // MARK: - Controls

    private func timeSlider(_ shown: Double) -> some View {
        VideoScrubBar(
            value: shown,
            duration: duration,
            onScrub: { seconds in
                if !isScrubbing { isScrubbing = true }
                scrubTime = seconds
                // The picture follows the thumb, not just the release.
                VideoScrubSession.shared(for: player).scrub(to: seconds)
            },
            onEnd: {
                VideoScrubSession.shared(for: player).end(at: scrubTime)
                isScrubbing = false
            }
        )
        .accessibilityIdentifier("video.timeSlider")
    }

    private var playPauseButton: some View {
        Button {
            // By the player's intended rate: `timeControlStatus` reads "waiting"
            // while a just-played video buffers, which would show Play again.
            if player.rate != 0 { player.pause() } else { player.play() }
            isPlaying = player.rate != 0
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundStyle(.white)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        .accessibilityIdentifier("video.playPauseButton")
        // Follows the player: autoplay, the end of a clip, or another
        // control can change it.
        .onReceive(player.publisher(for: \.rate).receive(on: RunLoop.main)) { isPlaying = $0 != 0 }
    }

    private var back15Button: some View {
        Button { skip(by: -Self.skipSeconds) } label: {
            Image(systemName: "gobackward.15")
                .font(.title3)
                .foregroundStyle(.white)
            .accessibilityLabel("Back 15 Seconds")
        }
        .accessibilityIdentifier("video.back15Button")
    }

    private var forward15Button: some View {
        Button { skip(by: Self.skipSeconds) } label: {
            Image(systemName: "goforward.15")
                .font(.title3)
                .foregroundStyle(.white)
            .accessibilityLabel("Forward 15 Seconds")
        }
        .accessibilityIdentifier("video.forward15Button")
    }

    private var muteUnmuteButton: some View {
        Button {
            if let onToggleMute { onToggleMute() } else { player.isMuted.toggle() }
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.title3)
                .foregroundStyle(.white)
        }
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
        .accessibilityIdentifier("video.muteUnmuteButton")
        // Follows the player: another video or the viewer can mute it.
        .onReceive(player.publisher(for: \.isMuted).receive(on: RunLoop.main)) { isMuted = $0 }
    }

    /// Real `AVRoutePickerView`, not a look-alike button: only the
    /// system picker can actually start an AirPlay session.
    private var airPlayButton: some View {
        AirPlayRoutePickerView()
            .frame(width: 28, height: 28)
            .accessibilityIdentifier("video.airPlayButton")
    }

    // MARK: - Behaviour

    /// Mirrors Apollo's `showsRouteButton`: the AirPlay button only
    /// appears when there is somewhere to send the video.
    private func startRouteDetection() {
        let detector = AVRouteDetector()
        detector.isRouteDetectionEnabled = true
        routeDetector = detector
        showsRouteButton = detector.multipleRoutesDetected
        routeObserver = NotificationCenter.default.addObserver(
            forName: .AVRouteDetectorMultipleRoutesDetectedDidChange,
            object: detector,
            queue: .main
        ) { _ in
            showsRouteButton = detector.multipleRoutesDetected
        }
    }

    private func stopRouteDetection() {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        routeObserver = nil
        // Detection keeps scanning (and drains battery) until it is
        // turned off explicitly.
        routeDetector?.isRouteDetectionEnabled = false
        routeDetector = nil
    }

    private func skip(by seconds: Double) {
        let target = max(0, min(duration, currentTime + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// `m:ss`, matching Apollo's own display format. Delegates to
    /// `PhoebusCore` so the smoke test can call the real function.
    static func timeLabel(_ seconds: Double) -> String {
        VideoControlPanelTimeLabel(seconds)
    }

    private func startObserving() {
        isPlaying = player.rate != 0
        isMuted = player.isMuted
        updateDuration()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            if !isScrubbing { currentTime = time.seconds }
            if duration <= 0 { updateDuration() }
        }
    }

    private func updateDuration() {
        guard let item = player.currentItem else { return }
        let d = item.duration.seconds
        if d.isFinite, d > 0 { duration = d }
    }

    private func stopObserving() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}

/// `AVRoutePickerView` bridged into SwiftUI.
struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        // The screen-and-triangle glyph, as Apollo's, not the audio one.
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Apollo's scrub bar: a 4pt rounded track, white up to the time and
/// #868686 after it, with a 17pt white round thumb. Drag or tap anywhere
/// on it to seek.
struct VideoScrubBar: View {
    let value: Double
    let duration: Double
    let onScrub: (Double) -> Void
    let onEnd: () -> Void

    private static let trackHeight: CGFloat = 4
    private static let thumb: CGFloat = 17

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = duration > 0 ? CGFloat(min(max(value / duration, 0), 1)) : 0
            let travel = max(width - Self.thumb, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0x86 / 255, green: 0x86 / 255, blue: 0x86 / 255))
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(.white)
                    .frame(width: Self.thumb / 2 + travel * fraction, height: Self.trackHeight)
                Circle()
                    .fill(.white)
                    .frame(width: Self.thumb, height: Self.thumb)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard duration > 0 else { return }
                        let position = min(max((drag.location.x - Self.thumb / 2) / travel, 0), 1)
                        onScrub(Double(position) * duration)
                    }
                    .onEnded { _ in
                        guard duration > 0 else { return }
                        onEnd()
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Video Progress")
        .accessibilityValue(VideoControlPanelTimeLabel(value))
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = direction == .increment ? 15.0 : -15.0
            onScrub(min(max(value + step, 0), duration))
            onEnd()
        }
    }
}
