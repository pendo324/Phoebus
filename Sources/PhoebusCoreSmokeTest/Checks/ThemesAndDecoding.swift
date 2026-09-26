import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// --- Bundled comment-color-depth palettes (CommentColorThemes.plist) ---
@MainActor func checkRealBundledCommentColorDepthPalettes() async throws {
    check("CommentColorPalette has all 6 real named palettes", Set(CommentColorPalette.all.keys) == Set(["Blep", "Combustion", "Forest", "Nuit", "Ocean", "Rainbow"]))
    check("Every real palette has 7 depth colors in both light and dark", CommentColorPalette.all.values.allSatisfy { $0[false]?.count == 7 && $0[true]?.count == 7 })
    check("CommentColorPalette.hexes returns the real Ocean light palette exactly", CommentColorPalette.hexes(named: "Ocean", isDark: false) == ["0370C1", "008FFB", "00C3F9", "008FFB", "24A1FF", "007AD5", "78B5FF"])
    check("CommentColorPalette.hexes returns the real Rainbow dark palette exactly", CommentColorPalette.hexes(named: "Rainbow", isDark: true) == ["AF2E27", "B15610", "967727", "2D704C", "1F68B1", "224688", "643B95"])

    // Decoding an older persisted theme (missing isDark/isGenerated keys)
    // succeeds and defaults both to false.
    let oldThemeJSON = """
    {"id":"old1","name":"Old Theme","accentColorHex":"FF0000","commentDepthColorHexes":["FF0000"]}
    """.data(using: .utf8)!
    let oldTheme = try! JSONDecoder().decode(Theme.self, from: oldThemeJSON)
    check("Theme decodes older data missing isDark/isGenerated", oldTheme.isDark == false && oldTheme.isGenerated == false)
}

// --- Theme AI generation ---
@MainActor func checkThemeAIGenerationRealGapFix() async throws {
    check("ThemeGenerationSettings.default uses OpenAI", ThemeGenerationSettings.default.provider == .openAI)
    let sampleThemeJSON = """
    ```json
    {"name": "Sunset", "accentColorHex": "#FF6B35", "commentDepthColorHexes": ["FF6B35", "4A90D9", "50C878"]}
    ```
    """
    let parsedGeneratedTheme = try! ThemeGenerationClient.parseThemeJSON(sampleThemeJSON, isDark: false)
    check("ThemeGenerationClient.parseThemeJSON strips markdown fences", parsedGeneratedTheme.name == "Sunset")
    check("ThemeGenerationClient.parseThemeJSON sanitizes a leading # from hex", parsedGeneratedTheme.accentColorHex == "FF6B35")
    check("ThemeGenerationClient.parseThemeJSON marks the result as generated", parsedGeneratedTheme.isGenerated)
    check("ThemeGenerationClient.parseThemeJSON preserves isDark", !parsedGeneratedTheme.isDark)
    check("ThemeGenerationClient.parseThemeJSON throws on invalid JSON", (try? ThemeGenerationClient.parseThemeJSON("not json", isDark: false)) == nil)
}

// --- Theme QR code sharing/import ---
@MainActor func checkThemeQRCodeSharingImportReal() async throws {
    let qrPayload = try! ThemeQRCodePayload.encode(Theme.navyLight)
    let importedTheme = try! ThemeQRCodePayload.decode(qrPayload)
    check("ThemeQRCodePayload round-trips name", importedTheme.name == Theme.navyLight.name)
    check("ThemeQRCodePayload round-trips accent color", importedTheme.accentColorHex == Theme.navyLight.accentColorHex)
    check("ThemeQRCodePayload round-trips comment depth colors", importedTheme.commentDepthColorHexes == Theme.navyLight.commentDepthColorHexes)
    check("ThemeQRCodePayload round-trips isDark", importedTheme.isDark == Theme.navyLight.isDark)
    check("ThemeQRCodePayload import gets a fresh ID distinct from the original", importedTheme.id != Theme.navyLight.id)
    check("ThemeQRCodePayload import is marked generated", importedTheme.isGenerated)
    check("ThemeQRCodePayload.decode throws on garbage input", (try? ThemeQRCodePayload.decode("not a payload")) == nil)

    ThemeStore.addGeneratedTheme(importedTheme)
    check("ThemeStore.loadGeneratedThemes includes an added generated theme", ThemeStore.loadGeneratedThemes().contains(where: { $0.id == importedTheme.id }))
    check("ThemeStore.allAvailableThemes includes both built-in and generated", ThemeStore.allAvailableThemes().count == Theme.allThemes.count + ThemeStore.loadGeneratedThemes().count)
    ThemeStore.removeGeneratedTheme(id: importedTheme.id)
    check("ThemeStore.removeGeneratedTheme removes it", !ThemeStore.loadGeneratedThemes().contains(where: { $0.id == importedTheme.id }))
}


// --- Badge Book (bundled achievement catalog + local evaluation engine, distinct from the Trophies tab) ---
@MainActor func checkBadgeBookRealGapFixBundled() async throws {
    check("BadgeCatalog is non-empty", !BadgeCatalog.all.isEmpty)
    check("Every badge has a unique ID", Set(BadgeCatalog.all.map(\.id)).count == BadgeCatalog.all.count)
}

// --- Achievements catalog (matches Reborn's bundled badgebook-catalog.json) ---
@MainActor func checkRealAchievementsCatalogRealGapFix() async throws {
    check("AchievementCatalog has the real 79-entry catalog", AchievementCatalog.all.count == 79)
    check("AchievementCatalog has the real 5 categories", Set(AchievementCatalog.categories) == Set(["Getting Started", "Building Community", "Community Moderation", "Exploration", "Reddit Streak"]))
    check("AchievementCatalog entries have unique IDs", Set(AchievementCatalog.all.map(\.id)).count == AchievementCatalog.all.count)
    check("AchievementCatalog includes a real named achievement from the real catalog", AchievementCatalog.all.contains(where: { $0.id == "thats-me" && $0.title == "That's Me" }))
    check("AchievementCatalog.achievements(inCategory:) filters correctly", AchievementCatalog.achievements(inCategory: "Getting Started").allSatisfy { $0.category == "Getting Started" })
    check("AchievementCatalog.achievements(inCategory:) is non-empty for every real category", AchievementCatalog.categories.allSatisfy { !AchievementCatalog.achievements(inCategory: $0).isEmpty })
    let newAccountContext = BadgeEvaluationContext(commentKarma: 0, linkKarma: 0, accountCreated: Date(), hasVerifiedEmail: false, isGold: false, trophyNames: [])
    let newAccountBadges = BadgeBookEngine.evaluate(context: newAccountContext)
    check("A brand-new account earns no badges", newAccountBadges.allSatisfy { !$0.isEarned })
    check("BadgeBookEngine.evaluate returns the full catalog regardless of earned state", newAccountBadges.count == BadgeCatalog.all.count)

    let veteranContext = BadgeEvaluationContext(
        commentKarma: 5000, linkKarma: 6000,
        accountCreated: Calendar(identifier: .gregorian).date(byAdding: .year, value: -6, to: Date())!,
        hasVerifiedEmail: true, isGold: true,
        trophyNames: ["Five-Year Club", "Verified Email"]
    )
    let veteranBadges = BadgeBookEngine.evaluate(context: veteranContext)
    check("A veteran account earns the verified-email badge", veteranBadges.first(where: { $0.id == "verified_email" })?.isEarned == true)
    check("A veteran account earns the gold badge", veteranBadges.first(where: { $0.id == "gold_member" })?.isEarned == true)
    check("A veteran account earns the 10,000+ karma badge", veteranBadges.first(where: { $0.id == "karma_10000" })?.isEarned == true)
    check("A veteran account does NOT earn the 100,000+ karma badge", veteranBadges.first(where: { $0.id == "karma_100000" })?.isEarned == false)
    check("A veteran account earns the 5-year account-age badge", veteranBadges.first(where: { $0.id == "account_age_5" })?.isEarned == true)
    check("A veteran account does NOT earn the 10-year account-age badge", veteranBadges.first(where: { $0.id == "account_age_10" })?.isEarned == false)
    check("A veteran account earns the Year-Club-linked trophy badge via substring match", veteranBadges.first(where: { $0.id == "veteran_trophy" })?.isEarned == true)
}

