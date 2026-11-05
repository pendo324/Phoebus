import Foundation

/// "Inline YouTube Player" (Phoebus-only; Apollo and Reborn always play inline):
/// decides whether a YouTube video draws the app's embedded player or only a
/// thumbnail that opens YouTube. Pure logic, so the smoke suite can assert it.
public enum YouTubeInlinePolicy {
    public enum Presentation: Equatable, Sendable {
        /// The IFrame player under the app's own controls.
        case inlinePlayer
        /// Apollo's "Open Videos in YouTube App": a thumbnail that hands the
        /// video to the YouTube app.
        case thumbnailOpensYouTubeApp
        /// "Inline YouTube Player" off: a thumbnail that opens the video like any
        /// other link, through "Open Links In".
        case thumbnailOpensLink

        /// Whether the embed page, its web view and the YouTube sign-in are
        /// used before a tap. The thumbnails load one image and nothing else.
        public var createsPlayer: Bool { self == .inlinePlayer }
    }

    /// Open in YouTube App is the user's stronger choice, so it wins over the
    /// inline player; with neither, the video plays in the post.
    public static func presentation(inlinePlayerEnabled: Bool, openInYouTubeApp: Bool) -> Presentation {
        if openInYouTubeApp { return .thumbnailOpensYouTubeApp }
        return inlinePlayerEnabled ? .inlinePlayer : .thumbnailOpensLink
    }

    public static func presentation(settings: GeneralSettings) -> Presentation {
        presentation(inlinePlayerEnabled: settings.inlineYouTubePlayer, openInYouTubeApp: settings.openVideosInYouTubeApp)
    }

    /// The presentation for a URL, or nil when it isn't a YouTube video link
    /// (another host, or a YouTube page with no video).
    public static func presentation(for url: URL, settings: GeneralSettings) -> Presentation? {
        guard LinkPreviewHosts.isYouTube(url), YouTubeURLParser.extractVideoID(from: url) != nil else { return nil }
        return presentation(settings: settings)
    }

    /// Whether the YouTube sign-in (Accounts & Security) does anything: it
    /// signs in the player's web views, so only the inline player uses it. A
    /// thumbnail opens YouTube in the browser or the YouTube app, which have
    /// their own sign-ins.
    public static func usesYouTubeSignIn(_ presentation: Presentation) -> Bool {
        presentation.createsPlayer
    }
}
