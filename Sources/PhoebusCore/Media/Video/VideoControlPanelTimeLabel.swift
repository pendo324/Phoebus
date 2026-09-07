import Foundation

/// `m:ss` (or `h:mm:ss`) for a video's elapsed/total labels.
///
/// In PhoebusCore because the smoke test links PhoebusCore only (PhoebusUI
/// needs UIKit).
///
/// Matches Apollo's control panel format ("0:14", "0:22"): minutes are
/// NOT zero-padded, seconds are.
public func VideoControlPanelTimeLabel(_ seconds: Double) -> String {
    // A duration that has not loaded yet is NaN, and a seek can
    // momentarily report a small negative. Both must render as 0:00
    // rather than as "nan:nan" or "-1:-4".
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}
