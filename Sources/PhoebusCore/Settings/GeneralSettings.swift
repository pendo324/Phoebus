import Foundation

/// Real Apollo setting `enableCompactThumbnails`/`enableLargeThumbnails`
/// ("Large Thumbnails"): `.compact` is the default dense row, `.large`
/// a taller card with a full-width image beneath the title.
public enum PostDisplayStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case compact
    case large

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .large: return "Large Thumbnails"
        }
    }
}

/// Matches Apollo's `CompactPostsThumbnailSize` setting (default
/// `small`). Point sizes follow the setting's own small/medium/large
/// convention.
public enum ThumbnailSize: String, Codable, Sendable, CaseIterable, Identifiable {
    case hidden
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var displayName: String {
        self == .hidden ? "No Thumbnails" : rawValue.capitalized
    }

    public var pointSize: CGFloat {
        switch self {
        case .hidden: return 0
        case .small: return 56
        case .medium: return 80
        case .large: return 112
        }
    }
}

/// Reborn's Rich Link Preview card style picker, separate from PhoebusUI's
/// `LinkPreviewStyle` view parameter type.
public enum LinkPreviewStyleSetting: String, Codable, Sendable, CaseIterable, Identifiable {
    case full
    case compact

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}
/// Reborn's `UDKeyNSFWBlurOverride` ("Blur NSFW Media"): a device-only
/// override of the account's Reddit NSFW-blur pref.
public enum NSFWBlurOverride: Int, Codable, Sendable, CaseIterable, Identifiable {
    case redditSetting = 0
    case always = 1
    case never = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .redditSetting: return "Reddit Setting"
        case .always: return "Always"
        case .never: return "Never"
        }
    }
}

/// Reborn's `UDKeyImageUploadProvider` ("Media Upload Host"): where
/// images/media attached to new posts are uploaded. Default Imgur.
public enum MediaUploadHost: Int, Codable, Sendable, CaseIterable, Identifiable {
    case imgur = 0
    case reddit = 1
    case imgChest = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .imgur: return "Imgur"
        case .reddit: return "Reddit"
        case .imgChest: return "Image Chest"
        }
    }
}

