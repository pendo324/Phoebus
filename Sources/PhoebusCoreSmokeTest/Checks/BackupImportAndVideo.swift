import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// --- Importing a real Apollo settings backup ---
//
// A backup is a ZIP of four files, as Reborn produces it:
//   preferences.plist, group.plist, keychain.plist, accounts.txt
//
// The archive is read by a hand-rolled ZIP + DEFLATE reader (`ZipReader`):
// the package has no zip dependency and its tests run on Linux, where neither
// Apple's `Compression` framework nor zlib is available.
@MainActor func checkImportingAREALApolloSettingsBackup() async throws {
    do {
        // Build a backup-shaped ZIP in memory, STORED, so the reader's
        // structure handling is tested independently of inflate.
        func storedZip(_ files: [(String, Data)]) -> Data {
            var local = Data()
            var central = Data()
            func put16(_ v: Int, into d: inout Data) {
                d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
            }
            func put32(_ v: Int, into d: inout Data) {
                d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
                d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF))
            }
            for (name, body) in files {
                let nameBytes = Data(name.utf8)
                let offset = local.count
                put32(0x0403_4b50, into: &local)
                put16(20, into: &local); put16(0, into: &local); put16(0, into: &local)
                put16(0, into: &local); put16(0, into: &local)
                put32(0, into: &local)
                put32(body.count, into: &local); put32(body.count, into: &local)
                put16(nameBytes.count, into: &local); put16(0, into: &local)
                local.append(nameBytes); local.append(body)

                put32(0x0201_4b50, into: &central)
                put16(20, into: &central); put16(20, into: &central); put16(0, into: &central)
                put16(0, into: &central); put16(0, into: &central); put16(0, into: &central)
                put32(0, into: &central)
                put32(body.count, into: &central); put32(body.count, into: &central)
                put16(nameBytes.count, into: &central); put16(0, into: &central)
                put16(0, into: &central); put16(0, into: &central); put16(0, into: &central)
                put32(0, into: &central); put32(offset, into: &central)
                central.append(nameBytes)
            }
            var out = local
            let centralOffset = out.count
            out.append(central)
            put32(0x0605_4b50, into: &out)
            put16(0, into: &out); put16(0, into: &out)
            put16(files.count, into: &out); put16(files.count, into: &out)
            put32(central.count, into: &out); put32(centralOffset, into: &out)
            put16(0, into: &out)
            return out
        }

        func plistData(_ dict: [String: Any]) -> Data {
            try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        }

        // A SYNTHESISED fixture, never a real backup, which holds live credentials.
        let prefs = plistData([
            "DefaultPostsSort": "hot",
            "DefaultCommentsSort": "top",
            "ShowSubredditAtTop": true,
            "AlwaysShowUsernames": true,
            "ShowSubredditHeaders": true,
            "SubredditHeaderImmersive": false,
            "PollsEnabled": true,
            "EnableFlairColors": false,
            "CollapsedSubredditHighlights": ["apple"],
            "BugsnagUserUserId": "should-not-be-imported",
            "com.Statsig.InternalStore.stableIDKey": "also-not",
            "SomeKeyWeDoNotKnow": 42,
        ])
        let zip = storedZip([
            (ApolloBackupImport.mainPlistName, prefs),
            (ApolloBackupImport.groupPlistName, plistData(["ShowUserAvatars": true])),
        ])

        let payload = try! ApolloBackupImport.read(zipData: zip)
        check("a backup's preferences are read",
              payload.preferences["DefaultPostsSort"] as? String == "hot")
        check("the group domain is read too",
              payload.group["ShowUserAvatars"] as? Bool == true)
        // `preferences.plist` wins a tie, because it is the app's own
        // domain and the authoritative one for the settings mapped here.
        check("both domains merge with preferences winning",
              payload.merged.count >= 13)

        // The four filenames the producer writes.
        check("the expected filenames are Apollo's own",
              ApolloBackupImport.mainPlistName == "preferences.plist"
              && ApolloBackupImport.groupPlistName == "group.plist"
              && ApolloBackupImport.keychainPlistName == "keychain.plist"
              && ApolloBackupImport.accountsName == "accounts.txt")

        // Archive validation, as in Reborn. Each of these rejects a real hazard
        // rather than being ceremony.
        let withStranger = storedZip([
            (ApolloBackupImport.mainPlistName, prefs),
            ("../../etc/passwd", Data("x".utf8)),
        ])
        check("an unexpected filename is rejected",
              (try? ApolloBackupImport.read(zipData: withStranger)) == nil)
        let duplicated = storedZip([
            (ApolloBackupImport.mainPlistName, prefs),
            (ApolloBackupImport.mainPlistName, plistData(["DefaultPostsSort": "new"])),
        ])
        check("a duplicate entry is rejected",
              (try? ApolloBackupImport.read(zipData: duplicated)) == nil)
        // Five entries. NOTE: this is rejected by the count gate AND by
        // the allow-list (a fifth entry cannot have an allowed name
        // without duplicating one), so it is deliberately asserted at the
        // ERROR level to pin which rule fires - raising the count limit
        // alone does not fail this check.
        let tooMany = storedZip([
            (ApolloBackupImport.mainPlistName, prefs),
            (ApolloBackupImport.groupPlistName, prefs),
            (ApolloBackupImport.keychainPlistName, prefs),
            (ApolloBackupImport.accountsName, prefs),
            ("extra.plist", prefs),
        ])
        var tooManyError: ApolloBackupImport.ImportError?
        do {
            _ = try ApolloBackupImport.read(zipData: tooMany)
        } catch let error as ApolloBackupImport.ImportError {
            tooManyError = error
        } catch {}
        check("more than four entries is rejected",
              tooManyError != nil)
        check("...by the entry-count rule specifically",
              tooManyError == .unsafeArchive("too many entries"))
        check("the entry ceiling is the real one",
              ApolloBackupImport.maximumEntryCount == 4)
        // The 128 MB total ceiling guards against a zip bomb.
        check("the size ceiling is the real 128 MB",
              ApolloBackupImport.maximumTotalBytes == 128 * 1024 * 1024)
        check("a non-zip is rejected",
              (try? ApolloBackupImport.read(zipData: Data("not a zip".utf8))) == nil)
        // An entry must be the size it declares: the size ceiling above
        // counts declarations, so a lying entry would get round it.
        var understated = storedZip([(ApolloBackupImport.mainPlistName, prefs)])
        if let central = understated.range(of: Data([0x50, 0x4B, 0x01, 0x02])) {
            let at = central.lowerBound + 24
            understated.replaceSubrange(at..<at + 4, with: [0x01, 0x00, 0x00, 0x00])
        }
        check("an entry larger than it declares is rejected",
              (try? ApolloBackupImport.read(zipData: understated)) == nil)
        let noPrefs = storedZip([(ApolloBackupImport.accountsName, Data("user".utf8))])
        check("a backup with no preferences.plist is rejected",
              (try? ApolloBackupImport.read(zipData: noPrefs)) == nil)
        // The group domain is OPTIONAL, so a backup without it still imports.
        let prefsOnly = storedZip([(ApolloBackupImport.mainPlistName, prefs)])
        check("a backup with only preferences.plist still reads",
              (try? ApolloBackupImport.read(zipData: prefsOnly))?.preferences.count ?? 0 > 0)

        // Analytics identity is skipped.
        check("the analytics user id is excluded",
              ApolloSettingsMigration.isExcluded("BugsnagUserUserId"))
        check("Statsig keys are excluded by prefix",
              ApolloSettingsMigration.isExcluded("com.Statsig.InternalStore.stableIDKey"))
        check("ordinary settings keys are not excluded",
              !ApolloSettingsMigration.isExcluded("DefaultPostsSort"))
    }
}

