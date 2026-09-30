import Foundation

/// Every other Apollo / Apollo-Reborn setting this app has an equivalent for,
/// imported from a backup.
///
/// Rules:
///  - Key names are Apollo's and Apollo-Reborn's own.
///  - A key is applied only if the backup has it and its value is the
///    type/range Apollo writes; anything else keeps this install's value.
///    Nothing is reset to a default by its absence.
///  - Enumerated values are translated from the raw values Apollo writes
///    (e.g. Reborn's link preview mode Off=0/Compact=1/Full=2), never by
///    assuming our own enum's order.
///  - Transient state (launch counters, review prompts, caches, PiP last
///    position, "migrated" flags, Statsig/Bugsnag IDs) is not imported.
///    `ApolloSettingsMigration.notImported` lists them with the reason.
extension ApolloSettingsMigration {
    /// Keys this file applies, so the summary and the smoke suite can account for
    /// every key a backup carries.
    static let rebornKeys: Set<String> = [
        // General (comments, feed, media, links)
        "CollapsePinnedComments", "AutoCollapseChildComments", "AutoCollapseAutoModeratorComments",
        "TapToCollapseEnabledType", "CompactModeLeftThumbnails", "CompactPostsThumbnailSize", "CompactModeHideThumbnails",
        "UseCompactThumbnails", "ShowUserAvatars", "TrendingSubredditsLimit", "ConfirmFavoriteToggle", "PostCommentsSnapshots", "ActionMenuLayouts",
        "HideRPopularRedditList", "HideRAllRedditList", "HideModeratorRedditList",
        "SubredditFeedIconStyle", "SubredditFeedLayout", "3DTouchMarksRead", "HideBarsOnScroll", "ShareOldRedditLinks",
        "HideTopBarOnScroll", "CollapseNavigationActions", "ScrollReturnButton",
        "ShowCommentJumpButton", "CommentJumpButtonPosition", "ShowAwards", "ShowPostFlair",
        "ShowUserFlair", "AllowSaveCategories", "UnifyModmailInInbox", "LiveTextAnalyzer",
        "LoopVideosWithAudio", "ShowMediaViewerControlsWhenOpened", "VideoDeblurinatorEnabled",
        "UnmuteVideosWhenOpenedSetting", "ShowCommentsButton", "SharePostIncludesTitle",
        "DoomscrollDefeater3", "HapticFeedback", "LiveCommentsFollow",
        "HideTabBarTitles", "ClassicTabBarScrollBehavior", "LGTitleGapCentering",
        "CenterTitleBetweenButtons", "IPadTabBarBottom", "PictureInPictureEnabled",
        "FeedGalleryCarousel", "FeedGalleryEdgeSwipeNavigation", "SwipeUpForComments",
        "NSFWBlurOverride", "PreferredGIFFallbackFormat", "UnmuteFeedVideos",
        "UnmuteCommentsVideos", "ShareLinkHost", "ImageUploadProvider", "CommentLinkHost",
        "CommentLinkPreferNative", "ProxyImgurDDG", "ImgurAlbumFallbackProxies",
        "ApolloShareAsImageLinkMode", "ApolloShareAsImageIncludeLink",
        "ForwardSwipeForgetAfterScrolling", "FeedTextPostThumbnails",
        "DevvitFeedWidgets", "PollOptionAlignment", "AutoplayGIFs",
        "RememberRedditCommentsSort", "PerPostCommentSort",
        // Appearance
        "BoldPostTitles", "CompactModeHideVotingButtons", "CompactModeRightVotingButtons",
        "LargeThumbnailsShowVotingButtons", "ShowGIFProgressLocation", "RememberRedditPostSize",
        // Subreddit header / highlights
        "SubredditShowBanner", "SubredditShowJoinButton", "SubredditShowDisplayName",
        "SubredditShowSubtitle", "SubredditShowDescription", "SubredditShowSidebarButton",
        "SubredditShowUserFlairButton", "CommunityHighlights", "CommunityHighlightsWeb",
        // Inline media, link previews
        "EnableInlineImages", "EnableChatMedia", "InlineImageAlignment", "AutoplayInlineGIFs",
        "InlineMediaSizePercent", "LinkPreviewBodyMode", "LinkPreviewCommentsMode",
        "LinkPreviewCardColorHex",
        // Picture in Picture
        "PictureInPictureActivation", "PictureInPictureNative", "PictureInPictureLoop",
        "PictureInPictureStartHidden", "PictureInPictureSkipButtons", "PictureInPictureSkipSeconds",
        "PictureInPictureProgressBar", "PictureInPictureStartPosition",
        // Deleted comments
        "ShowDeletedComments", "PassiveDeletedComments", "TapToRevealDeletedComments",
        // Translation
        "EnableBulkTranslation", "TranslationProvider", "AutoTranslateOnAppear", "TapToTranslate",
        "TranslatePostTitles", "ShowTranslationDetails", "ShowTranslationTitleDetails",
        "TranslationMarkerUseThemeColor", "AppleTranslateSheet", "TranslationTargetLanguage",
        "LibreTranslateURL", "LibreTranslateAPIKey", "MicrosoftTranslateAPIKey",
        "MicrosoftTranslateRegion", "TranslationSkipLanguages",
        // Info row
        "IconRowMagnifier", "InfoRowTapUpvote", "InfoRowTapComments", "InfoRowPopupMode",
        "InfoRowOverlayMode", "InfoRowTapTranslation",
        // Pure black (group domain)
        "UsePureBlackDarkMode", "UsePurePUREBlackMode", "PureBlackModeReduceSmearing",
        // Feed scrubber, hold speed
        "FeedVideoScrubber", "VideoHoldSpeedEnabled", "VideoHoldSpeed",
        "GalleryAutoplayVideos", "GalleryAutoplayGIFs", "TabBarSwipeNavigation", "SettingsTabShortcuts",
        // Profile layout
        "ProfileHeaderImmersive", "ShowDetailedProfiles", "ProfileShowBanner", "ProfileShowStatCards",
        "ProfileShowSocialLinks", "ProfileShowActions", "BadgeBookEnabled", "ProfileAvatarStyle",
        // Subreddit list sections
        "SeparateFollowedUsers", "HideMultiredditDescriptions", "SubredditListEnhancements",
        "ModernSubredditDividers",
        // Floating post tabs
        "FloatingPostTabs", "FloatingPostTabsMagnet", "FloatingPostTabsPreview",
        // Recently read
        "FilterNSFWRecentlyRead", "ShowRecentlyReadThumbnails", "ReadPostMaxCount",
        // Swipe gestures + navigation gestures
        "PostsSlideGestures", "CommentsSlideGestures", "InboxCommentsSlideGestures",
        "ProfilePostsSlideGestures", "ProfileCommentsSlideGestures",
        "LongSwipeGestureTriggerPoint",
        "TagFilterSubredditOverrides", "PostFilterSubreddits", "PostFilterNameSubstrings",
        "DisableMarkingPostsRead", "MarkReadOnScroll", "ShowHideReadPostsFloatingActionButton",
        "HidePostsTemporarily", "AutoHideReadPosts", "DisableAutoHideReadPostsInSubreddits",
        "ApolloCustomTextSize", "HideSubredditListDescriptions", "PerAccountFavoritesEnabled",
        "UseCustomOAuthSignIn", "NotificationSound", "NotificationBackendRegistrationToken",
        "CrashCaptureEnabled",
        // Theme switching
        "UseSystemLightDarkMode", "ThemeToggleGestureEnabled", "ThemeSwitchMode",
        "AutomaticThemeToggleThreshold", "AutomaticThemeToggleUseSunset",
        // Notifications backend / Bark
        "NotificationBackendURL", "BarkNotificationsEnabled", "BarkPushURL",
        // Tag filters, post filters, keyword filters
        "TagFilterEnabled", "TagFilterNSFW", "TagFilterSpoiler", "KeywordFilters",
        // Custom subreddit sources
        "RandomSubredditsSource", "TrendingSubredditsSource", "RandNsfwSubredditsSource",
        "ShowRandNsfwButton",
        // Lists and history
        "FavoriteSubreddits", "SortFavoritesAlphabetically", "ReadPostIDs", "ExpandedMultireddits",
        "FollowedUsersOrder", "HiddenModeratorSubreddits",
        // Open-in-app
        "OpenLinksInSteamApp", "OpenLinksInBlueskyApp", "OpenLinksInGitHubApp",
        // Media misc
        "ApolloGalleryVideosMuted", "ScrollEdgeEffectStyle",
        // Automatic backups
        "AutomaticBackupsEnabled", "AutomaticBackupIntervalDays",
    ]

