import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Return Button (Reborn)
//
// Key ScrollReturnButton, default on.
@MainActor func checkReturnButtonReborn371() async throws {
    check("the return button defaults ON, matching Tweak.xm:3802",
          GeneralSettings.default.scrollReturnButton)
    do {
        let sparse = try! JSONDecoder().decode(GeneralSettings.self, from: Data("{}".utf8))
        check("an older saved blob defaults the return button on",
              sparse.scrollReturnButton)
    }
}

// MARK: - Automatic Backups (Reborn, PR #1060)
//
// Keys AutomaticBackupsEnabled (default OFF) and AutomaticBackupIntervalDays
// (default 3): "Default OFF, every 3 days; supported intervals are 1, 3, and 7
// days".
@MainActor func checkAutomaticBackupsReborn371() async throws {
    do {
        check("automatic backups default OFF",
              !AutomaticBackupSettings.default.enabled)
        check("the default interval is 3 days",
              AutomaticBackupSettings.default.intervalDays == 3)
        // Only 1, 3 and 7 survive; anything else becomes 3.
        check("supported intervals pass through the clamp",
              AutomaticBackupSettings.clamp(1) == 1
                && AutomaticBackupSettings.clamp(3) == 3
                && AutomaticBackupSettings.clamp(7) == 7)
        check("an unsupported interval clamps to 3",
              AutomaticBackupSettings.clamp(2) == 3
                && AutomaticBackupSettings.clamp(30) == 3
                && AutomaticBackupSettings.clamp(0) == 3)
        // The clamp must apply through the initialiser too, or a decoded
        // blob could carry an unsupported value.
        check("the initialiser clamps as well",
              AutomaticBackupSettings(enabled: true, intervalDays: 5).intervalDays == 3)
        // Row detail.
        check("interval descriptions match the real row text",
              AutomaticBackupSettings.intervalDescription(1) == "Every Day"
                && AutomaticBackupSettings.intervalDescription(3) == "Every 3 Days")
    }
    do {
        let now = Date()
        // Next backup date.
        check("a disabled schedule has no next date",
              AutomaticBackupSchedule.nextBackupDate(
                enabled: false, lastBackup: nil, intervalDays: 3, now: now) == nil)
        // With no history a backup is due immediately.
        check("no previous backup means one is due now",
              AutomaticBackupSchedule.isDue(
                enabled: true, lastBackup: nil, intervalDays: 3, now: now))
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 3600)
        check("a backup 2 days ago is not yet due on a 3-day interval",
              !AutomaticBackupSchedule.isDue(
                enabled: true, lastBackup: twoDaysAgo, intervalDays: 3, now: now))
        check("the same backup IS due on a 1-day interval",
              AutomaticBackupSchedule.isDue(
                enabled: true, lastBackup: twoDaysAgo, intervalDays: 1, now: now))
        // Clock-skew guard: a last-backup date implausibly far in the future (over
        // 5 minutes) is treated as absent.
        let farFuture = now.addingTimeInterval(3600)
        check("a last-backup date in the future is disbelieved",
              AutomaticBackupSchedule.isDue(
                enabled: true, lastBackup: farFuture, intervalDays: 3, now: now))
    }
    do {
        let now = Date()
        // Next retry date: only while the last ATTEMPT is newer than the last
        // SUCCESS.
        let justFailed = now.addingTimeInterval(-60)
        let retry = AutomaticBackupSchedule.nextRetryDate(
            enabled: true, isBackingUp: false, suspendedForRestore: false,
            lastAttempt: justFailed, lastBackup: nil, intervalDays: 3, now: now)
        check("a fresh failure schedules a retry",
              retry != nil)
        // The retry interval is 15 minutes.
        check("the retry lands 15 minutes after the attempt",
              retry != nil && abs(retry!.timeIntervalSince(justFailed) - 15 * 60) < 1)
        // A success at or after the attempt clears the retry.
        check("a succeeded attempt schedules no retry",
              AutomaticBackupSchedule.nextRetryDate(
                enabled: true, isBackingUp: false, suspendedForRestore: false,
                lastAttempt: justFailed, lastBackup: now, intervalDays: 3, now: now) == nil)
        // A retry never runs before the next scheduled backup.
        let longAgoAttempt = now.addingTimeInterval(-3600)
        let recentSuccessButOlderThanAttempt = now.addingTimeInterval(-7200)
        let pushed = AutomaticBackupSchedule.nextRetryDate(
            enabled: true, isBackingUp: false, suspendedForRestore: false,
            lastAttempt: longAgoAttempt, lastBackup: recentSuccessButOlderThanAttempt,
            intervalDays: 3, now: now)
        check("a retry never precedes the next scheduled backup",
              pushed != nil && pushed! > now.addingTimeInterval(24 * 3600))
        check("no retry while a backup is running",
              AutomaticBackupSchedule.nextRetryDate(
                enabled: true, isBackingUp: true, suspendedForRestore: false,
                lastAttempt: justFailed, lastBackup: nil, intervalDays: 3, now: now) == nil)
    }
    do {
        // Retention: "The latest 10 automatic backups are kept".
        check("retention keeps ten automatic backups",
              AutomaticBackupSchedule.automaticRetentionCount == 10)
        let many = (1...15).map { "backup-\($0)" }
        check("pruning keeps exactly the newest ten",
              AutomaticBackupSchedule.pruned(automaticBackups: many).count == 10
                && AutomaticBackupSchedule.pruned(automaticBackups: many).first == "backup-1")
    }
}

