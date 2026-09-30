import Foundation

/// Maps an Apollo backup's `NSUserDefaults` keys onto this app's settings
/// models, and applies them. Apollo stores each preference as its own defaults
/// key; this app stores each settings domain as one JSON blob, so every mapping
/// is stated explicitly.
///
/// Not imported:
///   - Analytics identity: `BugsnagUserUserId` and anything prefixed
///     `com.Statsig.`, as Apollo's own restore skips them.
///   - View state: `ReadPostIDs`, scroll milestones, PiP window position,
///     last-seen-version markers, cached highlight blobs.
///
/// Anything unrecognised is ignored rather than guessed at, and `apply`
/// reports what it changed.
@MainActor
public enum ApolloSettingsMigration {
    /// Apollo keys this app has an equivalent for, kept as data so the count is
    /// assertable.
    public struct Mapping {
        public let apolloKey: String
        public let describes: String
    }

    /// Analytics identity, skipped as Apollo's restore skips it.
    public static func isExcluded(_ key: String) -> Bool {
        key == "BugsnagUserUserId" || key.hasPrefix("com.Statsig.")
    }

    /// The result of an import, so the UI can say what happened.
    public struct Summary: Equatable, Sendable {
        public var applied: [String] = []
        public var skippedUnknown: Int = 0
        public var skippedExcluded: Int = 0

        public var isEmpty: Bool { applied.isEmpty }
    }

    /// Restores the backup's accounts into `store`. Separate from `apply` since
    /// it needs the live `AccountStore` and signs the user in. Returns how many
    /// accounts were restored.
    ///
    /// An account is only taken if it carries an OAuth access token or a
    /// web-session cookie; otherwise it would be a broken row in the switcher.
    @discardableResult
    public static func applyAccounts(
        _ payload: ApolloBackupImport.Payload,
        to keychain: any AccountKeychainStore = AccountKeychainStoreBox()
    ) -> Int {
        // Written through the same keychain box `BackupBundle.restore` uses, since
        // the settings screen has no store to hand.
        var existing = keychain.load()?.accounts ?? []
        var restored = 0
        for account in payload.accounts {
            guard !account.username.isEmpty else { continue }
            guard account.hasOAuth || account.hasWebSession else { continue }

            var oauth: RedditCredential?
            if let accessToken = account.accessToken, !accessToken.isEmpty {
                // Marked already expired: Apollo's archive stores no expiry and an access
                // token lives one hour, so a future expiry would fail the first request
                // with a 401 read as "signed out". This sends it down the refresh path.
                oauth = RedditCredential(
                    accessToken: accessToken,
                    refreshToken: account.refreshToken,
                    expiration: Date(timeIntervalSince1970: 0),
                    isPermanent: account.refreshToken != nil)
            }

            var web: WebSessionCredential?
            if let cookie = account.cookieHeader, !cookie.isEmpty {
                web = WebSessionCredential(
                    username: account.username,
                    cookieHeader: cookie,
                    modhash: account.modhash)
            }

            let stored = StoredAccount(username: account.username,
                                       oauthCredential: oauth,
                                       webSession: web)
            // Replace an existing entry for the same username so importing the same
            // backup twice does not add a second row.
            if let index = existing.firstIndex(where: { $0.username == stored.username }) {
                existing[index] = stored
            } else {
                existing.append(stored)
            }
            restored += 1
        }
        guard restored > 0 else { return 0 }
        // The first restored account becomes active.
        keychain.save(AccountStorePersisted(accounts: existing, activeIndex: 0))
        return restored
    }