    /// Keys a backup carries that are deliberately not imported, with the reason,
    /// so "every key is accounted for" is checkable.
    public static let notImported: [String: String] = [
        // Transient/diagnostic state - importing it would be wrong, not just unnecessary.
        "DisableApollonouncements": "no announcement server; Block Announcements removed",
        "AppDidTheLaunchy_Date": "launch bookkeeping", "TotalLaunches": "launch counter",
        "TotalLaunchesWhenMostRecentAccountAdded": "launch counter",
        "TotalTimesPoppedNavigationStack": "usage counter",
        "TotalUnmuteButtonTogglesInMediaViewer": "usage counter",
        "DateLastX": "timestamp", "DateOfLastRateUsageTimestamp2": "rate-limit timestamp",
        "DateOfLastSavedItemsFullRefresh": "cache timestamp",
        "DateOfLastScrollProgressBeam110-2": "timestamp", "DateOfLatestProReminder": "purchase prompt",
        "LastReviewRequestDate": "review prompt", "ScrollDistanceMilestone2_Date": "timestamp",
        "SubmittedComment_Date": "timestamp", "WallpaperPromptMostRecent2": "prompt timestamp",
        "RatesUsedHistorically2": "API rate history", "RatesUsedInTimestamp2": "API rate history",
        "SKPurchaseIntentUpdatesLastChecked": "StoreKit state", "SavedAppBuildNumber": "version marker",
        "SavedAppVersion": "version marker", "LastSeenWhatsNewVersion": "what's-new marker",
        "ShowedMediaDisplayUpdate": "one-time explainer", "ShowedUnmuteButtonSettingExplainer": "one-time explainer",
        "HasUsedRandomSubreddit": "one-time hint", "MostRecentSharedURLSoNotToAskOnLaunch": "clipboard prompt state",
        "PictureInPictureLastCenterX": "window position", "PictureInPictureLastCenterY": "window position",
        "PictureInPictureLastStashSide": "window position",
        "CKEntryViewLayoutMetricsInfo": "system keyboard cache",
        "kCKMediaObjectManagerDefaultsClasses": "system cache", "kCKMediaObjectManagerDefaultsDynTypes": "system cache",
        "kCKMediaObjectManagerDefaultsOSVersion": "system cache", "kCKMediaObjectManagerDefaultsUTITypes": "system cache",
        "kPINRemoteImageDiskCacheVersionKey": "image cache", "CommunityHighlightsDiskCache": "cache",
        "SubredditIconData": "icon cache",
        "ApolloAppleSupportedLangCodes": "system language cache", "airprint-active": "system state",
        "awesome_notifications": "system state", "trackedKey": "analytics", "BugsnagUserUserId": "analytics",
        "com.Statsig.InternalStore.stableIDKey": "analytics",
        "ApolloLGDailyFeaturedDay": "daily rotation state", "ApolloLGDailyFeaturedIDs": "daily rotation state",
        // One-shot migrations Apollo ran on itself.
        "HasMigratedFiltersV1": "migration flag", "MigratedFiltersV1": "migration flag",
        "MigratedTapToCollapseSetting": "migration flag", "ModernMailboxChoiceMigrated": "migration flag",
        "UltraUnreadCommsMigrate": "migration flag", "ApolloLGLegacyClassicsMigrationV1": "migration flag",
        "CommMigrationOccurred": "migration flag", "ProMigrationOccurred": "migration flag",
        "SPMigrationOccurred": "migration flag", "UMigrationOccurred": "migration flag",
        // Accounts: restored separately by `applyAccounts` from the keychain file.
        "RedditAccounts2": "restored by applyAccounts", "RedditApplicationOnlyAccount2": "app-only token",
        "LoggedInAccountDetails": "restored by applyAccounts", "CurrentRedditAccountIndex": "restored by applyAccounts",
        "PerAccountAPICredentials": "per-account keys; the global keys are imported",
        "WebSessionPollOnlyIndex": "web-session index, rebuilt on sign-in",
        "WebSessionUsernameIndex": "web-session index, rebuilt on sign-in",
        // Features with no equivalent here.
        "DefaultSubreddits": "app-only signed-out list; this app uses the signed-in account",
        "ApolloRebornCustomThemes": "Reborn theme format differs from this app's themes",
        "ApolloRebornCustomThemeColors": "Reborn theme format differs",
        "ApolloRebornActiveCustomThemeID": "Reborn theme format differs",
        "ApolloReborn.customThemes": "Reborn theme format differs", "ApolloReborn.activeThemePointer": "Reborn theme format differs",
        "ApolloReborn.themeV1Backup": "Reborn theme format differs", "ApolloReborn.themeSchemaVersion": "Reborn theme format differs",
        "ApolloReborn.themeLaunchAttemptCompleted": "theme crash guard", "ApolloReborn.themeRecentCrashCount": "theme crash guard",
        "Theme": "stock Apollo theme name; mapped where a same-named theme exists (see applyTheme)",
        "ApolloOwnCommentFlairV1": "per-comment flair cache",
        "ApolloLGActiveIconID": "app icon is chosen by iOS per install",
        "BarkSelectedIconName": "Bark icon name, cosmetic",
        "EnableFlexDebugging": "FLEX is not included",
        "TouchIDPasscodeLockEnabled": "app lock is set up per device, never restored",
        "AppPasscodeEnabled": "app lock is set up per device, never restored",
        "WidgBackgroundOption": "no equivalent widget background option",
        "ShowSubredditWeatherTime": "no equivalent feature",
        "ShowUnreadComments": "no equivalent toggle (unread highlighting is always on)",
        "KeepSearchBarInPlace": "no equivalent toggle",
        "AutoHideTabBarShowOnIdle": "no equivalent toggle",
        "EnableShareAsImageWatermark": "no equivalent toggle",
        "CommunityHighlightsWebCache": "cache",
        "TranslationProviderUserSelected": "UI hint",
        "UseFullWidthSwipeBack": "stock key with no known meaning (no matching UI); not guessed",
        // Unlocks for Apollo's purchasable icon packs. Not transferable.
        "ATPUnlocked": "icon unlock", "AndruUnlocked": "icon unlock", "ApolloBookProUnlocked": "icon unlock",
        "CanadaUnlocked": "icon unlock", "Dave2DUnlocked": "icon unlock", "EAPUnlocked": "icon unlock",
        "ErnestUnlocked": "icon unlock", "HasUnlockedBeanVault": "icon unlock", "LinusUnlocked": "icon unlock",
        "MKBHDUnlocked": "icon unlock", "PeachyUnlocked": "icon unlock", "PhilUnlocked": "icon unlock",
        "ReneUnlocked": "icon unlock", "SlothkunUnlocked": "icon unlock", "SnazzyUnlocked": "icon unlock",
        "SusUnlocked": "icon unlock", "TLDTodayUnlocked": "icon unlock", "UkraineUnlocked": "icon unlock",
        "UnitedKingdomUnlocked": "icon unlock", "UnitedStates2Unlocked": "icon unlock",
        "UnitedStatesUnlocked": "icon unlock", "UnlockedWallpapers": "wallpaper unlock",
        "iJustineUnlocked": "icon unlock",
    ]

