import Foundation

/// Timing for the in-app browser's dark-mode loading shield (Reborn #1008,
/// #1052).
///
/// `SFSafariViewController` renders out of process. Its chrome comes up dark
/// immediately, but once WebKit's content process paints its first frame
/// the page area is an empty WHITE document until the real page paints, so
/// in dark mode every link opens with a white flash.
///
/// Nothing in the host can colour the remote page (`preferredBarTintColor`
/// only reaches the bars, and iOS 26's glass chrome ignores even that), so
/// the host covers the browser with an opaque black view while its trait
/// collection is dark, holds it across the white first frame, then fades.
/// The constants are Reborn's.
public enum SafariDarkLoadingPolicy {
    /// Opaque hold after the view service creates its web view - the
    /// white first frame lands right after that callback, which is
    /// where the cover actually matters.
    public static let holdAfterWebView: TimeInterval = 0.8

    /// Hold used when the web-view callback never arrives (older
    /// SafariServices without that delegate method), measured from
    /// `viewDidAppear`.
    public static let holdFallback: TimeInterval = 1.5

    /// Long fade for a page that has not finished loading: a gradual
    /// brightening rather than a flash, with painted content showing
    /// through as it goes.
    public static let rampDuration: TimeInterval = 1.4

    /// Quick fade once the service reports the initial load is done.
    public static let finishDuration: TimeInterval = 0.25

    /// Whether the shield should be installed at all: only while the browser's
    /// trait collection is DARK. In light mode a white blank page is the
    /// expected intermediate state, so covering it would be wrong.
    public static func shouldShield(isDarkMode: Bool) -> Bool { isDarkMode }
}