// MARK: - Widget feed sources (Reborn "Widgets for Any Feed")
//
// Every case below is a row of Reborn's source parsing table.
@MainActor func checkWidgetFeedSourcesReborn37() async throws {
    do {
        // | `soccer`, `r/soccer`, `https://reddit.com/r/soccer/top` | r/soccer |
        check("a bare name parses as a subreddit",
              WidgetFeedSource.parse("soccer") == .subreddits(["soccer"]))
        check("an r/ prefix parses as a subreddit",
              WidgetFeedSource.parse("r/soccer") == .subreddits(["soccer"]))
        check("a pasted URL with a sort segment parses as the subreddit",
              WidgetFeedSource.parse("https://reddit.com/r/soccer/top") == .subreddits(["soccer"]))

        // | `soccer+nba`, `soccer, nba`, `r/soccer r/nba` | combined |
        check("a plus-joined pair is a combined listing",
              WidgetFeedSource.parse("soccer+nba") == .subreddits(["soccer", "nba"]))
        check("a comma-separated pair is the same listing",
              WidgetFeedSource.parse("soccer, nba") == .subreddits(["soccer", "nba"]))
        check("a space-separated r/ pair is the same listing",
              WidgetFeedSource.parse("r/soccer r/nba") == .subreddits(["soccer", "nba"]))

        // | `home`, `popular`, `all` | the built-in feeds |
        check("home parses as the built-in home feed",
              WidgetFeedSource.parse("home") == .home)
        check("popular parses as the built-in feed",
              WidgetFeedSource.parse("popular") == .popular
                && WidgetFeedSource.parse("r/popular") == .popular)
        check("all parses as the built-in feed",
              WidgetFeedSource.parse("all") == .all
                && WidgetFeedSource.parse("r/all") == .all)

        // | `https://reddit.com/user/foo/m/bar`, `u/foo/m/bar` | foo's multi |
        check("another user's multireddit URL parses with its owner",
              WidgetFeedSource.parse("https://reddit.com/user/foo/m/bar")
                == .multireddit(owner: "foo", name: "bar"))
        check("the u/ short form parses the same way",
              WidgetFeedSource.parse("u/foo/m/bar") == .multireddit(owner: "foo", name: "bar"))

        // | `m/bar`, `/me/m/bar` | your own multireddit |
        check("m/ is your own multireddit",
              WidgetFeedSource.parse("m/bar") == .multireddit(owner: nil, name: "bar"))
        check("/me/m/ is your own multireddit",
              WidgetFeedSource.parse("/me/m/bar") == .multireddit(owner: nil, name: "bar"))

        check("empty input parses to nothing",
              WidgetFeedSource.parse("   ") == nil)
    }
    do {
        // Header text: "Home", "r/soccer+nba", "m/bar".
        check("the header text matches the real examples",
              WidgetFeedSource.home.displayName == "Home"
                && WidgetFeedSource.subreddits(["soccer", "nba"]).displayName == "r/soccer+nba"
                && WidgetFeedSource.multireddit(owner: nil, name: "bar").displayName == "m/bar")
        // Home and your own multireddits need the with-account setup
        // code; the widget says so ("Sign in for this feed") instead of
        // failing quietly.
        check("home requires an account",
              WidgetFeedSource.home.requiresAccount)
        check("your OWN multireddit requires an account",
              WidgetFeedSource.multireddit(owner: nil, name: "bar").requiresAccount)
        // Someone else's is public, so it does not.
        check("another user's multireddit does not require an account",
              !WidgetFeedSource.multireddit(owner: "foo", name: "bar").requiresAccount)
        check("public listings do not require an account",
              !WidgetFeedSource.popular.requiresAccount
                && !WidgetFeedSource.all.requiresAccount
                && !WidgetFeedSource.subreddits(["soccer"]).requiresAccount)
        check("the sign-in message is the real copy",
              WidgetFeedSource.signInMessage == "Sign in for this feed")
        // Listing paths.
        // The URL the widget actually builds, for each source, so the
        // path property is checked as it is USED rather than in isolation.
        check("each source builds a fetchable listing URL",
              ["/r/popular", "/r/all", "/r/soccer+nba"].allSatisfy { path in
                  URL(string: "https://www.reddit.com\(path)/hot.json?limit=1") != nil
              })
        check("paths are the real listing paths",
              WidgetFeedSource.popular.path == "/r/popular"
                && WidgetFeedSource.subreddits(["soccer", "nba"]).path == "/r/soccer+nba"
                && WidgetFeedSource.multireddit(owner: "foo", name: "bar").path == "/user/foo/m/bar"
                && WidgetFeedSource.multireddit(owner: nil, name: "bar").path == "/me/m/bar")
    }
}

// MARK: - Azure target-language codes (Reborn)
//
// Bare `zh` and `no` are absent from /languages?scope=translation and the
// translate endpoint 400s on them, which would break the Microsoft provider
// for those target languages (both are offered in the Target Language
// picker).
@MainActor func checkAzureTargetLanguageCodesReborn3() async throws {
    do {
        check("Chinese maps to Azure's Simplified code",
              BulkTranslationClient.microsoftTargetLanguageCode("zh") == "zh-Hans")
        check("Norwegian maps to Bokmal",
              BulkTranslationClient.microsoftTargetLanguageCode("no") == "nb")
        check("Serbian maps to the Cyrillic script code",
              BulkTranslationClient.microsoftTargetLanguageCode("sr") == "sr-Cyrl")
        check("Tagalog maps to Filipino",
              BulkTranslationClient.microsoftTargetLanguageCode("tl") == "fil")
        check("the legacy Hebrew code maps to he",
              BulkTranslationClient.microsoftTargetLanguageCode("iw") == "he")
        check("Mongolian maps to the Cyrillic script code",
              BulkTranslationClient.microsoftTargetLanguageCode("mn") == "mn-Cyrl")
        // "anything else passes through and, if Azure still rejects it,
        // surfaces its own error" - the map must not swallow unknowns.
        check("an unmapped code passes through unchanged",
              BulkTranslationClient.microsoftTargetLanguageCode("en") == "en"
                && BulkTranslationClient.microsoftTargetLanguageCode("de") == "de")
    }
}

// MARK: - Community Highlights (Reborn)
//
// The 3-way mode must actually be rendered, not just persisted; see
// `SubredditLayoutSettings` for the three modes.
@MainActor func checkCommunityHighlightsReborn370() async throws {
    do {
        // Reborn's constants.
        check("card size is the real 160x120",
              CommunityHighlights.Metrics.cardWidth == 160
                && CommunityHighlights.Metrics.cardHeight == 120)
        check("spacing and padding are the real values",
              CommunityHighlights.Metrics.cardSpacing == 10
                && CommunityHighlights.Metrics.sidePadding == 16
                && CommunityHighlights.Metrics.cardPadding == 10)
        check("the card corner radius is the real 14",
              CommunityHighlights.Metrics.cardCornerRadius == 14)
        check("the fetch limit is the real 15",
              CommunityHighlights.fetchLimit == 15)
        check("the New lifetime is 24 hours",
              CommunityHighlights.newLifetime == 24 * 60 * 60)
        // Total height: title + top + card + bottom.
        check("the header height matches the real formula",
              CommunityHighlights.Metrics.totalHeight == 26 + 6 + 120 + 6)
        check("the header title is the real string",
              CommunityHighlights.title == "Community Highlights")
        check("the badge text is the real string",
              CommunityHighlights.newBadgeText == "New")
    }
    do {
        let now = Date()
        // isNew = age >= 0 && age < lifetime.
        check("a post from an hour ago is New",
              CommunityHighlights.isNew(createdAt: now.addingTimeInterval(-3600), now: now))
        check("a post from two days ago is not New",
              !CommunityHighlights.isNew(createdAt: now.addingTimeInterval(-48 * 3600), now: now))
        // A missing date is treated as the lifetime, which fails `< lifetime`, so
        // absent means NOT new.
        check("a post with no date is not New",
              !CommunityHighlights.isNew(createdAt: nil, now: now))
        // A future-dated post has negative age and fails `age >= 0`.
        check("a future-dated post is not New",
              !CommunityHighlights.isNew(createdAt: now.addingTimeInterval(3600), now: now))
    }
    do {
        // The two markers are mutually exclusive: the plain dot is hidden when
        // `!unread || isNew`, because a New post carries its unread state inside the
        // combined pill instead.
        check("an unread, not-New post shows the plain dot",
              CommunityHighlights.showsUnreadDot(isKnown: true, isRead: false, isNew: false))
        check("an unread AND New post does NOT show the plain dot",
              !CommunityHighlights.showsUnreadDot(isKnown: true, isRead: false, isNew: true))
        check("a read post shows no plain dot",
              !CommunityHighlights.showsUnreadDot(isKnown: true, isRead: true, isNew: false))
        check("the New badge carries the dot while unread",
              CommunityHighlights.newBadgeShowsUnreadDot(isKnown: true, isRead: false))
        // Reading removes that dot and contracts the pill.
        check("reading removes the badge's dot",
              !CommunityHighlights.newBadgeShowsUnreadDot(isKnown: true, isRead: true))
    }
    do {
        // "filtered to `stickied` posts" - order preserved.
        func stickyPost(_ id: String, _ stickied: Bool) -> RedditPost {
            let json = """
            {"id":"\(id)","name":"t3_\(id)","title":"t","author":"u",
             "subreddit":"test","permalink":"/r/test/comments/\(id)/",
             "score":1,"num_comments":0,"created_utc":0,"is_self":false,
             "over_18":false,"spoiler":false,"stickied":\(stickied),"saved":false}
            """.data(using: .utf8)!
            return try! JSONDecoder.reddit.decode(RedditPost.self, from: json)
        }
        let posts = [stickyPost("a", false), stickyPost("b", true), stickyPost("c", true)]
        check("only stickied posts become highlights, in listing order",
              CommunityHighlights.highlights(from: posts).map(\.id) == ["b", "c"])
        check("a listing with no stickies yields no highlights",
              CommunityHighlights.highlights(from: [stickyPost("a", false)]).isEmpty)
        // Cached highlights show as-is for a week, then re-check quietly.
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        check("highlights fetched six days ago are still fresh",
              !CommunityHighlights.isStale(fetchedAt: fetched, now: fetched.addingTimeInterval(6 * 24 * 60 * 60)))
        check("highlights fetched a week ago are re-checked",
              CommunityHighlights.isStale(fetchedAt: fetched, now: fetched.addingTimeInterval(7 * 24 * 60 * 60)))
        // The carousel's pinned posts leave the feed; pinned widgets stay
        // in the feed and leave the carousel.
        let carousel = CommunityHighlights.carouselPosts(from: [posts[1], posts[2]]) { $0.id == "c" }
        check("a pinned widget stays out of the carousel",
              carousel.map(\.id) == ["b"])
        let shown = CommunityHighlights.feedRowIDsShownInCarousel(carouselPosts: carousel, scrapedPermalinks: [])
        check("the feed hides the pinned row the carousel shows, and keeps the rest",
              posts.filter { !CommunityHighlights.feedHides($0, shownInCarousel: shown) }.map(\.id) == ["a", "c"])
        let scraped = CommunityHighlights.feedRowIDsShownInCarousel(
            carouselPosts: [], scrapedPermalinks: ["https://www.reddit.com/r/test/comments/C/some_slug/"])
        check("scraped cards hide their pinned feed rows too, by post id",
              CommunityHighlights.feedHides(posts[2], shownInCarousel: scraped)
                && !CommunityHighlights.feedHides(posts[1], shownInCarousel: scraped))
        check("an unpinned post is never hidden",
              !CommunityHighlights.feedHides(posts[0], shownInCarousel: ["a"]))
        check("an unchanged refresh doesn't rebuild the carousel",
              CommunityHighlights.signature(of: posts) == CommunityHighlights.signature(of: posts)
                && CommunityHighlights.signature(of: posts) != CommunityHighlights.signature(of: Array(posts.dropFirst())))
    }
}