    /// Applies everything recognised in `payload`.
    @discardableResult
    public static func apply(_ payload: ApolloBackupImport.Payload) -> Summary {
        var summary = Summary()
        let values = TrackedValues(payload.merged)

        // API keys: the user's own developer credentials. Without
        // `RedditApiClientId`/`RedirectURI` a restored install cannot sign in.
        var customAPI = CustomAPISettingsStore.load()
        if let clientID = string("RedditApiClientId"), !clientID.isEmpty {
            customAPI.redditClientID = clientID
            note("Reddit API client ID")
        }
        if let secret = string("RedditApiClientSecret"), !secret.isEmpty {
            customAPI.redditClientSecret = secret
            note("Reddit API client secret")
        }
        if let redirect = string("RedirectURI"), !redirect.isEmpty {
            customAPI.redditRedirectURI = redirect
            note("Redirect URI")
        }
        if let userAgent = string("UserAgent"), !userAgent.isEmpty {
            customAPI.userAgent = userAgent
            note("User agent")
        }
        if let imgur = string("ImgurApiClientId"), !imgur.isEmpty {
            customAPI.imgurClientID = imgur
            note("Imgur client ID")
        }
        if let giphy = string("GiphyAPIKey"), !giphy.isEmpty {
            customAPI.giphyAPIKey = giphy
            note("Giphy API key")
        }
        if let chest = string("ImageChestAPIToken"), !chest.isEmpty {
            customAPI.imgChestAPIKey = chest
            note("ImageChest API token")
        }
        CustomAPISettingsStore.save(customAPI)

        var general = GeneralSettingsStore.load()
        var appearance = AppearanceSettingsStore.load()
        var layout = SubredditLayoutSettingsStore.load()

        func bool(_ key: String) -> Bool? {
            guard let value = values[key], isBoolean(value) else { return nil }
            return value as? Bool
        }
        func string(_ key: String) -> String? { values[key] as? String }
        // Once per label: several keys feed one setting (the two
        // deleted-comment booleans, a screen's swipe gestures).
        func note(_ name: String) {
            if !summary.applied.contains(name) { summary.applied.append(name) }
        }

        // MARK: Sorting

        // `UDKeyDefaultPostsSort` / `UDKeyDefaultCommentsSort`: the raw API sort
        // string, mapped only if the enum recognises it.
        if let sort = string("DefaultPostsSort"), let parsed = DefaultPostSort(rawValue: sort) {
            general.defaultPostsSort = parsed
            note("Default post sort")
        }
        if let range = string("DefaultPostsTimeSort"), ["hour", "day", "week", "month", "year", "all"].contains(range) {
            general.defaultPostsTimeSort = range
            note("Default post sort time range")
        }
        if let sort = string("DefaultCommentsSort"), !sort.isEmpty {
            general.defaultCommentSort = sort
            note("Default comment sort")
        }

        // MARK: Appearance

        if let value = bool("ShowSubredditAtTop") {
            appearance.showSubredditAtTop = value
            note("Show Subreddit at Top")
        }
        if let value = bool("AlwaysShowUsernames") {
            appearance.alwaysShowUsernames = value
            note("Always Show Usernames")
        }
        if let value = bool("ShowSubredditIconsForPosts") {
            appearance.showSubredditIconsForPosts = value
            note("Show Subreddit Icons for Posts")
        }
        if let value = bool("ShowSubredditIconsInSubredditList") {
            appearance.showSubredditIconsInSubredditList = value
            note("Show Subreddit Icons in Subreddit List")
        }
        if let value = bool("ShowPageEndings") {
            appearance.showPageEndings = value
            note("Show Page Endings")
        }
        if let value = bool("RememberRedditPostSize") {
            appearance.rememberPostSizePerSubreddit = value
            note("Remember Post Size per Subreddit")
        }
        if let value = bool("UseSystemTextSize") {
            appearance.useSystemTextSize = value
            note("Use System Text Size")
        }
        if let value = bool("CompactModeShowSelfPostThumbnails") {
            appearance.compactShowSelfPostThumbnails = value
            note("Show Self Post Thumbnails")
        }

        // MARK: Subreddit header (Reborn's own module)

        if let value = bool("ShowSubredditHeaders") {
            layout.showSubredditHeaders = value
            note("Show Subreddit Headers")
        }
        if let value = bool("SubredditHeaderImmersive") {
            layout.subredditHeaderImmersive = value
            note("Immersive Subreddit Header")
        }

        // MARK: General behaviour

        if let value = bool("OpenVideosInYouTubeApp") {
            general.openVideosInYouTubeApp = value
            note("Open Videos in YouTube")
        }
        if let value = bool("HideUsernameOnTabBar") {
            general.hideUsernameOnTabBar = value
            note("Hide Username on Tab Bar")
        }
        if let value = bool("UseProfileAvatarTabIcon") {
            general.useProfileAvatarTabIcon = value
            note("Profile Picture Tab Icon")
        }
        if let value = bool("PollsEnabled") {
            general.pollsEnabled = value
            note("Polls")
        }
        if let value = bool("DevvitInteractivePosts") {
            general.devvitInteractivePosts = value
            note("Live Interactive Posts")
        }
        if let value = bool("EnableFlairColors") {
            general.enableFlairColors = value
            note("Color Flairs")
        }

        // MARK: Runtime state with a real, non-view-state meaning
        //
        // The collapsed-highlights set is a per-subreddit user choice stored under
        // Apollo's own key name. See `HighlightsCollapseStore`.
        if let collapsed = values[HighlightsCollapseStore.defaultsKey] as? [String] {
            UserDefaults.standard.set(collapsed, forKey: HighlightsCollapseStore.defaultsKey)
            note("Collapsed community highlights")
        }

        // MARK: Apollo AI summaries (Reborn's own module)
        //
        // Only keys the backup contains are applied, so an unset one keeps this
        // install's own value.
        var ai = ApolloAISettingsStore.load()
        var aiTouched = false
        func int(_ key: String) -> Int? {
            guard let value = values[key], !isBoolean(value) else { return nil }
            if let number = value as? NSNumber { return number.intValue }
            return value as? Int
        }
        if let value = bool("EnableAISummaries") {
            ai.summariesEnabled = value; aiTouched = true
            note("AI Summaries")
        }
        if let value = bool("EnableAIPostSummaries") {
            ai.postSummariesEnabled = value; aiTouched = true
            note("AI Post Summaries")
        }
        if let value = bool("EnableAICommentSummaries") {
            ai.commentSummariesEnabled = value; aiTouched = true
            note("AI Discussion Summaries")
        }
        if let value = int("AIPostWordThreshold"),
           ApolloAISettings.wordThresholds.contains(value) {
            ai.postWordThreshold = value; aiTouched = true
            note("AI Post Word Threshold")
        }
        if let raw = int("AIPostSummaryDetail"), let value = AISummaryDetail(rawValue: raw) {
            ai.postDetail = value; aiTouched = true
            note("AI Post Summary Detail")
        }
        if let raw = int("AICommentSummaryDetail"), let value = AISummaryDetail(rawValue: raw) {
            ai.commentDetail = value; aiTouched = true
            note("AI Discussion Summary Detail")
        }
        // Two booleans, one mode here. Tap wins over auto-expand, as Reborn reconciles
        // a both-on state.
        let tap = bool("EnableTapToSummarize")
        let autoExpand = bool("EnableAIAutoExpandSummaries")
        if tap != nil || autoExpand != nil {
            ai.summaryMode = AISummaryMode.from(
                tapToSummarize: tap ?? ai.summaryMode.tapToSummarize,
                autoExpand: autoExpand ?? ai.summaryMode.autoExpand)
            aiTouched = true
            note("AI Summary Mode")
        }
        if let raw = string("AISummaryProvider"), let value = AIProvider(rawValue: raw) {
            ai.provider = value; aiTouched = true
            note("AI Summary Provider")
        }
        let aiStrings: [(String, WritableKeyPath<ApolloAISettings, String?>, String)] = [
            ("OpenRouterAPIKey", \.openRouterAPIKey, "OpenRouter API key"),
            ("OpenRouterAIModel", \.openRouterModel, "OpenRouter model"),
            ("GeminiAPIKey", \.geminiAPIKey, "Gemini API key"),
            ("GeminiAIModel", \.geminiModel, "Gemini model"),
            ("CustomAIAPIKey", \.customAPIKey, "Custom AI API key"),
            ("CustomAIModel", \.customModel, "Custom AI model"),
            ("CustomAIBaseURL", \.customBaseURL, "Custom AI base URL"),
        ]
        for (key, path, name) in aiStrings {
            if let value = string(key), !value.isEmpty {
                ai[keyPath: path] = value; aiTouched = true
                note(name)
            }
        }
        if aiTouched { ApolloAISettingsStore.save(ai) }
        let importedHeaders = AICustomHeaders.sanitized(values["CustomAIHeaders"])
        if !importedHeaders.isEmpty {
            AICustomHeaders.save(importedHeaders)
            note("Custom AI headers")
        }

        // Everything else with an equivalent: see `ApolloSettingsMigration+Reborn.swift`.
        // Run before the stores above are saved back, which are reloaded after.
        GeneralSettingsStore.save(general)
        AppearanceSettingsStore.save(appearance)
        SubredditLayoutSettingsStore.save(layout)
        applyReborn(values, note: note)
        general = GeneralSettingsStore.load()
        appearance = AppearanceSettingsStore.load()
        layout = SubredditLayoutSettingsStore.load()

        // Counted by key, not by label: "unknown" is every key the
        // import never looked at.
        for key in values.all.keys {
            if isExcluded(key) {
                summary.skippedExcluded += 1
            } else if !values.read.contains(key) {
                summary.skippedUnknown += 1
            }
        }

        GeneralSettingsStore.save(general)
        AppearanceSettingsStore.save(appearance)
        SubredditLayoutSettingsStore.save(layout)
        return summary
    }
}

/// The backup's values, remembering which keys the import asked for.
final class TrackedValues {
    let all: [String: Any]
    private(set) var read: Set<String> = []

    init(_ values: [String: Any]) { all = values }

    subscript(key: String) -> Any? {
        read.insert(key)
        return all[key]
    }
}