// --- App Icon picker + Community Icon Pack (Reborn "unlocked Ultra" feature) ---
@MainActor func checkAppIconPickerCommunityIconPack() async throws {
    check("AppIconStore defaults to .original", AppIconStore.load() == .original)
    check("AppIconOption.original has a nil alternateIconName (primary icon)", AppIconOption.original.alternateIconName == nil)
    check("AppIconOption.all has the real 155-icon catalog, Reborn's 8 Ultra additions and Original (164 total)", AppIconOption.all.count == 164)
    check("AppIconOption.all entries have unique IDs", Set(AppIconOption.all.map(\.id)).count == AppIconOption.all.count)
    check("AppIconOption's alternateIconName matches the real AppIcon-<id> Info.plist key convention", AppIconOption.all.first(where: { $0.id == "obsidian" })?.alternateIconName == "AppIcon-obsidian")
    check("AppIconOption includes a real Apollo icon name", AppIconOption.all.contains(where: { $0.id == "gorilla-gus" }))
    let obsidianIcon = AppIconOption.all.first(where: { $0.id == "obsidian" })!
    AppIconStore.save(obsidianIcon)
    check("AppIconStore persists a selection", AppIconStore.load() == obsidianIcon)
    AppIconStore.save(.original)
    check("AppIconStore round-trips back to .original", AppIconStore.load() == .original)
}

// --- Subreddits root loads from disk instantly ---
//
// The Favorites/Multireddits/subscriptions rows are cached to disk so the full
// list appears in the first frame instead of waiting for
// `/subreddits/mine/subscriber` to paginate.
@MainActor func checkSubredditsRootLoadsFromDiskInstantly() async throws {
    do {
        // Round-tripping is the mechanism: `RedditSubreddit` and `RedditMultireddit`
        // decode Reddit's JSON with custom `init(from:)`, so caching means
        // re-encoding into a shape those decoders accept.
        let sub = try! JSONDecoder.reddit.decode(RedditSubreddit.self, from: """
        {"display_name":"swift","name":"t5_2fwo","title":"Swift","over_18":false,
         "subscribers":142000,"user_is_subscriber":true,"icon_img":"https://e/i.png"}
        """.data(using: .utf8)!)
        let encoded = try! JSONEncoder().encode(sub)
        let round = try! JSONDecoder.reddit.decode(RedditSubreddit.self, from: encoded)
        check("a cached subreddit survives a save/load round trip",
              round.displayName == sub.displayName
              && round.id == sub.id
              && round.subscribers == sub.subscribers
              && round.userIsSubscriber == sub.userIsSubscriber
              && round.iconImage == sub.iconImage)
        // `over_18` has a second spelling (`over18`) on the listing endpoints and
        // `CodingKeys` carries both. Synthesis cannot encode that, so the encoder is
        // hand-written and emits the canonical key.
        let json = String(data: encoded, encoding: .utf8)!
        check("the cached subreddit writes the canonical over_18 key",
              json.contains("over_18") && !json.contains("\"over18\""))

        let multi = RedditMultireddit(
            name: "m1", displayName: "Music", path: "/user/x/m/m1",
            subreddits: [.init(name: "listentothis")], visibility: "private")
        let multiRound = try! JSONDecoder.reddit.decode(
            RedditMultireddit.self, from: try! JSONEncoder().encode(multi))
        check("a cached multireddit survives a round trip",
              multiRound.path == multi.path
              && multiRound.displayName == multi.displayName
              && multiRound.subreddits.first?.name == "listentothis")
    }
}

// --- Feed images use Reddit's preview ladder, not its thumbnail ---
//
// `post.thumbnail` is a 140px-wide thumbnail meant for a compact row, not the
// feed card. Reddit's `preview.images.resolutions` ladder (plus
// `variants.mp4/gif.resolutions`) has larger copies for the full-width card.
@MainActor func checkFeedImagesUseRedditSPreview() async throws {
    do {
        func post(withPreview json: String) -> RedditPost {
            let full = """
            {"id":"p1","name":"t3_p1","title":"t","author":"a","subreddit":"s",
             "permalink":"/r/s/comments/p1/t/","score":1,"num_comments":0,
             "created_utc":0,"is_self":false,"over_18":false,"spoiler":false,
             "stickied":false,"saved":false,"preview":\(json)}
            """
            return try! JSONDecoder.reddit.decode(RedditPost.self, from: full.data(using: .utf8)!)
        }

        // Reddit's ladder shape and widths.
        let ladder = post(withPreview: """
        {"images":[{"source":{"url":"https://e/s.jpg","width":3757,"height":4696},
         "resolutions":[
           {"url":"https://e/108.jpg","width":108,"height":135},
           {"url":"https://e/216.jpg","width":216,"height":270},
           {"url":"https://e/640.jpg","width":640,"height":800},
           {"url":"https://e/960.jpg","width":960,"height":1200},
           {"url":"https://e/1080.jpg","width":1080,"height":1350}]}]}
        """)
        // A 430pt card on a 3x screen needs 1290px, so nothing below the source
        // covers it.
        check("a wide card falls through the ladder to the source",
              ladder.previewImageURL(displayWidth: 430)?.absoluteString == "https://e/s.jpg")
        // The narrowest rung that still covers the target wins: a smaller one
        // upscales, the largest always wastes bandwidth.
        check("the narrowest sufficient rung is chosen",
              ladder.previewImageURL(displayWidth: 200, scale: 3)?.absoluteString == "https://e/640.jpg")
        check("a small target does not pull the full-size source",
              ladder.previewImageURL(displayWidth: 60, scale: 2)?.absoluteString == "https://e/216.jpg")

        // Reddit HTML-escapes these URLs in its JSON; an escaped one 403s.
        let escaped = post(withPreview: """
        {"images":[{"source":{"url":"https://e/s.jpg?a=1&amp;b=2","width":100,"height":100},
         "resolutions":[]}]}
        """)
        check("preview URLs are HTML-unescaped",
              escaped.previewImageURL(displayWidth: 430)?.absoluteString == "https://e/s.jpg?a=1&b=2")

        // No preview at all leaves the caller on its thumbnail path rather than
        // blanking the image.
        let bare = try! JSONDecoder.reddit.decode(RedditPost.self, from: """
        {"id":"p2","name":"t3_p2","title":"t","author":"a","subreddit":"s",
         "permalink":"/r/s/comments/p2/t/","score":1,"num_comments":0,
         "created_utc":0,"is_self":false,"over_18":false,"spoiler":false,
         "stickied":false,"saved":false}
        """.data(using: .utf8)!)
        check("a post with no preview returns nil", bare.previewImageURL(displayWidth: 430) == nil)
    }
}

// --- The Text Size slider takes effect immediately ---
//
// `apolloTextSizeOverride()` re-reads `AppearanceSettingsStore` on every
// change notification rather than only at view-build time, so the slider
// takes effect without a relaunch. Same shape as
// `GeneralSettingsStore.didChangeNotification`.
@MainActor func checkTheTextSizeSliderTakesEffect() async throws {
    do {
        // The post must be in `save`, or nothing fires it.
        let appearancePosted = NSLock.Protected(false)
        let appearanceToken = NotificationCenter.default.addObserver(
            forName: AppearanceSettingsStore.didChangeNotification, object: nil, queue: nil) { _ in appearancePosted.set(true) }
        AppearanceSettingsStore.save(AppearanceSettingsStore.load())
        NotificationCenter.default.removeObserver(appearanceToken)
        check("saving appearance settings posts the notification", appearancePosted.get())
    }
}