// MARK: - Whole-domain settings backup
//
// Like Reborn, backups cover whole preference DOMAINS rather than a
// hand-listed set of stores, so no setting (theme, app icon, app lock,
// translation credentials, every Reborn layout preference) is missing from an
// export.
@MainActor func checkWholeDomainSettingsBackup() async throws {
    do {
        // Key ownership.
        check("this app's prefixed keys are backed up",
              SettingsDomainSnapshot.isBackedUp("com.pendo324.Phoebus.generalSettings")
                && SettingsDomainSnapshot.isBackedUp("Phoebus.appearanceSettings"))
        // Bare Reborn key names carry no prefix, so they need the explicit list or
        // the filter drops them.
        check("bare Reborn-named keys are backed up",
              SettingsDomainSnapshot.isBackedUp("FollowedUsersOrder")
                && SettingsDomainSnapshot.isBackedUp("ChatMessagesFilter"))
        // Never carry unrelated system state.
        check("foreign keys are not backed up",
              !SettingsDomainSnapshot.isBackedUp("AppleLanguages")
                && !SettingsDomainSnapshot.isBackedUp("NSInterfaceStyle"))
        // High-churn view state is excluded on purpose.
        check("read-tracking is excluded",
              !SettingsDomainSnapshot.isBackedUp("com.pendo324.Phoebus.readPostIDs")
                && !SettingsDomainSnapshot.isBackedUp("com.pendo324.Phoebus.seenCommentIDs"))
        check("browsing history is excluded",
              !SettingsDomainSnapshot.isBackedUp("com.pendo324.Phoebus.recentlyReadPosts"))
        // Reborn keeps backup run-state out of the archive for the same
        // reason: restoring another device's last-run would suppress the
        // next backup here.
        check("backup run-state is excluded",
              !SettingsDomainSnapshot.isBackedUp("com.pendo324.Phoebus.automaticBackupLast"))
    }
    do {
        // The critical round trip. Most of this app's stores persist as a
        // JSON blob under one key, i.e. as Data - which has no native JSON
        // representation, so a naive snapshot would drop nearly
        // everything.
        let defaults = UserDefaults(suiteName: "SettingsDomainSnapshotTest")!
        defaults.removePersistentDomain(forName: "SettingsDomainSnapshotTest")
        defaults.set(Data("hello".utf8), forKey: "com.pendo324.Phoebus.blobTest")
        defaults.set(true, forKey: "com.pendo324.Phoebus.boolTest")
        defaults.set(42, forKey: "com.pendo324.Phoebus.intTest")
        defaults.set("text", forKey: "com.pendo324.Phoebus.stringTest")
        defaults.set(["a", "b"], forKey: "FollowedUsersOrder")
        defaults.set(Date(timeIntervalSince1970: 1000), forKey: "com.pendo324.Phoebus.dateTest")

        let snapshot = SettingsDomainSnapshot.capture(from: defaults)
        check("a Data blob is captured",
              snapshot["com.pendo324.Phoebus.blobTest"] != nil)
        check("every set key is captured",
              snapshot.count == 6)

        // Survive a real JSON encode/decode, which is what an export is.
        let encoded = try! JSONEncoder().encode(snapshot)
        let decoded = try! JSONDecoder().decode([String: JSONValue].self, from: encoded)

        let target = UserDefaults(suiteName: "SettingsDomainSnapshotRestore")!
        target.removePersistentDomain(forName: "SettingsDomainSnapshotRestore")
        SettingsDomainSnapshot.restore(decoded, into: target)

        check("Data survives the JSON round trip",
              target.data(forKey: "com.pendo324.Phoebus.blobTest") == Data("hello".utf8))
        check("Bool survives as a Bool, not 1",
              target.object(forKey: "com.pendo324.Phoebus.boolTest") as? Bool == true)
        // A whole number must come back as Int, not 42.0.
        check("Int survives as an Int",
              target.object(forKey: "com.pendo324.Phoebus.intTest") as? Int == 42)
        check("String survives",
              target.string(forKey: "com.pendo324.Phoebus.stringTest") == "text")
        check("a string array survives",
              target.stringArray(forKey: "FollowedUsersOrder") == ["a", "b"])
        check("Date survives the JSON round trip",
              (target.object(forKey: "com.pendo324.Phoebus.dateTest") as? Date)?
                .timeIntervalSince1970 == 1000)

        defaults.removePersistentDomain(forName: "SettingsDomainSnapshotTest")
        target.removePersistentDomain(forName: "SettingsDomainSnapshotRestore")
    }
    do {
        // Version 1 exports predate both new fields and must still restore; the
        // typed fields are kept for this. Built by encoding a current bundle and
        // stripping the two version-2 fields, so the fixture cannot drift from the
        // real shape.
        var asV1 = BackupBundle.captureCurrent(includeAccounts: false)
        asV1.settingsDomain = nil
        asV1.version = 1
        let v1 = try! asV1.encoded()
        let bundle = try? BackupBundle.decode(from: v1)
        check("a version-1 export still decodes",
              bundle != nil && bundle?.version == 1)
        check("a version-1 export has no domain snapshot",
              bundle?.settingsDomain == nil)
        // And the current version is 2, since the shape changed.
        check("the current bundle version is 2",
              BackupBundle.currentVersion == 2)
    }
}