/// Reborn's `UDKeyCommentLinkHost` ("Comment Link Host"): separate host
/// for images added to a comment, distinct from `MediaUploadHost`.
/// Default Off.
public enum CommentLinkHost: Int, Codable, Sendable, CaseIterable, Identifiable {
    case off = 0
    case imgur = 1
    case imgChest = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .imgur: return "Imgur"
        case .imgChest: return "Image Chest"
        }
    }
}
public struct GeneralSettings: Codable, Sendable, Equatable {
    /// Matches Apollo's `CompactModeLeftThumbnails` (default: true): whether
    /// the row thumbnail sits left of the title or right of it.
    public var thumbnailsOnLeft: Bool
    /// Matches Apollo's `CompactPostsThumbnailSize` (default: small).
    public var thumbnailSize: ThumbnailSize
    /// Real key: `enableCompactThumbnails` / `enableLargeThumbnails`
    /// ("Large Thumbnails" toggle). Governs the whole feed row layout;
    /// see `PostDisplayStyle`'s doc comment.
    public var postDisplayStyle: PostDisplayStyle
    /// Matches Apollo's `OpenVideosInYouTubeApp` setting (default
    /// false) — when true, tapping a YouTube link opens the native app
    /// instead of playing inline via the embedded IFrame player.
    public var openVideosInYouTubeApp: Bool
    /// Reborn "Show User Profile Pictures": small avatar next to author
    /// usernames. Off by default (extra network cost).
    public var showUserProfilePictures: Bool
    /// Reborn "Rich Link Previews": a link post's URL renders as an OpenGraph
    /// card instead of a plain link row.
    public var showRichLinkPreviews: Bool
    /// Full (image-on-top) or compact (thumbnail-left) card layout for
    /// rich link previews, matching Apollo-Reborn's two-style picker.
    public var linkPreviewStyle: LinkPreviewStyleSetting
    /// Phoebus addition: subreddit icons use the current community icon,
    /// falling back to the classic one. Off is Apollo's classic-only rule
    /// (a subreddit without one gets the letter badge).
    public var useCommunityIcons: Bool = true
    /// Reborn "Collapse Navigation Actions" (`CollapseNavigationActions`,
    /// default off): actions strip collapses on scroll/back-gesture
    /// triggers when on. Visible only under Liquid Glass.
    public var collapseNavigationActions: Bool
    /// Reborn "Return Button" (real key `ScrollReturnButton`, default
    /// on). Only gates the visible affordance (arrow beside Back, nav
    /// bar tap); the saved-position restore and double status-bar-tap
    /// stay unconditional regardless of this setting.
    public var scrollReturnButton: Bool
    /// Real Apollo "New Comments Highlightifier": highlights comments
    /// posted since last visit. Distinct from `highlightAccountAge`.
    public var newCommentsHighlightifier: Bool
    /// Real Apollo "Show Awards" (Settings > Appearance > Other):
    /// show or hide Reddit award icons on posts and comments.
    public var showAwards: Bool
    /// Real Apollo "Post Flair" (Settings > Appearance > Flair):
    /// show or hide a post's own link flair chip.
    public var showPostFlair: Bool
    /// Real key: `ExcludeSubsFromAllPopular` ("No Subscribed in
    /// All/Popular") — hides posts from subreddits you're subscribed
    /// to when browsing r/all or r/popular.
    public var excludeSubscribedFromAllPopular: Bool
    /// Real key: `LiveTextAnalyzer` — iOS Live Text OCR support for
    /// images shown in the media viewer.
    public var liveTextAnalyzer: Bool
    /// Real key: `HighlightAccountAge` ("New Account Highlight") —
    /// visually flags comments/posts from very new Reddit accounts.
    public var highlightAccountAge: Bool
    /// Real key: `IgnoreSuggestedSort` — ignores a subreddit
    /// moderator's suggested comment sort, always using the user's
    /// own default instead.
    public var ignoreSuggestedSort: Bool
    /// Real key: `RememberRedditCommentsSort` ("Remember Subreddit
    /// Sort"). `GeneralSettingsScreen`'s row reads/writes
    /// `CommentSortMemoryStore`'s `.subreddit` mode instead; this field
    /// is kept only so old persisted JSON still decodes.
    public var rememberCommentsSortPerSubreddit: Bool
    /// Real key: `DoomscrollDefeater3` ("Infinite Scrolling") — when
    /// false, feeds stop auto-loading more pages past a point,
    /// requiring an explicit tap to continue (a doomscrolling guard).
    public var infiniteScrollingEnabled: Bool
    /// Real key: `RememberRedditPostsSort` ("Remember Subreddit
    /// Sort") — the posts-sort analog of
    /// `rememberCommentsSortPerSubreddit`.
    public var rememberPostsSortPerSubreddit: Bool
    /// Real key: `HapticFeedback` (default on). Gates every
    /// `Haptics.light/medium/selection` call site throughout the app.
    public var hapticFeedbackEnabled: Bool

    /// Apollo-Reborn's Liquid Glass Tab Bar — a rounded floating pill
    /// tab bar, inset from the screen edges, translucent with content
    /// visible underneath, rather than a full-width opaque system tab
    /// bar. On by default, matching the real app.
    public var enableLiquidGlassTabBar: Bool

    /// Master switch for Liquid Glass chrome across the app. Mirrors
    /// `LiquidGlass.preferenceEnabled` in `UserDefaults` so it participates
    /// in backup/restore; `GeneralSettingsStore.save` writes through.
    public var enableLiquidGlass: Bool
    /// Real key: `sLGTitleGapCentering`, Liquid-Glass-only. Cosmetically
    /// inert here: SwiftUI's `.principal` toolbar item already centers.
    public var centerTitleGapCentering: Bool
    // MARK: - Shortcuts section

    /// Real key: `sEnableFlairColors` ("Color Flairs", default on).
    /// Governs whether link/user flair badges render with their real
    /// per-subreddit colors or fall back to plain monochrome capsules.
    public var enableFlairColors: Bool
    // MARK: - Media sub-screen: NSFW Media