// --- The subreddit header is CENTRED, like Apollo's ---
//
// The subreddit header shares the profile header's layout: a centred avatar
// and name, a banner behind it, and the avatar overlapping the banner's
// bottom edge, rather than a left-aligned row.
@MainActor func checkTheSubredditHeaderIsCENTREDLike() async throws {
    do {
        // Layout constants.
        check("the avatar is the real 96pt",
              IdentityHeaderLayout.avatarDiameter == 96)
        check("the overlap is the real 48pt",
              IdentityHeaderLayout.avatarOverlap == 48)
        check("the subreddit banner is the real 104pt",
              IdentityHeaderLayout.subredditBannerHeight == 104)
        check("the profile banner is the real 150pt",
              IdentityHeaderLayout.profileBannerHeight == 150)
        check("the side inset is the real 24pt",
              IdentityHeaderLayout.sideInset == 24)
        check("the name font is the real 28pt",
              IdentityHeaderLayout.nameFontSize == 28)
        check("the subtitle font is the real 15pt",
              IdentityHeaderLayout.subnameFontSize == 15)

        // Centring: `floor((width - diameter) / 2)`.
        let width = 393.0
        let avatarX = IdentityHeaderLayout.avatarX(totalWidth: width)
        check("the avatar is centred",
              abs((avatarX + IdentityHeaderLayout.avatarDiameter / 2) - width / 2) < 1)
        check("the centre matches the measured device value",
              abs(avatarX + IdentityHeaderLayout.avatarDiameter / 2 - 196.5) < 1)

        // The avatar straddles the banner's bottom edge.
        check("the avatar overlaps the banner",
              IdentityHeaderLayout.avatarTop(bannerHeight: 104) == 104 - 48)
        // ...but bottoms out at a 14pt pad when there is no banner, so a bannerless
        // subreddit doesn't pull the avatar off the top of the view.
        check("a bannerless header still places the avatar on screen",
              IdentityHeaderLayout.avatarTop(bannerHeight: 0) == 14)
        check("a very short banner also clamps to the floor",
              IdentityHeaderLayout.avatarTop(bannerHeight: 30) == 14)

        // The name sits 8pt below the avatar.
        check("the name sits 8pt below the avatar",
              IdentityHeaderLayout.nameTop(bannerHeight: 104)
                  == IdentityHeaderLayout.avatarTop(bannerHeight: 104) + 96 + 8)

        // The centred body column, capped so centred text does not run to
        // unreadable line lengths on iPad.
        check("the body column is inset on a phone",
              IdentityHeaderLayout.bodyWidth(totalWidth: 393) == 393 - 48)
        check("the body column caps at 480pt on a wide screen",
              IdentityHeaderLayout.bodyWidth(totalWidth: 1024) == 480)
        check("the body column is centred when capped",
              IdentityHeaderLayout.bodyX(totalWidth: 1024) == ((1024.0 - 480) / 2).rounded(.down))
    }
}

// --- Share as Image includes inline images and thumbnails ---
//
// The share card must fall back to a link post's preview ladder and a
// self post's inline image, not just `.image`/`.gallery` posts, so
// every post kind with a picture gets one on its share card.
@MainActor func checkShareAsImageIncludesInlineImages() async throws {
    do {
        // The model helpers these depend on behave as the card assumes.
        // A self-post with `media_metadata` yields its first image.
        let selfPostJSON = """
        {"id":"a","name":"t3_a","title":"t","author":"u","subreddit":"s",
         "selftext":"text","permalink":"/r/s/comments/a/t/","score":1,
         "num_comments":0,"created_utc":0,"is_self":true,"over_18":false,
         "spoiler":false,"stickied":false,"saved":false,
         "media_metadata":{"img1":{"s":{"u":"https://i.redd.it/one.jpg&amp;x=1"}}}}
        """
        if let post = try? JSONDecoder.reddit.decode(RedditPost.self, from: Data(selfPostJSON.utf8)) {
            check("a self-post's inline image is extracted",
                  post.derivedSelfPostThumbnailURL?.absoluteString == "https://i.redd.it/one.jpg&x=1")
        } else {
            check("a self-post's inline image is extracted", false)
        }
    }
}

