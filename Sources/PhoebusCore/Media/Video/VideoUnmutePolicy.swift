import Foundation

/// Where a video plays, which decides the setting that owns its sound.
/// Each video is owned by exactly one, as in Apollo-Reborn.
public enum VideoUnmuteContext: Sendable {
    /// Feed rows: Reborn's "Unmute Videos in Feed".
    case feed
    /// The post's own video at the top of comments: Reborn's "Unmute
    /// Videos in Comments" (Default / Remember from Fullscreen / Always).
    case commentsHeader
    /// The fullscreen viewer: stock "Unmute Videos When Opened".
    case fullscreen
    /// A video embedded in a comment or post body: always starts muted.
    case embed
}

public enum VideoUnmutePolicy {
    /// Whether a video starts muted.
    /// - `feedRememberedMuted`: the feed's own last manual choice.
    /// - `fullscreenUnmutedThisSession`: stock "Remember" keeps an
    ///   unmute until the user re-mutes or the app closes.
    /// - `alreadyAudible`: the viewer shares the inline video's player, so
    ///   a video already playing with sound keeps it when opened.
    public static func startsMuted(_ context: VideoUnmuteContext, settings: GeneralSettings,
                                   feedRememberedMuted: Bool, fullscreenUnmutedThisSession: Bool,
                                   alreadyAudible: Bool = false) -> Bool {
        if context == .fullscreen, alreadyAudible { return false }
        switch context {
        case .feed:
            switch settings.unmuteFeedVideosMode {
            case .never: return true
            case .always: return false
            case .remember: return feedRememberedMuted
            }
        case .commentsHeader:
            return settings.unmuteCommentsVideosMode != .always
        case .fullscreen:
            switch settings.unmuteVideosWhenOpened {
            case .never: return true
            case .always: return false
            case .remember: return !fullscreenUnmutedThisSession
            }
        case .embed:
            return true
        }
    }

    /// The comments-header video's mute state once the fullscreen viewer
    /// closes, given the state the viewer was left in.
    public static func headerMutedAfterFullscreen(mode: VideoUnmuteMode, fullscreenMuted: Bool) -> Bool {
        switch mode {
        case .never: return true
        case .remember: return fullscreenMuted
        case .always: return false
        }
    }
}

extension VideoUnmuteMode {
    /// Reborn's titles for "Unmute Videos in Comments".
    public var commentsDisplayName: String {
        switch self {
        case .never: return "Default"
        case .remember: return "Remember"
        case .always: return "Always"
        }
    }
}
