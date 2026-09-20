import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Loads the currently selected app icon's own artwork for the
/// Settings root's "App Icon" row.
///
/// Apollo shows the selected icon's art there, drawn at 29x29 in a
/// radius-6 rounded rect, not a tinted SF Symbol. Alternate icons live
/// at the bundle root where `Image(_:)` cannot reach them, hence
/// `UIImage`.
public enum AppIconArtwork {
    /// The selected icon's artwork, or nil when it cannot be loaded (the
    /// row then falls back to the symbol tile).
    public static func current() -> Image? {
        artwork(for: AppIconStore.load().id)
    }

    public static func artwork(for id: String) -> Image? {
        #if canImport(UIKit)
        // The default icon ships under its real slug, not "original", the
        // same mapping the picker's loader uses.
        let slug = id == "original" ? "Original" : id
        for scale in ["@3x", "@2x"] {
            if let path = Bundle.main.path(forResource: "AppIcon-\(slug)60x60\(scale)",
                                           ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                return Image(uiImage: image)
            }
        }
        return nil
        #else
        return nil
        #endif
    }
}