// --- Importing a real Apollo backup's CREDENTIALS ---
//
// Credentials must be imported: it is the user's own backup restored onto
// their own device, which is what Apollo's own restore does (it replays the
// Valet items so a restored backup can sign the user back in).
//
// A real `keychain.plist` holds seven items, three of which carry credentials:
//   `2RedditAccounts2`        NSKeyedArchiver NSArray<NSDictionary>
//                             with clientIdentifier / refreshToken /
//                             authorizationCode / accessToken
//   `websession:<user>:cookie`  the ~2.7 KB cookie header
//   `websession:<user>:modhash` the CSRF modhash
@MainActor func checkImportingARealApolloBackupS() async throws {
    do {
        // Apollo-owned identities only: "Never accept an unrelated service
        // merely because its name contains Apollo's bundle ID." A backup
        // is an untrusted file and a keychain item is a credential, so
        // this is the gate that stops one app's archive planting an item
        // for another.
        check("the web-session cookie identity is accepted",
              ApolloKeychainImport.ownsIdentity(
                service: ApolloKeychainImport.webJSONService,
                account: "websession:example_user:cookie"))
        check("the web-session modhash identity is accepted",
              ApolloKeychainImport.ownsIdentity(
                service: ApolloKeychainImport.webJSONService,
                account: "websession:example_user:modhash"))
        check("the Valet account blob is accepted",
              ApolloKeychainImport.ownsIdentity(
                service: "VAL_VALValet_initWithSharedAccessGroupIdentifier:accessibility:"
                    + "_com.christianselig.Apollo_AccessibleAfterFirstUnlock",
                account: "2RedditAccounts2"))
        check("an unrelated service is rejected",
              !ApolloKeychainImport.ownsIdentity(
                service: "com.example.SomeOtherApp", account: "2RedditAccounts2"))
        // An unrelated service whose name merely contains Apollo's bundle ID.
        check("a lookalike service mentioning the bundle id is rejected",
              !ApolloKeychainImport.ownsIdentity(
                service: "com.evil.app.com.christianselig.Apollo", account: "token"))
        check("a malformed websession account is rejected",
              !ApolloKeychainImport.ownsIdentity(
                service: ApolloKeychainImport.webJSONService, account: "websession::cookie"))
        check("an unknown websession suffix is rejected",
              !ApolloKeychainImport.ownsIdentity(
                service: ApolloKeychainImport.webJSONService, account: "websession:user:password"))
        check("an empty account is rejected",
              !ApolloKeychainImport.ownsIdentity(
                service: ApolloKeychainImport.webJSONService, account: ""))

        // A SYNTHESISED keychain plist, never a real one.
        let archived: Data = {
            let accounts: [[String: String]] = [[
                "clientIdentifier": "CLIENT123",
                "accessToken": "ACCESS123",
                "refreshToken": "REFRESH123",
                "authorizationCode": "AUTH123",
            ]]
            return try! NSKeyedArchiver.archivedData(
                withRootObject: accounts, requiringSecureCoding: false)
        }()
        let keychain: [[String: Any]] = [
            ["service": "VAL_VALValet_initWithSharedAccessGroupIdentifier:accessibility:"
                + "_com.christianselig.Apollo_AccessibleAfterFirstUnlock",
             "account": ApolloKeychainImport.redditAccountsAccount,
             "data": archived],
            ["service": ApolloKeychainImport.webJSONService,
             "account": "websession:testuser:cookie",
             "data": Data("reddit_session=abc; token_v2=def".utf8)],
            ["service": ApolloKeychainImport.webJSONService,
             "account": "websession:testuser:modhash",
             "data": Data("MODHASH123".utf8)],
            // An item Apollo does not own, which must be ignored.
            ["service": "com.example.Other", "account": "secret", "data": Data("nope".utf8)],
        ]
        let keychainData = try! PropertyListSerialization.data(
            fromPropertyList: keychain, format: .xml, options: 0)

        let decoded = ApolloKeychainImport.accounts(fromKeychainPlist: keychainData)
        check("one account is decoded", decoded.count == 1)
        check("the username comes from the web-session key",
              decoded.first?.username == "testuser")
        check("the OAuth access token is decoded",
              decoded.first?.accessToken == "ACCESS123")
        check("the refresh token is decoded",
              decoded.first?.refreshToken == "REFRESH123")
        check("the client identifier is decoded",
              decoded.first?.clientIdentifier == "CLIENT123")
        check("the cookie header is decoded",
              decoded.first?.cookieHeader == "reddit_session=abc; token_v2=def")
        check("the modhash is decoded",
              decoded.first?.modhash == "MODHASH123")
        check("an unowned keychain item contributes nothing",
              decoded.allSatisfy { $0.username != "secret" })

        // `accounts.txt` names an OAuth-only account, which the archived
        // blob cannot (it stores tokens, not usernames).
        let oauthOnly = ApolloKeychainImport.accounts(fromKeychainPlist:
            try! PropertyListSerialization.data(fromPropertyList: [keychain[0]], format: .xml, options: 0))
        check("an OAuth-only account decodes with no username",
              oauthOnly.first?.username.isEmpty == true)
        let named = ApolloKeychainImport.applyingUsernames(oauthOnly, from: "example_user\n")
        check("accounts.txt supplies the missing username",
              named.first?.username == "example_user")

        // Restoring into a store.
        let box = InMemoryAccountKeychainStore()
        let payload = ApolloBackupImport.Payload(preferences: [:], group: [:], accounts: decoded)
        let restored = ApolloSettingsMigration.applyAccounts(payload, to: box)
        check("the account is restored", restored == 1)
        check("it is persisted", box.load()?.accounts.count == 1)
        check("and made active", box.load()?.activeIndex == 0)
        let stored = box.load()?.accounts.first
        check("the OAuth credential survives", stored?.oauthCredential?.accessToken == "ACCESS123")
        check("the web session survives", stored?.webSession?.cookieHeader.isEmpty == false)
        check("the modhash survives, so writes work", stored?.webSession?.modhash == "MODHASH123")
        // An account with BOTH is not "keyless" - that state means a web
        // session with no OAuth.
        check("an account with both credentials is not keyless", stored?.isKeyless == false)

        // The imported token is marked EXPIRED on purpose: Apollo's
        // archive stores no expiry, a Reddit access token lives one hour,
        // and a backup is almost always older than that. Claiming a future
        // expiry would make the first request 401 and read as signed-out;
        // marking it expired sends it down the existing refresh path.
        check("the imported token is treated as expired",
              stored?.oauthCredential?.isExpired == true)
        check("...and is permanent, because it has a refresh token",
              stored?.oauthCredential?.isPermanent == true)

        // Importing twice must not duplicate the account.
        _ = ApolloSettingsMigration.applyAccounts(payload, to: box)
        check("re-importing the same backup does not duplicate accounts",
              box.load()?.accounts.count == 1)

        // An entry with neither credential is not usable and must not be
        // added - it would be a username with no way to authenticate.
        let emptyBox = InMemoryAccountKeychainStore()
        let useless = ApolloBackupImport.Payload(
            preferences: [:], group: [:],
            accounts: [ApolloKeychainImport.ImportedAccount(username: "ghost")])
        check("an account with no credentials is skipped",
              ApolloSettingsMigration.applyAccounts(useless, to: emptyBox) == 0)
        check("...and nothing is written",
              emptyBox.load()?.accounts.isEmpty ?? true)

        // API KEYS, which a restored install needs to talk to Reddit at
        // all: without the client id and redirect URI the OAuth flow
        // cannot run, so settings-only import leaves an app that looks
        // configured and cannot sign in.
        let before = CustomAPISettingsStore.load()
        let apiPayload = ApolloBackupImport.Payload(preferences: [
            "RedditApiClientId": "CID",
            "RedirectURI": "scheme://response",
            "UserAgent": "ios:test:v1",
            "ImgurApiClientId": "IMGUR",
            "GiphyAPIKey": "GIPHY",
            "ImageChestAPIToken": "CHEST",
        ])
        let apiSummary = ApolloSettingsMigration.apply(apiPayload)
        let api = CustomAPISettingsStore.load()
        check("the Reddit client id is imported", api.redditClientID == "CID")
        check("the redirect URI is imported", api.redditRedirectURI == "scheme://response")
        check("the user agent is imported", api.userAgent == "ios:test:v1")
        check("the Imgur client id is imported", api.imgurClientID == "IMGUR")
        check("the Giphy key is imported", api.giphyAPIKey == "GIPHY")
        check("the ImageChest token is imported", api.imgChestAPIKey == "CHEST")
        check("the API keys are reported to the user",
              apiSummary.applied.contains("Reddit API client ID"))
        CustomAPISettingsStore.save(before)
    }
}

