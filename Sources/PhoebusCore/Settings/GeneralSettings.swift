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

/// Matches the real `UnmuteVideosWhenOpenedSetting` key. "Remember"
/// (default) keeps the unmute state until you re-mute or close the app.
public enum UnmuteWhenOpenedSetting: String, Codable, Sendable, CaseIterable, Identifiable {
    case remember
    case always
    case never

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .remember: return "Remember"
        case .always: return "Always"
        case .never: return "Never"
        }
    }
}

/// Matches the real GIF-vs-video save preference: "Automatic" chooses
/// based on length, or always save as Video/GIF, or ask each time.
public enum GIFSaveFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case alwaysVideo
    case alwaysGIF
    case askEachTime

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .alwaysVideo: return "Always Video"
        case .alwaysGIF: return "Always GIF"
        case .askEachTime: return "Ask Each Time"
        }
    }
}

/// Matches the real `OpenTwitterLinksIn` key ("Open Tweets in…").
/// Aviary and Spring are third-party X clients Apollo lists as
/// destinations; both fall back to the in-app browser when not
/// installed, like every other choice here.
public enum TwitterLinkDestination: String, Codable, Sendable, CaseIterable, Identifiable {
    case inApp
    case twitterApp
    case twitterrific
    case tweetbot
    case aviary
    case spring
    case externalBrowser

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .inApp: return "In-App Safari"
        case .twitterApp: return "X/Twitter App"
        case .twitterrific: return "Twitterrific"
        case .tweetbot: return "Tweetbot"
        case .aviary: return "Aviary"
        case .spring: return "Spring"
        case .externalBrowser: return "Default Browser"
        }
    }
}

/// Matches the real `DefaultPostsSort`/`DefaultPostsTimeSort` keys and
/// Reddit's own post-sort case list.
public enum DefaultPostSort: String, Codable, Sendable, CaseIterable, Identifiable {
    case best
    case hot
    case new
    case top
    case rising
    case controversial

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    /// Only Top and Controversial take a time-range qualifier.
    public var supportsTimeRange: Bool { self == .top || self == .controversial }
}

/// Reborn's subreddit feed icon style: the icon appearance of the
/// Home/Popular/All/Moderator pseudo-feed rows in the Subreddits root list.
public enum FeedIconStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case classic
    case circle
    case tinted
    case softTile
    case solidTile

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .circle: return "Circle"
        case .tinted: return "Tinted"
        case .softTile: return "Soft Tile"
        case .solidTile: return "Solid Tile"
        }
    }
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

/// Reborn's `UDKeyPreferredGIFFallbackFormat`: playback fallback format
/// when a GIF can't play as a true animated GIF. Distinct from
/// `GIFSaveFormat` (saving/downloading). Default MP4.
public enum PreferredGIFFallbackFormat: Int, Codable, Sendable, CaseIterable, Identifiable {
    // Listed MP4 first, as Reborn's picker.
    case mp4 = 1
    case gif = 0

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .gif: return "GIF"
        case .mp4: return "MP4"
        }
    }
}

/// Reborn's independent `UDKeyUnmuteFeedVideos` /
/// `UDKeyUnmuteCommentsVideos` controls. Both default to Never.
public enum VideoUnmuteMode: Int, Codable, Sendable, CaseIterable, Identifiable {
    case never = 0
    case remember = 1
    case always = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .never: return "Never"
        case .remember: return "Remember"
        case .always: return "Always"
        }
    }

    public init(legacy: UnmuteWhenOpenedSetting) {
        switch legacy {
        case .remember: self = .remember
        case .always: self = .always
        case .never: self = .never
        }
    }
}

/// Reborn's `UDKeyShareLinkHost` ("Share Link Host"): Reddit, old.reddit,
/// vxReddit or fxReddit. Supersedes the boolean `shareOldRedditLinks`.
public enum ShareLinkHost: Int, Codable, Sendable, CaseIterable, Identifiable {
    case reddit = 0
    case oldReddit = 1
    case vxReddit = 2
    case fxReddit = 3

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .reddit: return "Reddit"
        case .oldReddit: return "old.reddit"
        case .vxReddit: return "vxReddit"
        case .fxReddit: return "fxReddit (fxddit.com)"
        }
    }
    /// Host domain to substitute; `nil` for `.reddit` means keep
    /// Apollo's original reddit.com host.
    public var domain: String? {
        switch self {
        case .reddit: return nil
        case .oldReddit: return "old.reddit.com"
        case .vxReddit: return "vxreddit.com"
        case .fxReddit: return "fxddit.com"
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

/// Reborn's subreddit feed layout: how the Home/Popular/All/Moderator
/// rows arrange in the Subreddits root list.
public enum FeedShortcutLayout: String, Codable, Sendable, CaseIterable, Identifiable {
    case rows
    case grid
    case sideBySide
    case iconDock

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .rows: return "Rows"
        case .grid: return "Grid"
        case .sideBySide: return "Side-by-Side"
        case .iconDock: return "Icon Dock"
        }
    }
}