    /// Applies every key in `rebornKeys` that `values` carries.
    static func applyReborn(_ values: TrackedValues, note: (String) -> Void) {
        func bool(_ key: String) -> Bool? {
            guard let value = values[key], Self.isBoolean(value) else { return nil }
            return value as? Bool
        }
        func int(_ key: String) -> Int? {
            guard let value = values[key], !Self.isBoolean(value) else { return nil }
            if let number = value as? NSNumber { return number.intValue }
            if let value = value as? Int { return value }
            if let value = value as? String { return Int(value) }
            return nil
        }
        func double(_ key: String) -> Double? {
            guard let value = values[key], !Self.isBoolean(value) else { return nil }
            if let number = value as? NSNumber { return number.doubleValue }
            if let value = value as? Double { return value }
            return nil
        }
        func string(_ key: String) -> String? { values[key] as? String }
        func strings(_ key: String) -> [String]? { values[key] as? [String] }

        /// Applies `key` to `target` via `apply` if the value parses,
        /// noting it under `label`. Returns whether anything changed.
        @discardableResult
        func take<T>(_ key: String, _ label: String, _ parse: (String) -> T?, _ apply: (T) -> Void) -> Bool {
            guard let value = parse(key) else { return false }
            apply(value)
            note(label)
            return true
        }

        // MARK: General

        var general = GeneralSettingsStore.load()
        take("CollapsePinnedComments", "Collapse Pinned Comments", bool) { general.autoCollapsePinnedComments = $0 }
        take("ConfirmFavoriteToggle", "Confirm Favorite Changes", bool) { FavoriteSubredditsStore.confirmChanges = $0 }
        // Apollo stores this as a string: "manually" (default) or "automatically".
        take("AutoCollapseChildComments", "Auto-Collapse Child Comments", string) {
            general.autoCollapseChildComments = ($0 != "manually")
        }
        take("AutoCollapseAutoModeratorComments", "Collapse AutoModerator", bool) { general.autoCollapseAutoModeratorComments = $0 }
        take("TapToCollapseEnabledType", "Tap to Collapse", { string($0).flatMap(TapToCollapseType.init(rawValue:)) }) {
            general.tapToCollapseType = $0
        }
        take("CompactModeLeftThumbnails", "Thumbnails on Left", bool) { general.thumbnailsOnLeft = $0 }
        take("CompactPostsThumbnailSize", "Thumbnail Size", { string($0).flatMap(ThumbnailSize.init(rawValue:)) }) {
            general.thumbnailSize = $0
        }
        // Stock `CompactModeHideThumbnails` hides compact thumbnails;
        // this app models that as the `hidden` thumbnail size. Applied
        // AFTER the size key so a hidden thumbnail is not overwritten by
        // the size it would have had.
        take("CompactModeHideThumbnails", "Hide Compact Thumbnails", bool) {
            if $0 { general.thumbnailSize = .hidden }
            else if general.thumbnailSize == .hidden { general.thumbnailSize = .small }
        }
        // `UseCompactThumbnails` is the real "Compact" vs "Large" post
        // size switch (stock default false = large).
        take("UseCompactThumbnails", "Post Size", bool) { general.postDisplayStyle = $0 ? .compact : .large }
        take("ShowUserAvatars", "Show User Avatars", bool) { general.showUserProfilePictures = $0 }
        take("TabBarSwipeNavigation", "Swipe Tab Bar to Navigate", bool) { general.tabBarSwipeNavigation = $0 }
        // Real type is a STRING ("5"), per Reborn's registered default.
        take("TrendingSubredditsLimit", "Trending Subreddits Limit", int) { general.trendingSubredditsLimit = $0 }
        take("HideRPopularRedditList", "Hide r/popular Row", bool) { general.hidePopularInSubredditList = $0 }
        take("HideRAllRedditList", "Hide r/all Row", bool) { general.hideAllInSubredditList = $0 }
        take("HideModeratorRedditList", "Hide Moderator Row", bool) { general.hideModeratorInSubredditList = $0 }
        // `ApolloSubredditFeedIconStyle` Classic..SolidTile = 0...4 and
        // `ApolloSubredditFeedLayout` Rows..IconDock = 0...3, in the same
        // order as our cases.
        take("SubredditFeedIconStyle", "Feed Icon Style", { int($0).flatMap { i in FeedIconStyle.allCases[safe: i] } }) {
            general.subredditFeedIconStyle = $0
        }
        take("SubredditFeedLayout", "Feed Shortcut Layout", { int($0).flatMap { i in FeedShortcutLayout.allCases[safe: i] } }) {
            general.subredditFeedLayout = $0
        }
        take("3DTouchMarksRead", "3D Touch Marks Read", bool) { general.threeDTouchMarksRead = $0 }
        take("HideBarsOnScroll", "Hide Bars on Scroll", bool) { general.hideBarsOnScroll = $0 }
        take("ShareOldRedditLinks", "Share old.reddit Links", bool) { general.shareOldRedditLinks = $0 }
        take("HideTopBarOnScroll", "Hide Top Bar on Scroll", bool) { general.hideTopBarOnScroll = $0 }
        take("CollapseNavigationActions", "Collapse Navigation Actions", bool) { general.collapseNavigationActions = $0 }
        take("ScrollReturnButton", "Scroll Return Button", bool) { general.scrollReturnButton = $0 }
        take("ShowCommentJumpButton", "Comment Jump Button", bool) { general.showJumpButton = $0 }
        // Stock values "bottom-right" (default), "bottom-left", etc.
        take("CommentJumpButtonPosition", "Jump Button Position", string) {
            general.jumpButtonPosition = JumpButtonPosition(stockValue: $0) ?? .bottomTrailing
        }
        take("ShowAwards", "Show Awards", bool) { general.showAwards = $0 }
        take("ShowPostFlair", "Show Post Flair", bool) { general.showPostFlair = $0 }
        take("ShowUserFlair", "Show User Flair", bool) { general.showUserFlair = $0 }
        take("AllowSaveCategories", "Saved Categories", bool) { general.allowSaveCategories = $0 }
        take("UnifyModmailInInbox", "Unify Modmail in Inbox", bool) { general.unifyModmailInInbox = $0 }
        take("LiveTextAnalyzer", "Live Text", bool) { general.liveTextAnalyzer = $0 }
        take("LoopVideosWithAudio", "Loop Videos with Audio", bool) { general.loopVideosWithAudio = $0 }
        take("ShowMediaViewerControlsWhenOpened", "Media Viewer Controls", bool) { general.showMediaViewerControlsWhenOpened = $0 }
        take("VideoDeblurinatorEnabled", "Video Deblurinator", bool) { general.videoDeblurinatorEnabled = $0 }
        take("UnmuteVideosWhenOpenedSetting", "Unmute Videos When Opened",
             { string($0).flatMap(UnmuteWhenOpenedSetting.init(rawValue:)) }) {
            general.unmuteVideosWhenOpened = $0
        }
        take("ShowCommentsButton", "Show Comments Button", bool) { general.showCommentsButton = $0 }
        take("SharePostIncludesTitle", "Share Includes Title", bool) { general.sharePostIncludesTitle = $0 }
        take("DoomscrollDefeater3", "Infinite Scrolling", bool) { general.infiniteScrollingEnabled = $0 }
        take("HapticFeedback", "Haptic Feedback", bool) { general.hapticFeedbackEnabled = $0 }
        take("LiveCommentsFollow", "Live Comments Follow", bool) { general.liveCommentsFollow = $0 }
        take("HideTabBarTitles", "Icon-Only Tab Bar", bool) { general.iconOnlyTabBar = $0 }
        take("ClassicTabBarScrollBehavior", "Classic Tab Bar Scrolling", bool) { general.classicTabBarScrollBehavior = $0 }
        // Older Reborn builds write `LGTitleGapCentering`, current ones
        // `CenterTitleBetweenButtons`. Either sets the same switch; the current
        // key wins.
        take("LGTitleGapCentering", "Center Title Between Buttons", bool) { general.centerTitleGapCentering = $0 }
        take("CenterTitleBetweenButtons", "Center Title Between Buttons", bool) { general.centerTitleGapCentering = $0 }
        take("IPadTabBarBottom", "iPad Tab Bar at Bottom", bool) { general.ipadTabBarBottom = $0 }
        take("FeedGalleryCarousel", "Feed Gallery Carousel", bool) { general.feedGalleryCarousel = $0 }
        take("FeedGalleryEdgeSwipeNavigation", "Gallery Edge Swipe", bool) { general.feedGalleryEdgeSwipeNav = $0 }
        take("SwipeUpForComments", "Swipe Up for Comments", bool) { general.swipeUpForComments = $0 }
        take("NSFWBlurOverride", "NSFW Blur", { int($0).flatMap(NSFWBlurOverride.init(rawValue:)) }) { general.nsfwBlurOverride = $0 }
        take("PreferredGIFFallbackFormat", "GIF Fallback Format",
             { int($0).flatMap(PreferredGIFFallbackFormat.init(rawValue:)) }) { general.preferredGIFFallbackFormat = $0 }
        take("UnmuteFeedVideos", "Unmute Feed Videos", { int($0).flatMap(VideoUnmuteMode.init(rawValue:)) }) {
            general.unmuteFeedVideosMode = $0
        }
        take("UnmuteCommentsVideos", "Unmute Comment Videos", { int($0).flatMap(VideoUnmuteMode.init(rawValue:)) }) {
            general.unmuteCommentsVideosMode = $0
        }
        take("ShareLinkHost", "Share Link Host", { int($0).flatMap(ShareLinkHost.init(rawValue:)) }) { general.shareLinkHost = $0 }
        take("ImageUploadProvider", "Image Upload Host", { int($0).flatMap(MediaUploadHost.init(rawValue:)) }) {
            general.mediaUploadHost = $0
        }
        take("CommentLinkHost", "Comment Link Host", { int($0).flatMap(CommentLinkHost.init(rawValue:)) }) {
            general.commentLinkHost = $0
        }
        take("CommentLinkPreferNative", "Prefer Native Comment Links", bool) { general.commentLinkPreferNative = $0 }
        take("ProxyImgurDDG", "Proxy Imgur via DuckDuckGo", bool) { general.proxyImgurViaDuckDuckGo = $0 }
        take("ImgurAlbumFallbackProxies", "Imgur Album Fallbacks", bool) { general.imgurAlbumFallbackProxies = $0 }
        take("ForwardSwipeForgetAfterScrolling", "Forget Forward Swipe After Scrolling", bool) {
            general.forwardSwipeForgetAfterScrolling = $0
        }
        take("FeedTextPostThumbnails", "Text Post Thumbnails", bool) { general.textPostThumbnailsEnabled = $0 }
        take("DevvitFeedWidgets", "Live Post Widgets in Feed", bool) { general.devvitFeedWidgets = $0 }
        // `ApolloPollOptionAlignment`: Center = 0, Left = 1.
        take("PollOptionAlignment", "Poll Option Alignment", int) { general.pollOptionAlignmentLeft = ($0 == 1) }
        // Stock values "always" / "wifi" / "never".
        take("AutoplayGIFs", "Autoplay GIFs", string) {
            switch $0 {
            case "wifi", "wifi-only": general.autoplayMode = .wifiOnly
            case "never": general.autoplayMode = .never
            default: general.autoplayMode = .always
            }
        }
        take("RememberRedditCommentsSort", "Remember Comment Sort", bool) { general.rememberCommentsSortPerSubreddit = $0 }
        GeneralSettingsStore.save(general)
        // `PerPostCommentSort` / `RememberRedditCommentsSort`: Reborn's
        // two booleans, one three-way mode here. Per-post wins, as it is
        // the more specific memory.
        let perPost = bool("PerPostCommentSort")
        let perSub = bool("RememberRedditCommentsSort")
        if perPost != nil || perSub != nil {
            CommentSortMemoryStore.saveMode(perPost == true ? .post : (perSub == true ? .subreddit : .off))
            note("Comment Sort Memory")
        }

        // MARK: Appearance

        var appearance = AppearanceSettingsStore.load()
        take("BoldPostTitles", "Bold Post Titles", bool) { appearance.boldPostTitles = $0 }
        take("RememberRedditPostSize", "Remember Post Size", bool) { appearance.rememberPostSizePerSubreddit = $0 }
        take("CompactModeHideVotingButtons", "Voting Buttons", bool) { appearance.showVotingButtons = !$0 }
        take("CompactModeRightVotingButtons", "Voting Buttons Position", bool) { appearance.votingButtonsPosition = $0 ? .right : .left }
        take("LargeThumbnailsShowVotingButtons", "Large Posts Voting Buttons", bool) { appearance.largePostsShowVotingButtons = $0 }
        // Stock values "everywhere" / "thumbnail" / "media-viewer".
        take("ShowGIFProgressLocation", "GIF Progress", string) {
            switch $0 {
            case "thumbnail": appearance.gifProgressLocation = .thumbnail
            case "media-viewer", "mediaViewer": appearance.gifProgressLocation = .mediaViewer
            default: appearance.gifProgressLocation = .everywhere
            }
        }
        AppearanceSettingsStore.save(appearance)

        // MARK: Subreddit header, community highlights

        var layout = SubredditLayoutSettingsStore.load()
        take("SubredditShowBanner", "Subreddit Banner", bool) { layout.subredditShowBanner = $0 }
        take("SubredditShowJoinButton", "Subreddit Join Button", bool) { layout.subredditShowJoinButton = $0 }
        take("SubredditShowDisplayName", "Subreddit Display Name", bool) { layout.subredditShowDisplayName = $0 }
        take("SubredditShowSubtitle", "Subreddit Subtitle", bool) { layout.subredditShowSubtitle = $0 }
        take("SubredditShowDescription", "Subreddit Description", bool) { layout.subredditShowDescription = $0 }
        take("SubredditShowSidebarButton", "Subreddit Sidebar Button", bool) { layout.subredditShowSidebarButton = $0 }
        take("SubredditShowUserFlairButton", "Subreddit Flair Button", bool) { layout.subredditShowUserFlairButton = $0 }
        // Two real booleans, one mode here: off / REST only (partial) /
        // REST + web (full).
        if let rest = bool("CommunityHighlights") {
            let web = bool("CommunityHighlightsWeb") ?? false
            layout.communityHighlights = !rest ? .off : (web ? .full : .partial)
            note("Community Highlights")
        }
        SubredditLayoutSettingsStore.save(layout)

        // MARK: Inline media, link previews

        var inline = InlineMediaSettingsStore.load()
        take("EnableInlineImages", "Inline Images", bool) { inline.enabled = $0 }
        take("EnableChatMedia", "Inline Media in Messages", bool) { inline.enabledInMessages = $0 }
        // `ApolloInlineImageAlignment`: Center = 0, Left = 1, Right = 2.
        take("InlineImageAlignment", "Inline Media Alignment", int) {
            inline.alignment = [0: .center, 1: .left, 2: .right][$0] ?? inline.alignment
        }
        // `ApolloAutoplayInlineGIFMode`: Default = 0, Never = 1,
        // WiFiOnly = 2, Always = 3, TapToPlay = 4. Default (0) resolves to
        // the app-wide autoplay setting, as Reborn does on load.
        take("AutoplayInlineGIFs", "Inline GIF Autoplay", int) {
            let resolvedDefault = InlineGIFAutoplayMode.following(GeneralSettingsStore.load().autoplayMode)
            inline.autoplayMode = [0: resolvedDefault, 1: .never, 2: .wifiOnly, 3: .always, 4: .tapToPlay][$0] ?? inline.autoplayMode
        }
        take("InlineMediaSizePercent", "Inline Media Size", { int($0).flatMap(InlineMediaSize.init(rawValue:)) }) { inline.size = $0 }
        InlineMediaSettingsStore.save(inline)

        var preview = LinkPreviewSettingsStore.load()
        // `ApolloLinkPreviewMode`: Off = 0, Compact = 1, Full = 2.
        let previewMode: (Int) -> LinkPreviewDisplayMode? = { [0: .off, 1: .compact, 2: .full][$0] }
        take("LinkPreviewBodyMode", "Link Previews in Posts", { int($0).flatMap(previewMode) }) { preview.bodyDisplayMode = $0 }
        take("LinkPreviewCommentsMode", "Link Previews in Comments", { int($0).flatMap(previewMode) }) { preview.commentsDisplayMode = $0 }
        // Empty string is the real "default colour" value.
        take("LinkPreviewCardColorHex", "Link Preview Colour", string) { preview.cardColorHex = $0.isEmpty ? nil : $0 }
        LinkPreviewSettingsStore.save(preview)

        // MARK: Picture in Picture

        var pip = PictureInPictureSettingsStore.load()
        take("PictureInPictureEnabled", "Picture in Picture", bool) { pip.inAppEnabled = $0 }
        // Apollo's own switch (`PictureInPicture`) is the system PiP button;
        // Reborn's `PictureInPictureNative` below wins when both are present.
        take("PictureInPicture", "System PiP", bool) { pip.systemEnabled = $0 }
        // `ApolloPiPActivationMode`: AllVideos = 0, UnmutedOnly = 1,
        // AllVideosAndGifs = 2. Our enum puts unmutedOnly at 0, so this
        // translates by meaning.
        take("PictureInPictureActivation", "PiP Activation", int) {
            pip.activation = [0: .allVideos, 1: .unmutedOnly, 2: .allVideosAndGIFs][$0] ?? pip.activation
        }
        take("PictureInPictureNative", "System PiP", bool) { pip.systemEnabled = $0 }
        take("PictureInPictureLoop", "PiP Loop", bool) { pip.loopVideos = $0 }
        take("PictureInPictureStartHidden", "PiP Start Hidden", bool) { pip.startHidden = $0 }
        take("PictureInPictureSkipButtons", "PiP Skip Buttons", bool) { pip.skipButtons = $0 }
        take("PictureInPictureSkipSeconds", "PiP Skip Seconds", int) { pip.skipSeconds = $0 }
        take("PictureInPictureProgressBar", "PiP Progress Bar", bool) { pip.progressBar = $0 }
        take("PictureInPictureStartPosition", "PiP Start Position",
             { int($0).flatMap(PictureInPictureSettings.StartPosition.init(rawValue:)) }) { pip.startPosition = $0 }
        PictureInPictureSettingsStore.save(pip)

        // MARK: Deleted comments

        if bool("ShowDeletedComments") != nil || bool("PassiveDeletedComments") != nil
            || bool("TapToRevealDeletedComments") != nil {
            var deleted = DeletedCommentsSettingsStore.load()
            // Two real booleans, one tri-state here.
            let show = bool("ShowDeletedComments") ?? (deleted.mode == .alwaysShow)
            let passive = bool("PassiveDeletedComments") ?? (deleted.mode == .passive)
            deleted.mode = show ? .alwaysShow : (passive ? .passive : .off)
            if let tap = bool("TapToRevealDeletedComments") { deleted.tapToReveal = tap }
            DeletedCommentsSettingsStore.save(deleted)
            note("Deleted Comments")
        }

        // MARK: Translation

        var translation = TranslationSettingsStore.load()
        take("EnableBulkTranslation", "Translation", bool) { translation.enableBulkTranslation = $0 }
        // Real values "google" / "libre" / "microsoft"; ours spell
        // LibreTranslate out.
        take("TranslationProvider", "Translation Provider", string) {
            switch $0 {
            case "libre", "libretranslate", "libreTranslate": translation.provider = .libreTranslate
            case "microsoft": translation.provider = .microsoft
            case "google": translation.provider = .google
            case "apple": translation.provider = .apple
            default: break
            }
        }
        // Two real booleans, one mode here: auto-translate on appear,
        // tap-to-translate, or neither (manual).
        if let auto = bool("AutoTranslateOnAppear") {
            let tap = bool("TapToTranslate") ?? false
            translation.mode = auto ? .automatic : (tap ? .tapToTranslate : .manual)
            note("Translation Mode")
        }
        take("TranslatePostTitles", "Translate Titles", bool) { translation.translatePostTitles = $0 }
        take("ShowTranslationDetails", "Translation Details", bool) { translation.showDetails = $0 }
        take("ShowTranslationTitleDetails", "Title Translation Details", bool) { translation.showTitleDetails = $0 }
        take("TranslationMarkerUseThemeColor", "Translation Marker Colour", bool) { translation.matchAppColour = $0 }
        take("AppleTranslateSheet", "Apple Translate Sheet", bool) { translation.useAppleTranslateSheet = $0 }
        take("TranslationTargetLanguage", "Translation Language", string) { if !$0.isEmpty { translation.targetLanguageCode = $0 } }
        take("LibreTranslateURL", "LibreTranslate URL", string) { if !$0.isEmpty { translation.libreTranslateURL = $0 } }
        take("LibreTranslateAPIKey", "LibreTranslate API key", string) { if !$0.isEmpty { translation.libreTranslateAPIKey = $0 } }
        take("MicrosoftTranslateAPIKey", "Microsoft Translator key", string) { if !$0.isEmpty { translation.microsoftAPIKey = $0 } }
        take("MicrosoftTranslateRegion", "Microsoft Translator region", string) { if !$0.isEmpty { translation.microsoftRegion = $0 } }
        take("TranslationSkipLanguages", "Skip Languages", strings) { translation.skipLanguageCodes = $0 }
        TranslationSettingsStore.save(translation)

        // MARK: Info row

        var info = InfoRowSettingsStore.load()
        take("IconRowMagnifier", "Info Row Magnifier", bool) { info.magnifierOnHold = $0 }
        take("InfoRowTapUpvote", "Info Row Tap to Upvote", bool) { info.tapToUpvote = $0 }
        take("InfoRowTapComments", "Info Row Tap to Comments", bool) { info.tapToComments = $0 }
        take("InfoRowPopupMode", "Info Row Popup", bool) { info.popupMode = $0 }
        take("InfoRowOverlayMode", "Info Row Overlay", bool) { info.overlayMode = $0 }
        take("InfoRowTapTranslation", "Info Row Tap to Translate", bool) { info.tapToTranslation = $0 }
        InfoRowSettingsStore.save(info)

        // MARK: Pure black (stock Apollo, group domain)

        var black = PureBlackSettingsStore.load()
        take("UsePureBlackDarkMode", "Pure Black Dark Mode", bool) { black.isEnabled = $0 }
        take("UsePurePUREBlackMode", "Purer Black", bool) { black.isPurerEnabled = $0 }
        take("PureBlackModeReduceSmearing", "Reduce Smearing", bool) { black.reduceSmearing = $0 }
        PureBlackSettingsStore.save(black)

        // MARK: Feed scrubber, hold for speed

        var scrubber = FeedVideoScrubberStore.load()
        take("FeedVideoScrubber", "Feed Video Scrubber", bool) { scrubber.isEnabled = $0 }
        var galleryAutoplay = GalleryAutoplayStore.load()
        take("GalleryAutoplayVideos", "Play Videos in Gallery View", bool) { galleryAutoplay.playVideos = $0 }
        take("GalleryAutoplayGIFs", "Play GIFs in Gallery View", bool) { galleryAutoplay.playGIFs = $0 }
        GalleryAutoplayStore.save(galleryAutoplay)
        FeedVideoScrubberStore.save(scrubber)
        var hold = VideoHoldSpeedStore.load()
        take("VideoHoldSpeedEnabled", "Hold for Speed", bool) { hold.isEnabled = $0 }
        take("VideoHoldSpeed", "Hold Speed", double) { if $0 > 0 { hold.holdSpeed = Float($0) } }
        VideoHoldSpeedStore.save(hold)

        // MARK: Profile layout

        var profile = ProfileLayoutSettingsStore.load()
        take("ProfileHeaderImmersive", "Immersive Profile Header", bool) { profile.headerImmersive = $0 }
        take("ShowDetailedProfiles", "Profile Style (Native)", bool) { profile.showDetailedProfiles = $0 }
        take("ProfileShowBanner", "Profile Banner", bool) { profile.showBanner = $0 }
        take("ProfileShowStatCards", "Profile Stat Cards", bool) { profile.showStatCards = $0 }
        take("ProfileShowSocialLinks", "Profile Social Links", bool) { profile.showSocialLinks = $0 }
        take("ProfileShowActions", "Profile Actions", bool) { profile.showActions = $0 }
        take("BadgeBookEnabled", "Badge Book", bool) { profile.badgeBookEnabled = $0 }
        take("ProfileAvatarStyle", "Profile Avatar Style",
             { int($0).flatMap(ProfileLayoutSettings.AvatarStyle.init(rawValue:)) }) { profile.avatarStyle = $0 }
        ProfileLayoutSettingsStore.save(profile)

        // MARK: Subreddit list sections

        var sections = SubredditSectionsSettingsStore.load()
        take("SeparateFollowedUsers", "Separate Followed Users", bool) { sections.separateFollowedUsers = $0 }
        take("HideMultiredditDescriptions", "Hide Multireddit Descriptions", bool) { sections.hideMultiredditDescriptions = $0 }
        take("SubredditListEnhancements", "Subreddit List Enhancements", bool) { sections.subredditListEnhancements = $0 }
        take("ModernSubredditDividers", "Modern Subreddit Dividers", bool) { sections.modernSubredditDividers = $0 }
        SubredditSectionsSettingsStore.save(sections)

        // MARK: Floating post tabs, recently read

        var tabs = FloatingPostTabsSettingsStore.load()
        take("FloatingPostTabs", "Floating Post Tabs", bool) { tabs.enabled = $0 }
        take("FloatingPostTabsMagnet", "Magnetic Tab Stacking", bool) { tabs.magneticStacking = $0 }
        take("FloatingPostTabsPreview", "Hold to Preview Tabs", bool) { tabs.holdToPreview = $0 }
        FloatingPostTabsSettingsStore.save(tabs)

        var recent = RecentlyReadSettingsStore.load()
        take("FilterNSFWRecentlyRead", "Filter NSFW from Recently Read", bool) { recent.filterNSFW = $0 }
        take("ShowRecentlyReadThumbnails", "Recently Read Thumbnails", bool) { recent.showThumbnails = $0 }
        // 0 means "no limit" in Reborn.
        take("ReadPostMaxCount", "Recently Read Limit", int) { recent.maxCount = $0 > 0 ? $0 : nil }
        RecentlyReadSettingsStore.save(recent)

        // MARK: Swipe gestures

        // Five real arrays, each [leftShort, leftLong, rightShort,
        // rightLong] in stock Apollo's own action vocabulary.
        let screens: [(String, SwipeActionScreen)] = [
            ("PostsSlideGestures", .posts), ("CommentsSlideGestures", .comments),
            ("InboxCommentsSlideGestures", .inbox), ("ProfilePostsSlideGestures", .profilePosts),
            ("ProfileCommentsSlideGestures", .profileComments),
        ]
        for (key, screen) in screens {
            guard let raw = strings(key), raw.count == 4 else { continue }
            let actions = raw.map(Self.swipeAction(fromApollo:))
            SwipeActionStore.save(SwipeActionSettings(
                leftShort: actions[0], leftLong: actions[1],
                rightShort: actions[2], rightLong: actions[3]), for: screen)
            note("\(screen.displayName) Swipe Actions")
        }
        var navigation = NavigationGestureSettingsStore.load()
        // Apollo spells the third value "later".
        take("LongSwipeGestureTriggerPoint", "Long Swipe Trigger Point",
             { string($0).map(LongSwipeTriggerPoint.init(storedValue:)) }) { navigation.longSwipeTriggerPoint = $0 }
        NavigationGestureSettingsStore.save(navigation)

        // MARK: Mark Read / Hiding

        var markRead = ReadPostStore.loadSettings()
        take("DisableMarkingPostsRead", "Disable Marking Posts Read", bool) { markRead.markReadOnOpen = !$0 }
        take("MarkReadOnScroll", "Mark Read on Scroll", bool) { markRead.markReadOnScroll = $0 }
        take("ShowHideReadPostsFloatingActionButton", "Show Hide Read Button", bool) { markRead.showHideReadButton = $0 }
        take("HidePostsTemporarily", "Hide Posts", bool) { markRead.hideReadPosts = !$0 }
        take("AutoHideReadPosts", "Auto Hide Read Posts", bool) { markRead.autoHideReadPosts = $0 }
        take("DisableAutoHideReadPostsInSubreddits", "Disable Auto Hide in Subreddits", bool) { markRead.disableAutoHideInSubreddits = $0 }
        ReadPostStore.saveSettings(markRead)

        // MARK: Appearance text size

        // One-based, 1 = Extra Small ... 4 = Large ... 7 = XXX Large.
        var textAppearance = AppearanceSettingsStore.load()
        take("ApolloCustomTextSize", "Text Size", { int($0).flatMap(AppearanceTextSizeStep.scale(forApolloTextSize:)) }) {
            textAppearance.textSizeScale = $0
        }
        AppearanceSettingsStore.save(textAppearance)

        // MARK: Subreddit list

        var subredditList = GeneralSettingsStore.load()
        take("HideSubredditListDescriptions", "Hide Feed Descriptions", bool) { subredditList.hideFeedDescriptions = $0 }
        GeneralSettingsStore.save(subredditList)
        take("PerAccountFavoritesEnabled", "Per-Account Favorites", bool) { FavoriteSubredditsStore.perAccountEnabled = $0 }

        // MARK: Custom API / notifications

        take("CrashCaptureEnabled", "Store Crash Reports Locally", bool) {
            UserDefaults.standard.set($0, forKey: CrashCaptureSettings.enabledKey)
        }
        var customAPI = CustomAPISettingsStore.load()
        take("UseCustomOAuthSignIn", "Universal OAuth Sign-In", bool) { customAPI.useCustomOAuthSignIn = $0 }
        CustomAPISettingsStore.save(customAPI)
        var notifications = NotificationSettingsStore.load()
        take("NotificationSound", "Notification Sound", { string($0).flatMap(NotificationSound.init(rawValue:)) }) {
            notifications.notificationSound = $0
        }
        NotificationSettingsStore.save(notifications)

        // MARK: Theme switching

        var themeSwitch = ThemeAutoSwitchSettingsStore.load()
        take("UseSystemLightDarkMode", "Match System Light/Dark", bool) { themeSwitch.useSystemLightDarkMode = $0 }
        take("ThemeToggleGestureEnabled", "Quick Switch", bool) { themeSwitch.quickSwitchEnabled = $0 }
        take("ThemeSwitchMode", "Theme Switch Mode", { string($0).flatMap(ThemeSwitchMode.init(rawValue:)) }) {
            themeSwitch.switchMode = $0
        }
        take("AutomaticThemeToggleThreshold", "Brightness Threshold", double) { themeSwitch.brightnessThreshold = $0 }
        take("AutomaticThemeToggleUseSunset", "Use Sunset/Sunrise", bool) { themeSwitch.useLocationSunsetSunrise = $0 }
        ThemeAutoSwitchSettingsStore.save(themeSwitch)

        // MARK: Notification backend / Bark

        var backend = NotificationBackendSettingsStore.load()
        take("NotificationBackendURL", "Notification Backend", string) { if !$0.isEmpty { backend.backendURL = $0 } }
        take("BarkNotificationsEnabled", "Bark Notifications", bool) { backend.barkEnabled = $0 }
        take("BarkPushURL", "Bark Push URL", string) { if !$0.isEmpty { backend.barkPushURL = $0 } }
        take("NotificationBackendRegistrationToken", "Notification Backend Token", string) {
            if !$0.isEmpty { backend.registrationToken = $0 }
        }
        NotificationBackendSettingsStore.save(backend)

        // MARK: Filters

        var tags = TagFilterStore.load()
        take("TagFilterEnabled", "Tag Filters", bool) { tags.enabled = $0 }
        take("TagFilterNSFW", "Filter NSFW Tag", bool) { tags.nsfw = $0 }
        take("TagFilterSpoiler", "Filter Spoiler Tag", bool) { tags.spoiler = $0 }
        // {sub: {"nsfw": Bool, "spoiler": Bool, "mode": "hide"|"blur"}};
        // this app has no per-subreddit mode, so only the tags travel.
        if let overrides = values["TagFilterSubredditOverrides"] as? [String: [String: Any]] {
            for (sub, entry) in overrides {
                let override = TagFilterSettings.Override(nsfw: entry["nsfw"] as? Bool, spoiler: entry["spoiler"] as? Bool)
                if override.nsfw != nil || override.spoiler != nil { tags.subredditOverrides[sub.lowercased()] = override }
            }
            note("Tag Filter Subreddit Overrides")
        }
        TagFilterStore.save(tags)

        // Reborn's Post Filters: {sub: {"keywords": [..], "flairs": [..]}}
        // and a list of subreddit-name substrings, all lowercased.
        var postFilters = PostFilterStore.load()
        if let subs = values["PostFilterSubreddits"] as? [String: [String: Any]] {
            for (sub, entry) in subs {
                postFilters.subreddits[sub.lowercased()] = PostFilterRules.SubredditRules(
                    keywords: (entry["keywords"] as? [String]) ?? [], flairs: (entry["flairs"] as? [String]) ?? [])
            }
            note("Post Filters")
        }
        take("PostFilterNameSubstrings", "Subreddit Name Filters", strings) { postFilters.nameSubstrings = $0 }
        PostFilterStore.save(postFilters)
        // Stock `KeywordFilters` is an array of strings (group domain).
        // Merged into our keyword filters without duplicating.
        if let keywords = strings("KeywordFilters"), !keywords.isEmpty {
            var filters = ContentFilterStore.load()
            let existing = Set(filters.filter { $0.kind == .keyword }.map { $0.value.lowercased() })
            for word in keywords where !existing.contains(word.lowercased()) {
                filters.append(ContentFilter(kind: .keyword, value: word))
            }
            ContentFilterStore.save(filters)
            note("Keyword Filters")
        }

        // MARK: Custom subreddit sources

        var sources = CustomSubredditSourceStore.load()
        take("RandomSubredditsSource", "Random Subreddits Source", string) { if !$0.isEmpty { sources.randomSourceURL = $0 } }
        take("TrendingSubredditsSource", "Trending Subreddits Source", string) { if !$0.isEmpty { sources.trendingSourceURL = $0 } }
        take("RandNsfwSubredditsSource", "Random NSFW Source", string) { if !$0.isEmpty { sources.randomNSFWSourceURL = $0 } }
        take("ShowRandNsfwButton", "Random NSFW Button", bool) { sources.showRandNSFWInSearch = $0 }
        CustomSubredditSourceStore.save(sources)

        // MARK: Lists and history

        if let favorites = strings("FavoriteSubreddits") {
            // Additive: an import never removes a favourite this install
            // already has.
            // In the backup's order, which is Apollo's native order.
            FavoriteSubredditsStore.setOrder(favorites)
            note("Favorite Subreddits (\(favorites.count))")
        }
        take("SortFavoritesAlphabetically", "Sort Favorites Alphabetically", bool) {
            FavoriteSubredditsStore.sortAlphabetically = $0
        }
        // Stock stores bare post IDs ("1abc234"); this app tracks
        // fullnames ("t3_1abc234").
        if let ids = strings("ReadPostIDs"), !ids.isEmpty {
            ReadPostStore.importRead(ids.map { $0.hasPrefix("t3_") ? $0 : "t3_" + $0 })
            note("Read Posts (\(ids.count))")
        }
        // Apollo's per-post comment totals at last visit, so the feed's
        // "+ N" new-comments pills carry over.
        if let raw = values["PostCommentsSnapshots"] {
            let data = (raw as? Data) ?? (raw as? String).map { Data($0.utf8) }
            let snapshots = data.map(NewCommentsTracker.decodeApolloSnapshots) ?? [:]
            if !snapshots.isEmpty {
                NewCommentsTracker.importCommentCounts(snapshots)
                note("New Comment Counts (\(snapshots.count))")
            }
        }
        // Stock stores `{username: [multireddit names]}`.
        if let expanded = values["ExpandedMultireddits"] as? [String: [String]] {
            var current = ExpandedMultiredditsStore.load()
            for names in expanded.values { current.formUnion(names) }
            ExpandedMultiredditsStore.save(current)
            note("Expanded Multireddits")
        }
        take("FollowedUsersOrder", "Followed Users Order", strings) { FollowedUsersOrderStore.save($0) }
        take("SettingsTabShortcuts", "Settings Shortcuts", strings) { SettingsShortcutsStore.save($0) }
        // Reborn Action Menus (#1131): same key and shape here.
        if let layouts = values[ActionMenuLayoutStore.key] as? [String: Any] {
            ActionMenuLayoutStore.defaults.set(layouts, forKey: ActionMenuLayoutStore.key)
            note("Action Menus")
        }
        take("HiddenModeratorSubreddits", "Hidden Moderator Subreddits", strings) {
            HiddenModeratorSubredditsStore.save(Set($0))
        }

        // MARK: Open in app, gallery mute, header style

        for key in ["OpenLinksInSteamApp", "OpenLinksInBlueskyApp", "OpenLinksInGitHubApp"] {
            take(key, key.replacingOccurrences(of: "OpenLinksIn", with: "Open in ")
                .replacingOccurrences(of: "App", with: " App"), bool) { UserDefaults.standard.set($0, forKey: key) }
        }
        take("ApolloGalleryVideosMuted", "Gallery Videos Muted", bool) { GalleryMuteStore.isMuted = $0 }
        // Share as Image "Link" (#1278); the Boolean is its pre-menu form.
        if !take("ApolloShareAsImageLinkMode", "Share Link", { int($0).flatMap(ShareLinkMode.init(rawValue:)) }, { ShareLinkMode.write($0) }) {
            take("ApolloShareAsImageIncludeLink", "Share Link", bool) { ShareLinkMode.write($0 ? .post : .none) }
        }
        // `ApolloScrollEdgeEffectStyle`: Automatic 0, Soft 1, Hard 2,
        // Hidden 3, Blur 4.
        take("ScrollEdgeEffectStyle", "Header Style", int) {
            let map: [Int: HeaderStyle] = [0: .automatic, 1: .soft, 2: .hard, 3: .hidden, 4: .blur]
            if let style = map[$0] { HeaderStyleStore.save(style) }
        }

        // MARK: Automatic backups

        var backups = AutomaticBackupSettingsStore.load()
        take("AutomaticBackupsEnabled", "Automatic Backups", bool) { backups.enabled = $0 }
        take("AutomaticBackupIntervalDays", "Backup Interval", int) { if $0 > 0 { backups.intervalDays = $0 } }
        AutomaticBackupSettingsStore.save(backups)
    }