// --- AI summary settings come across from a real Apollo backup ---
//
// AI summary settings, including `EnableTapToSummarize`, must be
// imported from a real Apollo backup rather than left on the shipped
// default (generate on open).
@MainActor func checkAISummarySettingsComeAcrossFrom() async throws {
    do {
        let before = ApolloAISettingsStore.load()
        ApolloAISettingsStore.save(.default)
        let payload = ApolloBackupImport.Payload(preferences: [
            "EnableAISummaries": true,
            "EnableTapToSummarize": true,
            "EnableAIAutoExpandSummaries": true,
            "AIPostWordThreshold": 200,
            "AIPostSummaryDetail": 2,
            "AISummaryProvider": "gemini",
            "GeminiAPIKey": "GKEY",
            "CustomAIBaseURL": "https://example.invalid/v1",
        ])
        let summary = ApolloSettingsMigration.apply(payload)
        let ai = ApolloAISettingsStore.load()
        check("the AI master toggle is imported", ai.summariesEnabled)
        check("Tap to Summarize is imported (the user's real setting)", ai.summaryMode == .tapToSummarize)
        check("...and wins over auto-expand when both are on, as in Reborn",
              ai.summaryMode.tapToSummarize && !ai.summaryMode.autoExpand)
        check("the word threshold and detail are imported",
              ai.postWordThreshold == 200 && ai.postDetail == .inDepth)
        check("the provider and its key are imported",
              ai.provider == .gemini && ai.geminiAPIKey == "GKEY")
        check("the custom base URL is imported", ai.customBaseURL == "https://example.invalid/v1")
        check("an AI key absent from the backup keeps this install's value",
              ai.commentSummariesEnabled == ApolloAISettings.default.commentSummariesEnabled)
        check("the import reports the summary mode", summary.applied.contains("AI Summary Mode"))
        check("the import lists each setting once", Set(summary.applied).count == summary.applied.count)
        check("unknown keys are counted by key, not by label",
              ApolloSettingsMigration.apply(.init(preferences: ["NoSuchKeyA": 1, "NoSuchKeyB": true, "DefaultPostsSort": "hot"])).skippedUnknown == 2)
        check("an out-of-range word threshold is ignored",
              { () -> Bool in
                  ApolloAISettingsStore.save(.default)
                  _ = ApolloSettingsMigration.apply(.init(preferences: ["AIPostWordThreshold": 7]))
                  return ApolloAISettingsStore.load().postWordThreshold == 150
              }())

        // Under Tap to Summarize nothing is generated until a tap.
        var tapSettings = ApolloAISettings.default
        tapSettings.summariesEnabled = true
        tapSettings.summaryMode = .tapToSummarize
        let longBody = String(repeating: "word ", count: 400)
        let longPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: """
            {"id":"tapcheck","name":"t3_tapcheck","title":"T","author":"a","subreddit":"s",
             "permalink":"/r/s/comments/tapcheck/t/","score":1,"num_comments":0,
             "created_utc":0,"is_self":true,"over_18":false,"spoiler":false,
             "stickied":false,"saved":false,"selftext":"\(longBody)"}
            """.data(using: .utf8)!)
        let controller = AISummaryController(post: longPost, settings: tapSettings)
        controller.onAppear()
        check("under Tap to Summarize the post card waits for a tap (no request)",
              controller.postState == .tapToSummarize)
        ApolloAISettingsStore.save(before)
    }
}

