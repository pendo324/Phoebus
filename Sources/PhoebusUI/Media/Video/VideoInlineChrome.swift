import SwiftUI
import PhoebusCore

/// The inline mute toggle, flush in the bottom-right corner of a video.
struct VideoMuteBadge: View {
    /// Measured size, shared with `VideoSurfaceTap`'s hit region so the two
    /// cannot drift apart.
    static let size = CGSize(width: 38, height: 37)

    let isMuted: Bool
    /// False when a tap layer over the whole surface owns the touches: two
    /// UIKit controls in one subtree meant the mute button won every hit test.
    let isInteractive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(width: Self.size.width, height: Self.size.height)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.black.opacity(0.55))
                )
        }
        // Plain: a default-styled button turns a `List` row into one whole
        // button, so touching the badge highlighted the entire feed row.
        .buttonStyle(.plain)
        .allowsHitTesting(isInteractive)
        .accessibilityIdentifier("video.inlineMuteButton")
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
    }
}

/// The playback speed menu in the top-right corner of an inline video.
struct VideoInlineSpeedMenu: View {
    let speed: Float
    let onSelect: (Float) -> Void

    var body: some View {
        Menu {
            // A `Toggle`, not a checkmark image: SwiftUI maps
            // a toggle inside a `Menu` onto
            // `UIAction.state`, so UIKit draws the checkmark on
            // the trailing edge; a checkmark image would land in
            // the leading icon slot instead.
            ForEach(MutedVideoPlayerView.playbackSpeeds, id: \.self) { option in
                Toggle(isOn: Binding(
                    get: { option == speed },
                    set: { isOn in
                        guard isOn else { return }
                        onSelect(option)
                    }
                )) {
                    Text(MutedVideoPlayerView.speedTitle(option))
                }
            }
        } label: {
            Image(systemName: "speedometer")
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(6)
                .background(Circle().fill(.black.opacity(0.5)))
            .accessibilityLabel("Playback Speed")
        }
        // Plain for the same reason as the mute badge.
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityIdentifier("video.playbackSpeedMenu")
    }
}

/// Where a tap on an inline video's surface lands.
enum VideoSurfaceTap {
    enum Target { case muteBadge, logo, scrubStrip, fullscreen }

    /// The mute badge's own rect toggles mute; the scrub strip's bottom band
    /// is left alone since it's a drag target; a visible YouTube logo's rect
    /// (`logoRect`) is the logo's; everything else opens fullscreen.
    static func target(at point: CGPoint, in size: CGSize, hasMuteBadge: Bool, hasScrubStrip: Bool,
                       logoRect: CGRect? = nil) -> Target {
        let inMuteBadge = hasMuteBadge
            && point.x >= size.width - VideoMuteBadge.size.width
            && point.y >= size.height - VideoMuteBadge.size.height
        if inMuteBadge { return .muteBadge }
        if let logoRect, logoRect.contains(point) { return .logo }
        if hasScrubStrip, point.y >= size.height - VideoScrubStrip.height { return .scrubStrip }
        return .fullscreen
    }
}

/// Reborn's "Feed Video Scrubber": an invisible touch strip over the bottom
/// of an inline video, with its own thin progress track, that scrubs on drag
/// without opening fullscreen.
///
/// A plain tap on the strip scrubs to that exact position, rather
/// than being forwarded to open-fullscreen: SwiftUI has no bridge
/// for UIKit's "classify by movement, forward on tap" arbitration.
struct VideoScrubStrip: View {
    /// Height of the touch strip; its visible track is 3 pt.
    static let height: CGFloat = 28

    let transport: any VideoTransport
    /// Reads the duration when the transport doesn't know it yet (an
    /// `AVPlayer` item that hasn't loaded).
    var loadDuration: (() async -> Double)?
    @State private var isScrubbing = false
    @State private var scrubFraction: CGFloat = 0
    @State private var wasPlayingBeforeScrub = false
    @State private var loadedDuration: Double = 0

    /// Total duration in seconds, or 0 when unknown/live: never lie
    /// about scrubbing an indefinite-length stream.
    private var duration: Double {
        let seconds = transport.durationSeconds
        return seconds >= 1 ? seconds : loadedDuration
    }

    var body: some View {
        GeometryReader { geo in
            VideoLiveTime(transport: transport) { seconds in
                let duration = duration
                let progress: CGFloat = isScrubbing
                    ? scrubFraction
                    : (duration > 0 ? CGFloat(seconds / duration) : 0)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(height: 3)
                    Rectangle()
                        .fill(.white)
                        .frame(width: max(0, min(1, progress)) * geo.size.width, height: 3)
                }
            }
            .frame(height: Self.height, alignment: .bottom)
            .contentShape(Rectangle())
            .highPriorityGesture(
                // High priority, not plain `.gesture`: this strip is
                // layered inside `PostMediaView`'s media cases,
                // which also attach a whole-view `.onTapGesture`
                // that would otherwise win every time.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let duration = duration
                        guard duration > 0 else { return }
                        if !isScrubbing {
                            isScrubbing = true
                            wasPlayingBeforeScrub = transport.isPlaying
                            // Pauses for the duration of the drag so
                            // the progress only moves as seeks land,
                            // matching the finger.
                            if wasPlayingBeforeScrub { transport.pause() }
                            Haptics.selection()
                        }
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        scrubFraction = fraction
                        VideoScrubSession.shared(for: transport).scrub(to: duration * Double(fraction))
                    }
                    .onEnded { value in
                        let duration = duration
                        guard duration > 0 else { return }
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        isScrubbing = false
                        let resume = wasPlayingBeforeScrub
                        VideoScrubSession.shared(for: transport).end(at: duration * Double(fraction)) {
                            if resume { transport.play() }
                        }
                    }
            )
            .task {
                guard transport.durationSeconds < 1, let loadDuration else { return }
                let seconds = await loadDuration()
                if seconds >= 1 { loadedDuration = seconds }
            }
        }
        .frame(height: Self.height)
        .accessibilityIdentifier("video.feedScrubStrip")
        .accessibilityLabel("Video progress")
    }
}