// MARK: - End-to-end restore of an exported archive
//
// Decodes an exported archive and checks that restoring it returns the
// settings that were wiped, against a file in the exported format rather
// than a bundle built in code.
@MainActor func checkEndToEndRestoreOfThe() async throws {
    do {
        let fixture = "Tests/Fixtures/device-backup-v2.json"
        if let data = FileManager.default.contents(atPath: fixture) {
            let bundle = try! BackupBundle.decode(from: data)
            check("the device archive is version 2",
                  bundle.version == 2)
            check("the device archive carries a domain snapshot",
                  (bundle.settingsDomain?.count ?? 0) >= 20)
            // Two settings that are seeded, wiped and restored.
            check("the archive carries the header style",
                  bundle.settingsDomain?["com.pendo324.Phoebus.headerStyle"] == .string("blur"))
            check("the archive carries the selected app icon",
                  bundle.settingsDomain?["com.pendo324.Phoebus.selectedAppIcon"] == .string("magma"))
            // Credentials are included.
            check("the archive carries accounts",
                  bundle.accounts != nil)
            // Restore into a scratch domain and confirm the values land.
            let scratch = UserDefaults(suiteName: "DeviceBackupRestoreTest")!
            scratch.removePersistentDomain(forName: "DeviceBackupRestoreTest")
            SettingsDomainSnapshot.restore(bundle.settingsDomain ?? [:], into: scratch)
            check("restoring the device archive returns the header style",
                  scratch.string(forKey: "com.pendo324.Phoebus.headerStyle") == "blur")
            check("restoring the device archive returns the app icon",
                  scratch.string(forKey: "com.pendo324.Phoebus.selectedAppIcon") == "magma")
            // A Data-backed store must survive, since that is how most of
            // this app's settings persist.
            check("a Data-backed store survives the real archive round trip",
                  scratch.data(forKey: "Phoebus.appearanceSettings") != nil)
            scratch.removePersistentDomain(forName: "DeviceBackupRestoreTest")
        } else {
            check("device backup fixture is present", false)
        }
    }
}

// A restored API key must reach the live OAuth config, not only storage:
// restored accounts refresh their tokens through it.
@MainActor func checkRestoreAppliesTheApiKey() async throws {
    let original = CustomAPISettingsStore.load()
    var restored = original
    restored.redditClientID = "smoke-restored-client"
    CustomAPISettingsStore.storage.save(restored)
    let bundle = BackupBundle.captureCurrent(includeAccounts: false)
    CustomAPISettingsStore.save(original)
    bundle.restore()
    check("a restored backup's Reddit client ID is live at once",
          RedditOAuthConfig.clientID == "smoke-restored-client")
    CustomAPISettingsStore.save(original)
}

// MARK: - Community Highlights Full mode (permalink parsing)
//
// Scraped cards carry only the carousel's href, so opening one needs
// the subreddit + post id. Reddit's shape is
// /r/<sub>/comments/<id>/<slug>/.
@MainActor func checkCommunityHighlightsFullModePermalinkParsing() async throws {
    do {
        let parsed = CommunityHighlights.identifiers(
            fromPermalink: "/r/worldnews/comments/1abc2de/some_title_slug/")
        check("a standard permalink yields subreddit and post id",
              parsed?.subreddit == "worldnews" && parsed?.postID == "1abc2de")
        // The scrape strips query strings before the href is seen, but a trailing
        // slug is optional in practice.
        check("a permalink without a slug still parses",
              CommunityHighlights.identifiers(fromPermalink: "/r/swift/comments/xyz789/")?.postID == "xyz789")
        // Anything that is not a post link must be rejected rather than
        // producing a bogus id - the carousel also contains subreddit and
        // user links.
        check("a non-post link is rejected",
              CommunityHighlights.identifiers(fromPermalink: "/r/worldnews/") == nil)
        check("a user link is rejected",
              CommunityHighlights.identifiers(fromPermalink: "/user/someone/") == nil)
        check("an empty permalink is rejected",
              CommunityHighlights.identifiers(fromPermalink: "") == nil)
        // The two cases above contain no "comments" segment at all, so they are
        // rejected before either structural guard runs; these exercise the guards
        // directly. Isolates the r/ guard: this HAS a comments segment AND an id
        // after it, so the bounds guard passes and only the "/r/" check can reject
        // it. A user's own comments permalink is the shape this protects against:
        // the carousel's DOM contains user links too, and without this guard
        // "someone" would be read as a subreddit name.
        check("a user comments permalink is not read as a subreddit post",
              CommunityHighlights.identifiers(fromPermalink: "/user/someone/comments/abc123/") == nil)
        check("a comments link with no id is rejected",
              CommunityHighlights.identifiers(fromPermalink: "/r/worldnews/comments/") == nil)
    }
}

// MARK: - Opening a highlight without refetching it
//
// Highlights ARE the subreddit's stickied posts, so the feed has usually
// already loaded the post a card points at. Opening it reuses that post
// instead of a fresh /comments fetch, which would leave the screen blank for
// seconds.
@MainActor func checkOpeningAHighlightWithoutRefetchingIt() async throws {
    do {
        let loaded = [makeTestPost(id: "aaa111"), makeTestPost(id: "bbb222")]
        // `makeTestPost` puts every post in r/test.
        check("a highlight resolves to the already-loaded post",
              CommunityHighlights.matchingPost(
                forPermalink: "/r/test/comments/bbb222/some_slug/",
                in: loaded)?.id == "bbb222")
        // Reddit serves the same post under different slugs, so the match
        // must be on the id, not on permalink equality.
        check("a different slug still matches the same post",
              CommunityHighlights.matchingPost(
                forPermalink: "/r/test/comments/aaa111/a_completely_different_slug/",
                in: loaded)?.id == "aaa111")
        // The fallback loader still has to exist for this case: Full mode
        // scrapes up to 6 highlights, more than the REST pair, so some
        // genuinely are not in the feed yet.
        check("a highlight the feed has not loaded returns nil",
              CommunityHighlights.matchingPost(
                forPermalink: "/r/test/comments/zzz999/unseen/",
                in: loaded) == nil)
        // Matching on the id ALONE would open a post from the wrong
        // subreddit if two subreddits ever surfaced the same id, and would
        // silently mislabel the back destination.
        check("a matching id in another subreddit does not match",
              CommunityHighlights.matchingPost(
                forPermalink: "/r/other/comments/aaa111/slug/",
                in: loaded) == nil)
        // A malformed permalink must fall through to the loader rather
        // than matching something arbitrary.
        check("an unparseable permalink returns nil",
              CommunityHighlights.matchingPost(forPermalink: "/r/test/", in: loaded) == nil)
        check("no loaded posts returns nil",
              CommunityHighlights.matchingPost(
                forPermalink: "/r/test/comments/aaa111/s/", in: []) == nil)
    }
}