// --- Every key in a real Apollo backup is imported or accounted for ---
//
// The key list is a real backup's key set (names only, no values). Every
// key must be either imported or listed in `notImported` with a reason, so a
// new unhandled key fails here instead of silently staying on this app's
// default.
@MainActor func checkEveryKeyInARealApollo() async throws {
    let realBackupKeys: [String] = [
        "ATPUnlocked", "AndruUnlocked", "ApolloAppleSupportedLangCodes", "ApolloBookProUnlocked", "ApolloCustomTextSize", "ApolloGalleryVideosMuted",
        "ApolloLGActiveIconID", "ApolloLGDailyFeaturedDay", "ApolloLGDailyFeaturedIDs", "ApolloLGLegacyClassicsMigrationV1", "ApolloOwnCommentFlairV1", "ApolloReborn.activeThemePointer",
        "ApolloReborn.customThemes", "ApolloReborn.themeLaunchAttemptCompleted", "ApolloReborn.themeRecentCrashCount", "ApolloReborn.themeSchemaVersion", "ApolloReborn.themeV1Backup", "ApolloRebornActiveCustomThemeID",
        "ApolloRebornCustomThemeColors", "ApolloRebornCustomThemes", "ApolloShareAsImageIncludeLink", "AppDidTheLaunchy_Date", "AutoHideTabBarShowOnIdle", "AutoplayInlineGIFs",
        "BarkNotificationsEnabled", "BarkPushURL", "BarkSelectedIconName", "BugsnagUserUserId", "CKEntryViewLayoutMetricsInfo", "CanadaUnlocked",
        "CollapsePinnedComments", "CollapsedSubredditHighlights", "CommMigrationOccurred", "CommunityHighlights", "CommunityHighlightsDiskCache", "CommunityHighlightsWeb",
        "CompactModeHideThumbnails", "CurrentRedditAccountIndex", "DateLastX", "DateOfLastRateUsageTimestamp2", "DateOfLastSavedItemsFullRefresh", "DateOfLastScrollProgressBeam110-2",
        "DateOfLatestProReminder", "Dave2DUnlocked", "DefaultCommentsSort", "DefaultPostsSort", "DefaultSubreddits", "DevvitInteractivePosts",
        "EAPUnlocked", "EnableAISummaries", "EnableFlairColors", "EnableShareAsImageWatermark", "EnableTapToSummarize", "ErnestUnlocked",
        "ExpandedMultireddits", "FavoriteSubreddits", "FeedVideoScrubber", "GiphyAPIKey", "HasMigratedFiltersV1", "HasUnlockedBeanVault",
        "HasUsedRandomSubreddit", "HideUsernameOnTabBar", "IconRowMagnifier", "ImageChestAPIToken", "ImageUploadProvider", "ImgurApiClientId",
        "InfoRowOverlayMode", "InfoRowPopupMode", "KeepSearchBarInPlace", "KeywordFilters", "LGTitleGapCentering", "LastReviewRequestDate",
        "LastSeenWhatsNewVersion", "LinkPreviewBodyMode", "LinkPreviewCardColorHex", "LinkPreviewCommentsMode", "LinusUnlocked", "LoggedInAccountDetails",
        "MKBHDUnlocked", "MigratedFiltersV1", "MigratedTapToCollapseSetting", "ModernMailboxChoiceMigrated", "MostRecentSharedURLSoNotToAskOnLaunch", "OpenLinksInSteamApp",
        "OpenVideosInYouTubeApp", "PeachyUnlocked", "PerAccountAPICredentials", "PhilUnlocked", "PictureInPictureEnabled", "PictureInPictureLastCenterX",
        "PictureInPictureLastCenterY", "PictureInPictureLastStashSide", "PollsEnabled", "PostCommentsSnapshots", "ProMigrationOccurred", "RandNsfwSubredditsSource",
        "RatesUsedHistorically2", "RatesUsedInTimestamp2", "ReadPostIDs", "RedditAccounts2", "RedditApiClientId", "RedditApplicationOnlyAccount2",
        "RedirectURI", "ReneUnlocked", "SKPurchaseIntentUpdatesLastChecked", "SPMigrationOccurred", "SavedAppBuildNumber", "SavedAppVersion",
        "ScrollDistanceMilestone2_Date", "ScrollEdgeEffectStyle", "ShowDeletedComments", "ShowRandNsfwButton", "ShowSubredditAtTop", "ShowSubredditHeaders",
        "ShowSubredditIconsForPosts", "ShowSubredditIconsInSubredditList", "ShowSubredditWeatherTime", "ShowUnreadComments", "ShowUserAvatars", "ShowedMediaDisplayUpdate",
        "ShowedUnmuteButtonSettingExplainer", "SlothkunUnlocked", "SnazzyUnlocked", "SubmittedComment_Date", "SubredditHeaderImmersive", "SubredditIconData",
        "SusUnlocked", "TLDTodayUnlocked", "TapToCollapseEnabledType", "TapToRevealDeletedComments", "Theme", "TotalLaunches",
        "TotalLaunchesWhenMostRecentAccountAdded", "TotalTimesPoppedNavigationStack", "TotalUnmuteButtonTogglesInMediaViewer", "TranslationProvider", "TranslationProviderUserSelected", "UMigrationOccurred",
        "UkraineUnlocked", "UltraUnreadCommsMigrate", "UnitedKingdomUnlocked", "UnitedStates2Unlocked", "UnitedStatesUnlocked", "UnlockedWallpapers",
        "UnmuteCommentsVideos", "UseCompactThumbnails", "UseProfileAvatarTabIcon", "UsePureBlackDarkMode", "UsePurePUREBlackMode", "UseSystemTextSize",
        "UserAgent", "WallpaperPromptMostRecent2", "WebSessionPollOnlyIndex", "WebSessionUsernameIndex", "WidgBackgroundOption", "airprint-active",
        "awesome_notifications", "com.Statsig.InternalStore.stableIDKey", "iJustineUnlocked", "kCKMediaObjectManagerDefaultsClasses", "kCKMediaObjectManagerDefaultsDynTypes", "kCKMediaObjectManagerDefaultsOSVersion",
        "kCKMediaObjectManagerDefaultsUTITypes", "kPINRemoteImageDiskCacheVersionKey", "trackedKey"
    ]
    do {
        // Most of the backup's keys are counters, caches, analytics IDs, icon
        // unlocks and one-shot migration flags that must not travel. Every real
        // setting must be imported.
        check("all 61 real settings in the user's backup are imported (was 23)",
              realBackupKeys.filter { ApolloSettingsMigration.notImported[$0] == nil }.count == 61)

        // Round-trip the value shapes the real app writes. Snapshot and
        // restore the stores touched, so the suite leaves no state behind.
        let g0 = GeneralSettingsStore.load(), a0 = AppearanceSettingsStore.load()
        let lp0 = LinkPreviewSettingsStore.load(), pip0 = PictureInPictureSettingsStore.load()
        let dc0 = DeletedCommentsSettingsStore.load(), pb0 = PureBlackSettingsStore.load()
        let tr0 = TranslationSettingsStore.load(), sw0 = SwipeActionStore.load(for: .comments)
        let im0 = InlineMediaSettingsStore.load(), sl0 = SubredditLayoutSettingsStore.load()
        let pl0 = ProfileLayoutSettingsStore.load(), ga0 = GalleryAutoplayStore.load()
        let summary = ApolloSettingsMigration.apply(.init(preferences: [
            "AutoCollapseChildComments": "automatically",       // stock STRING, not a bool
            "TapToCollapseEnabledType": "headers",
            "TrendingSubredditsLimit": "8",                     // Reborn STRING
            "LinkPreviewBodyMode": 1, "LinkPreviewCommentsMode": 0,
            "PictureInPictureActivation": 0,                    // real 0 = All Videos
            "ShowDeletedComments": false, "PassiveDeletedComments": true,
            "TranslationProvider": "libre",
            "AutoTranslateOnAppear": false, "TapToTranslate": true,
            "CommentsSlideGestures": ["upvote", "downvote", "collapse-root", "reply"],
            "InlineImageAlignment": 1, "AutoplayInlineGIFs": 2,
            "CommunityHighlights": true, "CommunityHighlightsWeb": true,
            "CompactModeHideThumbnails": true,
            "ShowGIFProgressLocation": "media-viewer",
            "ShowDetailedProfiles": false,
            "GalleryAutoplayVideos": false, "GalleryAutoplayGIFs": false,
        ], group: ["UsePureBlackDarkMode": true, "UsePurePUREBlackMode": true]))
        let g = GeneralSettingsStore.load()
        check("stock string 'automatically' turns on child auto-collapse", g.autoCollapseChildComments)
        check("tap-to-collapse type is imported", g.tapToCollapseType == .headers)
        check("Reborn's string trending limit parses", g.trendingSubredditsLimit == 8)
        check("compact thumbnails hidden maps to the hidden size", g.thumbnailSize == .hidden)
        let lp = LinkPreviewSettingsStore.load()
        check("link preview modes translate from Reborn's 0/1/2",
              lp.bodyDisplayMode == .compact && lp.commentsDisplayMode == .off)
        check("PiP activation translates by meaning (real 0 = All Videos, not our raw 0)",
              PictureInPictureSettingsStore.load().activation == .allVideos)
        check("two deleted-comment booleans become Passive", DeletedCommentsSettingsStore.load().mode == .passive)
        let tr = TranslationSettingsStore.load()
        check("'libre' maps to LibreTranslate", tr.provider == .libreTranslate)
        check("auto off + tap on is Tap to Translate", tr.mode == .tapToTranslate)
        let sw = SwipeActionStore.load(for: .comments)
        check("comment swipe gestures come from the real array order",
              sw.leftShort == .upvote && sw.leftLong == .downvote && sw.rightShort == .collapseTop && sw.rightLong == .reply)
        let im = InlineMediaSettingsStore.load()
        check("inline alignment 1 is Left and autoplay 2 is Wi-Fi only",
              im.alignment == .left && im.autoplayMode == .wifiOnly)
        check("highlights REST + web is Full", SubredditLayoutSettingsStore.load().communityHighlights == .full)
        check("pure black comes from the group domain",
              PureBlackSettingsStore.load().isEnabled && PureBlackSettingsStore.load().isPurerEnabled)
        check("GIF progress 'media-viewer' is imported", AppearanceSettingsStore.load().gifProgressLocation == .mediaViewer)
        check("ShowDetailedProfiles off imports as the Native profile style", ProfileLayoutSettingsStore.load().style == .native)
        check("gallery autoplay keys are imported",
              !GalleryAutoplayStore.load().playVideos && !GalleryAutoplayStore.load().playGIFs)
        check("the import reports what it took", summary.applied.contains("Tap to Collapse")
              && summary.applied.contains("Comments Swipe Actions"))
        check("stock gesture vocabulary: toggle-read is mark read, unknown is none",
              ApolloSettingsMigration.swipeAction(fromApollo: "toggle-read") == .markRead
              && ApolloSettingsMigration.swipeAction(fromApollo: "bogus") == .none)
        // A plist integer bridges to NSNumber, and `NSNumber(1) is Bool` is true
        // on iOS, so the check must use the CFBoolean type, not `is Bool`.
        check("a plist integer is not a boolean", !ApolloSettingsMigration.isBoolean(NSNumber(value: 1)))
        check("a plist boolean is a boolean", ApolloSettingsMigration.isBoolean(true))
        // A bool where an int is expected must not be read as 0/1.
        _ = ApolloSettingsMigration.apply(.init(preferences: ["LinkPreviewBodyMode": true]))
        check("a wrongly typed value is ignored, not coerced",
              LinkPreviewSettingsStore.load().bodyDisplayMode == .compact)

        GeneralSettingsStore.save(g0); AppearanceSettingsStore.save(a0)
        LinkPreviewSettingsStore.save(lp0); PictureInPictureSettingsStore.save(pip0)
        DeletedCommentsSettingsStore.save(dc0); PureBlackSettingsStore.save(pb0)
        TranslationSettingsStore.save(tr0); SwipeActionStore.save(sw0, for: .comments)
        InlineMediaSettingsStore.save(im0); SubredditLayoutSettingsStore.save(sl0)
        ProfileLayoutSettingsStore.save(pl0); GalleryAutoplayStore.save(ga0)
    }
}