    /// Real key: `UDKeyNSFWBlurOverride` ("Blur NSFW Media") — device-
    /// only override of the account's Reddit NSFW-blur preference.
    /// Wired into `TagFilterSettings.shouldBlur` via
    /// `GeneralSettingsStore`.
    public var nsfwBlurOverride: NSFWBlurOverride
    // MARK: - Media sub-screen: Uploads

    /// Real key: `UDKeyImageUploadProvider` ("Media Upload Host") —
    /// where images attached to NEW POSTS upload to.
    public var mediaUploadHost: MediaUploadHost
    /// Real key: `UDKeyCommentLinkHost` ("Comment Link Host") — a
    /// separate host for images added to a COMMENT/reply.
    public var commentLinkHost: CommentLinkHost
    // MARK: - Media sub-screen: Network

    /// Real key: `UDKeyProxyImgurDDG` (default off) — loads Imgur images
    /// through DuckDuckGo's cache where Imgur is blocked.
    public var proxyImgurViaDuckDuckGo: Bool
    /// Real key: `UDKeyImgurAlbumFallbackProxies` (default on) — DDG can't
    /// fetch an album's image list, so this falls back to text proxies.
    public var imgurAlbumFallbackProxies: Bool
    /// Apollo-Reborn "Text Post Thumbnails" (real key
    /// `UDKeyFeedTextPostThumbnails`, default on). Gates
    /// `RedditPost.derivedSelfPostThumbnailURL` in
    /// `FeedScreen.resolvedThumbnailURL`.
    public var textPostThumbnailsEnabled: Bool
    public static let `default` = GeneralSettings(
        thumbnailsOnLeft: true,
        thumbnailSize: .small,
        postDisplayStyle: .large,
        openVideosInYouTubeApp: false,
        showUserProfilePictures: false,
        showRichLinkPreviews: false,
        linkPreviewStyle: .full,
        collapseNavigationActions: false,
        scrollReturnButton: true,
        newCommentsHighlightifier: false,
        showAwards: true,
        showPostFlair: true,
        excludeSubscribedFromAllPopular: false,
        liveTextAnalyzer: true,
        highlightAccountAge: false,
        ignoreSuggestedSort: false,
        rememberCommentsSortPerSubreddit: false,
        infiniteScrollingEnabled: true,
        rememberPostsSortPerSubreddit: false,
        hapticFeedbackEnabled: true,
        enableLiquidGlassTabBar: true,
        enableLiquidGlass: true,
        centerTitleGapCentering: false,
        enableFlairColors: false,
        nsfwBlurOverride: .redditSetting,
        mediaUploadHost: .imgur,
        commentLinkHost: .off,
        proxyImgurViaDuckDuckGo: false,
        imgurAlbumFallbackProxies: true,
        textPostThumbnailsEnabled: true,
    )

