import Foundation

/// The gallery viewer's transport clock.
///
/// Format matches Apollo's own gallery time string: `h:mm:ss` once
/// past an hour, `m:ss` otherwise, with a negative or non-finite
/// input clamped to zero rather than rendering "-0:01" or "nan:nan"
/// while an asset is still loading its duration.
///
/// It lives in PhoebusCore, not beside the view, so the smoke test can
/// call the REAL formatter instead of asserting on a copy of it.
public enum GalleryTimeFormat {
    public static func string(_ seconds: Double) -> String {
        var value = seconds
        if !value.isFinite || value < 0 { value = 0 }
        let total = Int(value.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