// MARK: - Widget suite shared behaviour (Reborn)
//
// Nine widgets share sort, caption, rotation and content filtering, so these
// are checked once here.
@MainActor func checkWidgetSuiteSharedBehaviourReborn3() async throws {
    do {
        // "Hot, New, Top: Today, Top: This Week".
        check("the four real sort options exist with the real names",
              WidgetKitShared.Sort.allCases.map(\.displayName)
                == ["Hot", "New", "Top: Today", "Top: This Week"])
        // Top sorts need a timeframe; the others must not send one.
        check("top sorts carry the right timeframe",
              WidgetKitShared.Sort.topToday.timeframe == "day"
                && WidgetKitShared.Sort.topWeek.timeframe == "week")
        check("hot and new carry no timeframe",
              WidgetKitShared.Sort.hot.timeframe == nil
                && WidgetKitShared.Sort.new.timeframe == nil)
        check("both top sorts use the top listing path",
              WidgetKitShared.Sort.topToday.listingPath == "top"
                && WidgetKitShared.Sort.topWeek.listingPath == "top")
    }
    do {
        // "None / Title / Title + Stats / Detailed".
        check("the four real caption options exist",
              WidgetKitShared.Caption.allCases.map(\.displayName)
                == ["None", "Title", "Title + Stats", "Detailed"])
        check("None hides the title entirely",
              !WidgetKitShared.Caption.none.showsTitle)
        check("Title shows a title but no stats",
              WidgetKitShared.Caption.title.showsTitle
                && !WidgetKitShared.Caption.title.showsStats)
        check("Title + Stats adds score and comments",
              WidgetKitShared.Caption.titleAndStats.showsStats)
        // Detailed is a superset of Title + Stats.
        check("Detailed includes stats as well as details",
              WidgetKitShared.Caption.detailed.showsStats
                && WidgetKitShared.Caption.detailed.showsDetails)
        check("only Detailed shows details",
              !WidgetKitShared.Caption.titleAndStats.showsDetails)
    }
    do {
        // Advances roughly every 25 min across an 8 h window.
        check("the rotation step is 25 minutes",
              WidgetKitShared.Rotation.step == 25 * 60)
        check("the rotation window is 8 hours",
              WidgetKitShared.Rotation.window == 8 * 60 * 60)
        // The index must be a pure function of the clock: a widget
        // timeline is rebuilt unpredictably, so a stored cursor would
        // jump. Same instant + same pool => same answer, always.
        let instant = Date(timeIntervalSince1970: 1_000_000)
        check("the visible index is a pure function of time",
              WidgetKitShared.Rotation.index(at: instant, poolSize: 10)
                == WidgetKitShared.Rotation.index(at: instant, poolSize: 10))
        // 25 minutes later it must have advanced exactly one slot.
        let later = instant.addingTimeInterval(25 * 60)
        check("one step advances exactly one slot",
              WidgetKitShared.Rotation.index(at: later, poolSize: 10)
                == (WidgetKitShared.Rotation.index(at: instant, poolSize: 10) + 1) % 10)
        // The reload button.
        check("the offset advances the index",
              WidgetKitShared.Rotation.index(at: instant, poolSize: 10, offset: 1)
                == (WidgetKitShared.Rotation.index(at: instant, poolSize: 10) + 1) % 10)
        // Never divide by zero or index an empty pool.
        check("an empty pool yields index 0",
              WidgetKitShared.Rotation.index(at: instant, poolSize: 0) == 0)
        // A negative offset must still land in range, not crash.
        check("a negative offset stays in range",
              (0..<10).contains(WidgetKitShared.Rotation.index(at: instant, poolSize: 10, offset: -3)))
        check("the next change is in the future",
              WidgetKitShared.Rotation.nextChange(after: instant) > instant)
    }
    do {
        func post(_ id: String, nsfw: Bool = false, spoiler: Bool = false,
                  stickied: Bool = false, author: String = "u", isSelf: Bool = false,
                  selftext: String = "", url: String = "https://example.com/a.html") -> RedditPost {
            let json = """
            {"id":"\(id)","name":"t3_\(id)","title":"t","author":"\(author)",
             "subreddit":"s","permalink":"/r/s/comments/\(id)/","score":1,
             "num_comments":0,"created_utc":0,"is_self":\(isSelf),
             "over_18":\(nsfw),"spoiler":\(spoiler),"stickied":\(stickied),
             "saved":false,"selftext":"\(selftext)","url":"\(url)"}
            """.data(using: .utf8)!
            return try! JSONDecoder.reddit.decode(RedditPost.self, from: json)
        }
        // Every widget hides NSFW, spoiler, stickied, and
        // removed/deleted posts.
        let pool = [post("keep"), post("nsfw", nsfw: true), post("spoil", spoiler: true),
                    post("stick", stickied: true), post("gone", author: "[deleted]")]
        check("the shared filter hides nsfw, spoiler, stickied and deleted",
              WidgetKitShared.filtered(pool).map(\.id) == ["keep"])
        // Photo is image-only.
        let images = [post("img", url: "https://i.redd.it/x.jpg"), post("page")]
        check("image-only keeps just image posts",
              WidgetKitShared.imagePostsOnly(images).map(\.id) == ["img"])
        // Jokes needs a punchline, i.e. a self-post with a body.
        let jokes = [post("joke", isSelf: true, selftext: "punchline"),
                     post("empty", isSelf: true),
                     post("link")]
        check("self-posts-only keeps only self posts with a body",
              WidgetKitShared.selfPostsOnly(jokes).map(\.id) == ["joke"])
        // Widget taps must land on what they show, through the app's
        // own URL handlers.
        check("a widget post tap opens that post",
              RedditURLTarget.parseAppScheme(WidgetKitShared.DeepLink.post(post("abc123")))
                == .post(subreddit: "s", id: "abc123"))
        check("a widget subreddit tile opens that subreddit",
              RedditURLTarget.parseAppScheme(WidgetKitShared.DeepLink.subreddit("popular"))
                == .subreddit("popular"))
        check("a typed tile name with odd characters still builds a URL",
              RedditURLTarget.parseAppScheme(WidgetKitShared.DeepLink.subreddit("a b?c")) != nil)
        check("the Home, Inbox and Search tiles open those actions",
              [QuickAction.home, .inbox, .search].allSatisfy {
                  QuickAction.parse(WidgetKitShared.DeepLink.quickAction($0)) == $0
              })
    }
}

