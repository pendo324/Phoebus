import Foundation

/// The video player's playback-speed menu.
///
/// Apollo's own speeds are 0.25x, 0.5x, 1x (default), 1.5x, 2x. Reborn adds
/// 0.75x after 0.5x and 1.25x before 1.5x (#445), keeping ascending order.
///
/// Lives in PhoebusCore so the ordering and titles are assertable without a
/// UI host.
public enum VideoPlaybackSpeeds {
    public static let all: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2]

    /// `SpeedTitle`, including its U+00D7 multiplication sign (written as an
    /// explicit codepoint so source encoding can't drift).
    public static func title(_ speed: Float) -> String {
        if speed == 1 { return "Playback Speed (1\u{00D7})" }
        let label: String
        switch speed {
        case 0.25: label = "0.25"
        case 0.5: label = "0.5"
        case 0.75: label = "0.75"
        case 1.25: label = "1.25"
        case 1.5: label = "1.5"
        case 2: label = "2"
        default: label = String(format: "%g", speed)
        }
        return "Playback Speed (\(label)\u{00D7})"
    }
}