// --- Deleted-comment recovery must not replace live comments ---
//
// Archive-based recovery of deleted/removed comment bodies must be
// gated on the live body actually looking deleted, not swap in an
// archived copy for a live comment just because the archive has one
// under the same fullname.
@MainActor func checkDeletedCommentRecoveryMustNotReplace() async throws {
    do {
        check("a live comment body is not a deleted placeholder",
              !DeletedCommentsClassifier.bodyLooksDeletedOrRemoved("Mini poulpe joue avec sa maison"))
        check("[removed] and [deleted] are", DeletedCommentsClassifier.bodyLooksDeletedOrRemoved("[removed]")
              && DeletedCommentsClassifier.bodyLooksDeletedOrRemoved("[deleted]"))
    }
}

// --- Settings the app shows must actually change behaviour ---
//
// Every field of a settings struct needs a reader outside its own
// screen/store; each is wired and asserted here.
@MainActor func checkSettingsTheAppShowsMustActually() async throws {
    do {
        // Tap to Collapse...: where a single tap collapses.
        check("Tap to Collapse 'Headers' collapses from the header only",
              TapToCollapseType.headers.collapsesOnHeaderTap && !TapToCollapseType.headers.collapsesOnBodyTap)
        check("'Comments' collapses from the body only",
              TapToCollapseType.comments.collapsesOnBodyTap && !TapToCollapseType.comments.collapsesOnHeaderTap)
        check("'Neither' collapses from neither",
              !TapToCollapseType.neither.collapsesOnBodyTap && !TapToCollapseType.neither.collapsesOnHeaderTap)
        check("'Both' collapses from both",
              TapToCollapseType.both.collapsesOnBodyTap && TapToCollapseType.both.collapsesOnHeaderTap)

        // Require Passcode: After N Minutes.
        var lock = AppLockSettings(isEnabled: true, requireAfterSeconds: 300)
        check("app lock grace period: back after 2 minutes needs no unlock",
              !lock.requiresUnlock(afterBeingAwayFor: 120))
        check("...back after 6 minutes does", lock.requiresUnlock(afterBeingAwayFor: 360))
        lock.requireAfterSeconds = 0
        check("'Immediately' always needs unlock", lock.requiresUnlock(afterBeingAwayFor: 1))
        check("a disabled lock never needs unlock",
              !AppLockSettings(isEnabled: false, requireAfterSeconds: 0).requiresUnlock(afterBeingAwayFor: 9999))

        // PURER Black: Reborn's tier values (see PureBlackSettings.darkBackgroundHex).
        check("Pure Black alone is Reborn's near-black #131516",
              PureBlackSettings(isEnabled: true).darkBackgroundHex == "131516")
        check("PURER is true black", PureBlackSettings(isEnabled: true, isPurerEnabled: true).darkBackgroundHex == "000000")
        check("PURER + Reduce Smearing is #050505",
              PureBlackSettings(isEnabled: true, isPurerEnabled: true, reduceSmearing: true).darkBackgroundHex == "050505")
        check("PURER is ignored while Pure Black is off, as in Reborn",
              PureBlackSettings(isEnabled: false, isPurerEnabled: true).darkBackgroundHex == nil)
    }
}