// --- YouTube links show a thumbnail ---
//
// A YouTube link in a comment draws the video's poster frame, and opens
// YouTube only on tap; scrolling past a link must not launch the app.
@MainActor func checkYouTubeLinksShowAThumbnailNot() async throws {
    do {
        check("a YouTube thumbnail URL is built from the video id",
              YouTubeURLParser.thumbnailURL(forVideoID: "dQw4w9WgXcQ")?.absoluteString
              == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        // `hqdefault`, not `maxresdefault`: every video has the former, while
        // the latter 404s for anything never published at 1080p.
        check("the thumbnail uses the always-present size",
              YouTubeURLParser.thumbnailURL(forVideoID: "abc")?.absoluteString.contains("hqdefault") == true)
        check("an empty video id yields no thumbnail",
              YouTubeURLParser.thumbnailURL(forVideoID: "") == nil)
    }

    // Gallery View leads the menu, in its own separated section.
    //
    // Reborn registers the row with `inlineSection = YES` and
    // `placement = ...AfterLeadingSubmitAffordance`: its own group, directly
    // under the composer affordance when there is one. A multireddit has no
    // Submit Post row, so it lands first.
    do {
        // The row list for a multireddit feed.
        let titles = ["Gallery View", "Submit Post", "Unsubscribe", "Share"]
        let markers: Set<Int> = [1, 3]
        let sections = ApolloMenuSectioning
            .sections(count: titles.count) { markers.contains($0) }
            .map { $0.map { titles[$0] } }
        check("the menu splits into its real separated groups",
              sections.count == 3
              && sections[0] == ["Gallery View"]
              && sections[1] == ["Submit Post", "Unsubscribe"]
              && sections[2] == ["Share"])
        // A leading marked row must not produce an empty first group, which
        // would draw a stray separator above the first row.
        check("a leading section marker doesn't create an empty group",
              ApolloMenuSectioning.sections(count: 1) { _ in true }.count == 1)
        check("an empty menu has no groups",
              ApolloMenuSectioning.sections(count: 0) { _ in false }.isEmpty)
    }
}

// --- On-device AI runs a model ---
//
// `AIProvider.onDevice` is the default provider, so `ApolloAIClient` must be
// able to produce a summary with it (FoundationModels, iOS 26).
//
// These checks run on Linux, where FoundationModels does not exist, so they
// assert on structure and the pure logic reachable without the framework.
@MainActor func checkOnDeviceAIActuallyRunsA() async throws {
    do {
        // On-device is the default, so a fresh install can summarize. Decoded
        // from an empty payload to exercise the first-launch path.
        let freshSettings = try! JSONDecoder().decode(
            ApolloAISettings.self,
            from: Data("{}".utf8))
        check("on-device is still the default provider",
              freshSettings.provider == .onDevice)

        // Availability explanations must be distinct and actionable: the status
        // tells the user which thing to change.
        let reasons: [OnDeviceSummarizer.Availability] = [
            .available, .appleIntelligenceNotEnabled, .modelNotReady,
            .deviceNotEligible, .osTooOld, .unknown,
        ]
        check("every availability reason has its own explanation",
              Set(reasons.map(\.explanation)).count == reasons.count)
        check("the 'off' and 'downloading' cases name what to do",
              OnDeviceSummarizer.Availability.appleIntelligenceNotEnabled
                  .explanation.contains("Apple Intelligence")
              && OnDeviceSummarizer.Availability.modelNotReady
                  .explanation.lowercased().contains("downloading"))
    }
}

// --- Apollo's video control panel ---
//
// Apollo's panel has mute, play/pause, back/forward 15s, current and
// remaining time, a time slider, a live-broadcast label and AirPlay, with
// separate normal and landscape heights. The skip is 15s; Reborn's
// Picture-in-Picture overlay has its own configurable skip (default 10),
// which is a different surface.
@MainActor func checkApolloSRealVideoControlPanel() async throws {
    do {
        // Time formatting is m:ss with no leading zero on minutes.
        check("times render as m:ss like the screenshot",
              VideoControlPanelTimeLabel(14) == "0:14"
              && VideoControlPanelTimeLabel(22) == "0:22"
              && VideoControlPanelTimeLabel(0) == "0:00"
              && VideoControlPanelTimeLabel(75) == "1:15")
        // Long videos use hours rather than "83:20".
        check("an hour-long video keeps an hours field",
              VideoControlPanelTimeLabel(5000) == "1:23:20")
        // A not-yet-loaded duration is NaN and must not render as garbage.
        check("an unknown duration renders as 0:00",
              VideoControlPanelTimeLabel(.nan) == "0:00"
              && VideoControlPanelTimeLabel(-5) == "0:00")
    }
}

// --- Settings root row order and tiles ---
//
// The root order is: General, Appearance, Notifications, App Icon,
// Passcode, Filters & Blocks, Gestures.
@MainActor func checkSettingsRootRowsAreInThe() async throws {
    do {
        let order = SettingsSection.allCases.map(\.rawValue)
        // The run appears contiguously and in this exact sequence; a contiguous
        // slice is checked rather than pairwise "before" relations so another row
        // cannot be interleaved into the middle.
        let real = ["general", "appearance", "notifications", "appIcon",
                    "security", "filters", "gestures"]
        check("the attested settings rows lead, in their real order",
              Array(order.prefix(real.count)) == real)
        // Titles are asserted too, not only case order, since `rawValue` checks
        // leave the visible text unasserted. "Touch ID / Face ID & Passcode" is a
        // longer title for Apollo's "Passcode" row, so it is checked by prefix.
        check("the attested rows carry their real titles",
              SettingsSection.general.title == "General"
              && SettingsSection.appearance.title == "Appearance"
              && SettingsSection.notifications.title == "Notifications"
              && SettingsSection.appIcon.title == "App Icon"
              && SettingsSection.filters.title == "Filters & Blocks"
              && SettingsSection.gestures.title == "Gestures"
              && SettingsSection.about.title == "About"
              && SettingsSection.security.title == "Passcode")
        // Screens outside the main group are kept but sit below the run rather
        // than being interleaved into it.
        check("unattested settings rows sit below the real ones",
              Set(order.dropFirst(real.count)).isDisjoint(with: Set(real)))

        // Tile colours are sampled from Apollo's settings screen; see
        // `iconTintRGB`.
        func tile(_ s: SettingsSection) -> (Double, Double, Double) {
            let t = s.iconTintRGB
            return (t.red, t.green, t.blue)
        }
        func near(_ a: (Double, Double, Double), _ r: Double, _ g: Double, _ b: Double) -> Bool {
            abs(a.0 - r) < 0.03 && abs(a.1 - g) < 0.03 && abs(a.2 - b) < 0.03
        }
        // App Icon's tile is magenta, RGB(179,36,120).
        check("the App Icon tile is the real magenta",
              near(tile(.appIcon), 0.70, 0.14, 0.47))
        // About's tile is grey, RGB(99,99,101).
        check("the About tile is the real grey",
              near(tile(.about), 0.39, 0.39, 0.40))
        // Filters' tile is a softer green, RGB(103,206,103).
        check("the Filters tile is the real green",
              near(tile(.filters), 0.40, 0.81, 0.40))
        // The glyphs are Reborn's own table, filled variants throughout.
        check("root glyphs follow ApolloRootSettingsIconForTitle",
              SettingsSection.general.systemImage == "gearshape.fill"
              && SettingsSection.appearance.systemImage == "paintbrush.fill"
              && SettingsSection.notifications.systemImage == "bell.fill"
              && SettingsSection.security.systemImage == "lock.fill"
              && SettingsSection.filters.systemImage == "nosign"
              && SettingsSection.gestures.systemImage == "hand.tap.fill"
              && SettingsSection.about.systemImage == "info.circle.fill")
    }
}

// --- Glass needs the app's linked SDK to be new enough ---
//
// `UIDesignRequiresCompatibility` in Info.plist and the deployment target
// both gate iOS 26's Liquid Glass menu layout. Reborn checks the same field
// via `IsLiquidGlass()`, requiring the `UIGlassEffect` class and
// `(sdk >> 16) >= 19`.
@MainActor func checkGlassNeedsTheAppSOwn() async throws {
    do {
        // The version decode is the testable half; the image walk can only report
        // this process's own SDK.
        check("a packed Mach-O version decodes to major.minor.patch",
              MachOLinkedSDK.decode(0x001A0000) == MachOLinkedSDK.Version(major: 26, minor: 0, patch: 0)
              && MachOLinkedSDK.decode(0x00110300) == MachOLinkedSDK.Version(major: 17, minor: 3, patch: 0))
        // The threshold is stated as behaviour: 17 is refused, 19 (the first iOS 26
        // SDK's encoding) and 26 are accepted.
        let enables: (UInt32) -> Bool = { MachOLinkedSDK.decode($0).major >= 19 }
        check("only an iOS-26-era linked SDK opts into the design system",
              !enables(0x00110000) && enables(0x00130000) && enables(0x001A0000))
    }
}

// --- Wallpapers (Reborn "unlocked Ultra" feature) ---
//
// Stock Apollo bundles 14 wallpapers; Reborn's browser ships 32 remote ones
// with artist credits, via its `goodbyeIPhoneURLs`/`goodbyeIPadURLs` arrays.
@MainActor func checkWallpapersUnlockedFeature() async throws {
    check("GoodbyeWallpaper.all has the real 32", GoodbyeWallpaper.all.count == 32)
    check("every wallpaper carries an iPhone and iPad URL",
          GoodbyeWallpaper.all.allSatisfy { !$0.iPhoneURL.isEmpty && !$0.iPadURL.isEmpty })
    check("wallpaper IDs are unique",
          Set(GoodbyeWallpaper.all.map(\.id)).count == GoodbyeWallpaper.all.count)
    // Captions are "<Name> by <Artist>"; the credit is part of the feature.
    check("every wallpaper credits its artist",
          GoodbyeWallpaper.all.allSatisfy { $0.artist?.isEmpty == false })
    check("the first entry matches the real list verbatim",
          GoodbyeWallpaper.all[0].caption == "Adventures by David Lanham"
          && GoodbyeWallpaper.all[0].iPhoneURL == "https://i.imgur.com/8dY2Pp9.jpeg")
    check("a name drops the artist credit",
          GoodbyeWallpaper.all[0].name == "Adventures")
}

// --- Bulk Translation (Reborn feature) ---
// Apollo defaults to Google, not LibreTranslate.
@MainActor func checkBulkTranslationApolloRebornFeature() async throws {
    check("TranslationSettings.default uses Google (matches real primaryProvider default)", TranslationSettings.default.provider == .google)
    // The registered defaults are `AutoTranslateOnAppear: YES`,
    // `TapToTranslate: NO`, which `currentTranslationMode` reads as Automatic.
    check("TranslationSettings.default mode is Automatic", TranslationSettings.default.mode == .automatic)
    check("TranslationSettings defaults: details on, title details on, titles off, marker colour off, Apple sheet off (Tweak.xm:3810-3821)",
          TranslationSettings.default.showDetails && TranslationSettings.default.showTitleDetails
          && !TranslationSettings.default.translatePostTitles && !TranslationSettings.default.matchAppColour
          && !TranslationSettings.default.useAppleTranslateSheet && TranslationSettings.default.skipLanguageCodes.isEmpty)
    check("provider detail text is Google / LibreTranslate / Microsoft (providerDetailText)",
          TranslationProvider.google.displayName == "Google" && TranslationProvider.microsoft.displayName == "Microsoft" && TranslationProvider.libreTranslate.displayName == "LibreTranslate")
    check("Manual mode reads Manual (Globe)", TranslationMode.manual.displayName == "Manual (Globe)")
    check("language options are the real 31, starting with Device Default and ending Bosnian",
          TranslationSettings.languageOptions.count == 31 && TranslationSettings.languageOptions.first?.name == "Device Default" && TranslationSettings.languageOptions.last?.code == "bs")
    check("displayName(forLanguageCode:) normalises en-US and falls back to upper-case",
          TranslationSettings.displayName(forLanguageCode: "en-US") == "English" && TranslationSettings.displayName(forLanguageCode: "") == "Device Default")
    check("target language detail reads Device Default (…) when unset",
          TranslationSettings.default.targetLanguageDetailText.hasPrefix("Device Default ("))
    do {
        check("TapToCollapseType is comments/headers/both/neither, default both, tolerant of old raw values",
              TapToCollapseType.allCases.map(\.rawValue) == ["comments", "headers", "both", "neither"] && GeneralSettings.default.tapToCollapseType == .both
              && (try? JSONDecoder().decode(TapToCollapseType.self, from: Data("\"allComments\"".utf8))) == .both)
        check("Jump Button Position reads Right Bottom", JumpButtonPosition.bottomTrailing.displayName == "Right Bottom")
        check("PiP defaults match Tweak.xm:3831-3839", { let d = PictureInPictureSettings(); return !d.inAppEnabled && d.startPosition == .topRight && !d.startHidden && !d.skipButtons && d.skipSeconds == 10 && !d.progressBar && !d.systemEnabled && d.activation == .unmutedOnly && d.loopVideos && PictureInPictureSettings.skipChoices == [5, 10, 15, 30] }())
    }
    check("TranslationSettings.default has bulk translation disabled", TranslationSettings.default.enableBulkTranslation == false)
    // The default LibreTranslate URL is the .com instance; the .de instance is
    // dead.
    check("TranslationSettings.default LibreTranslate URL is the real live .com instance, not the dead .de one", TranslationSettings.default.libreTranslateURL == "https://libretranslate.com/translate")
    check("TranslationSettings.normalizedLibreTranslateURL upgrades the real known-dead .de URL", TranslationSettings(enableBulkTranslation: true, provider: .libreTranslate, mode: .automatic, libreTranslateURL: "https://libretranslate.de/translate", libreTranslateAPIKey: nil, targetLanguageCode: "").normalizedLibreTranslateURL == "https://libretranslate.com/translate")
    check("TranslationSettings.normalizedLibreTranslateURL upgrades an empty stored URL too", TranslationSettings(enableBulkTranslation: true, provider: .libreTranslate, mode: .automatic, libreTranslateURL: "", libreTranslateAPIKey: nil, targetLanguageCode: "").normalizedLibreTranslateURL == "https://libretranslate.com/translate")
    check("TranslationSettings.normalizedLibreTranslateURL preserves a genuine custom self-hosted URL", TranslationSettings(enableBulkTranslation: true, provider: .libreTranslate, mode: .automatic, libreTranslateURL: "https://my-own-server.example/translate", libreTranslateAPIKey: nil, targetLanguageCode: "").normalizedLibreTranslateURL == "https://my-own-server.example/translate")
    check("TranslationProvider includes the real Microsoft Translator option", TranslationProvider.allCases.contains(.microsoft))
    var translationSettings = TranslationSettings.default
    translationSettings.enableBulkTranslation = true
    translationSettings.provider = .google
    translationSettings.targetLanguageCode = "es"
    TranslationSettingsStore.save(translationSettings)
    let reloadedTranslationSettings = TranslationSettingsStore.load()
    check("TranslationSettingsStore round-trips provider", reloadedTranslationSettings.provider == .google)
    check("TranslationSettingsStore round-trips target language", reloadedTranslationSettings.targetLanguageCode == "es")
    TranslationSettingsStore.save(.default)

    let googleTranslateResponseJSON = """
    [[["Hola","hello",null,null,1],[" mundo"," world",null,null,1]],null,"en"]
    """.data(using: .utf8)!
    let parsedTranslation = try! BulkTranslationClient.parseGoogleResponse(googleTranslateResponseJSON)
    check("BulkTranslationClient.parseGoogleResponse concatenates translated chunks", parsedTranslation == "Hola mundo")
}

// --- Recently Read NSFW filter / thumbnail settings (Reborn) ---
@MainActor func checkRecentlyReadNSFWFilterThumbnailSettings() async throws {
    check("RecentlyReadSettings.default shows thumbnails and doesn't filter NSFW", RecentlyReadSettings.default.showThumbnails && !RecentlyReadSettings.default.filterNSFW)
    RecentlyReadSettingsStore.save(RecentlyReadSettings(filterNSFW: true, showThumbnails: false))
    let reloadedRecentlyReadSettings = RecentlyReadSettingsStore.load()
    check("RecentlyReadSettingsStore round-trips filterNSFW", reloadedRecentlyReadSettings.filterNSFW)
    check("RecentlyReadSettingsStore round-trips showThumbnails", reloadedRecentlyReadSettings.showThumbnails == false)
    RecentlyReadSettingsStore.save(.default)

    RecentlyReadStore.clearAll()
    RecentlyReadStore.recordView(fullname: "t3_nsfw1", title: "NSFW", subreddit: "test", author: "a", permalink: "/r/test/comments/nsfw1", isNSFW: true, thumbnailURL: "https://example.com/thumb.jpg")
    let nsfwEntry = RecentlyReadStore.load().first
    check("RecentlyReadEntry carries isNSFW through recordView", nsfwEntry?.isNSFW == true)
    check("RecentlyReadEntry carries thumbnailURL through recordView", nsfwEntry?.thumbnailURL == "https://example.com/thumb.jpg")
    RecentlyReadStore.clearAll()

    // Decoding an older persisted entry (missing isNSFW/thumbnailURL keys)
    // succeeds and defaults isNSFW to false.
    let oldEntryJSON = """
    {"fullname":"t3_old1","title":"Old","subreddit":"test","author":"a","permalink":"/r/test/comments/old1","viewedAt":0}
    """.data(using: .utf8)!
    let oldEntry = try! JSONDecoder.reddit.decode(RecentlyReadEntry.self, from: oldEntryJSON)
    check("RecentlyReadEntry decodes older data missing isNSFW/thumbnailURL", oldEntry.isNSFW == false && oldEntry.thumbnailURL == nil)
}

// --- Gallery View waterfall aspect ratio ---
@MainActor func checkGalleryViewWaterfallAspectRatioReal() async throws {
    let galleryWithDimsJSON = """
    {
        "id": "gal1", "name": "t3_gal1", "title": "Gallery Post",
        "author": "u1", "subreddit": "test", "selftext": "",
        "url": null, "permalink": "/r/test/comments/gal1/x/",
        "score": 1, "upvote_ratio": 1.0, "num_comments": 0,
        "created_utc": 0, "is_self": false, "over_18": false,
        "spoiler": false, "stickied": false, "saved": false, "likes": null,
        "is_gallery": true,
        "gallery_data": {"items": [{"media_id": "abc123"}]},
        "media_metadata": {"abc123": {"status": "valid", "s": {"u": "https://example.com/img.jpg", "x": 1600, "y": 800}}}
    }
    """.data(using: .utf8)!
    let galleryWithDimsPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: galleryWithDimsJSON)
    check("GalleryPostMedia.aspectRatio computes width/height from gallery dimensions", GalleryPostMedia.aspectRatio(for: galleryWithDimsPost) == 2.0)
    check("GalleryPostMedia.aspectRatio returns nil when no dimensions are known", GalleryPostMedia.aspectRatio(for: textPost) == nil)
}

