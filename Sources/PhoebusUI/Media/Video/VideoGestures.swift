import SwiftUI
import PhoebusCore

/// Reborn's "Hold for Video Speed" (#78) against any `VideoTransport`: a
/// finger resting on the right third of a fullscreen video for a moment
/// speeds it up until lifted; moving first (a swipe) or a quick tap doesn't.
@MainActor
final class VideoHoldForSpeed: ObservableObject {
    @Published private(set) var isHolding = false
    private var pending: Task<Void, Never>?
    private var rateBeforeHold: Double = 1

    func start(_ transport: any VideoTransport, speed: Float) {
        guard !isHolding else { return }
        isHolding = true
        rateBeforeHold = transport.playbackRate == 0 ? 1 : transport.playbackRate
        transport.setPlaybackRate(Double(speed))
        Haptics.selection()
    }

    func end(_ transport: any VideoTransport) {
        pending?.cancel()
        pending = nil
        guard isHolding else { return }
        isHolding = false
        transport.setPlaybackRate(rateBeforeHold)
    }

    /// Hold for Video Speed, on the surface layer that owns the video's
    /// touches. Armed after 250 ms on the right third, cancelled by more than
    /// 12 pt of movement.
    func gesture(width: CGFloat, isEnabled: Bool, transport: any VideoTransport, speed: Float) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { [self] value in
                guard isEnabled, value.startLocation.x > width * 2 / 3 else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                if isHolding { return }
                if moved > 12 {
                    pending?.cancel()
                    pending = nil
                    return
                }
                guard pending == nil else { return }
                pending = Task { @MainActor [self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    start(transport, speed: speed)
                }
            }
            .onEnded { [self] _ in end(transport) }
    }
}

/// The "2×" capsule shown while a hold speeds the video up.
struct VideoHoldSpeedBadge: View {
    let speed: Float

    var body: some View {
        Text(speed.formatted() + "\u{00D7}")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.6)))
            .allowsHitTesting(false)
            .accessibilityIdentifier("video.holdForSpeedIndicator")
    }
}

/// Apollo's own hold-and-drag scrub for a fullscreen video, against any
/// `VideoTransport`: it pauses the video while the finger drags, seeks
/// relative to where the scrub began, and resumes if it was playing. Covers
/// the left two-thirds when Hold for Video Speed owns the right third.
struct VideoGestureScrubLayer: View {
    let transport: any VideoTransport
    let leavesRightThird: Bool
    @State private var isActive = false
    @State private var startTime: Double = 0
    @State private var wasPlaying = false

    var body: some View {
        GeometryReader { geo in
            let scrubWidth = leavesRightThird ? geo.size.width * 2 / 3 : geo.size.width
            VideoScrubGestureCatcher(
                scrubDuration: {
                    let duration = transport.durationSeconds
                    return duration > 0 ? duration : nil
                },
                onScrubBegan: {
                    wasPlaying = transport.isPlaying
                    startTime = transport.currentSeconds
                    isActive = true
                    Haptics.selection()
                    transport.pause()
                    return startTime
                },
                onScrubChanged: { fraction, duration in
                    guard isActive else { return }
                    let target = max(0, min(duration, startTime + Double(fraction) * duration))
                    VideoScrubSession.shared(for: transport).scrub(to: target)
                },
                onScrubEnded: {
                    guard isActive else { return }
                    isActive = false
                    let resume = wasPlaying
                    VideoScrubSession.shared(for: transport).end {
                        if resume { transport.play() }
                    }
                })
                .frame(width: scrubWidth, height: geo.size.height)
                .position(x: scrubWidth / 2, y: geo.size.height / 2)
        }
    }
}
