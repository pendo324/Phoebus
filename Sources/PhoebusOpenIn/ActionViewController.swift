import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

/// A Share Sheet action extension that takes a Reddit URL (or text containing
/// one) from any app and hands it to the main app via a custom URL scheme,
/// matching Apollo's "Open in Apollo" share action.
@objc(ActionViewController)
final class ActionViewController: UIViewController {
    private var resolvedURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        extractURL()
    }

    private func extractURL() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            completeWithFailure()
            return
        }

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                    if let url = item as? URL {
                        DispatchQueue.main.async { self?.handleResolved(url: url) }
                    } else {
                        DispatchQueue.main.async { self?.completeWithFailure() }
                    }
                }
                return
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                    if let text = item as? String, let url = firstURLNonisolated(in: text) {
                        DispatchQueue.main.async { self?.handleResolved(url: url) }
                    } else {
                        DispatchQueue.main.async { self?.completeWithFailure() }
                    }
                }
                return
            }
        }
        completeWithFailure()
    }

    /// Converts a reddit.com URL into the app's custom scheme and opens the
    /// containing app.
    private func handleResolved(url: URL) {
        resolvedURL = url
        guard let appURL = Self.phoebusURL(from: url) else {
            completeWithFailure()
            return
        }
        // Action extensions have no `UIApplication.shared`, but the host app's
        // application object is on the responder chain. The request completes only
        // after the open is handed off; completing first tears the extension down
        // before the app is asked.
        openURLViaResponderChain(appURL) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Calls `-[UIApplication openURL:options:completionHandler:]` through the
    /// runtime: the one-argument `openURL:` was removed in iOS 18 and does
    /// nothing, and the modern method is marked unavailable to extensions.
    private func openURLViaResponderChain(_ url: URL, completion: @escaping () -> Void) {
        typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
        let selector = sel_registerName("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, let method = current.method(for: selector) {
                let open = unsafeBitCast(method, to: OpenURL.self)
                open(current, selector, url as NSURL, NSDictionary(), { _ in DispatchQueue.main.async(execute: completion) })
                return
            }
            responder = current.next
        }
        completion()
    }

    private func completeWithFailure() {
        extensionContext?.cancelRequest(withError: NSError(domain: "PhoebusOpenIn", code: 1))
    }

    /// Maps a reddit.com URL to phoebus://open?url=...; the main app registers
    /// this scheme (CFBundleURLTypes) and routes it to the post, comment or
    /// subreddit screen.
    static func phoebusURL(from redditURL: URL) -> URL? {
        guard let host = redditURL.host?.lowercased(),
              ["reddit.com", "redd.it"].contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return nil }
        var components = URLComponents()
        components.scheme = "phoebus"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: redditURL.absoluteString)]
        return components.url
    }
}

/// Non-actor-isolated URL extraction, callable from the non-main-actor
/// completion handler in extractURL().
nonisolated func firstURLNonisolated(in text: String) -> URL? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let range = NSRange(text.startIndex..., in: text)
    return detector?.firstMatch(in: text, range: range)?.url
}