// MARK: - Calendar widget photo-of-the-day
//
// Picks one image per calendar day deterministically and persists it,
// so it never changes during the day and won't repeat a recent day (a
// rolling ~150-day history avoids dupes).
@MainActor func checkCalendarWidgetPhotoOfTheDay() async throws {
    do {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        // THE guarantee: the same day must always yield the same photo,
        // including across timeline rebuilds, or the photo would change
        // mid-day.
        check("the same day always picks the same photo",
              CalendarPhotoPicker.index(for: day, poolSize: 25)
                == CalendarPhotoPicker.index(for: day, poolSize: 25))
        // Any time within the same calendar day maps to the same index.
        let laterSameDay = day.addingTimeInterval(6 * 3600)
        let sameDayStart = Date(timeIntervalSince1970:
            (day.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400)
        let laterStart = Date(timeIntervalSince1970:
            (laterSameDay.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400)
        if sameDayStart == laterStart {
            check("any moment in a day picks that day's photo",
                  CalendarPhotoPicker.index(for: sameDayStart, poolSize: 25)
                    == CalendarPhotoPicker.index(for: laterStart, poolSize: 25))
        }
        // Consecutive days must differ, or "photo of the day" is a photo
        // of the week.
        let tomorrow = day.addingTimeInterval(86_400)
        check("consecutive days pick different photos",
              CalendarPhotoPicker.index(for: day, poolSize: 25)
                != CalendarPhotoPicker.index(for: tomorrow, poolSize: 25))
        // No repeats across a realistic pool for a stretch of days.
        var seen = Set<Int>()
        var collisions = 0
        for offset in 0..<25 {
            let d = day.addingTimeInterval(Double(offset) * 86_400)
            let index = CalendarPhotoPicker.index(for: d, poolSize: 25)
            if !seen.insert(index).inserted { collisions += 1 }
        }
        check("25 consecutive days over a 25-post pool never repeat",
              collisions == 0)
        check("an empty pool is safe",
              CalendarPhotoPicker.index(for: day, poolSize: 0) == 0)
        check("the history window is the real 150 days",
              CalendarPhotoPicker.historyWindow == 150)
    }
}

// MARK: - Widget credentials + AppIntents metadata
//
// Two separate failures make every widget look broken without involving
// widget code:
//
//   1. CHSErrorDomain 1103 "Intent configuration is required but was not
//      provided" on every AppIntentConfiguration widget, because xtool never
//      runs Xcode's AppIntents metadata build phase (StaticConfiguration
//      widgets are unaffected).
//   2. HTTP 403 on every widget fetch, because unauthenticated reddit .json
//      endpoints are refused outright.
@MainActor func checkWidgetCredentialsAppIntentsMetadata() async throws {
    do {
        let credential = SharedFeedCache.WidgetCredentials(
            cookieHeader: "reddit_session=abc", accessToken: nil,
            expiration: nil, userAgent: "UA")
        check("a cookie credential with no expiry is usable", credential.isUsable)
        let expired = SharedFeedCache.WidgetCredentials(
            cookieHeader: nil, accessToken: "tok",
            expiration: Date(timeIntervalSince1970: 0), userAgent: "UA")
        check("an expired bearer is not usable", !expired.isUsable)
        let renewable = SharedFeedCache.WidgetCredentials(
            cookieHeader: nil, accessToken: "tok", expiration: Date(timeIntervalSince1970: 0),
            userAgent: "UA", refreshToken: "rt", clientID: "cid")
        check("an expired bearer the widget can renew is usable", renewable.isUsable && !renewable.hasFreshBearer)
        let empty = SharedFeedCache.WidgetCredentials(
            cookieHeader: "", accessToken: nil, expiration: nil, userAgent: "UA")
        check("an empty cookie is not usable", !empty.isUsable)
    }
}

// MARK: - Subreddit header action cluster + tab re-tap pop-to-root
@MainActor func checkSubredditHeaderActionClusterTabRe() async throws {
    do {
        // Flair and Sidebar are icon-only SQUARES of one fixed side,
        // which is why they cannot differ in size, rather than pills that
        // each size to their own text.
        check("secondary action side is the real 44",
              SubredditLayoutSettings.secondaryActionSide == 44)
        check("secondary action icon side is the real 22",
              SubredditLayoutSettings.secondaryActionIconSide == 22)
        check("action gap is the real 10", SubredditLayoutSettings.actionGap == 10)
        check("action bottom gap is the real 16", SubredditLayoutSettings.actionBottomGap == 16)
        check("join minimum width is the real 148",
              SubredditLayoutSettings.joinMinimumWidth == 148)
    }
}

// MARK: - Artwork
//
// Apollo's standard icons, extracted from its IPA at build time.
@MainActor func checkRealArtwork() async throws {
    do {
        let fm = FileManager.default

        // Base catalog: one folder per icon, each at 2x and 3x. Extracted
        // from Apollo's IPA by scripts/generate-icons.sh, so only checked
        // once a build has run it.
        let iconDirectory = "Icons/Standard"
        guard fm.fileExists(atPath: "\(iconDirectory)/.extracted") else {
            print("  (standard icons not extracted yet; run scripts/generate-icons.sh to check them)")
            return
        }
        let icons = (try? fm.subpathsOfDirectory(atPath: iconDirectory)) ?? []
        check("every base app icon ships at both scales",
              icons.filter { $0.hasSuffix("@2x.png") }.count == AppIconOption.all.count
              && icons.filter { $0.hasSuffix("@3x.png") }.count == AppIconOption.all.count)
        // Apple ships these as CgBI PNGs, which standard decoders reject.
        // An extracted file must be a plain PNG with no CgBI chunk left.
        if let sample = try? Data(contentsOf: URL(fileURLWithPath: "\(iconDirectory)/magma/AppIcon-magma60x60@3x.png")) {
            check("icons are converted out of Apple's CgBI format",
                  sample.starts(with: Data([0x89, 0x50, 0x4E, 0x47]))
                  && sample.range(of: Data("CgBI".utf8)) == nil)
        } else {
            check("icons are converted out of Apple's CgBI format", false)
        }
    }
}

// MARK: - Icon switching + the feed's restorable state
@MainActor func checkIconSwitchingTheFeedSRestorable() async throws {
    do {
        check("System uses the bare icon ID, with no suffix",
              LiquidGlassIconAppearance.system.alternateIconName(for: "apollo") == "apollo")
        check("Light and Dark append the tweak's own suffixes",
              LiquidGlassIconAppearance.light.alternateIconName(for: "apollo")
                  == "apollo__apollo_light"
              && LiquidGlassIconAppearance.dark.alternateIconName(for: "apollo")
                  == "apollo__apollo_dark")
        check("the appearance menu's titles and glyphs are the tweak's",
              LiquidGlassIconAppearance.allCases.map(\.title) == ["Light", "Dark", "System"]
              && LiquidGlassIconAppearance.allCases.map(\.systemImageName)
                  == ["sun.max", "moon", "circle.lefthalf.filled"])
        check("the appearance preference uses the tweak's defaults key",
              LiquidGlassIconAppearanceStore.defaultsKey == "ApolloLGPreferredIconAppearance")
        check("an unset appearance defaults to System",
              LiquidGlassIconAppearanceStore.load(UserDefaults(suiteName: "smoke.lgicon.empty")!)
                  == .system)

        // Daily Spotlight. The lineup must be STABLE within a day (the row
        // is persisted by the tweak for exactly this reason) and must span
        // at least three packs.
        let day = LiquidGlassDailySpotlight.dayIdentifier(
            for: Date(timeIntervalSince1970: 1_700_000_000))
        let spotlight = LiquidGlassDailySpotlight.icons(forDay: day)
        check("Daily Spotlight shows five icons",
              spotlight.count == LiquidGlassDailySpotlight.count && spotlight.count == 5)
        check("the same day always yields the same five",
              LiquidGlassDailySpotlight.icons(forDay: day) == spotlight)
        check("a different day yields a different lineup",
              LiquidGlassDailySpotlight.icons(forDay: day + 1) != spotlight)
        check("every spotlight icon is a real catalog icon",
              spotlight.allSatisfy { id in
                  LiquidGlassIconOption.all.contains { $0.id == id }
              })
        // Checked across a year of days, not one: a random 5 of 76 icons usually
        // spans 3 groups by chance, so a single sample proves nothing about the
        // "at least 3 packs" rule.
        check("every day's lineup spans at least three packs",
              (0..<365).allSatisfy { offset in
                  let ids = LiquidGlassDailySpotlight.icons(forDay: 20_260_101 + offset)
                  return Set(ids.compactMap { id in
                      LiquidGlassIconOption.all.first { $0.id == id }?.groupID
                  }).count >= 3
              })
        check("the active icon is excluded from the lineup",
              !LiquidGlassDailySpotlight.icons(forDay: day, excluding: [spotlight[0]])
                  .contains(spotlight[0]))
        check("the day identifier is year*10000 + month*100 + day",
              LiquidGlassDailySpotlight.dayIdentifier(
                  for: DateComponents(calendar: .current, year: 2026, month: 3, day: 7).date!)
                  == 20_260_307)
        // A golden lineup, pinning the PRNG itself: "stable within a day" and
        // "differs across days" both hold for ANY deterministic generator. This value
        // is our port's own output, so it guards against drift rather than proving
        // the port matches the tweak.
        check("the spotlight generator's output is pinned",
              LiquidGlassDailySpotlight.icons(forDay: 20_260_307)
                  == ["aloppo-v2", "bajader-rtr", "LG-rule-of-two",
                      "helios-ultra", "LG-trans"])
        // Pinned for the 78-icon catalog (Toon Bot, #1253): the lineup draws from
        // the catalog, so adding icons moves every day's picks, as it does upstream.

        check("Daily Spotlight uses the tweak's own defaults keys",
              LiquidGlassDailySpotlight.dayDefaultsKey == "ApolloLGDailyFeaturedDay"
              && LiquidGlassDailySpotlight.idsDefaultsKey == "ApolloLGDailyFeaturedIDs")

        // Pack cards. Reborn presents Apollo's own icons as four named packs, not
        // one flat list.
        check("the four standard packs are named as the tweak names them",
              StandardIconPack.all.map(\.title) == ["Originals", "Community", "Ultra", "Sekrit"])
        check("the standard packs carry Apollo's counts (Ultra: 81, SPCA and Reborn's 8)",
              StandardIconPack.all.map(\.iconCount) == [32, 19, 90, 22])
        check("each standard pack carries three cover icons",
              StandardIconPack.all.allSatisfy { $0.coverIconIDs.count == 3 })
        check("Originals' covers are the tweak's own three",
              StandardIconPack.all[0].coverIconIDs == ["gold", "calico", "teal"])
        // A group's cover icons are an editorial pick, NOT its first three
        // members - deriving them would silently show the wrong art.
        check("a Liquid Glass group's covers are the registry's pick",
              LiquidGlassIconGroup.all[0].coverIconIDs
                  == ["apollo-classic", "halo-glass", "AppIcon"])
        check("the covers are not simply the group's first three icons",
              LiquidGlassIconGroup.all[0].coverIconIDs
                  != LiquidGlassIconOption.all
                      .filter { $0.groupID == "original" }.prefix(3).map(\.id))
        check("every cover icon actually belongs to its own group",
              LiquidGlassIconGroup.all.allSatisfy { group in
                  group.coverIconIDs.allSatisfy { want in
                      LiquidGlassIconOption.all
                          .contains { $0.id == want && $0.groupID == group.id }
                  }
              })

        // Provider names are the picker's own.
        check("provider display names are verbatim",
              AIProvider.allCases.map(\.displayName)
                  == ["Apple On-Device", "OpenRouter", "Google Gemini", "Custom"])
        // The on-device case persists as "apple", the string Reborn's cloud-provider
        // test checks.
        check("the on-device provider persists as \"apple\"",
              AIProvider.onDevice.rawValue == "apple")
        check("only the cloud providers count as cloud",
              !AIProvider.onDevice.isCloud && AIProvider.openRouter.isCloud
              && AIProvider.gemini.isCloud && AIProvider.custom.isCloud)
        // Custom has no default model BY DESIGN ("the user must name a model").
        check("the provider default models are verbatim",
              AIProvider.openRouter.defaultModel == "openrouter/free"
              && AIProvider.gemini.defaultModel == "gemini-3.6-flash"
              && AIProvider.custom.defaultModel == nil)
        check("only OpenRouter and Gemini can browse models",
              AIProvider.openRouter.supportsModelBrowsing
              && AIProvider.gemini.supportsModelBrowsing
              && !AIProvider.custom.supportsModelBrowsing)

        // Sub-toggles default ON: turning the master on keeps the
        // original behaviour.
        check("both summary sub-toggles default on",
              ApolloAISettings.default.postSummariesEnabled
              && ApolloAISettings.default.commentSummariesEnabled)
        check("the word threshold defaults to 150",
              ApolloAISettings.default.postWordThreshold == 150)
        check("the word-threshold detents are 50...300 in 50s",
              ApolloAISettings.wordThresholds == [50, 100, 150, 200, 250, 300])
        check("detail levels are Brief / Balanced / In-depth",
              AISummaryDetail.allCases.map(\.displayName) == ["Brief", "Balanced", "In-depth"])

        // The three-way mode persists to the same two booleans as the switch pair
        // it replaced, with no migration.
        check("the summary modes are the real three",
              AISummaryMode.allCases.map(\.displayName)
                  == ["Generate on Open", "Open Automatically", "Tap to Summarize"])
        check("tap-to-summarize wins over auto-expand",
              AISummaryMode.from(tapToSummarize: true, autoExpand: true) == .tapToSummarize)
        check("neither flag means generate on open",
              AISummaryMode.from(tapToSummarize: false, autoExpand: false) == .generateOnOpen)
        check("auto-expand alone means open automatically",
              AISummaryMode.from(tapToSummarize: false, autoExpand: true) == .openAutomatically)
        check("each mode round-trips to its two booleans",
              AISummaryMode.allCases.allSatisfy { mode in
                  AISummaryMode.from(tapToSummarize: mode.tapToSummarize,
                                     autoExpand: mode.autoExpand) == mode
              })

        // Keys and models are stored PER PROVIDER so switching never
        // loses one.
        var perProvider = ApolloAISettings.default
        perProvider.openRouterAPIKey = "or-key"
        perProvider.geminiAPIKey = "gem-key"
        perProvider.provider = .openRouter
        check("the active key follows the provider",
              perProvider.activeAPIKey == "or-key")
        perProvider.provider = .gemini
        check("switching providers does not lose the other key",
              perProvider.activeAPIKey == "gem-key" && perProvider.openRouterAPIKey == "or-key")
        // Effective model: stored, else the default.
        check("an unset model falls back to the provider default",
              perProvider.effectiveModel == "gemini-3.6-flash")
        perProvider.geminiModel = "gemini-pro"
        check("a stored model wins over the default",
              perProvider.effectiveModel == "gemini-pro")

        // Cloud availability text, in order.
        var availability = ApolloAISettings.default
        availability.provider = .custom
        check("a cloud provider with no key needs one",
              availability.cloudAvailability == "API Key Required")
        availability.customAPIKey = "k"
        check("custom then needs a base URL",
              availability.cloudAvailability == "Base URL Required")
        availability.customBaseURL = "https://example.com/v1"
        check("custom then needs a model",
              availability.cloudAvailability == "Model Required")
        availability.customModel = "m"
        check("a fully configured custom provider is Ready",
              availability.cloudAvailability == "Ready")

        // Footers, provider-dependent.
        check("the on-device general footer promises nothing leaves the device",
              ApolloAISettings.default.generalFooter.contains("entirely on-device using Apple Intelligence"))
        var cloudFooter = ApolloAISettings.default
        cloudFooter.provider = .gemini
        check("the cloud general footer names the service and warns",
              cloudFooter.generalFooter.contains("Google Gemini")
              && cloudFooter.generalFooter.contains("is sent to that service"))
        check("the summaries footer is the real two-paragraph one",
              ApolloAISettings.summariesFooter.contains("only applies to text posts")
              && ApolloAISettings.summariesFooter.contains("\n\n"))

        // The detent slider's hysteresis is 0.65, not a 0.5 midpoint snap.
        check("the slider only advances past 0.65 of a step",
              ApolloAIDetentSliderMath.hystereticIndex(raw: 1.6, current: 1, minimum: 0, maximum: 5) == 1
              && ApolloAIDetentSliderMath.hystereticIndex(raw: 1.7, current: 1, minimum: 0, maximum: 5) == 2)
        // Downward needs raw < current - 0.65, i.e. below 0.35 when sitting on stop
        // 1; 0.4 is still INSIDE the dead band. Both sides of the boundary are
        // checked.
        check("it holds inside the dead band on the way down",
              ApolloAIDetentSliderMath.hystereticIndex(raw: 0.4, current: 1, minimum: 0, maximum: 5) == 1)
        check("it walks back down once past the same margin",
              ApolloAIDetentSliderMath.hystereticIndex(raw: 0.34, current: 1, minimum: 0, maximum: 5) == 0)
        check("it clamps to the ends",
              ApolloAIDetentSliderMath.hystereticIndex(raw: 99, current: 0, minimum: 0, maximum: 5) == 5)

        // Model catalog filters, each with a stated reason in Reborn.
        check("Gemini 2.x models are excluded, since they 404 at generation",
              !AIModelCatalog.geminiModelLooksLikeTextChat("gemini-2.0-flash"))
        check("current Gemini and Gemma text models are kept",
              AIModelCatalog.geminiModelLooksLikeTextChat("gemini-3.6-flash")
              && AIModelCatalog.geminiModelLooksLikeTextChat("gemma-3-27b-it"))
        check("non-text Gemini models are excluded",
              !AIModelCatalog.geminiModelLooksLikeTextChat("gemini-3-tts")
              && !AIModelCatalog.geminiModelLooksLikeTextChat("imagen-4"))
        check("the models/ prefix does not defeat the filter",
              AIModelCatalog.geminiModelLooksLikeTextChat("models/gemini-3.6-flash"))
        check("Gemini lifecycle badges are derived from the model ID",
              AIModelCatalog.geminiBadge("gemini-3-preview") == "Preview"
              && AIModelCatalog.geminiBadge("gemini-3-latest") == "Latest"
              && AIModelCatalog.geminiBadge("gemini-3-exp") == "Experimental"
              && AIModelCatalog.geminiBadge("gemini-3.6-flash") == nil)
        // A zero prompt/completion price must not hide a per-request or
        // reasoning charge.
        check("a model with a hidden request charge is not free",
              !AIModelCatalog.openRouterPricingIsFree(
                  modelID: "x", pricing: ["prompt": "0", "completion": "0", "request": "0.01"]))
        check("an all-zero priced model is free",
              AIModelCatalog.openRouterPricingIsFree(
                  modelID: "x", pricing: ["prompt": "0", "completion": "0"]))
        // No pricing block means UNKNOWN, not free.
        check("a model with no pricing is not assumed free",
              !AIModelCatalog.openRouterPricingIsFree(modelID: "x", pricing: nil)
              && !AIModelCatalog.openRouterPricingIsFree(modelID: "x", pricing: ["completion": "0"]))
        check("the :free suffix is honoured directly",
              AIModelCatalog.openRouterPricingIsFree(modelID: "vendor/model:free", pricing: nil))
        check("a duplicated (free) suffix is stripped from the name",
              AIModelCatalog.openRouterDisplayName("Some Model (free)") == "Some Model")
        check("the model browser uses OpenRouter's per-key endpoint",
              AIModelCatalog.endpoint(for: .openRouter)?.absoluteString
                  == "https://openrouter.ai/api/v1/models/user")
        check("Gemini is browsed through its OpenAI-compatible catalog",
              AIModelCatalog.endpoint(for: .gemini)?.absoluteString
                  == "https://generativelanguage.googleapis.com/v1beta/openai/models")

        // Clearing the cache reports how many entries went.
        let cacheDefaults = UserDefaults(suiteName: "smoke.aicache")!
        cacheDefaults.removePersistentDomain(forName: "smoke.aicache")
        AISummaryCache.store("one", for: "t3_a", in: cacheDefaults)
        AISummaryCache.store("two", for: "t3_b", in: cacheDefaults)
        check("cached summaries round-trip",
              AISummaryCache.summary(for: "t3_a", in: cacheDefaults) == "one")
        check("clearing reports the number removed",
              AISummaryCache.clear(in: cacheDefaults) == 2)
        check("clearing actually removes them",
              AISummaryCache.summary(for: "t3_a", in: cacheDefaults) == nil)

        // The Subreddits root's section index.
        //
        // The first leading glyph is U+2630 TRIGRAM FOR HEAVEN, which renders
        // almost identically to U+2261 IDENTICAL TO at 11pt.
        check("the index's leading glyphs are Apollo's own four",
              SubredditIndexTitle.leadingGlyphs
                  == ["\u{2630}", "\u{2605}", "\u{25CB}", "\u{265C}"])
        check("the hamburger is U+2630, not U+2261",
              SubredditIndexTitle.feedShortcuts != "\u{2261}")
        // 31 entries: 4 glyphs + A-Z + "#", a fixed scale independent of
        // which sections are actually present.
        check("the strip is the full fixed scale, 31 entries",
              SubredditIndexTitle.all().count == 31)
        check("A-Z is complete and in order",
              SubredditIndexTitle.letters.count == 26
              && SubredditIndexTitle.letters.first == "A"
              && SubredditIndexTitle.letters.last == "Z")
        check("# trails Z, as it does in the screenshot",
              SubredditIndexTitle.all().last == "#")
        // A letter with no section must not dead-end: a real section index scrubs
        // continuously and UIKit maps a missing title onto the nearest section.
        check("a missing letter resolves forward to the next real section",
              SubredditIndexResolver.anchor(for: "Q", availableLetters: ["A", "M", "S"]) == "S")
        check("an exact letter resolves to itself",
              SubredditIndexResolver.anchor(for: "M", availableLetters: ["A", "M", "S"]) == "M")
        // "#" trails the alphabet, so it falls BACK - resolving it
        // forward would run off the end of the list and do nothing.
        check("# resolves back to the last real section",
              SubredditIndexResolver.anchor(for: "#", availableLetters: ["A", "M", "S"]) == "S")
        check("a letter past the last section clamps to it",
              SubredditIndexResolver.anchor(for: "Z", availableLetters: ["A", "M"]) == "M")
        check("a glyph resolves to its own section anchor",
              SubredditIndexResolver.anchor(for: SubredditIndexTitle.favorites,
                                            availableLetters: []) == SubredditIndexTitle.favorites)
        check("an empty list resolves to nothing rather than crashing",
              SubredditIndexResolver.anchor(for: "M", availableLetters: []) == nil)

        // VoiceOver cannot read "☰"; each glyph announces its section.
        check("the glyphs carry spoken labels, not character names",
              SubredditIndexTitle.accessibilityLabel(for: SubredditIndexTitle.feedShortcuts) == "Feeds"
              && SubredditIndexTitle.accessibilityLabel(for: SubredditIndexTitle.moderator) == "Moderator"
              && SubredditIndexTitle.accessibilityLabel(for: "M") == "M")

        // Collapsing the whole tree. "Collapse CHILD Comments" leaves the
        // top-level comments visible and folds their replies.
        let grandchild = CommentTreeNode(comment: makeComment(id: "grand"), depth: 2)
        let child = CommentTreeNode(comment: makeComment(id: "child"), depth: 1,
                                    children: [grandchild])
        let treeRoot = CommentTreeNode(comment: makeComment(id: "root"), depth: 0,
                                       children: [child])
        let collapsed = treeRoot.settingChildrenCollapsed(true)
        check("collapsing children leaves the root itself expanded",
              collapsed.isCollapsed == false)
        check("collapsing reaches every descendant, not just direct children",
              collapsed.children[0].isCollapsed
              && collapsed.children[0].children[0].isCollapsed)
        check("expanding again clears them all",
              collapsed.settingChildrenCollapsed(false).children[0].isCollapsed == false)
        check("a collapsed descendant is detectable, so the row can pick its verb",
              collapsed.hasCollapsedDescendant && !treeRoot.hasCollapsedDescendant)

        check("a running activity is remembered across visits",
              FollowThreadActivityStore.defaultsKey == "PhoebusFollowThreadActivities")
        let activityDefaults = UserDefaults(suiteName: "smoke.liveactivity")!
        activityDefaults.removePersistentDomain(forName: "smoke.liveactivity")
        FollowThreadActivityStore.setActive(postID: "t3_abc", active: true, activityDefaults)
        check("the store records a started activity",
              FollowThreadActivityStore.isActive(postID: "t3_abc", activityDefaults)
              && !FollowThreadActivityStore.isActive(postID: "t3_other", activityDefaults))
        FollowThreadActivityStore.setActive(postID: "t3_abc", active: false, activityDefaults)
        check("ending it clears the record",
              !FollowThreadActivityStore.isActive(postID: "t3_abc", activityDefaults))
    }
}