/// Real Apollo "Autoplay GIFs/Videos" (Settings > General > Posts):
/// Always, Wi-Fi Only, or Never.
public enum AutoplayMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case always
    case wifiOnly
    case never

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .always: return "Always"
        case .wifiOnly: return "Wi-Fi Only"
        case .never: return "Never"
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
    /// Reborn "Hide Feed Descriptions": hides a subreddit's description text
    /// in subreddit list rows.
    public var hideFeedDescriptions: Bool
    /// Matches the real base-Apollo (not Reborn) "Share old.reddit
    /// Links" setting. Real key: `ShareOldRedditLinks`.
    public var shareOldRedditLinks: Bool

    /// The host share links use. Independent settings, as in Reborn: stock
    /// "Share old.reddit Links" builds old.reddit links, then a Share Link
    /// Host other than Reddit rewrites them.
    public var effectiveShareLinkHost: ShareLinkHost {
        shareLinkHost == .reddit && shareOldRedditLinks ? .oldReddit : shareLinkHost
    }

    // MARK: - General settings (base Apollo)

    /// Real key: `DefaultRedditToLoad`. Empty string means Apollo's
    /// own default (Home). "Default Reddit to Load…" in the real UI.
    public var defaultRedditToLoad: String
    /// Real key: `HideRPopularRedditList` ("Hide the following rows
    /// in the subreddit listing…").
    public var hidePopularInSubredditList: Bool
    /// Real key: `HideRAllRedditList`.
    public var hideAllInSubredditList: Bool
    /// Real key: `HideModeratorRedditList`.
    public var hideModeratorInSubredditList: Bool
    /// Phoebus addition: subreddit icons use the current community icon,
    /// falling back to the classic one. Off is Apollo's classic-only rule
    /// (a subreddit without one gets the letter badge).
    public var useCommunityIcons: Bool = true
    /// Real keys: `sSubredditFeedIconStyle` / `sSubredditFeedLayout` —
    /// appearance and arrangement of the Home/Popular/All/Moderator
    /// pseudo-feed rows. Independent of the hide-toggles above.
    public var subredditFeedIconStyle: FeedIconStyle
    public var subredditFeedLayout: FeedShortcutLayout
    /// Real key: `3DTouchMarksRead` ("3D Touch Marks Read") — a
    /// 3D-Touch/long-press peek on a post row marks it read.
    public var threeDTouchMarksRead: Bool
    /// Real key: `HideBarsOnScroll`.
    public var hideBarsOnScroll: Bool
    /// Reborn's "Hide Style": 0 Left, 1 Right, 2 Fade, 3 Down. Shown
    /// only while Hide Bars on Scroll is on.
    public var tabBarHideStyle: Int
    /// Apollo-Reborn "Hide Header on Scroll" (#1079, `HideTopBarOnScroll`,
    /// default off): nav bar slides away with the tab bar while scrolling.
    public var hideTopBarOnScroll: Bool
    /// Reborn "Collapse Navigation Actions" (`CollapseNavigationActions`,
    /// default off): actions strip collapses on scroll/back-gesture
    /// triggers when on. Visible only under Liquid Glass.
    public var collapseNavigationActions: Bool
    /// Reborn "Return Button" (real key `ScrollReturnButton`, default
    /// on). Only gates the visible affordance (arrow beside Back, nav
    /// bar tap); the saved-position restore and double status-bar-tap
    /// stay unconditional regardless of this setting.
    public var scrollReturnButton: Bool
    /// Real Apollo "Upvote on Save" (Settings > General > Posts, real
    /// default off): saving a post also upvotes it.
    public var upvoteOnSave: Bool
    /// Real Apollo "Autoplay GIFs/Videos" - see `AutoplayMode`.
    public var autoplayMode: AutoplayMode
    /// Real Apollo "New Comments Highlightifier": highlights comments
    /// posted since last visit. Distinct from `highlightAccountAge`.
    public var newCommentsHighlightifier: Bool
    /// Real Apollo "Show Awards" (Settings > Appearance > Other):
    /// show or hide Reddit award icons on posts and comments.
    public var showAwards: Bool
    /// Real Apollo "Post Flair" (Settings > Appearance > Flair):
    /// show or hide a post's own link flair chip.
    public var showPostFlair: Bool
    /// Real Apollo "User Flair" (Settings > Appearance > Flair):
    /// show or hide author flair.
    public var showUserFlair: Bool
    /// Real key: `OpenTwitterLinksIn` ("Open Tweets in…").
    public var openTwitterLinksIn: TwitterLinkDestination
    /// Real key: `ExcludeSubsFromAllPopular` ("No Subscribed in
    /// All/Popular") — hides posts from subreddits you're subscribed
    /// to when browsing r/all or r/popular.
    public var excludeSubscribedFromAllPopular: Bool
    /// Real key: `UnifyModmailInInbox` ("Unify Modmail in Inbox").
    public var unifyModmailInInbox: Bool
    /// Real key: `LiveTextAnalyzer` — iOS Live Text OCR support for
    /// images shown in the media viewer.
    public var liveTextAnalyzer: Bool
    /// Real key: `LoopVideosWithAudio` — by default Apollo only loops
    /// silent (GIF-equivalent) videos; this extends looping to videos
    /// with audio too.
    public var loopVideosWithAudio: Bool
    /// Real key: `SaveToApolloAlbum` ("Save to "Apollo" Album") —
    /// saved media goes into a dedicated "Apollo" Photos album instead
    /// of the Camera Roll.
    public var saveToApolloAlbum: Bool
    /// Real key: `ShowMediaViewerControlsWhenOpened` ("Show Controls
    /// When Opened") — video controls are visible by default rather
    /// than requiring a tap to reveal.
    public var showMediaViewerControlsWhenOpened: Bool
    /// Real key implied by "Saving as GIF versus Video" / "Download
    /// GIFs as…" footer copy.
    public var gifSaveFormat: GIFSaveFormat
    /// Real key: `UnmuteVideosWhenOpenedSetting`.
    public var unmuteVideosWhenOpened: UnmuteWhenOpenedSetting
    /// Real key: `ShowCommentsButton` — the in-app browser's floating
    /// button that goes to the post's comments.
    public var showCommentsButton: Bool
    /// Real key: `AlwaysUseReaderMode` — the in-app browser opens pages
    /// in Reader Mode when available.
    public var alwaysUseReaderMode: Bool
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
    /// Real key: `SharePostIncludesTitle` ("Share Includes Title") —
    /// shared post links include the post title as share-sheet text,
    /// not just the bare URL.
    public var sharePostIncludesTitle: Bool
    /// Real key: `DoomscrollDefeater3` ("Infinite Scrolling") — when
    /// false, feeds stop auto-loading more pages past a point,
    /// requiring an explicit tap to continue (a doomscrolling guard).
    public var infiniteScrollingEnabled: Bool
    /// Real key: `RememberRedditPostsSort` ("Remember Subreddit
    /// Sort") — the posts-sort analog of
    /// `rememberCommentsSortPerSubreddit`.
    public var rememberPostsSortPerSubreddit: Bool
    /// Real keys: `DefaultPostsSort` / `DefaultPostsTimeSort`
    /// ("Default Posts Sort…").
    public var defaultPostsSort: DefaultPostSort
    /// Time range qualifier for Top/Controversial post sorts, per the
    /// real "Sort by Controversial for…" / "Sort by Top for…" copy.
    public var defaultPostsTimeSort: String
    /// "Open Reddit Links in Apollo": persisted intent only; Associated
    /// Domains are not registered.
    public var openRedditLinksInApollo: Bool

    /// Real key: `RememberRedditToLoad`. Distinct from
    /// `defaultRedditToLoad`: this remembers whichever subreddit was
    /// last open and reopens it on launch, while that field always
    /// opens one fixed subreddit.
    public var rememberSubredditToLoad: Bool

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

    /// Forces the glass or fallback render path, for testing. Not stored
    /// in this struct: a forced render path shouldn't travel via
    /// backup/restore, so this proxies `LiquidGlass.renderOverride` directly.
    public var glassRenderOverride: LiquidGlass.RenderOverride {
        get { LiquidGlass.renderOverride }
        nonmutating set { LiquidGlass.renderOverride = newValue }
    }
    // MARK: - Interface sub-screen

    /// Real key: `UDKeyUseProfileAvatarTabIcon` ("Profile Picture Tab
    /// Icon") — when true, the Profile tab's icon shows the signed-in
    /// user's avatar instead of the generic `person.circle` symbol.
    /// Wired in `MainTabView`.
    public var useProfileAvatarTabIcon: Bool
    /// Real key: `UDKeyHideTabBarTitles` ("Icon-Only Tab Bar") — hides
    /// every tab's text label, icons only. Hides the narrower "Hide
    /// Username on Tab Bar" row while on, since icon-only already
    /// implies no username text.
    public var iconOnlyTabBar: Bool
    /// Real key: `sClassicTabBarScrollBehavior` ("Scroll Behavior") —
    /// only matters while `hideBarsOnScroll` is on. `false` = Two-Gesture
    /// (default), `true` = Classic.
    public var classicTabBarScrollBehavior: Bool
    /// Real key: `sLGTitleGapCentering`, Liquid-Glass-only. Cosmetically
    /// inert here: SwiftUI's `.principal` toolbar item already centers.
    public var centerTitleGapCentering: Bool
    /// Real key: `UDKeyIPadTabBarBottom` (iPad stopgap #387),
    /// Liquid-Glass-only on iPad. Docks the floating top tab bar at the bottom.
    public var ipadTabBarBottom: Bool
    /// Reborn "Swipe Tab Bar to Navigate" (#1075, `TabBarSwipeNavigation`,
    /// default off, Liquid Glass only): trades the native drag-to-switch-tab
    /// for left/right back/forward. Relaunch to apply, as upstream.
    public var tabBarSwipeNavigation: Bool = false

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

    // MARK: - Media sub-screen: Playback

    /// Real key: `UDKeyPreferredGIFFallbackFormat` — distinct from
    /// `gifSaveFormat` (saving, not playback fallback).
    public var preferredGIFFallbackFormat: PreferredGIFFallbackFormat
    /// Real key: `UDKeyUnmuteFeedVideos` — replaces the feed half of the
    /// old combined `unmuteVideosWhenOpened`; migrated on first decode.
    public var unmuteFeedVideosMode: VideoUnmuteMode
    /// Real key: `UDKeyUnmuteCommentsVideos` — replaces the comments half
    /// of the old combined `unmuteVideosWhenOpened`.
    public var unmuteCommentsVideosMode: VideoUnmuteMode

    // MARK: - Media sub-screen: Sharing

    /// Real key: `UDKeyShareLinkHost` — replaces boolean
    /// `shareOldRedditLinks` with a 4-way host picker; that field is
    /// kept only for migration.
    public var shareLinkHost: ShareLinkHost

    // MARK: - Media sub-screen: Uploads

    /// Real key: `UDKeyImageUploadProvider` ("Media Upload Host") —
    /// where images attached to NEW POSTS upload to.
    public var mediaUploadHost: MediaUploadHost
    /// Real key: `UDKeyCommentLinkHost` ("Comment Link Host") — a
    /// separate host for images added to a COMMENT/reply.
    public var commentLinkHost: CommentLinkHost
    /// Real key: `UDKeyCommentLinkPreferNative` ("Prefer Native
    /// Images") — only meaningful while `commentLinkHost != .off`:
    /// comment images upload to Reddit natively wherever the subreddit
    /// allows it, falling back to the link host only where it doesn't.
    public var commentLinkPreferNative: Bool

    // MARK: - Media sub-screen: Network

    /// Real key: `UDKeyProxyImgurDDG` (default off) — loads Imgur images
    /// through DuckDuckGo's cache where Imgur is blocked.
    public var proxyImgurViaDuckDuckGo: Bool
    /// Real key: `UDKeyImgurAlbumFallbackProxies` (default on) — DDG can't
    /// fetch an album's image list, so this falls back to text proxies.
    public var imgurAlbumFallbackProxies: Bool

    // MARK: - Feed section additions

    /// Apollo-Reborn "Forget Forward Swipe After Scrolling" (real key
    /// `UDKeyForwardSwipeForgetAfterScrolling`, default off). Wired in
    /// `FeedScreen`'s `expireForwardTargetIfNeeded`.
    public var forwardSwipeForgetAfterScrolling: Bool
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
        hideFeedDescriptions: false,
        shareOldRedditLinks: false,
        defaultRedditToLoad: "",
        hidePopularInSubredditList: false,
        hideAllInSubredditList: false,
        hideModeratorInSubredditList: false,
        subredditFeedIconStyle: .classic,
        subredditFeedLayout: .rows,
        threeDTouchMarksRead: true,
        hideBarsOnScroll: false,
        tabBarHideStyle: 0,
        hideTopBarOnScroll: false,
        collapseNavigationActions: false,
        scrollReturnButton: true,
        upvoteOnSave: false,
        autoplayMode: .always,
        newCommentsHighlightifier: false,
        showAwards: true,
        showPostFlair: true,
        showUserFlair: true,

        openTwitterLinksIn: .inApp,
        excludeSubscribedFromAllPopular: false,
        unifyModmailInInbox: true,
        liveTextAnalyzer: true,
        loopVideosWithAudio: true,
        saveToApolloAlbum: false,
        showMediaViewerControlsWhenOpened: true,
        gifSaveFormat: .automatic,
        unmuteVideosWhenOpened: .remember,
        showCommentsButton: true,
        alwaysUseReaderMode: false,
        highlightAccountAge: false,
        ignoreSuggestedSort: false,
        rememberCommentsSortPerSubreddit: false,
        sharePostIncludesTitle: false,
        infiniteScrollingEnabled: true,
        rememberPostsSortPerSubreddit: false,
        defaultPostsSort: .best,
        defaultPostsTimeSort: "day",
        openRedditLinksInApollo: true,
        rememberSubredditToLoad: false,
        hapticFeedbackEnabled: true,
        enableLiquidGlassTabBar: true,
        enableLiquidGlass: true,
        useProfileAvatarTabIcon: false,
        iconOnlyTabBar: false,
        classicTabBarScrollBehavior: false,
        centerTitleGapCentering: false,
        ipadTabBarBottom: false,
        enableFlairColors: false,
        nsfwBlurOverride: .redditSetting,
        preferredGIFFallbackFormat: .mp4,
        unmuteFeedVideosMode: .never,
        unmuteCommentsVideosMode: .never,
        shareLinkHost: .reddit,
        mediaUploadHost: .imgur,
        commentLinkHost: .off,
        commentLinkPreferNative: false,
        proxyImgurViaDuckDuckGo: false,
        imgurAlbumFallbackProxies: true,
        forwardSwipeForgetAfterScrolling: false,
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
        hideFeedDescriptions: Bool,
        shareOldRedditLinks: Bool = false,
        defaultRedditToLoad: String = "",
        hidePopularInSubredditList: Bool = false,
        hideAllInSubredditList: Bool = false,
        hideModeratorInSubredditList: Bool = false,
        subredditFeedIconStyle: FeedIconStyle = .classic,
        subredditFeedLayout: FeedShortcutLayout = .rows,
        threeDTouchMarksRead: Bool = false,
        hideBarsOnScroll: Bool = false,
        tabBarHideStyle: Int = 0,
        hideTopBarOnScroll: Bool = false,
        collapseNavigationActions: Bool = false,
        scrollReturnButton: Bool = true,
        upvoteOnSave: Bool = false,
        autoplayMode: AutoplayMode = .always,
        newCommentsHighlightifier: Bool = false,
        showAwards: Bool = true,
        showPostFlair: Bool = true,
        showUserFlair: Bool = true,
        openTwitterLinksIn: TwitterLinkDestination = .inApp,
        excludeSubscribedFromAllPopular: Bool = false,
        unifyModmailInInbox: Bool = false,
        liveTextAnalyzer: Bool = true,
        loopVideosWithAudio: Bool = false,
        saveToApolloAlbum: Bool = false,
        showMediaViewerControlsWhenOpened: Bool = false,
        gifSaveFormat: GIFSaveFormat = .automatic,
        unmuteVideosWhenOpened: UnmuteWhenOpenedSetting = .remember,
        showCommentsButton: Bool = false,
        alwaysUseReaderMode: Bool = false,
        highlightAccountAge: Bool = false,
        ignoreSuggestedSort: Bool = false,
        rememberCommentsSortPerSubreddit: Bool = false,
        sharePostIncludesTitle: Bool = true,
        infiniteScrollingEnabled: Bool = true,
        rememberPostsSortPerSubreddit: Bool = false,
        defaultPostsSort: DefaultPostSort = .best,
        defaultPostsTimeSort: String = "day",
        openRedditLinksInApollo: Bool = true,
        rememberSubredditToLoad: Bool = false,
        hapticFeedbackEnabled: Bool = true,
        enableLiquidGlassTabBar: Bool = true,
        enableLiquidGlass: Bool = true,
        useProfileAvatarTabIcon: Bool = false,
        iconOnlyTabBar: Bool = false,
        classicTabBarScrollBehavior: Bool = false,
        centerTitleGapCentering: Bool = false,
        ipadTabBarBottom: Bool = false,
        enableFlairColors: Bool = false,
        nsfwBlurOverride: NSFWBlurOverride = .redditSetting,
        preferredGIFFallbackFormat: PreferredGIFFallbackFormat = .mp4,
        unmuteFeedVideosMode: VideoUnmuteMode = .never,
        unmuteCommentsVideosMode: VideoUnmuteMode = .never,
        shareLinkHost: ShareLinkHost = .reddit,
        mediaUploadHost: MediaUploadHost = .imgur,
        commentLinkHost: CommentLinkHost = .off,
        commentLinkPreferNative: Bool = false,
        proxyImgurViaDuckDuckGo: Bool = false,
        imgurAlbumFallbackProxies: Bool = true,
        forwardSwipeForgetAfterScrolling: Bool = false,
        textPostThumbnailsEnabled: Bool = true,
    ) {
        self.thumbnailsOnLeft = thumbnailsOnLeft
        self.thumbnailSize = thumbnailSize
        self.postDisplayStyle = postDisplayStyle
        self.openVideosInYouTubeApp = openVideosInYouTubeApp
        self.showUserProfilePictures = showUserProfilePictures
        self.showRichLinkPreviews = showRichLinkPreviews
        self.linkPreviewStyle = linkPreviewStyle
        self.hideFeedDescriptions = hideFeedDescriptions
        self.shareOldRedditLinks = shareOldRedditLinks
        self.defaultRedditToLoad = defaultRedditToLoad
        self.hidePopularInSubredditList = hidePopularInSubredditList
        self.hideAllInSubredditList = hideAllInSubredditList
        self.hideModeratorInSubredditList = hideModeratorInSubredditList
        self.subredditFeedIconStyle = subredditFeedIconStyle
        self.subredditFeedLayout = subredditFeedLayout
        self.threeDTouchMarksRead = threeDTouchMarksRead
        self.hideBarsOnScroll = hideBarsOnScroll
        self.tabBarHideStyle = tabBarHideStyle
        self.hideTopBarOnScroll = hideTopBarOnScroll
        self.collapseNavigationActions = collapseNavigationActions
        self.scrollReturnButton = scrollReturnButton
        self.upvoteOnSave = upvoteOnSave
        self.autoplayMode = autoplayMode
        self.newCommentsHighlightifier = newCommentsHighlightifier
        self.showAwards = showAwards
        self.showPostFlair = showPostFlair
        self.showUserFlair = showUserFlair
        self.openTwitterLinksIn = openTwitterLinksIn
        self.excludeSubscribedFromAllPopular = excludeSubscribedFromAllPopular
        self.unifyModmailInInbox = unifyModmailInInbox
        self.liveTextAnalyzer = liveTextAnalyzer
        self.loopVideosWithAudio = loopVideosWithAudio
        self.saveToApolloAlbum = saveToApolloAlbum
        self.showMediaViewerControlsWhenOpened = showMediaViewerControlsWhenOpened
        self.gifSaveFormat = gifSaveFormat
        self.unmuteVideosWhenOpened = unmuteVideosWhenOpened
        self.showCommentsButton = showCommentsButton
        self.alwaysUseReaderMode = alwaysUseReaderMode
        self.highlightAccountAge = highlightAccountAge
        self.ignoreSuggestedSort = ignoreSuggestedSort
        self.rememberCommentsSortPerSubreddit = rememberCommentsSortPerSubreddit
        self.sharePostIncludesTitle = sharePostIncludesTitle
        self.infiniteScrollingEnabled = infiniteScrollingEnabled
        self.rememberPostsSortPerSubreddit = rememberPostsSortPerSubreddit
        self.defaultPostsSort = defaultPostsSort
        self.defaultPostsTimeSort = defaultPostsTimeSort
        self.openRedditLinksInApollo = openRedditLinksInApollo
        self.rememberSubredditToLoad = rememberSubredditToLoad
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.enableLiquidGlassTabBar = enableLiquidGlassTabBar
        self.enableLiquidGlass = enableLiquidGlass
        self.useProfileAvatarTabIcon = useProfileAvatarTabIcon
        self.iconOnlyTabBar = iconOnlyTabBar
        self.classicTabBarScrollBehavior = classicTabBarScrollBehavior
        self.centerTitleGapCentering = centerTitleGapCentering
        self.ipadTabBarBottom = ipadTabBarBottom
        self.enableFlairColors = enableFlairColors
        self.nsfwBlurOverride = nsfwBlurOverride
        self.preferredGIFFallbackFormat = preferredGIFFallbackFormat
        self.unmuteFeedVideosMode = unmuteFeedVideosMode
        self.unmuteCommentsVideosMode = unmuteCommentsVideosMode
        self.shareLinkHost = shareLinkHost
        self.mediaUploadHost = mediaUploadHost
        self.commentLinkHost = commentLinkHost
        self.commentLinkPreferNative = commentLinkPreferNative
        self.proxyImgurViaDuckDuckGo = proxyImgurViaDuckDuckGo
        self.imgurAlbumFallbackProxies = imgurAlbumFallbackProxies
        self.forwardSwipeForgetAfterScrolling = forwardSwipeForgetAfterScrolling
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
        hideFeedDescriptions = try container.decode(.hideFeedDescriptions, default: d, \.hideFeedDescriptions)
        shareOldRedditLinks = try container.decode(.shareOldRedditLinks, default: d, \.shareOldRedditLinks)
        defaultRedditToLoad = try container.decode(.defaultRedditToLoad, default: d, \.defaultRedditToLoad)
        hidePopularInSubredditList = try container.decode(.hidePopularInSubredditList, default: d, \.hidePopularInSubredditList)
        hideAllInSubredditList = try container.decode(.hideAllInSubredditList, default: d, \.hideAllInSubredditList)
        hideModeratorInSubredditList = try container.decode(.hideModeratorInSubredditList, default: d, \.hideModeratorInSubredditList)
        useCommunityIcons = try container.decode(.useCommunityIcons, default: d, \.useCommunityIcons)
        subredditFeedIconStyle = try container.decode(.subredditFeedIconStyle, default: d, \.subredditFeedIconStyle)
        subredditFeedLayout = try container.decode(.subredditFeedLayout, default: d, \.subredditFeedLayout)
        threeDTouchMarksRead = try container.decode(.threeDTouchMarksRead, default: d, \.threeDTouchMarksRead)
        hideBarsOnScroll = try container.decode(.hideBarsOnScroll, default: d, \.hideBarsOnScroll)
        tabBarHideStyle = try container.decode(.tabBarHideStyle, default: d, \.tabBarHideStyle)
        hideTopBarOnScroll = try container.decode(.hideTopBarOnScroll, default: d, \.hideTopBarOnScroll)
        collapseNavigationActions = try container.decode(.collapseNavigationActions, default: d, \.collapseNavigationActions)
        scrollReturnButton = try container.decode(.scrollReturnButton, default: d, \.scrollReturnButton)
        upvoteOnSave = try container.decode(.upvoteOnSave, default: d, \.upvoteOnSave)
        autoplayMode = try container.decode(.autoplayMode, default: d, \.autoplayMode)
        newCommentsHighlightifier = try container.decode(.newCommentsHighlightifier, default: d, \.newCommentsHighlightifier)
        showAwards = try container.decode(.showAwards, default: d, \.showAwards)
        showPostFlair = try container.decode(.showPostFlair, default: d, \.showPostFlair)
        showUserFlair = try container.decode(.showUserFlair, default: d, \.showUserFlair)
        openTwitterLinksIn = try container.decode(.openTwitterLinksIn, default: d, \.openTwitterLinksIn)
        excludeSubscribedFromAllPopular = try container.decode(.excludeSubscribedFromAllPopular, default: d, \.excludeSubscribedFromAllPopular)
        unifyModmailInInbox = try container.decode(.unifyModmailInInbox, default: d, \.unifyModmailInInbox)
        liveTextAnalyzer = try container.decode(.liveTextAnalyzer, default: d, \.liveTextAnalyzer)
        loopVideosWithAudio = try container.decode(.loopVideosWithAudio, default: d, \.loopVideosWithAudio)
        saveToApolloAlbum = try container.decode(.saveToApolloAlbum, default: d, \.saveToApolloAlbum)
        showMediaViewerControlsWhenOpened = try container.decode(.showMediaViewerControlsWhenOpened, default: d, \.showMediaViewerControlsWhenOpened)
        gifSaveFormat = try container.decode(.gifSaveFormat, default: d, \.gifSaveFormat)
        unmuteVideosWhenOpened = try container.decode(.unmuteVideosWhenOpened, default: d, \.unmuteVideosWhenOpened)
        showCommentsButton = try container.decode(.showCommentsButton, default: d, \.showCommentsButton)
        alwaysUseReaderMode = try container.decode(.alwaysUseReaderMode, default: d, \.alwaysUseReaderMode)
        highlightAccountAge = try container.decode(.highlightAccountAge, default: d, \.highlightAccountAge)
        ignoreSuggestedSort = try container.decode(.ignoreSuggestedSort, default: d, \.ignoreSuggestedSort)
        rememberCommentsSortPerSubreddit = try container.decode(.rememberCommentsSortPerSubreddit, default: d, \.rememberCommentsSortPerSubreddit)
        sharePostIncludesTitle = try container.decode(.sharePostIncludesTitle, default: d, \.sharePostIncludesTitle)
        infiniteScrollingEnabled = try container.decode(.infiniteScrollingEnabled, default: d, \.infiniteScrollingEnabled)
        rememberPostsSortPerSubreddit = try container.decode(.rememberPostsSortPerSubreddit, default: d, \.rememberPostsSortPerSubreddit)
        defaultPostsSort = try container.decode(.defaultPostsSort, default: d, \.defaultPostsSort)
        defaultPostsTimeSort = try container.decode(.defaultPostsTimeSort, default: d, \.defaultPostsTimeSort)
        openRedditLinksInApollo = try container.decode(.openRedditLinksInApollo, default: d, \.openRedditLinksInApollo)
        rememberSubredditToLoad = try container.decode(.rememberSubredditToLoad, default: d, \.rememberSubredditToLoad)
        hapticFeedbackEnabled = try container.decode(.hapticFeedbackEnabled, default: d, \.hapticFeedbackEnabled)
        enableLiquidGlassTabBar = try container.decode(.enableLiquidGlassTabBar, default: d, \.enableLiquidGlassTabBar)
        enableLiquidGlass = try container.decode(.enableLiquidGlass, default: d, \.enableLiquidGlass)
        useProfileAvatarTabIcon = try container.decode(.useProfileAvatarTabIcon, default: d, \.useProfileAvatarTabIcon)
        iconOnlyTabBar = try container.decode(.iconOnlyTabBar, default: d, \.iconOnlyTabBar)
        classicTabBarScrollBehavior = try container.decode(.classicTabBarScrollBehavior, default: d, \.classicTabBarScrollBehavior)
        centerTitleGapCentering = try container.decode(.centerTitleGapCentering, default: d, \.centerTitleGapCentering)
        ipadTabBarBottom = try container.decode(.ipadTabBarBottom, default: d, \.ipadTabBarBottom)
        tabBarSwipeNavigation = try container.decode(.tabBarSwipeNavigation, default: d, \.tabBarSwipeNavigation)
        enableFlairColors = try container.decode(.enableFlairColors, default: d, \.enableFlairColors)
        nsfwBlurOverride = try container.decode(.nsfwBlurOverride, default: d, \.nsfwBlurOverride)
        preferredGIFFallbackFormat = try container.decode(.preferredGIFFallbackFormat, default: d, \.preferredGIFFallbackFormat)
        // Migration: the old combined `unmuteVideosWhenOpened` carries
        // into both new fields on first decode.
        if let feedMode = (try? container.decodeIfPresent(VideoUnmuteMode.self, forKey: .unmuteFeedVideosMode)) {
            unmuteFeedVideosMode = feedMode
        } else {
            switch unmuteVideosWhenOpened {
            case .always: unmuteFeedVideosMode = .always
            case .never: unmuteFeedVideosMode = .never
            case .remember: unmuteFeedVideosMode = .remember
            }
        }
        if let commentsMode = (try? container.decodeIfPresent(VideoUnmuteMode.self, forKey: .unmuteCommentsVideosMode)) {
            unmuteCommentsVideosMode = commentsMode
        } else {
            switch unmuteVideosWhenOpened {
            case .always: unmuteCommentsVideosMode = .always
            case .never: unmuteCommentsVideosMode = .never
            case .remember: unmuteCommentsVideosMode = .remember
            }
        }
        // Migration: the old boolean `shareOldRedditLinks` maps onto
        // the new 4-way host picker.
        if let host = (try? container.decodeIfPresent(ShareLinkHost.self, forKey: .shareLinkHost)) {
            shareLinkHost = host
        } else {
            shareLinkHost = shareOldRedditLinks ? .oldReddit : .reddit
        }
        mediaUploadHost = try container.decode(.mediaUploadHost, default: d, \.mediaUploadHost)
        commentLinkHost = try container.decode(.commentLinkHost, default: d, \.commentLinkHost)
        commentLinkPreferNative = try container.decode(.commentLinkPreferNative, default: d, \.commentLinkPreferNative)
        proxyImgurViaDuckDuckGo = try container.decode(.proxyImgurViaDuckDuckGo, default: d, \.proxyImgurViaDuckDuckGo)
        imgurAlbumFallbackProxies = try container.decode(.imgurAlbumFallbackProxies, default: d, \.imgurAlbumFallbackProxies)
        forwardSwipeForgetAfterScrolling = try container.decode(.forwardSwipeForgetAfterScrolling, default: d, \.forwardSwipeForgetAfterScrolling)
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
        mirror: { settings, defaults in defaults.set(settings.enableLiquidGlass, forKey: LiquidGlass.preferenceKey) }
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
