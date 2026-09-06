import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// "Copy Text" for a post, comment or message: puts just its raw text on
/// the clipboard. Exposed as a plain context menu action, since SwiftUI's
/// share sheet can't register custom UIActivity items.
public enum PasteboardHelper {
    /// Copy Link: sets the pasteboard's URL (Apollo's activity type is
    /// `com.christianselig.Apollo.CopyLink`), not its string, as Apollo does.
    public static func copy(url: URL) {
        #if canImport(UIKit)
        UIPasteboard.general.url = url
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
    }

    public static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Copies an image's original bytes (a GIF stays a GIF), as
    /// Reborn's feed "Copy Image" does.
    public static func copyImage(_ data: Data) {
        #if canImport(UIKit)
        // A GIF goes on as GIF data, so it stays animated where it's pasted.
        if data.starts(with: Array("GIF8".utf8)) {
            UIPasteboard.general.setData(data, forPasteboardType: "com.compuserve.gif")
        } else if let image = UIImage(data: data) {
            UIPasteboard.general.image = image
        }
        #endif
    }
}