    public init(
        thumbnailsOnLeft: Bool,
        thumbnailSize: ThumbnailSize,
        postDisplayStyle: PostDisplayStyle = .large,
        openVideosInYouTubeApp: Bool,
        showUserProfilePictures: Bool,
        showRichLinkPreviews: Bool,
        linkPreviewStyle: LinkPreviewStyleSetting,
        collapseNavigationActions: Bool = false,
        scrollReturnButton: Bool = true,
        newCommentsHighlightifier: Bool = false,
        showAwards: Bool = true,
        showPostFlair: Bool = true,
        excludeSubscribedFromAllPopular: Bool = false,
        liveTextAnalyzer: Bool = true,
        highlightAccountAge: Bool = false,
        ignoreSuggestedSort: Bool = false,
        rememberCommentsSortPerSubreddit: Bool = false,
        infiniteScrollingEnabled: Bool = true,
        rememberPostsSortPerSubreddit: Bool = false,
        hapticFeedbackEnabled: Bool = true,
        enableLiquidGlassTabBar: Bool = true,
        enableLiquidGlass: Bool = true,
        centerTitleGapCentering: Bool = false,
        enableFlairColors: Bool = false,
        nsfwBlurOverride: NSFWBlurOverride = .redditSetting,
        mediaUploadHost: MediaUploadHost = .imgur,
        commentLinkHost: CommentLinkHost = .off,
        proxyImgurViaDuckDuckGo: Bool = false,
        imgurAlbumFallbackProxies: Bool = true,
        textPostThumbnailsEnabled: Bool = true,
    ) {
        self.thumbnailsOnLeft = thumbnailsOnLeft
        self.thumbnailSize = thumbnailSize
        self.postDisplayStyle = postDisplayStyle
        self.openVideosInYouTubeApp = openVideosInYouTubeApp
        self.showUserProfilePictures = showUserProfilePictures
        self.showRichLinkPreviews = showRichLinkPreviews
        self.linkPreviewStyle = linkPreviewStyle
        self.collapseNavigationActions = collapseNavigationActions
        self.scrollReturnButton = scrollReturnButton
        self.newCommentsHighlightifier = newCommentsHighlightifier
        self.showAwards = showAwards
        self.showPostFlair = showPostFlair
        self.excludeSubscribedFromAllPopular = excludeSubscribedFromAllPopular
        self.liveTextAnalyzer = liveTextAnalyzer
        self.highlightAccountAge = highlightAccountAge
        self.ignoreSuggestedSort = ignoreSuggestedSort
        self.rememberCommentsSortPerSubreddit = rememberCommentsSortPerSubreddit
        self.infiniteScrollingEnabled = infiniteScrollingEnabled
        self.rememberPostsSortPerSubreddit = rememberPostsSortPerSubreddit
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.enableLiquidGlassTabBar = enableLiquidGlassTabBar
        self.enableLiquidGlass = enableLiquidGlass
        self.centerTitleGapCentering = centerTitleGapCentering
        self.enableFlairColors = enableFlairColors
        self.nsfwBlurOverride = nsfwBlurOverride
        self.mediaUploadHost = mediaUploadHost
        self.commentLinkHost = commentLinkHost
        self.proxyImgurViaDuckDuckGo = proxyImgurViaDuckDuckGo
        self.imgurAlbumFallbackProxies = imgurAlbumFallbackProxies
        self.textPostThumbnailsEnabled = textPostThumbnailsEnabled
    }

    /// Custom decode: every field falls back to `.default` when absent,
    /// so one missing key doesn't discard the whole settings blob.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralSettings.default
        thumbnailsOnLeft = try container.decode(.thumbnailsOnLeft, default: d, \.thumbnailsOnLeft)
        thumbnailSize = try container.decode(.thumbnailSize, default: d, \.thumbnailSize)
        postDisplayStyle = try container.decode(.postDisplayStyle, default: d, \.postDisplayStyle)
        openVideosInYouTubeApp = try container.decode(.openVideosInYouTubeApp, default: d, \.openVideosInYouTubeApp)
        showUserProfilePictures = try container.decode(.showUserProfilePictures, default: d, \.showUserProfilePictures)
        showRichLinkPreviews = try container.decode(.showRichLinkPreviews, default: d, \.showRichLinkPreviews)
        linkPreviewStyle = try container.decode(.linkPreviewStyle, default: d, \.linkPreviewStyle)
        useCommunityIcons = try container.decode(.useCommunityIcons, default: d, \.useCommunityIcons)
        collapseNavigationActions = try container.decode(.collapseNavigationActions, default: d, \.collapseNavigationActions)
        scrollReturnButton = try container.decode(.scrollReturnButton, default: d, \.scrollReturnButton)
        newCommentsHighlightifier = try container.decode(.newCommentsHighlightifier, default: d, \.newCommentsHighlightifier)
        showAwards = try container.decode(.showAwards, default: d, \.showAwards)
        showPostFlair = try container.decode(.showPostFlair, default: d, \.showPostFlair)
        excludeSubscribedFromAllPopular = try container.decode(.excludeSubscribedFromAllPopular, default: d, \.excludeSubscribedFromAllPopular)
        liveTextAnalyzer = try container.decode(.liveTextAnalyzer, default: d, \.liveTextAnalyzer)
        highlightAccountAge = try container.decode(.highlightAccountAge, default: d, \.highlightAccountAge)
        ignoreSuggestedSort = try container.decode(.ignoreSuggestedSort, default: d, \.ignoreSuggestedSort)
        rememberCommentsSortPerSubreddit = try container.decode(.rememberCommentsSortPerSubreddit, default: d, \.rememberCommentsSortPerSubreddit)
        infiniteScrollingEnabled = try container.decode(.infiniteScrollingEnabled, default: d, \.infiniteScrollingEnabled)
        rememberPostsSortPerSubreddit = try container.decode(.rememberPostsSortPerSubreddit, default: d, \.rememberPostsSortPerSubreddit)
        hapticFeedbackEnabled = try container.decode(.hapticFeedbackEnabled, default: d, \.hapticFeedbackEnabled)
        enableLiquidGlassTabBar = try container.decode(.enableLiquidGlassTabBar, default: d, \.enableLiquidGlassTabBar)
        enableLiquidGlass = try container.decode(.enableLiquidGlass, default: d, \.enableLiquidGlass)
        centerTitleGapCentering = try container.decode(.centerTitleGapCentering, default: d, \.centerTitleGapCentering)
        enableFlairColors = try container.decode(.enableFlairColors, default: d, \.enableFlairColors)
        nsfwBlurOverride = try container.decode(.nsfwBlurOverride, default: d, \.nsfwBlurOverride)
        mediaUploadHost = try container.decode(.mediaUploadHost, default: d, \.mediaUploadHost)
        commentLinkHost = try container.decode(.commentLinkHost, default: d, \.commentLinkHost)
        proxyImgurViaDuckDuckGo = try container.decode(.proxyImgurViaDuckDuckGo, default: d, \.proxyImgurViaDuckDuckGo)
        imgurAlbumFallbackProxies = try container.decode(.imgurAlbumFallbackProxies, default: d, \.imgurAlbumFallbackProxies)
        textPostThumbnailsEnabled = try container.decode(.textPostThumbnailsEnabled, default: d, \.textPostThumbnailsEnabled)
    }
}