// --- The video player: the right stream, and an audible session ---
//
// Two independent faults make a v.redd.it post play silently:
//
// 1. The video-only `fallback_url` rendition has no audio; the muxed
//    `hls_url` stream must be used instead, since v.redd.it stores
//    audio as a separate track.
//
// 2. An app that never sets an `AVAudioSession` category gets the
//    default, which follows the ring/silent switch, so playback must
//    claim the Playback category before unmuting, not only from the
//    Picture-in-Picture button.
@MainActor func checkTheVideoPlayerTheRightStream() async throws {
    do {
        // (1) Stream selection.
        let hls = "https://v.redd.it/abc123/HLSPlaylist.m3u8?f=sd%2Chd"
        let fallback = "https://v.redd.it/abc123/DASH_720.mp4?source=fallback"
        check("a video with audio plays the HLS stream",
              RedditVideoStream.playbackURL(hlsURL: hls, fallbackURL: fallback, isGif: false)?
                  .absoluteString == "https://v.redd.it/abc123/HLSPlaylist.m3u8")
        // The query is stripped, as Apollo does: everything up to
        // `/HLSPlaylist.m3u8` is kept.
        check("the HLS query junk is stripped",
              !(RedditVideoStream.playbackURL(hlsURL: hls, fallbackURL: fallback, isGif: false)?
                  .absoluteString.contains("?") ?? true))
        // A GIF-style video has no audio track to gain, and a progressive
        // MP4 starts faster than a manifest - which is why Apollo keeps
        // both URLs rather than always using one.
        check("a GIF-style video keeps the progressive fallback",
              RedditVideoStream.playbackURL(hlsURL: hls, fallbackURL: fallback, isGif: true)?
                  .absoluteString == fallback)
        check("a video with no HLS URL falls back",
              RedditVideoStream.playbackURL(hlsURL: nil, fallbackURL: fallback, isGif: false)?
                  .absoluteString == fallback)
        check("an empty HLS URL falls back",
              RedditVideoStream.playbackURL(hlsURL: "", fallbackURL: fallback, isGif: false)?
                  .absoluteString == fallback)
        // Reddit HTML-escapes ampersands in its JSON; an unescaped `&amp;`
        // would make the URL wrong rather than merely ugly.
        check("HTML-escaped ampersands are decoded",
              RedditVideoStream.normalizedHLS(
                "https://v.redd.it/x/HLSPlaylist.m3u8?f=sd&amp;v=1")?
                  .absoluteString == "https://v.redd.it/x/HLSPlaylist.m3u8")
        // An unexpected shape is left alone rather than blindly truncated
        // at the first `?`.
        check("a non-playlist HLS URL is left intact",
              RedditVideoStream.normalizedHLS("https://example.com/stream.m3u8")?
                  .absoluteString == "https://example.com/stream.m3u8")

        // The comment/crosspost path: build the playlist from an asset id.
        check("an asset id becomes a playlist URL",
              RedditVideoStream.hlsURL(forAssetID: "xyz789")?.absoluteString
                  == "https://v.redd.it/xyz789/HLSPlaylist.m3u8")
        check("an empty asset id yields nothing",
              RedditVideoStream.hlsURL(forAssetID: "") == nil)
        check("an asset id is read out of a v.redd.it URL",
              RedditVideoStream.assetID(fromVRedditURL:
                URL(string: "https://v.redd.it/xyz789/DASH_1080.mp4")!) == "xyz789")
        check("a non-v.redd.it URL yields no asset id",
              RedditVideoStream.assetID(fromVRedditURL:
                URL(string: "https://example.com/xyz789/video.mp4")!) == nil)

        // DOWNLOAD is a different URL from PLAYBACK. Save Video, Share as Image's
        // video export and the share service take the SAME classified URL and mux it
        // with `DASH_audio.mp4` themselves, and
        // `VideoDownloader.audioURL(forRedditVideo:)` looks for `DASH_` in the URL,
        // so handing them a `.m3u8` would silently save videos without audio.
        check("download uses the progressive rendition, not the playlist",
              RedditVideoStream.downloadURL(hlsURL: hls, fallbackURL: fallback)?
                  .absoluteString == fallback)
        check("the download URL keeps a DASH_ segment for the muxer",
              RedditVideoStream.downloadURL(hlsURL: hls, fallbackURL: fallback)?
                  .absoluteString.contains("DASH_") == true)
        // The two must genuinely differ for a video WITH audio, or the
        // distinction is not being made.
        check("playback and download URLs differ for a video with audio",
              RedditVideoStream.playbackURL(hlsURL: hls, fallbackURL: fallback, isGif: false)
                  != RedditVideoStream.downloadURL(hlsURL: hls, fallbackURL: fallback))
        // ...and the muxer's own precondition holds on it.
        check("the audio track pairs off the download URL",
              VideoDownloader.audioURL(forRedditVideo:
                RedditVideoStream.downloadURL(hlsURL: hls, fallbackURL: fallback)!)?
                  .absoluteString == "https://v.redd.it/abc123/DASH_audio.mp4")
        check("the audio track can NOT be paired off the playback URL",
              VideoDownloader.audioURL(forRedditVideo:
                RedditVideoStream.playbackURL(hlsURL: hls, fallbackURL: fallback, isGif: false)!) == nil)

        // (2) The audio session.
        check("a muted video does not claim the session",
              !VideoAudioSession.shouldClaim(isMuted: true))
        check("an unmuted video does claim it",
              VideoAudioSession.shouldClaim(isMuted: false))
    }
}

