import SwiftUI
import PhoebusCore
#if canImport(SafariServices)
import SafariServices
#endif

/// Opens external links in an in-app Safari sheet rather than kicking
/// the user out to the standalone Safari app, matching Apollo's default
/// link-handling behavior.
#if canImport(SafariServices) && canImport(UIKit)
public struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL
    /// "Show Comments Button": Apollo's floating button in the browser
    /// that goes to the post's comments. Nil where there is no post.
    var onComments: (() -> Void)?

    public init(url: URL, onComments: (() -> Void)? = nil) {
        self.url = url
        self.onComments = onComments
    }

    /// `SFSafariViewController` accepts only http/https and raises an
    /// unrecoverable ObjC exception for anything else. `LinkRouter
    /// .absoluteRedditURL` resolves scheme-relative links before they get here,
    /// but this view is reachable from several call sites, so it also refuses
    /// to hand Safari a URL it rejects.
    static func safeURL(_ url: URL) -> URL {
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" { return url }
        // A scheme-relative Reddit path is the common real case.
        if url.scheme == nil, url.absoluteString.hasPrefix("/"),
           let resolved = URL(string: "https://www.reddit.com" + url.absoluteString) {
            return resolved
        }
        // Anything else (a custom scheme, a malformed link) becomes a
        // harmless about:blank rather than a crash.
        return URL(string: "https://www.reddit.com")!
    }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        // Settings key: `AlwaysUseReaderMode`.
        configuration.entersReaderIfAvailable = GeneralSettingsStore.load().alwaysUseReaderMode
        let controller = SFSafariViewController(url: Self.safeURL(url), configuration: configuration)
        controller.delegate = context.coordinator
        // Bars can be coloured from the host even though the page
        // cannot, so tint them to remove the bright chrome (dark-mode
        // white flash; see `SafariDarkLoadingPolicy`).
        controller.preferredBarTintColor = .black
        controller.preferredControlTintColor = .systemBlue
        context.coordinator.install(on: controller)
        if let onComments, GeneralSettingsStore.load().showCommentsButton {
            context.coordinator.installCommentsButton(on: controller, action: onComments)
        }
        return controller
    }

    public func makeCoordinator() -> SafariDarkLoadingCoordinator {
        SafariDarkLoadingCoordinator()
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Holds an opaque black view over the out-of-process page while it
/// makes its white first paint in dark mode, then fades it. Touches
/// pass through so the close button and edge-swipe keep working.
@MainActor
public final class SafariDarkLoadingCoordinator: NSObject, @MainActor SFSafariViewControllerDelegate {
    private weak var shield: UIView?
    private var finished = false
    private var commentsAction: (() -> Void)?
    private weak var commentsButton: UIView?

    /// A blurred circle with the stock comment bubble, above the
    /// browser's bottom toolbar.
    func installCommentsButton(on controller: SFSafariViewController, action: @escaping () -> Void) {
        commentsAction = action
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        blur.layer.cornerRadius = 24
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        let button = UIButton(type: .system)
        button.setImage(StockIcon.image(named: "safari-vc-comments", size: CGSize(width: 25, height: 23)), for: .normal)
        button.tintColor = .systemBlue
        button.accessibilityLabel = "Comments"
        button.accessibilityIdentifier = "safari.commentsButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(commentsTapped), for: .touchUpInside)
        blur.contentView.addSubview(button)
        controller.view.addSubview(blur)
        commentsButton = blur
        // Safari's own page view is added after this; keep the button above it.
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak blur] in
                guard let blur else { return }
                blur.superview?.bringSubviewToFront(blur)
            }
        }
        NSLayoutConstraint.activate([
            blur.widthAnchor.constraint(equalToConstant: 48),
            blur.heightAnchor.constraint(equalToConstant: 48),
            blur.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            blur.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            button.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
        ])
    }

    @objc private func commentsTapped() { commentsAction?() }

    func install(on controller: SFSafariViewController) {
        // Only in dark mode: in light mode a blank white page is the
        // correct intermediate state.
        guard SafariDarkLoadingPolicy.shouldShield(
            isDarkMode: controller.traitCollection.userInterfaceStyle == .dark
        ) else { return }

        let shield = UIView()
        shield.backgroundColor = .black
        shield.isUserInteractionEnabled = false
        shield.translatesAutoresizingMaskIntoConstraints = false
        shield.accessibilityIdentifier = "safari.darkLoadingShield"
        controller.view.addSubview(shield)
        NSLayoutConstraint.activate([
            shield.topAnchor.constraint(equalTo: controller.view.topAnchor),
            shield.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            shield.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            shield.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
        ])
        self.shield = shield

        // No web-view callback is exposed to third-party hosts, so
        // this falls back to a fixed hold from presentation, then a
        // long ramp so a still-blank page brightens gradually.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SafariDarkLoadingPolicy.holdFallback * 1_000_000_000))
            guard let self, !self.finished else { return }
            UIView.animate(withDuration: SafariDarkLoadingPolicy.rampDuration) {
                self.shield?.alpha = 0
            } completion: { _ in
                self.shield?.removeFromSuperview()
            }
        }
    }

    /// The shield fades out immediately once the service reports the
    /// initial load finished, rather than waiting out the hold.
    public func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        finished = true
        if let commentsButton { commentsButton.superview?.bringSubviewToFront(commentsButton) }
        guard let shield, shield.superview != nil else { return }
        UIView.animate(withDuration: SafariDarkLoadingPolicy.finishDuration) {
            shield.alpha = 0
        } completion: { _ in
            shield.removeFromSuperview()
        }
    }
}
#endif