public enum GeneralSettingsStore {
    /// `LiquidGlass.isEnabled` reads a plain flag before any decode, so
    /// this blob (the source of truth, and what gets backed up) writes
    /// through to it whenever it's read or saved.
    public static let storage = SettingsStore<GeneralSettings>(
        key: "com.pendo324.Phoebus.generalSettings",
        didChange: didChangeNotification,
    ) { .default }

    /// Posted after any save, alongside `.apolloSettingsChanged`.
    public static let didChangeNotification =
        Notification.Name("com.pendo324.Phoebus.generalSettingsDidChange")

    public static func load() -> GeneralSettings { storage.load() }

    public static func save(_ settings: GeneralSettings) { storage.save(settings) }
}

extension GeneralSettings: StoredSettingsModel {
    public static var store: SettingsStore<GeneralSettings> { GeneralSettingsStore.storage }
}

/// Stock `DefaultRedditToLoad` (home, popular, allPosts, redditsList, a
/// subreddit or a multireddit), stored in `defaultRedditToLoad` as text:
/// "" is the Subreddits list, "home" / "popular" / "all" the feeds,
/// "m:<path>|<name>" a multireddit, anything else a subreddit name.
public enum DefaultRedditToLoadChoice: Equatable, Sendable {
    case redditsList, home, popular, all
    case subreddit(String)
    case multireddit(path: String, name: String)

    public init(stored: String) {
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        switch trimmed.lowercased() {
        case "": self = .redditsList
        case "home": self = .home
        case "popular": self = .popular
        case "all": self = .all
        default:
            if trimmed.hasPrefix("m:"), let bar = trimmed.firstIndex(of: "|") {
                self = .multireddit(path: String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<bar]),
                                    name: String(trimmed[trimmed.index(after: bar)...]))
            } else {
                self = .subreddit(trimmed.hasPrefix("r/") ? String(trimmed.dropFirst(2)) : trimmed)
            }
        }
    }

    public var stored: String {
        switch self {
        case .redditsList: return ""
        case .home: return "home"
        case .popular: return "popular"
        case .all: return "all"
        case .subreddit(let name): return name
        case .multireddit(let path, let name): return "m:\(path)|\(name)"
        }
    }

    public var displayName: String {
        switch self {
        case .redditsList: return "Subreddits List"
        case .home: return "Home"
        case .popular: return "Popular Posts"
        case .all: return "All Posts"
        case .subreddit(let name): return "r/\(name)"
        case .multireddit(_, let name): return name
        }
    }
}