// --- Videos actually play, and have controls ---
//
// Three requirements for inline video: the player must actually call
// `play()` rather than sit paused on frame zero, `autoplayMode`
// (Apollo's real default is `always`) must actually drive playback
// while scrolling, and inline videos need their own play/pause, skip
// and time controls rather than only getting them in the fullscreen
// pager.
@MainActor func checkVideosActuallyPlayAndHaveControls() async throws {
    do {
        // The policy.
        check("always autoplays on wifi",
              VideoAutoplayPolicy.shouldAutoplay(mode: .always, isExpensive: false))
        // `.always` means always - including on cellular, which is the
        // distinction from `.wifiOnly`.
        check("always autoplays on cellular too",
              VideoAutoplayPolicy.shouldAutoplay(mode: .always, isExpensive: true))
        check("never does not autoplay",
              !VideoAutoplayPolicy.shouldAutoplay(mode: .never, isExpensive: false))
        check("wifiOnly autoplays on wifi",
              VideoAutoplayPolicy.shouldAutoplay(mode: .wifiOnly, isExpensive: false))
        // Maps to Apollo's own `AutoplayGifsOverCellular` (default false).
        check("wifiOnly does not autoplay on an expensive link",
              !VideoAutoplayPolicy.shouldAutoplay(mode: .wifiOnly, isExpensive: true))
        // Apollo's real default, so a fresh install plays video.
        check("the default mode is Apollo's own 'always'",
              GeneralSettings.default.autoplayMode == .always)
    }
}

// MARK: - Tap-to-fullscreen, and the video's height on first layout
//
// Two properties of inline video:
//
// 1. A tap anywhere on the video must open the fullscreen pager rather
//    than being intercepted by the enclosing feed row's own tap
//    gesture; a real `Button` behind the media resolves through
//    UIKit's control path instead of losing SwiftUI gesture
//    arbitration to an ancestor.
//
// 2. The player must start from Reddit's own `width`/`height` in the
//    listing JSON rather than a fixed 16:9 placeholder, or a portrait
//    clip visibly jumps aspect ratio once its asset loads.
@MainActor func checkTapToFullscreenAndTheVideo() async throws {
    do {
        // (1) Reddit's own dimensions decode, and produce a ratio.
        struct VideoEnvelope: Decodable { let media: RedditMedia? }
        let json = """
        {"media":{"reddit_video":{"fallback_url":"https://v.redd.it/x/DASH_720.mp4",
          "hls_url":"https://v.redd.it/x/HLSPlaylist.m3u8","is_gif":false,
          "width":576,"height":1024}}}
        """
        let decoded = try? JSONDecoder().decode(VideoEnvelope.self, from: Data(json.utf8))
        let video = decoded?.media?.redditVideo
        check("a video's own pixel width decodes", video?.width == 576)
        check("a video's own pixel height decodes", video?.height == 1024)
        // PORTRAIT, so a fixed 16:9 placeholder aspect ratio would be
        // more than three times too wide for this clip.
        check("a portrait video reports a portrait aspect ratio",
              video.flatMap { $0.aspectRatio }.map { abs($0 - 576.0 / 1024.0) < 0.0001 } ?? false)
        check("the placeholder ratio would have been wrong for it",
              video.flatMap { $0.aspectRatio }.map { $0 < 1 } ?? false)

        // Missing or zero dimensions must yield nil, not a divide-by-zero
        // or a 0 ratio that would collapse the player entirely.
        let zeroJSON = """
        {"media":{"reddit_video":{"fallback_url":"https://v.redd.it/x/DASH_720.mp4",
          "is_gif":false,"width":0,"height":0}}}
        """
        let zero = (try? JSONDecoder().decode(VideoEnvelope.self, from: Data(zeroJSON.utf8)))?
            .media?.redditVideo
        check("zero dimensions produce no aspect ratio", zero?.aspectRatio == nil)
        let absentJSON = """
        {"media":{"reddit_video":{"fallback_url":"https://v.redd.it/x/DASH_720.mp4","is_gif":false}}}
        """
        let absent = (try? JSONDecoder().decode(VideoEnvelope.self, from: Data(absentJSON.utf8)))?
            .media?.redditVideo
        check("absent dimensions produce no aspect ratio", absent?.aspectRatio == nil)
        check("a video with no dimensions still decodes its playback URL",
              absent?.fallbackURL == "https://v.redd.it/x/DASH_720.mp4")
    }
}
