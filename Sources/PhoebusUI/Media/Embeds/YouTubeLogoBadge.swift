import SwiftUI
import UIKit
import PhoebusCore

/// The YouTube logo on the app's player when it fronts a YouTube video: a
/// red rounded play mark with a white triangle, then the wordmark in white,
/// drawn here rather than shipped as an image. It shows while the video is
/// paused, not yet played or ended, and tapping it opens the video on
/// YouTube.
struct YouTubeLogoBadge: View {
    /// The height of the play mark; the wordmark is sized to it.
    var height: CGFloat = 16

    /// The badge's size, fixed so a tap layer can hit-test its rect.
    static func size(height: CGFloat) -> CGSize {
        CGSize(width: height * (1.43 + 0.18 + 3.45), height: height)
    }

    /// The tappable area around the badge.
    static let tapPadding: CGFloat = 6

    /// The badge's tap rect inside a picture of `size`, `bottomInset` up from
    /// its bottom edge and `leadingInset` in from its left.
    static func tapRect(height: CGFloat, in size: CGSize, leadingInset: CGFloat = 2, bottomInset: CGFloat) -> CGRect {
        let badge = Self.size(height: height)
        let width = badge.width + tapPadding * 2
        let tapHeight = badge.height + tapPadding * 2
        return CGRect(x: leadingInset, y: size.height - bottomInset - tapHeight, width: width, height: tapHeight)
    }

    var body: some View {
        HStack(spacing: height * 0.18) {
            ZStack {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .fill(Color(red: 1, green: 0, blue: 0))
                YouTubePlayTriangle()
                    .fill(.white)
                    .frame(width: height * 0.36, height: height * 0.4)
                    .offset(x: height * 0.03)
            }
            .frame(width: height * 1.43, height: height)
            Text("YouTube")
                .font(.system(size: height * 0.95, weight: .bold))
                .tracking(-height * 0.05)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: height * 3.45, alignment: .leading)
        }
        .frame(width: Self.size(height: height).width, height: height)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 0.5)
        .accessibilityHidden(true)
    }
}

private struct YouTubePlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Opens a YouTube video from the logo, at the player's current time, with
/// the player paused first.
@MainActor
enum YouTubeLogoLink {
    static func open(_ bridge: YouTubePlayerBridge, openURL: OpenURLAction? = nil) {
        bridge.pause()
        guard let url = YouTubeURLParser.nativeAppURL(forVideoID: bridge.videoID,
                                                      startSeconds: Int(bridge.currentSeconds)) else { return }
        if let openURL { openURL(url) } else { UIApplication.shared.open(url) }
    }

    /// The badge as an image, for UIKit.
    static func image(height: CGFloat, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: YouTubeLogoBadge(height: height).padding(4))
        renderer.scale = scale
        return renderer.uiImage
    }
}

/// The logo over a picture: faded in while the video isn't playing, out while
/// it is. It isn't hit-testable itself; the inline picture's tap layer routes
/// a tap in `YouTubeLogoBadge.tapRect` to `YouTubeLogoLink`.
struct YouTubeLogoOverlay: View {
    @ObservedObject var bridge: YouTubePlayerBridge
    var height: CGFloat = 16
    @Environment(\.openURL) private var openURL

    var body: some View {
        YouTubeLogoBadge(height: height)
            .padding(YouTubeLogoBadge.tapPadding)
            .opacity(bridge.isPlaying ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: bridge.isPlaying)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Watch on YouTube")
            .accessibilityAddTraits(.isButton)
            .accessibilityHidden(bridge.isPlaying)
            .accessibilityIdentifier("youtube.logo")
            .accessibilityAction { YouTubeLogoLink.open(bridge, openURL: openURL) }
    }
}

/// The tappable logo for a SwiftUI screen that doesn't route taps itself.
struct YouTubeLogoButton: View {
    @ObservedObject var bridge: YouTubePlayerBridge
    var height: CGFloat = 20
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            YouTubeLogoLink.open(bridge, openURL: openURL)
        } label: {
            YouTubeLogoBadge(height: height)
                .padding(YouTubeLogoBadge.tapPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(bridge.isPlaying ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: bridge.isPlaying)
        .allowsHitTesting(!bridge.isPlaying)
        .accessibilityHidden(bridge.isPlaying)
        .accessibilityLabel("Watch on YouTube")
        .accessibilityIdentifier("youtube.logo")
    }
}
