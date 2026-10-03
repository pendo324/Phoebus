import Foundation
#if canImport(SafariServices)
import SafariServices
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Native host for the "Open in Phoebus" Safari Web Extension.
/// A content script validates the page URL and produces
/// `phoebus://<host>/<path>`; this class exists because Safari
/// requires a principal class for the extension point.
///
/// A custom scheme is used rather than a Universal Link because the
/// `apple-app-site-association` file is keyed on Team ID + bundle ID, which
/// a sideloaded build can never match.
///
/// A plain `window.location = "phoebus://..."` always raises iOS's "Open in
/// Phoebus?" confirmation, but this extension is packaged inside the app, so
/// `NSExtensionContext.open(_:)` is not a cross-app launch. Whether Safari
/// grants it from a web-extension context varies by iOS version, so the
/// result is returned and the content script falls back to a scheme
/// navigation on anything but explicit success.
@objc(SafariWebExtensionHandler)
public final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    public func beginRequest(with context: NSExtensionContext) {
        guard let url = Self.requestedURL(in: context) else {
            // Not an open request (or not a trusted one). Complete immediately;
            // leaving it hanging makes Safari log a misbehaving extension.
            Self.reply(opened: false, to: context)
            return
        }

        #if canImport(UIKit)
        // Called directly rather than dispatched to main: `beginRequest` already
        // arrives on the main thread, and hopping would send the non-Sendable
        // context across an isolation boundary. The reply waits for the result so
        // the content script's fallback is not skipped.
        context.open(url) { opened in
            Self.reply(opened: opened, to: context)
        }
        #else
        Self.reply(opened: false, to: context)
        #endif
    }

    /// Extracts the URL to open, rejecting anything outside the app's scheme so
    /// a spoofed page cannot use this handler to open arbitrary URLs.
    static func requestedURL(in context: NSExtensionContext) -> URL? {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[Self.messageKey] as? [String: Any],
              message["action"] as? String == "open",
              let string = message["url"] as? String,
              let url = URL(string: string)
        else { return nil }
        return isOwnScheme(url) ? url : nil
    }

    /// The app's own scheme, compared case-insensitively (RFC 3986; `URL` does
    /// not normalise schemes).
    static func isOwnScheme(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "phoebus"
    }

    /// Key Safari uses for `sendNativeMessage` payloads: `SFExtensionMessageKey`
    /// where SafariServices is available; the literal keeps this file compiling
    /// and testable where it is not.
    static let messageKey = "message"

    private static func reply(opened: Bool, to context: NSExtensionContext) {
        let item = NSExtensionItem()
        item.userInfo = [messageKey: ["opened": opened]]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