// --- S3 XML error parsing (RedditMediaUploadClient must parse the S3
// <Error> body, not just check HTTP status) ---
@MainActor func checkS3XMLErrorParsingRedditMediaUploadClientMust() async throws {
    let s3ErrorXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Error><Code>AccessDenied</Code><Message>Request has expired.</Message></Error>
    """.data(using: .utf8)!
    if case .s3Error(let code, let message)? = RedditMediaUploadClient.parseS3XMLError(s3ErrorXML) {
        check("RedditMediaUploadClient.parseS3XMLError extracts the error code", code == "AccessDenied")
        check("RedditMediaUploadClient.parseS3XMLError extracts the error message", message == "Request has expired.")
    } else {
        check("RedditMediaUploadClient.parseS3XMLError detects an <Error> body", false)
    }
    check("RedditMediaUploadClient.parseS3XMLError returns nil for a non-error body", RedditMediaUploadClient.parseS3XMLError("ok".data(using: .utf8)!) == nil)
}

// --- TrendingSubredditsLimit setting ---
@MainActor func checkTrendingSubredditsLimitSettingRealGapFix() async throws {
    check("GeneralSettings.default trending limit is 5", GeneralSettings.default.trendingSubredditsLimit == 5)
    let oldGeneralSettingsJSON = """
    {"autoCollapseChildComments":false,"autoCollapsePinnedComments":false,"defaultCommentSort":"top","thumbnailsOnLeft":true,"thumbnailSize":"small","openVideosInYouTubeApp":false,"showUserProfilePictures":false,"showRichLinkPreviews":false,"linkPreviewStyle":"full","hideFeedDescriptions":false}
    """.data(using: .utf8)!
    let oldGeneralSettings = try! JSONDecoder().decode(GeneralSettings.self, from: oldGeneralSettingsJSON)
    check("GeneralSettings decodes older data missing trendingSubredditsLimit, defaulting to 5", oldGeneralSettings.trendingSubredditsLimit == 5)
}

// --- Text Faces (Apollo's 40 text faces) ---
@MainActor func checkTextFacesRealGapFixRecovered() async throws {
    check("TextFaces.all has exactly the real 40 bundled entries", TextFaces.all.count == 40)
    check("TextFaces.all has no empty entries", TextFaces.all.allSatisfy { !$0.isEmpty })
    check("TextFaces.all includes the real classic table-flip face", TextFaces.all.contains("(╯°□°）╯︵ ┻━┻"))
    check("TextFaces.all includes the real shrug face", TextFaces.all.contains("¯\\_(ツ)_/¯"))
    check("TextFaces.all entries are unique", Set(TextFaces.all).count == TextFaces.all.count)
}

// --- External Browser (Apollo's "Open Links In" LSApplicationQueriesSchemes support) ---
@MainActor func checkExternalBrowserRealGapFixApollo() async throws {
    check("ExternalBrowserSettings.default uses the in-app browser", ExternalBrowserSettings.default.preferredBrowser == .inApp)
    let chromeURL = ExternalBrowser.chrome.translate(URL(string: "https://example.com/path?x=1")!)
    check("ExternalBrowser.chrome translates https to googlechromes scheme", chromeURL?.scheme == "googlechromes")
    let firefoxURL = ExternalBrowser.firefox.translate(URL(string: "https://example.com")!)
    check("ExternalBrowser.firefox matches the real firefox://open-url?url= template", firefoxURL?.absoluteString.hasPrefix("firefox://open-url?url=") == true)
    let braveURL = ExternalBrowser.brave.translate(URL(string: "https://example.com")!)
    check("ExternalBrowser.brave matches the real brave://open-url?url= template", braveURL?.absoluteString.hasPrefix("brave://open-url?url=") == true)
    let edgeURL = ExternalBrowser.edge.translate(URL(string: "https://example.com")!)
    check("ExternalBrowser.edge translates https to the real microsoft-edge-https scheme", edgeURL?.scheme == "microsoft-edge-https")
    let icabURL = ExternalBrowser.iCabMobile.translate(URL(string: "https://example.com")!)
    check("ExternalBrowser.iCabMobile matches the real x-icabmobile:// x-callback-url template", icabURL?.absoluteString.hasPrefix("x-icabmobile://x-callback-url/open?url=") == true)
    check("ExternalBrowser.inApp/.safari have no scheme translation", ExternalBrowser.inApp.translate(URL(string: "https://example.com")!) == nil && ExternalBrowser.safari.translate(URL(string: "https://example.com")!) == nil)
    var externalBrowserSettings = ExternalBrowserSettings.default
    externalBrowserSettings.preferredBrowser = .firefox
    ExternalBrowserSettingsStore.save(externalBrowserSettings)
    check("ExternalBrowserSettingsStore round-trips a selection", ExternalBrowserSettingsStore.load().preferredBrowser == .firefox)
    ExternalBrowserSettingsStore.save(.default)
}

// --- OpenMultiredditIntent / RedditURLTarget.multireddit (SiriKit intent) ---
@MainActor func checkOpenMultiredditIntentRedditURLTargetMultiredditThe4thReal() async throws {
    check("RedditURLTarget.multireddit is Equatable and distinct from .subreddit", RedditURLTarget.multireddit("test") != RedditURLTarget.subreddit("test"))
}

// --- JumpDestination: a single enum rather than two String? properties,
// since two `.navigationDestination(item:)` modifiers collide when SwiftUI
// dispatches by value type ---
@MainActor func checkJumpDestinationRealBugFixTwoSeparate() async throws {
    check("JumpDestination.subreddit and .user have distinct ids even for the same string", JumpDestination.subreddit("test").id != JumpDestination.user("test").id)
    check("JumpDestination.subreddit is stable/Equatable", JumpDestination.subreddit("apolloapp") == JumpDestination.subreddit("apolloapp"))
    check("JumpDestination.subreddit and .user are never equal even with the same name", JumpDestination.subreddit("apolloapp") != JumpDestination.user("apolloapp"))
    FavoriteSubredditsStore.setFavorite("ApolloReborn", isFavorite: true)
    check("FavoriteSubredditsStore.isFavorite is case-insensitive", FavoriteSubredditsStore.isFavorite("apolloreborn"))
    FavoriteSubredditsStore.toggle("ApolloReborn")
    check("FavoriteSubredditsStore.toggle unfavorites an existing favorite", !FavoriteSubredditsStore.isFavorite("apolloreborn"))
    FavoriteSubredditsStore.setFavorite("ApolloReborn", isFavorite: false)

    // Per-Account Favorites: refuses while the account is unknown; the first
    // enable copies the shared list to every existing account.
    let savedCurrent = FavoriteSubredditsAccountContext.currentUsernameProvider
    let savedAll = FavoriteSubredditsAccountContext.allUsernamesProvider
    FavoriteSubredditsAccountContext.currentUsernameProvider = { nil }
    check("Per-Account Favorites stays off while the account is unknown",
          !FavoriteSubredditsStore.setPerAccountEnabled(true) && !FavoriteSubredditsStore.perAccountEnabled)
    FavoriteSubredditsStore.setFavorite("pics", isFavorite: true)
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smokeone" }
    FavoriteSubredditsAccountContext.allUsernamesProvider = { ["smokeone", "smoketwo"] }
    FavoriteSubredditsStore.setPerAccountEnabled(true)
    let firstHas = FavoriteSubredditsStore.isFavorite("pics")
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smoketwo" }
    check("first enable copies the shared favorites to every existing account",
          firstHas && FavoriteSubredditsStore.isFavorite("pics"))
    FavoriteSubredditsStore.setFavorite("pics", isFavorite: false)
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smokeone" }
    FavoriteSubredditsStore.setFavorite("pics", isFavorite: false)
    FavoriteSubredditsStore.setPerAccountEnabled(false)
    FavoriteSubredditsStore.setFavorite("pics", isFavorite: false)
    for name in ["smokeone", "smoketwo"] {
        UserDefaults.standard.removeObject(forKey: "com.pendo324.Phoebus.favoriteSubreddits.account.\(name)")
    }
    FavoriteSubredditsAccountContext.currentUsernameProvider = savedCurrent
    FavoriteSubredditsAccountContext.allUsernamesProvider = savedAll
    // Favorites keep Apollo's native order: a backup's FavoriteSubreddits
    // array order on import, new favorites appended.
    FavoriteSubredditsStore.setOrder(["Apple", "AskHistorians", "apolloapp", "Linux"])
    FavoriteSubredditsStore.setFavorite("nba", isFavorite: true)
    check("imported favorites keep the backup's order, new ones appended",
          FavoriteSubredditsStore.loadOrdered() == ["apple", "askhistorians", "apolloapp", "linux", "nba"])
    check("imported favorites remember their casing", FavoriteSubredditsStore.displayName(for: "askhistorians") == "AskHistorians")
    for name in ["Apple", "AskHistorians", "apolloapp", "Linux", "nba"] { FavoriteSubredditsStore.setFavorite(name, isFavorite: false) }
    check("RedditSubreddit.named builds a row for an unsubscribed favorite", RedditSubreddit.named("iOSProgramming")?.displayName == "iOSProgramming")
    // One malformed multireddit (no `subreddits`) still decodes.
    check("RedditMultireddit decodes without subreddits/visibility",
          (try? JSONDecoder.reddit.decode(RedditMultireddit.self, from: Data(#"{"name":"m","display_name":"M","path":"/user/u/m/m"}"#.utf8)))?.subreddits.isEmpty == true)
}

// --- RedditSubreddit: /subreddits/mine/subscriber key-spelling quirks ---
@MainActor func checkRedditSubredditRealSubredditsMineSubscriberKey() async throws {
    let subredditWithOver18Alt = """
    {"id": "2qh1e", "name": "t5_2qh1e", "display_name": "videos", "title": "videos", "over18": true}
    """.data(using: .utf8)!
    check("RedditSubreddit decodes the real 'over18' (no underscore) key seen on /subreddits/mine/subscriber", (try? JSONDecoder.reddit.decode(RedditSubreddit.self, from: subredditWithOver18Alt))?.over18 == true)

    let subredditWithUnderscoreKey = """
    {"id": "2qh1e", "name": "t5_2qh1e", "display_name": "videos", "title": "videos", "over_18": true}
    """.data(using: .utf8)!
    check("RedditSubreddit still decodes the standard 'over_18' key", (try? JSONDecoder.reddit.decode(RedditSubreddit.self, from: subredditWithUnderscoreKey))?.over18 == true)

    let subredditMissingID = """
    {"name": "t5_2qh1e", "display_name": "videos", "title": "videos"}
    """.data(using: .utf8)!
    check("RedditSubreddit falls back to name-derived id when 'id' is missing (real, confirmed live)", (try? JSONDecoder.reddit.decode(RedditSubreddit.self, from: subredditMissingID))?.id == "2qh1e")
}

// --- RedditPost: crosspost decode ---
// Reddit's `crosspost_parent` is a string fullname ("t3_xxxxx"), not a
// boolean. Per-post decodes are wrapped in `try?`, so a type mismatch would
// silently drop every crosspost from the feed. This checks decoding of the
// `crosspost_parent_list` array (always sent alongside `crosspost_parent`)
// into `RedditCrosspostParent`.
@MainActor func checkRedditPostRealCrosspostDecodeBugFixed() async throws {
    let crosspostPostJSON = """
    {
      "id": "abc123", "name": "t3_abc123", "title": "Check this out",
      "author": "someuser", "subreddit": "pics", "permalink": "/r/pics/abc123",
      "score": 42, "num_comments": 7, "created_utc": 1700000000,
      "is_self": false, "over_18": false, "spoiler": false, "stickied": false,
      "saved": false,
      "crosspost_parent": "t3_original1",
      "crosspost_parent_list": [
        {
          "id": "original1", "name": "t3_original1", "title": "Original post title",
          "author": "originalauthor", "subreddit": "aww", "permalink": "/r/aww/original1",
          "score": 9001, "num_comments": 250, "created_utc": 1699999000,
          "over_18": false, "spoiler": false
        }
      ]
    }
    """.data(using: .utf8)!
    let decodedCrosspost = try? JSONDecoder.reddit.decode(RedditPost.self, from: crosspostPostJSON)
    check("RedditPost decodes a real crosspost without throwing (previously threw on 'crosspost_parent' as Bool)", decodedCrosspost != nil)
    check("RedditPost.isCrosspost is true when crosspost_parent_list is present", decodedCrosspost?.isCrosspost == true)
    check("RedditPost.crosspostParent resolves the original post's title", decodedCrosspost?.crosspostParent?.title == "Original post title")
    check("RedditPost.crosspostParent resolves the original post's subreddit", decodedCrosspost?.crosspostParent?.subreddit == "aww")
    check("RedditPost.crosspostParent resolves the original post's score", decodedCrosspost?.crosspostParent?.score == 9001)

    let nonCrosspostJSON = """
    {
      "id": "xyz789", "name": "t3_xyz789", "title": "A normal post",
      "author": "someuser", "subreddit": "pics", "permalink": "/r/pics/xyz789",
      "score": 5, "num_comments": 1, "created_utc": 1700000000,
      "is_self": false, "over_18": false, "spoiler": false, "stickied": false,
      "saved": false
    }
    """.data(using: .utf8)!
    let decodedNonCrosspost = try? JSONDecoder.reddit.decode(RedditPost.self, from: nonCrosspostJSON)
    check("RedditPost.isCrosspost is false when crosspost_parent_list is absent", decodedNonCrosspost?.isCrosspost == false)
    check("RedditPost.crosspostParent is nil for a normal post", decodedNonCrosspost?.crosspostParent == nil)

    // InboxCategory: old Reddit's inbox tabs.
    check("each Boxes category reads its own /message listing",
          InboxCategory.inbox.apiPath == "inbox" && InboxCategory.unreadMessages.apiPath == "unread"
          && InboxCategory.commentReplies.apiPath == "comments" && InboxCategory.postReplies.apiPath == "selfreply"
          && InboxCategory.usernameMentions.apiPath == "mentions" && InboxCategory.messages.apiPath == "messages")
    check("InboxCategory.title matches the real Boxes-menu row titles", InboxCategory.commentReplies.title == "Comment Replies" && InboxCategory.usernameMentions.title == "Mentions")

    // ModmailInboxTab: 5-tab structure + Apollo's per-tab empty-state strings.
    check("ModmailInboxTab has exactly the real 5 cases", ModmailInboxTab.allCases.count == 5)
    check("ModmailInboxTab.notifications real empty-state copy", ModmailInboxTab.notifications.emptyStateText == "No notification messages")
    check("ModmailInboxTab.modDiscussions real empty-state copy", ModmailInboxTab.modDiscussions.emptyStateText == "No mod discussions")
    check("ModmailInboxTab.highlighted real empty-state copy", ModmailInboxTab.highlighted.emptyStateText == "No highlighted messages")
    check("ModmailInboxTab.archived real empty-state copy", ModmailInboxTab.archived.emptyStateText == "No archived messages")
    check("ModmailInboxTab.inProgress real empty-state copy", ModmailInboxTab.inProgress.emptyStateText == "No in progress messages")
    check("ModmailInboxTab.modDiscussions maps to the real 'mod' api state", ModmailInboxTab.modDiscussions.apiState == "mod")
    check("ModmailInboxTab.inProgress maps to the real 'inprogress' api state", ModmailInboxTab.inProgress.apiState == "inprogress")

    // VideoDownloader: DASH audio-track pairing for "Download Video…". Reddit
    // serves v.redd.it audio as a separate stream, so the download derives the
    // sibling DASH_audio.mp4 URL or the saved clip is silent.
    check(
        "VideoDownloader derives the sibling DASH audio URL",
        VideoDownloader.audioURL(forRedditVideo: URL(string: "https://v.redd.it/abc123/DASH_720.mp4")!)?.absoluteString
            == "https://v.redd.it/abc123/DASH_audio.mp4"
    )
    check(
        "VideoDownloader handles a DASH URL with a query string",
        VideoDownloader.audioURL(forRedditVideo: URL(string: "https://v.redd.it/xyz/DASH_1080.mp4?source=fallback")!)?.absoluteString
            == "https://v.redd.it/xyz/DASH_audio.mp4"
    )
    check(
        "VideoDownloader ignores non-v.redd.it hosts",
        VideoDownloader.audioURL(forRedditVideo: URL(string: "https://i.imgur.com/abc.mp4")!) == nil
    )
    // Newer uploads name the track CMAF_AUDIO_*/DASH_AUDIO_*; the manifest
    // says which, best bitrate first.
    let dashManifest = """
    <MPD><Period>
    <AdaptationSet contentType="video" mimeType="video/mp4"><Representation bandwidth="900000"><BaseURL>CMAF_720.mp4</BaseURL></Representation></AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4">
    <Representation id="5" bandwidth="64000"><BaseURL>CMAF_AUDIO_64.mp4</BaseURL></Representation>
    <Representation id="6" bandwidth="128000"><BaseURL>CMAF_AUDIO_128.mp4</BaseURL></Representation>
    </AdaptationSet></Period></MPD>
    """
    check("the DASH manifest names the audio track, best bitrate first",
          VideoDownloader.audioFileNames(fromManifest: dashManifest) == ["CMAF_AUDIO_128.mp4", "CMAF_AUDIO_64.mp4"])
    check("a manifest with no audio set means a silent clip",
          VideoDownloader.audioFileNames(fromManifest: "<MPD><AdaptationSet contentType=\"video\"><Representation><BaseURL>DASH_720.mp4</BaseURL></Representation></AdaptationSet></MPD>").isEmpty)
    // An inline v.redd.it video plays HLS, which has no readable frame;
    // its poster comes from a progressive file, the sharpest up to 720p.
    let videoManifest = """
    <MPD><Period><AdaptationSet contentType="video" mimeType="video/mp4">
    <Representation bandwidth="5000000" height="1080"><BaseURL>CMAF_1080.mp4</BaseURL></Representation>
    <Representation bandwidth="2400000" height="720"><BaseURL>CMAF_720.mp4</BaseURL></Representation>
    <Representation bandwidth="240000" height="220"><BaseURL>CMAF_220.mp4</BaseURL></Representation>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4"><Representation bandwidth="64000"><BaseURL>CMAF_AUDIO_64.mp4</BaseURL></Representation></AdaptationSet>
    </Period></MPD>
    """
    check("the poster comes from the sharpest video file up to 720p",
          VideoDownloader.posterFileName(fromManifest: videoManifest) == "CMAF_720.mp4")
    check("a manifest with no video has no poster file",
          VideoDownloader.posterFileName(fromManifest: dashManifest.replacingOccurrences(of: "contentType=\"video\" mimeType=\"video/mp4\"", with: "contentType=\"text\"")) == nil)

    // GIFURLHelpers: shared "Save GIFs as…" (gifSaveFormat) / "Preferred GIF
    // Fallback Format" (preferredGIFFallbackFormat) mp4-sibling rewrite, pure
    // logic shared by `GIFSaveService` and `AnimatedGIFView`.
    check(
        "GIFURLHelpers finds the mp4 sibling of a .gif URL",
        GIFURLHelpers.mp4SiblingURL(for: URL(string: "https://i.redd.it/abc123.gif")!)?.absoluteString
            == "https://i.redd.it/abc123.mp4"
    )
    check(
        "GIFURLHelpers finds the mp4 sibling of a .gifv URL",
        GIFURLHelpers.mp4SiblingURL(for: URL(string: "https://i.imgur.com/xyz.gifv")!)?.absoluteString
            == "https://i.imgur.com/xyz.mp4"
    )
    check(
        "GIFURLHelpers is case-insensitive on the GIF extension",
        GIFURLHelpers.mp4SiblingURL(for: URL(string: "https://i.redd.it/abc123.GIF")!)?.absoluteString
            == "https://i.redd.it/abc123.mp4"
    )
    check(
        "GIFURLHelpers returns nil for a non-GIF URL",
        GIFURLHelpers.mp4SiblingURL(for: URL(string: "https://i.redd.it/abc123.png")!) == nil
    )
    check(
        "GIFSaveFormat has exactly the real 4 cases",
        GIFSaveFormat.allCases.count == 4 && GIFSaveFormat.allCases.contains(.askEachTime)
    )

    // Apollo's per-listing failure copy rather than a raw thrown-error
    // description.
    check(
        "Private subreddit uses Apollo's real copy",
        FeedErrorCopy.message(status: 403, body: "", subreddit: "pics")
            == "r/pics has been set to private by its subreddit moderators"
    )
    check(
        "Quarantined subreddit uses Apollo's real copy",
        FeedErrorCopy.message(status: 403, body: "{\"reason\": \"quarantined\"}", subreddit: "pics")
            == "r/pics has been quarantined by Reddit Administrators for offensive content"
    )
    check(
        "Banned subreddit uses Apollo's real copy",
        FeedErrorCopy.message(status: 404, body: "", subreddit: "pics")
            == "r/pics has been banned by Reddit Administrators for breaking Reddit rules"
    )

    // Apollo's flair sheet row structure: a "✓ " prefix marks the
    // applied flair, and "Remove Flair" is destructive and shown only when
    // a flair is applied or the user is a moderator.
    let flairOptions = [(id: "t1", text: "Discussion"), (id: "t2", text: "Question")]
    let flairRowsApplied = FlairActionRows.build(options: flairOptions, currentFlairID: "t2", isModerator: false)
    check("Flair sheet marks the applied flair with a real check prefix", flairRowsApplied[1].title == "\u{2713} Question")
    check("Flair sheet leaves unapplied flairs unprefixed", flairRowsApplied[0].title == "Discussion")
    check("Flair sheet offers Remove Flair when one is applied", flairRowsApplied.last?.title == "Remove Flair")
    check("Remove Flair is destructive", flairRowsApplied.last?.isDestructive == true)

    let flairRowsNone = FlairActionRows.build(options: flairOptions, currentFlairID: nil, isModerator: false)
    check("Flair sheet hides Remove Flair when none is applied", flairRowsNone.allSatisfy { $0.title != "Remove Flair" })

    let flairRowsMod = FlairActionRows.build(options: flairOptions, currentFlairID: nil, isModerator: true)
    check("Moderators always get Remove Flair", flairRowsMod.last?.title == "Remove Flair")

    // Vimeo + Imgflip: hosts Apollo previews that PostMediaKind.classify must
    // recognise.
    check("Vimeo plain URL", VimeoURLParser.extractVideoID(from: URL(string: "https://vimeo.com/123456789")!) == "123456789")
    check("Vimeo channel URL", VimeoURLParser.extractVideoID(from: URL(string: "https://vimeo.com/channels/staffpicks/987654321")!) == "987654321")
    check("Vimeo player URL", VimeoURLParser.extractVideoID(from: URL(string: "https://player.vimeo.com/video/555555")!) == "555555")
    check("Vimeo ignores other hosts", VimeoURLParser.extractVideoID(from: URL(string: "https://youtube.com/watch?v=abc")!) == nil)
    check("Vimeo player URL uses the real host", VimeoURLParser.playerURL(forVideoID: "42")?.absoluteString == "https://player.vimeo.com/video/42")

    check("Imgflip direct host", ImgflipURLParser.extractID(from: URL(string: "https://i.imgflip.com/abc123.jpg")!) == "abc123")
    check("Imgflip /i/ path", ImgflipURLParser.extractID(from: URL(string: "https://imgflip.com/i/xyz789")!) == "xyz789")
    check("Imgflip ignores other hosts", ImgflipURLParser.extractID(from: URL(string: "https://imgur.com/i/abc")!) == nil)
    check("Imgflip image URL uses the real base", ImgflipURLParser.imageURL(forID: "abc")?.absoluteString == "https://i.imgflip.com/abc.jpg")

    // A v.redd.it DASH URL yields both a video URL and its sibling audio URL,
    // and the muxer is given two distinct files.
    let dashVideo = URL(string: "https://v.redd.it/abc123/DASH_720.mp4?source=fallback")!
    let pairedAudio = VideoDownloader.audioURL(forRedditVideo: dashVideo)
    check("Download pairs a distinct audio URL", pairedAudio != nil && pairedAudio != dashVideo)
    check("Paired audio keeps the same v.redd.it asset id", pairedAudio?.absoluteString.contains("abc123") == true)

    // subreddit_autocomplete_v2 returns a normal t5 Listing, the same shape
    // subreddits/search returns, so the Jump Bar's existing decoder works
    // unchanged.
    let autocompletePayload = Data("""
    {"kind":"Listing","data":{"after":null,"children":[
     {"kind":"t5","data":{"display_name":"atheism","name":"t5_2qh4d","title":"atheism","over18":false}},
     {"kind":"t5","data":{"display_name":"atheismindia","name":"t5_2s3xr","title":"Atheism India","over18":false}}
    ]}}
    """.utf8)
    if let listing = try? JSONDecoder.reddit.decode(RedditListing.self, from: autocompletePayload) {
        let names: [String] = listing.data.children.compactMap { child in
            let plain = JSONValue.object(child.data.raw).plain
            guard let d = try? JSONSerialization.data(withJSONObject: plain),
                  let sr = try? JSONDecoder.reddit.decode(RedditSubreddit.self, from: d) else { return nil }
            return sr.displayName
        }
        check("autocomplete_v2 Listing decodes to subreddit names", names == ["atheism", "atheismindia"])
        check("autocomplete results all share the typed prefix", names.allSatisfy { $0.lowercased().hasPrefix("athe") })
    } else {
        check("autocomplete_v2 Listing decodes to subreddit names", false)
    }

    // CommentSortMemoryStore: mutually-exclusive per-post/per-subreddit
    // sort memory.
    CommentSortMemoryStore.saveMode(.off)
    UserDefaults.standard.removeObject(forKey: "Phoebus.commentSortBySubreddit")
    UserDefaults.standard.removeObject(forKey: "Phoebus.commentSortByPost")

    check("Sort memory off by default returns nil", CommentSortMemoryStore.rememberedSort(subreddit: "pics", postID: "abc") == nil)

    CommentSortMemoryStore.saveMode(.subreddit)
    CommentSortMemoryStore.recordSortChange(subreddit: "pics", postID: "abc", sort: "top")
    check("Subreddit mode remembers by subreddit", CommentSortMemoryStore.rememberedSort(subreddit: "pics", postID: "xyz") == "top")
    check("Subreddit mode is case-insensitive", CommentSortMemoryStore.rememberedSort(subreddit: "PICS", postID: "other") == "top")

    CommentSortMemoryStore.saveMode(.post)
    CommentSortMemoryStore.recordSortChange(subreddit: "pics", postID: "abc", sort: "new")
    check("Post mode remembers only that post", CommentSortMemoryStore.rememberedSort(subreddit: "pics", postID: "abc") == "new")
    check("Post mode does not leak to a different post", CommentSortMemoryStore.rememberedSort(subreddit: "pics", postID: "other-post") == nil)

    CommentSortMemoryStore.saveMode(.post)
    CommentSortMemoryStore.recordSortChange(subreddit: "aww", postID: "livepost", sort: "live")
    check("Live Update sort is never persisted (real Apollo behavior)", CommentSortMemoryStore.rememberedSort(subreddit: "aww", postID: "livepost") == nil)

    // CommentSearchEngine: Find-in-Comments matcher semantics.
    check("Single-term query finds one term only", CommentSearchEngine.terms(for: "hello") == ["hello"])
    check("Comma query splits into trimmed terms", CommentSearchEngine.terms(for: "word1, word2 , word3") == ["word1", "word2", "word3"])
    check("Empty query has no terms", CommentSearchEngine.terms(for: "  ").isEmpty)

    check("matches() is case-insensitive", CommentSearchEngine.matches("Hello World", query: "hello"))
    check("matches() OR-combines comma terms", CommentSearchEngine.matches("socks and shoes", query: "Leao, why, socks"))
    check("matches() returns false with no term hit", !CommentSearchEngine.matches("nothing here at all", query: "zzz, qqq"))

    let flatComments: [(id: String, author: String, body: String)] = [
        ("c1", "alice", "I love cats"),
        ("c2", "bob", "dogs are great too"),
        ("c3", "carol", "CATS and dogs, best combo"),
    ]
    let found = CommentSearchEngine.findMatches(
        query: "cats",
        postTitle: "A post about pets",
        postSelftext: nil,
        postAuthor: "dave",
        subreddit: "pets",
        flattenedComments: flatComments
    )
    check("findMatches finds all case-insensitive body hits in document order", found.map(\.commentID) == ["c1", "c3"])

    let multiTerm = CommentSearchEngine.findMatches(
        query: "dogs, alice",
        postTitle: "irrelevant title",
        postSelftext: nil,
        postAuthor: "dave",
        subreddit: "pets",
        flattenedComments: flatComments
    )
    check("findMatches OR-combines multi-term across authors and bodies", multiTerm.map(\.commentID) == ["c1", "c2", "c3"])

    let postMatch = CommentSearchEngine.findMatches(
        query: "pets",
        postTitle: "A post about pets",
        postSelftext: nil,
        postAuthor: "dave",
        subreddit: "pets",
        flattenedComments: flatComments
    )
    check("findMatches includes the post itself when it matches (subreddit name)", postMatch.first?.commentID == nil)

    // VideoHoldSpeedSettings: defaults (Reborn #78).
    check("Hold-for-speed defaults ON", VideoHoldSpeedSettings.default.isEnabled == true)
    check("Hold speed defaults to 2x", VideoHoldSpeedSettings.default.holdSpeed == 2)
    check("Real speed set is 0.25/0.5/0.75/1.25/1.5/2x", VideoHoldSpeedSettings.availableSpeeds == [0.25, 0.5, 0.75, 1.25, 1.5, 2])

    // FeedVideoScrubberSettings: default is OFF.
    check("Feed Video Scrubber defaults OFF", FeedVideoScrubberSettings.default.isEnabled == false)
    FeedVideoScrubberStore.save(FeedVideoScrubberSettings(isEnabled: true))
    check("Feed Video Scrubber setting persists", FeedVideoScrubberStore.load().isEnabled == true)
    FeedVideoScrubberStore.save(FeedVideoScrubberSettings(isEnabled: false))
    check("Feed Video Scrubber setting persists off too", FeedVideoScrubberStore.load().isEnabled == false)

    // SocialLinkScraper: <faceplate-tracker> tag parsing (Reborn #697 profile
    // layout companion feature).
    let socialHTML = """
    <div data-testid="profile-main">
    <faceplate-tracker source="profile" action="click" noun="add_social_link" data-faceplate-tracking-context="{&quot;social_link&quot;:{&quot;type&quot;:&quot;ADD&quot;}}"></faceplate-tracker>
    <faceplate-tracker source="profile" action="click" noun="social_link" data-faceplate-tracking-context="{&quot;social_link&quot;:{&quot;type&quot;:&quot;BUY_ME_A_COFFEE&quot;,&quot;url&quot;:&quot;https://buymeacoffee.com/dev&quot;,&quot;name&quot;:&quot;Support Me&quot;,&quot;position&quot;:0}}"></faceplate-tracker>
    <faceplate-tracker source="profile" action="click" noun="social_link" data-faceplate-tracking-context="{&quot;social_link&quot;:{&quot;type&quot;:&quot;TWITTER&quot;,&quot;url&quot;:&quot;https://x.com/dev&quot;,&quot;name&quot;:&quot;&quot;,&quot;position&quot;:1}}"></faceplate-tracker>
    </div>
    """
    let socialLinks = SocialLinkScraper.parse(html: socialHTML)
    check("parses only noun=social_link trackers, skips add_social_link", socialLinks.count == 2)
    check("first link decodes URL and title", socialLinks.first?.urlString == "https://buymeacoffee.com/dev" && socialLinks.first?.title == "Support Me")
    check("empty name falls back to real display-name map", socialLinks.last?.title == "X")
    check("host-based type classification", socialLinks.first?.type == "buymeacoffee" && socialLinks.last?.type == "twitter")
    check("looksLikeRealProfile detects data-testid=profile-main", SocialLinkScraper.looksLikeRealProfile(html: socialHTML))
    check("looksLikeUserGone detects the real deleted-user sentence", SocialLinkScraper.looksLikeUserGone(html: "chrome-only shell: nobody on Reddit goes by that name"))
    check("dedupes repeated URLs", SocialLinkScraper.parse(html: socialHTML + socialHTML).count == 2)

    // Poll voting: GraphQL mutation's CSRF token extraction from a cookie
    // header.
    let sampleCookieHeader = "reddit_session=abc123; loid=xyz; csrf_token=deadbeef1234; edgebucket=qqq"
    check("csrfToken extracts the real cookie value", PollVoteService.csrfToken(fromCookieHeader: sampleCookieHeader) == "deadbeef1234")
    check("csrfToken returns nil when absent", PollVoteService.csrfToken(fromCookieHeader: "reddit_session=abc123; loid=xyz") == nil)
    check("csrfToken returns nil for an empty value", PollVoteService.csrfToken(fromCookieHeader: "csrf_token=; loid=xyz") == nil)
}
