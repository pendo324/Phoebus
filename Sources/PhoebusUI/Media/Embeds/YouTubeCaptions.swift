#if canImport(UIKit)
import UIKit
import MediaAccessibility

/// Whether the system caption settings ask for captions.
enum YouTubeCaptions {
    /// True when Closed Captions + SDH is on or Subtitles is set to On for
    /// this app.
    @MainActor
    static var wanted: Bool {
        UIAccessibility.isClosedCaptioningEnabled
            || MACaptionAppearanceGetDisplayType(.user) == .alwaysOn
    }
}
#else
enum YouTubeCaptions {
    @MainActor static var wanted: Bool { false }
}
#endif