    /// Whether a property-list value is a real boolean. A plist `<true/>` bridges
    /// to a CFBoolean NSNumber (ObjC type `c`), an `<integer>` to type `q` or `i`.
    /// On Linux the two decode to distinct Swift types.
    public nonisolated static func isBoolean(_ value: Any) -> Bool {
        #if canImport(ObjectiveC)
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        }
        return false
        #else
        // swift-corelibs-foundation: a real Swift `Bool` is a Bool; an
        // NSNumber is boolean only if it was created from one.
        if let number = value as? NSNumber, type(of: value) != Bool.self {
            return String(cString: number.objCType) == "c" && (number.int8Value == 0 || number.int8Value == 1)
                && !(value is Int)
        }
        return value is Bool
        #endif
    }

    /// Stock Apollo's gesture vocabulary to ours: upvote, downvote,
    /// save, collapse, collapse-root, reply, toggle-read, mark-read,
    /// share, hide, none.
    public static func swipeAction(fromApollo raw: String) -> SwipeAction {
        switch raw {
        case "upvote": return .upvote
        case "downvote": return .downvote
        case "save": return .save
        case "reply": return .reply
        case "share": return .share
        case "hide": return .hide
        case "collapse": return .collapse
        case "collapse-root": return .collapseTop
        case "toggle-read", "mark-read", "mark-unread": return .markRead
        case "hide-above": return .hidePostsAbove
        case "parent-comment": return .parentComment
        case "select-mode": return .selectText
        case "author": return .author
        case "subreddit": return .subreddit
        // `more-options` has no row action here.
        default: return .none
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