/// The post on screen, whose comments the in-app browser's "Show
/// Comments Button" goes to when a link is opened from it.
@MainActor
public enum InAppBrowserContext {
    private static var postID: String?
    static var commentsAction: (() -> Void)?

    public static func set(postID: String, commentsAction: (() -> Void)?) {
        self.postID = postID
        self.commentsAction = commentsAction
    }

    public static func clear(postID: String) {
        guard self.postID == postID else { return }
        self.postID = nil
        commentsAction = nil
    }
}

/// Convenience modifier: presents a link in an in-app Safari sheet
/// instead of opening the system Safari app.
public extension View {
    func apolloInAppBrowser(url: Binding<URL?>, onComments: (() -> Void)? = nil) -> some View {
        #if canImport(SafariServices) && canImport(UIKit)
        return self.sheet(item: url) { wrapped in
            InAppSafariView(url: wrapped, onComments: (onComments ?? InAppBrowserContext.commentsAction).map { comments in
                { url.wrappedValue = nil; comments() }
            })
                .ignoresSafeArea()
        }
        #else
        return self
        #endif
    }
}

/// "Open in App": hands a link to its enabled dedicated app, calling
/// `fallback` when there's no such app or it isn't installed. Returns false
/// when no enabled service claims the link.
@MainActor
public enum DedicatedAppOpener {
    @discardableResult
    public static func open(_ url: URL, fallback: @escaping @MainActor () -> Void) -> Bool {
        #if canImport(UIKit)
        guard let target = DedicatedAppLink.appTarget(
            for: url, youTubeEnabled: GeneralSettingsStore.load().openVideosInYouTubeApp) else { return false }
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] =
            target.universalLinksOnly ? [.universalLinksOnly: true] : [:]
        UIApplication.shared.open(target.url, options: options) { opened in
            if !opened { MainActor.assumeIsolated { fallback() } }
        }
        return true
        #else
        return false
        #endif
    }
}

/// Opens a link honoring the user's "Open Links In" browser
/// preference. Falls back to the in-app browser/Safari when the
/// preferred browser's translated URL fails to open (app not installed).
public struct ExternalLinkOpener {
    @MainActor
    public static func open(_ url: URL, openURL: OpenURLAction, fallback: @escaping (URL) -> Void) {
        // A service that claims this link gets first refusal, before
        // the browser preference is consulted, so e.g. a github.com
        // link doesn't open in Chrome when "GitHub" app is preferred.
        //
        // Universal Links, not a custom scheme: iOS opens the app when
        // installed and reports failure otherwise, so the fallback is exact.
        if DedicatedAppOpener.open(url, fallback: {
            // Fall through to normal handling rather than leaving the
            // tap dead.
            openInPreferredBrowser(url, openURL: openURL, fallback: fallback)
        }) { return }
        openInPreferredBrowser(url, openURL: openURL, fallback: fallback)
    }

    @MainActor
    private static func openInPreferredBrowser(_ url: URL, openURL: OpenURLAction, fallback: @escaping (URL) -> Void) {
        // Open Tweets in… Default Browser: the system's default, whatever
        // Open Links In says.
        if LinkRouter.isTwitterURL(url), GeneralSettingsStore.load().openTwitterLinksIn == .externalBrowser {
            #if canImport(UIKit)
            UIApplication.shared.open(url) { opened in if !opened { fallback(url) } }
            #endif
            return
        }
        let settings = ExternalBrowserSettingsStore.load()
        switch settings.preferredBrowser {
        case .inApp:
            fallback(url)
        case .safari:
            openURL(url)
        default:
            guard let translated = settings.preferredBrowser.translate(url) else {
                fallback(url)
                return
            }
            openURL(translated) { accepted in
                if !accepted {
                    fallback(url)
                }
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
