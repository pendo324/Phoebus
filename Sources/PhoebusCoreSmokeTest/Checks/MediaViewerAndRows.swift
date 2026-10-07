import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - The fullscreen video viewer: layout and gestures
//
// Apollo ships its own custom video controls panel, floating over a
// video that fills the whole screen, rather than native iOS controls.
// The panel opens visible by default, a tap toggles all chrome
// (panel, speed menu, PiP button) together, and a mostly-vertical
// swipe exits downward or opens comments upward through one shared
// handler.
@MainActor func checkTheFullscreenVideoViewerLayoutAnd() async throws {
    do {
        // (1) Controls visible on open. Apollo's own default:
        // ShowMediaViewerControlsWhenOpened=true.
        check("the viewer opens with its controls visible by default",
              GeneralSettings.default.showMediaViewerControlsWhenOpened)
    }
}

// MARK: - Gallery View's own fullscreen viewer, and fullscreen chrome
//
// Apollo's fullscreen video chrome shows no speedometer or PiP button;
// playback speed lives in the "..." menu instead. Tapping a gallery tile opens
// the gallery's own fullscreen viewer ("Done", a running counter over the
// whole loaded feed, and a bottom info card that taps through to the post)
// rather than pushing the post screen.
@MainActor func checkGalleryViewSOwnFullscreenViewer() async throws {
    do {
        // Time formatting: m:ss, and h:mm:ss past an hour.
        check("times are m:ss, and h:mm:ss past an hour",
              GalleryTimeFormat.string(0) == "0:00"
                  && GalleryTimeFormat.string(62) == "1:02"
                  && GalleryTimeFormat.string(3661) == "1:01:01")
    }
}

// MARK: - Gallery viewer: real media, real chrome, swipe up for comments
//
// Three properties of the gallery viewer:
//
// 1. It must play the actual media, not a still thumbnail. `imageURL`
//    (full resolution) and `thumbnailURL` (grid preview) are kept
//    distinct, and RedGifs/gfycat/Streamable/sports-clip items resolve
//    their stream asynchronously rather than showing a static poster.
//
// 2. The info card needs a material background (glass, or translucent
//    black), not floating text over the letterbox.
//
// 3. `SwipeUpForComments` (default on) opens a media-owned comments
//    sheet on an upward flick or comments-button tap, without leaving
//    the still-live media pager; downward still dismisses.
@MainActor func checkGalleryViewerRealMediaRealChrome() async throws {
    do {
        // Decoded from real listing JSON: a post whose `preview` carries a
        // resolution ladder must resolve to the SOURCE, not a rung, and
        // not to Reddit's tiny `thumbnail`.
        struct PostEnvelope: Decodable { let data: RedditPost }
        let previewJSON = """
        {"data":{"id":"abc","name":"t3_abc","title":"T","author":"a","subreddit":"s",
          "score":1,"num_comments":0,"created_utc":0,"permalink":"/r/s/comments/abc/",
          "url":"https://reddit.com/r/s/comments/abc/","is_self":false,"over_18":false,
          "spoiler":false,"saved":false,"stickied":false,"locked":false,"archived":false,
          "thumbnail":"https://b.thumbs.redditmedia.com/tiny.jpg",
          "preview":{"images":[{"source":{"url":"https://i.redd.it/full.jpg","width":4000,"height":3000},
            "resolutions":[{"url":"https://i.redd.it/small.jpg","width":320,"height":240}]}]}}}
        """
        let previewPost = try? JSONDecoder().decode(PostEnvelope.self, from: Data(previewJSON.utf8)).data
        check("a still resolves to its full-size source, not a preview rung",
              previewPost.flatMap { GalleryPostMedia.fullResolutionURL(for: $0)?.absoluteString }
                  == "https://i.redd.it/full.jpg")
        check("the grid tile uses a preview rung wide enough for a tile, not the 140px thumbnail",
              previewPost.flatMap { GalleryPostMedia.thumbnailURL(for: $0)?.absoluteString }
                  == "https://i.redd.it/full.jpg")

        // Reborn #1134: default OFF.
        check("the toggle defaults OFF, as Reborn's does since #1134",
              !GeneralSettings.default.swipeUpForComments)
    }
}

// MARK: - Gallery mute is sticky, and the chrome cannot desync
//
// Three properties of the gallery video viewer:
//
// 1. Mute is one flag for the whole viewer, persisted (as in Apollo,
//    default muted) and read by every player as it is created, not
//    per-screen `@State` applied only to whichever player happens to be
//    current.
//
// 2. Play/pause and mute controls must observe `player.rate` and
//    `player.isMuted` rather than assert a toggled value, so a stall,
//    loop restart or rate change cannot desync the glyph from the
//    video.
//
// 3. The full-screen swipe catcher must refuse touches inside the
//    info panel and transport bar regions while the chrome is visible,
//    so a tap on those controls does not also toggle the chrome.
@MainActor func checkGalleryMuteIsStickyAndThe() async throws {
    do {
        // (1) One sticky flag, on Reborn's own key and default.
        check("gallery mute uses Reborn's own defaults key",
              GalleryMuteStore.key == "ApolloGalleryVideosMuted")
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: GalleryMuteStore.key)
        check("a gallery starts MUTED when nothing is stored",
              GalleryMuteStore.isMuted)
        GalleryMuteStore.isMuted = false
        check("unmuting persists", !GalleryMuteStore.isMuted)
        check("...and survives a fresh read of the store",
              defaults.object(forKey: GalleryMuteStore.key) != nil
                  && defaults.bool(forKey: GalleryMuteStore.key) == false)
        GalleryMuteStore.isMuted = true
        check("re-muting persists too", GalleryMuteStore.isMuted)
        defaults.removeObject(forKey: GalleryMuteStore.key)

        check("...dropping every audio claim, not just one",
              { VideoAudioSession.claim("smoke.a"); VideoAudioSession.claim("smoke.b")
                VideoAudioSession.releaseAll()
                return !VideoAudioSession.holds("smoke.a") && !VideoAudioSession.holds("smoke.b")
                    && !VideoAudioSession.holdsClaim }())
    }
}

// MARK: - The audio session survives a page handover
//
// `VideoAudioSession` must count claims rather than track a single
// boolean, so a stale outgoing page's `onDisappear` cannot deactivate
// the session an incoming page already claimed. An overlapping
// handover is normal in a pager and must never tear down shared
// state, the same shape `VideoPlayerCache` uses; release stays guarded
// by the same "still held" test as pause.
@MainActor func checkTheAudioSessionSurvivesAPage() async throws {
    do {
        // Per-holder claims: a balanced count would drift, and a leaving view's
        // release must not be gated off, or the session is never handed back and
        // other apps' audio stays paused.
        VideoAudioSession.releaseAll()
        VideoAudioSession.claim("smoke.one"); VideoAudioSession.claim("smoke.one"); VideoAudioSession.claim("smoke.two")
        VideoAudioSession.release("smoke.one")
        check("audio: a holder claims once; another holder keeps the session",
              VideoAudioSession.holdsClaim && !VideoAudioSession.holds("smoke.one") && VideoAudioSession.holds("smoke.two"))
        VideoAudioSession.release("smoke.one")
        VideoAudioSession.release("smoke.two")
        check("audio: the last holder's release deactivates; a repeat release is harmless",
              !VideoAudioSession.holdsClaim)
    }
}

// --- Compact feed row ---
//
// Feed row constants match Apollo's compact row.
@MainActor func checkCompactFeedRowMeasuredAgainstThe() async throws {
    do {
        // (8) Unread comments badge, driven by total-count snapshots
        // (real defaults key `PostCommentsSnapshots`).
        check("the tracker records total comment counts",
              NewCommentsTracker.newCommentCount(postID: "smoke-unseen-post", currentCount: 12) == 0)
        NewCommentsTracker.recordCommentCount(postID: "smoke-seen-post", count: 10)
        check("a grown thread reports its new-comment delta",
              NewCommentsTracker.newCommentCount(postID: "smoke-seen-post", currentCount: 645) == 635)
        check("a shrunken thread never reports a negative delta",
              NewCommentsTracker.newCommentCount(postID: "smoke-seen-post", currentCount: 3) == 0)
        check("the snapshot is readable on its own",
              NewCommentsTracker.lastSeenCommentCount(postID: "smoke-seen-post") == 10
              && NewCommentsTracker.lastSeenCommentCount(postID: "smoke-unseen-post") == nil)
    }

    // Settings layout details.
    do {
        // (3) Profile Layout: Native style + Reborn's summary line.
        var p = ProfileLayoutSettings.default
        p.style = .native
        check("Native profile style clears detailed profiles and summarises as Native (Apollo)",
              !p.showDetailedProfiles && p.summaryText == "Native (Apollo)")
        p.style = .compact
        check("Compact is detailed but not immersive",
              p.showDetailedProfiles && !p.headerImmersive && p.summaryText.hasPrefix("Compact"))
    }

    // Profile picture shape, gallery autoplay, quick actions.
    do {
        // Shared Profile Picture Shape (Reborn #1136): Circle default, the
        // Interface row, and every small avatar honours it.
        check("profile picture shape defaults to Circle (#1136)",
              ProfileLayoutSettings.default.avatarStyle == .circle)
        // Gallery View grid autoplay (#1142).
        check("gallery autoplay defaults on with Reborn's caps",
              GalleryAutoplaySettings.default.playVideos && GalleryAutoplaySettings.default.playGIFs
              && GalleryAutoplaySettings.maxPlayingTiles == 12 && GalleryAutoplaySettings.tilePeakBitRate == 1_500_000)
        // Quick actions.
        check("quick actions parse Reborn-style URLs and shortcut types",
              QuickAction.parse(URL(string: "phoebus://reborn/inbox")!) == .inbox
              && QuickAction.parse(URL(string: "phoebus://reborn/nope")!) == nil
              && QuickAction.parse(shortcutType: QuickAction.typePrefix + "search") == .search)
    }

    // Tweet previews (Reborn TweetBuddy): parse captured responses for tweet 20
    // ("just setting up my twttr") from both endpoints.
    do {
        let gql = (try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/x-graphql-tweet-20.json"))) ?? Data()
        let syn = (try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/x-syndication-tweet-20.json"))) ?? Data()
        let a = TweetClient.parseGraphQL(gql)
        let b = TweetClient.parseSyndication(syn)
        check("X GraphQL tweet parses (name, handle, text, avatar)",
              a?.username == "jack" && a?.name == "jack" && a?.text == "just setting up my twttr" && a?.profilePictureURL != nil)
        check("syndication fallback tweet parses",
              b?.username == "jack" && b?.text == "just setting up my twttr")
        check("tweet status IDs are recognised on x.com, twitter.com and mirrors",
              TweetURL.statusID(from: URL(string: "https://x.com/jack/status/20?s=46")!) == "20"
              && TweetURL.statusID(from: URL(string: "https://mobile.twitter.com/jack/status/20")!) == "20"
              && TweetURL.statusID(from: URL(string: "https://fxtwitter.com/jack/status/20")!) == "20"
              && TweetURL.statusID(from: URL(string: "https://x.com/jack")!) == nil
              && TweetURL.statusID(from: URL(string: "https://example.com/a/status/20")!) == nil)
        check("tweet text drops the trailing t.co media link",
              TweetClient.cleanText("hi &amp; bye https://t.co/AbC123") == "hi & bye")
    }

    // Settings Shortcuts (Reborn #1150).
    do {
        UserDefaults.standard.removeObject(forKey: SettingsShortcutsStore.key)
        check("settings shortcuts default to Reborn's five",
              SettingsShortcutsStore.load() == ["theme-manager", "automatic-backups", "feature-requests", "bug-reports", "buy-coffee"])
        UserDefaults.standard.set(["inline-media", "bogus", "general", "general"], forKey: SettingsShortcutsStore.key)
        check("saved shortcuts are migrated, validated and de-duplicated",
              SettingsShortcutsStore.load() == ["media", "general"])
        UserDefaults.standard.removeObject(forKey: SettingsShortcutsStore.key)
        // Reborn's 27 routes, less Pixel Pals.
        check("the catalog has Reborn's routes and a limit of 15",
              SettingsShortcutsStore.catalog.count == 26 && SettingsShortcutsStore.limit == 15)
    }

    // Swipe Tab Bar to Navigate (Reborn #1075).
    do {
        check("Swipe Tab Bar to Navigate defaults off",
              !GeneralSettings.default.tabBarSwipeNavigation)
    }

    // Swipe Past Gallery to Navigate: Reborn #1271's begin-time ownership
    // decision, ported as `FeedGalleryPanPolicy` with upstream's test table.
    do {
        func d(_ o: Double, _ vx: Double, _ vy: Double, _ x: Double, _ rtl: Bool, _ back: Bool, _ fwd: Bool) -> FeedGalleryPanPolicy.Disposition {
            FeedGalleryPanPolicy.disposition(contentOffsetX: o, maximumOffsetX: 640, velocityX: vx, velocityY: vy,
                                             touchX: x, viewWidth: 320, rightToLeft: rtl, canGoBack: back, canGoForward: fwd)
        }
        let w = 320.0
        check("gallery pan: the ~24pt edge band (34 with UIKit's hysteresis)",
              FeedGalleryPanPolicy.screenEdgeWidth == 34
                && d(320, 300, 10, 28, false, true, false) == .yield && d(320, 300, 10, 36, false, true, false) == .consume
                && d(320, -300, 10, w - 28, false, false, true) == .yield && d(320, -300, 10, w - 36, false, false, true) == .consume)
        check("gallery pan: a pull past the first or last image always yields",
              d(0, 300, 10, 160, false, false, false) == .yield && d(640, -300, 10, 160, false, false, false) == .yield)
        check("gallery pan: paging inward or mid-gallery stays with the carousel",
              d(0, -300, 10, 160, false, true, true) == .consume && d(640, 300, 10, 160, false, true, true) == .consume
                && d(320, 300, 10, 160, false, true, true) == .consume)
        check("gallery pan: slow or vertical pans stay with the carousel",
              d(0, 149, 0, 160, false, true, true) == .consume && d(0, 300, 350, 160, false, true, true) == .consume)
        check("gallery pan: an edge pan yields only where navigation can act",
              d(320, 300, 10, 8, false, true, false) == .yield && d(320, -300, 10, w - 8, false, false, true) == .yield
                && d(320, 300, 10, 8, false, false, true) == .consume)
        check("gallery pan: right-to-left mirrors back and forward",
              d(320, -300, 10, w - 8, true, true, false) == .yield && d(320, 300, 10, 8, true, false, true) == .yield)
    }

    // Reborn #1273/#1246: comment images from `media_metadata`.
    do {
        let json = #"{"abc123def45":{"status":"valid","e":"Image","m":"image/png","s":{"x":800,"y":400,"u":"https://preview.redd.it/abc123def45.png?width=800&amp;s=x"}},"gif9xyz12":{"status":"valid","e":"AnimatedImage","m":"image/gif","s":{"x":300,"y":300,"gif":"https://i.redd.it/gif9xyz12.gif"}},"wait1":{"status":"unprocessed"}}"#
        let meta = try? JSONDecoder().decode([String: GalleryMediaItem].self, from: Data(json.utf8))
        let urls = RedditMediaTokens.imageURLs(from: meta)
        check("comment images: a png token names a .png, not the jpeg guess",
              urls["abc123def45"] == "https://i.redd.it/abc123def45.png"
                && RedditMediaTokens.expand("look ![img](abc123def45)", imageURLs: urls) == "look https://i.redd.it/abc123def45.png")
        check("comment images: a GIF uses its own file; unprocessed items are skipped",
              urls["gif9xyz12"] == "https://i.redd.it/gif9xyz12.gif" && urls["wait1"] == nil)
        check("comment images: the box shape comes from the metadata's pixel size",
              RedditMediaTokens.ratios(from: meta)["https://i.redd.it/abc123def45.png"] == 2.0)
    }

    // "Swipe anywhere" (the no-inset branch; Gestures footers "Becomes swipe
    // anywhere to go back/forward").
    do {
        check("back from mid-screen only when swipe-anywhere is on",
              PushPopGesturePolicy.shouldBeginBack(velocityX: 300, velocityY: 20, locationX: 200, anywhere: true)
              && !PushPopGesturePolicy.shouldBeginBack(velocityX: 300, velocityY: 20, locationX: 200, anywhere: false))
        check("forward from mid-screen only when swipe-anywhere is on",
              PushPopGesturePolicy.shouldBeginForward(velocityX: -300, velocityY: 20, locationX: 200, viewWidth: 393, anywhere: true)
              && !PushPopGesturePolicy.shouldBeginForward(velocityX: -300, velocityY: 20, locationX: 200, viewWidth: 393, anywhere: false))
        check("swipe-anywhere still needs Apollo's 1.65 horizontal ratio",
              !PushPopGesturePolicy.shouldBeginBack(velocityX: 100, velocityY: 100, locationX: 200, anywhere: true))
    }

    // Use Location Sunset & Sunrise: on-device NOAA solar times.
    do {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let london = SolarTimes.Coordinates(latitude: 51.5074, longitude: -0.1278)
        let t = SolarTimes.sunriseSunset(on: day, at: london, calendar: cal)
        let rise = t.map { SolarTimes.minutes(of: $0.sunrise, calendar: cal) } ?? -1
        let set = t.map { SolarTimes.minutes(of: $0.sunset, calendar: cal) } ?? -1
        // Published: 04:43 and 21:21 BST.
        check("London midsummer sunrise ~04:43 (\(rise / 60):\(rise % 60))", abs(rise - (4 * 60 + 43)) <= 3)
        check("London midsummer sunset ~21:21 (\(set / 60):\(set % 60))", abs(set - (21 * 60 + 21)) <= 3)
        check("polar night has no sunrise",
              SolarTimes.sunriseSunset(on: cal.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!,
                                       at: .init(latitude: 78.2, longitude: 15.6), calendar: cal) == nil)
    }

    // Hidden & Deleted (#1137): matching Apollo's own classification.
    do {
        typealias F = HiddenContentFinder
        check("archive removed_by_category=deleted reads DELETED by Author",
              F.resolveReason(archive: ["removed_by_category": "deleted"], kind: .post, live: nil) == (.deleted, "Author"))
        check("moderator/automod/admin categories read as Removed with who",
              F.resolveReason(archive: ["removed_by_category": "moderator"], kind: .post, live: [:]) == (.removed, "Moderator")
              && F.resolveReason(archive: ["removed_by_category": "automod_filtered"], kind: .post, live: [:]) == (.removed, "AutoMod")
              && F.resolveReason(archive: ["removed_by_category": "reddit"], kind: .post, live: [:]) == (.removed, "Reddit Admins"))
        check("an unknown category still names who (capitalised), not nil",
              F.removalDetail(forCategory: "copyright_takedown") == "Copyright_Takedown")
        check("an item that no longer resolves live is Deleted",
              F.resolveReason(archive: [:], kind: .comment, live: nil) == (.deleted, "Author"))
        check("live [removed] body is Removed with no who; [deleted] author is Deleted",
              F.resolveReason(archive: [:], kind: .comment, live: ["body": "[removed]", "author": "x"]) == (.removed, nil)
              && F.resolveReason(archive: [:], kind: .comment, live: ["author": "[deleted]"]) == (.deleted, "Author"))
        check("intact live copy missing from the listing is Hidden",
              F.resolveReason(archive: [:], kind: .post, live: ["selftext": "hi", "author": "x"]) == (.hidden, nil))

        let archive: [[String: Any]] = [
            ["id": "a", "created_utc": 300], ["id": "a", "created_utc": 300],   // repeated by Arctic's cursor
            ["id": "b", "created_utc": 200], ["name": "t3_c", "created_utc": 50],
        ]
        let picked = F.candidates(archive: archive, kind: .post, liveFullNames: ["t3_b"], liveIncomplete: false, liveOldestCreatedUTC: nil)
        check("candidates drop live items and de-duplicate by fullname",
              picked.count == 2 && F.fullName(of: picked[0], kind: .post) == "t3_a")
        let partial = F.candidates(archive: archive, kind: .post, liveFullNames: ["t3_b"], liveIncomplete: true, liveOldestCreatedUTC: 100)
        check("with a partial live listing, older-than-coverage items are dropped (no false HIDDEN)",
              partial.count == 1 && F.fullName(of: partial[0], kind: .post) == "t3_a")

        let gallery: [String: Any] = [
            "id": "g", "title": "T", "created_utc": 1_700_000_000,
            "gallery_data": ["items": [["media_id": "m2"], ["media_id": "m1"]]],
            "media_metadata": [
                "m1": ["s": ["u": "https://i.redd.it/one.jpg?a=1&amp;b=2", "x": 100, "y": 50]],
                "m2": ["s": ["u": "https://i.redd.it/two.jpg", "x": 300, "y": 600]],
            ],
        ]
        let g = F.item(fromArchive: gallery, kind: .post, reason: .deleted, removalDetail: "Author")
        check("gallery media follows gallery_data order with &amp; unescaped",
              g?.mediaURLs.map(\.absoluteString) == ["https://i.redd.it/two.jpg", "https://i.redd.it/one.jpg?a=1&b=2"])
        check("aspect ratio comes from the first media item", g?.previewAspectRatio == 0.5)
        let direct = F.item(fromArchive: ["id": "d", "url": "https://i.imgur.com/x.png"], kind: .post, reason: .hidden, removalDetail: nil)
        check("a direct image link becomes the media", direct?.mediaURLs.first?.absoluteString == "https://i.imgur.com/x.png")
        check("pill text matches upstream", F.Reason.removed.pillText == "REMOVED" && F.Reason.hidden.pillText == "HIDDEN")
    }

    // Save All Media (#1048): result wording matches upstream.
    do {
        typealias S = SaveAllMediaSummary
        check("everything saved reads 'Saved All N Items!' as success",
              S.result(total: 4, saved: 4, failed: 0, cancelled: false) == .init(title: "Saved All 4 Items!", detail: nil, style: .success))
        check("a single item reads 'Saved!'", S.result(total: 1, saved: 1, failed: 0, cancelled: false).title == "Saved!")
        check("failures read 'Saved X of N Items' with a Photos detail, as an error",
              S.result(total: 5, saved: 3, failed: 2, cancelled: false) == .init(title: "Saved 3 of 5 Items", detail: "2 could not be saved to Photos.", style: .error))
        check("cancel reports skipped items as info",
              S.result(total: 5, saved: 2, failed: 0, cancelled: true) == .init(title: "Saved 2 of 5 Items", detail: "Cancelled · 3 skipped", style: .info))
        check("cancel with failures lists both",
              S.result(total: 5, saved: 1, failed: 1, cancelled: true).detail == "Cancelled · 1 failed · 3 skipped")
        check("the menu title is upstream's single 'Save All Media'", S.menuTitle == "Save All Media")
        check("the panel counter clamps at the total", S.counter(completed: 7, total: 5) == "5 / 5")
    }

    // Prefer Native Images (Reborn Auto mode for comment photos).
    do {
        typealias N = NativeCommentImages
        check("static/animated in allowed_media_in_comments allows images; giphy alone does not; absent is unknown",
              N.allowsImageComments(aboutData: ["allowed_media_in_comments": ["giphy", "static"]]) == true
              && N.allowsImageComments(aboutData: ["allowed_media_in_comments": ["giphy"]]) == false
              && N.allowsImageComments(aboutData: [:]) == nil)
        let text = "look\nhttps://i.redd.it/abc123.jpeg\nnice"
        let rich = N.richTextJSON(for: text, assetIDs: ["abc123"]) ?? ""
        check("RTJSON wraps the native image between text paragraphs",
              rich == #"{"document":[{"c":[{"e":"text","t":"look"}],"e":"par"},{"c":"","e":"img","id":"abc123"},{"c":[{"e":"text","t":"nice"}],"e":"par"}]}"#)
        check("an i.redd.it link not uploaded here stays plain text",
              N.richTextJSON(for: text, assetIDs: []) == nil)
        check("the markdown fallback embeds the native URL as an image",
              N.markdownBody(for: text, assetIDs: ["abc123"]) == "look\n![image](https://i.redd.it/abc123.jpeg)\nnice")
    }

    // Pure Black tiers are visible: stock #20252F, Pure Black #131516,
    // PURER #000000 / #050505.
    do {
        check("Off draws Apollo's stock dark card", PureBlackSettings().darkCardHex == "20252F")
        check("Pure Black draws #131516", PureBlackSettings(isEnabled: true).darkCardHex == "131516")
        check("PURER draws #000000, #050505 with Reduce Smearing",
              PureBlackSettings(isEnabled: true, isPurerEnabled: true).darkCardHex == "000000"
              && PureBlackSettings(isEnabled: true, isPurerEnabled: true, reduceSmearing: true).darkCardHex == "050505")
        check("PURER is ignored while Pure Black is off", PureBlackSettings(isPurerEnabled: true).darkCardHex == "20252F")
    }

    // Reborn source checks.
    do {
        check("Concepts cover shows Happy Toon Bot",
              LiquidGlassIconGroup.all.first { $0.id == "concepts" }?.coverIconIDs == ["paulo1manso-modern", "bajader-rtr", "toon-bot-2"])
    }

    // Reborn #1264: subscriptions stay in sync everywhere.
    do {
        let change = SubscriptionChange(name: "AskReddit", subscribed: true)
        check("subscription change: matches by name, case-insensitively, or by fullname",
              change.matches(name: "askreddit", fullname: nil) && !change.matches(name: "pics", fullname: "t5_2qh1i")
                && SubscriptionChange(fullname: "t5_2qh1i", subscribed: false).matches(name: "AskReddit", fullname: "t5_2qh1i"))
        var limiter = DevvitSubscriptionCheckLimiter()
        let spent = (0..<12).allSatisfy { limiter.take("Pics", now: Double($0)) }
        check("devvit sync: 12 checks per subreddit per 10 minutes, then a fresh window",
              spent && !limiter.take("pics", now: 20) && limiter.take("other", now: 20) && limiter.take("pics", now: 700))
        check("devvit sync: checks 2, 5 and 12 s after the last tap", DevvitSubscriptionCheckLimiter.delays == [2, 5, 12])
    }

    // Reborn #1220: API-Key-Free rate limit and batched avatars.
    do {
        typealias H = RedditRateLimitHold
        check("rate limit: a stated reset wins, then Retry-After, clamped to 30 s-10 min",
              H.holdSeconds(reset: "412.0", retryAfter: "90", now: 0) == 412
                && H.holdSeconds(reset: nil, retryAfter: "90", now: 0) == 90
                && H.holdSeconds(reset: "5", retryAfter: nil, now: 0) == 30
                && H.holdSeconds(reset: "9999", retryAfter: nil, now: 0) == 600)
        check("rate limit: with no header, hold to the next ten-minute mark",
              H.holdSeconds(reset: nil, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT", now: 600_450) == 150)
        let hold = RedditRateLimitHold()
        check("rate limit: only the first 429 of a hold announces it",
              hold.record(reset: "120", retryAfter: nil, now: 1000) == 120 && hold.record(reset: "120", retryAfter: nil, now: 1010) == nil
                && hold.remaining(now: 1060) == 70 && hold.remaining(now: 2000) == 0)
        check("rate limit: Reborn's toast detail",
              H.detail(seconds: 45) == "Try again in under a minute" && H.detail(seconds: 412) == "Try again in about 7 min")
        let users = RedditRepository.parseUserData(Data(#"{"t2_a":{"name":"alice","profile_img":"https://i.redd.it/a.png?x=1&amp;y=2"},"t2_b":{"name":"bob","profile_img":""}}"#.utf8))
        check("avatars: user_data_by_account_ids parses names and pictures",
              users["t2_a"]?.name == "alice" && users["t2_a"]?.profileImage == "https://i.redd.it/a.png?x=1&y=2"
                && users["t2_b"]?.name == "bob" && users["t2_b"]?.profileImage == nil)
    }

    // Reborn #1275 step 2: re-reading the thread explains a refused comment.
    do {
        typealias C = CommentSubmitFailure
        typealias S = C.ThreadState
        let removed = C.explain(state: S(post: ["subreddit": "pics", "author": "me", "removed_by_category": "moderator"],
                                         moderatorCommented: true, username: "Me"))
        check("thread: a mod-removed own post says so and where the reason is",
              removed == .init(title: "Post Removed", message: "Your post was removed by the moderators of r/pics, so it can't take new comments. They left a comment on it explaining why (pull to refresh if you don't see it)."))
        check("thread: an own removed post without a mod comment points at the inbox",
              C.explain(state: S(post: ["subreddit": "pics", "author": "me", "removed_by_category": "moderator"], username: "me"))?.message.hasSuffix("If they sent a reason, it's in your inbox.") == true)
        check("thread: a deleted post, or a moderator, isn't blocked by removal",
              C.explain(state: S(post: ["removed_by_category": "deleted"])) == nil
                && C.explain(state: S(post: ["removed_by_category": "moderator", "can_mod_post": true])) == nil)
        check("thread: admin removals, AutoModerator holds, locks and archives",
              C.explain(state: S(post: ["removed_by_category": "anti_evil_ops"]))?.message == "This post was removed by Reddit, so it can't take new comments."
                && C.explain(state: S(post: ["subreddit": "a", "removed_by_category": "automod_filtered"]))?.title == "Post Awaiting Approval"
                && C.explain(state: S(post: ["subreddit": "a", "locked": true]))?.message == "The moderators of r/a locked this thread, so it can't take new comments."
                && C.explain(state: S(post: ["archived": true]))?.title == "Post Archived")
        check("thread: a removed or locked parent comment",
              C.explain(state: S(parent: ["subreddit": "a", "body": "[removed]"]))?.title == "Comment Removed"
                && C.explain(state: S(parent: ["locked": true]))?.title == "Replies Locked")
        check("thread: a ban and approved-users-only commenting",
              C.explain(state: S(post: ["subreddit": "a"], subredditAbout: ["user_is_banned": true]))?.title == "Banned from r/a"
                && C.explain(state: S(post: ["subreddit": "a"], subredditAbout: ["restrict_commenting": true]))?.message == "Only approved users can comment in r/a."
                && C.explain(state: S(post: ["subreddit": "a"], subredditAbout: ["restrict_commenting": true, "user_is_contributor": true])) == nil)
        check("thread: a stickied ModTeam comment counts as a removal reason",
              C.hasRemovalComment(["data": ["children": [["data": ["stickied": true, "distinguished": "moderator", "author": "pics-ModTeam", "body": "Rule 1"]]]]])
                && !C.hasRemovalComment(["data": ["children": [["data": ["stickied": true, "distinguished": "moderator", "author": "mod", "body": "Welcome"]]]]]))
        check("thread: looked up only where it can help",
              C.shouldLookUp(parentFullname: "t1_x", error: CommentRejectedError(code: "SOMETHING", message: ""))
                && !C.shouldLookUp(parentFullname: "t1_x", error: CommentRejectedError(code: "RATELIMIT", message: ""))
                && !C.shouldLookUp(parentFullname: "t4_x", error: RedditAPIError.httpError(status: 403, body: ""))
                && C.shouldLookUp(parentFullname: "t3_x", error: RedditAPIError.httpError(status: 403, body: ""))
                && !C.shouldLookUp(parentFullname: "t3_x", error: RedditAPIError.httpError(status: 503, body: "")))
    }

    // Profile listing items.
    do {
        let json = #"{"kind":"Listing","data":{"after":"t1_c2","children":[{"kind":"t1","data":{"id":"c1","name":"t1_c1","author":"a","body":"x","score":1,"created_utc":1,"parent_id":"t3_p","link_id":"t3_p","saved":false,"score_hidden":false,"stickied":false}},{"kind":"t3","data":{"id":"p1","name":"t3_p1","title":"T","author":"a","subreddit":"s","permalink":"/r/s/comments/p1/","score":1,"num_comments":0,"created_utc":2,"is_self":true,"over_18":false,"spoiler":false,"stickied":false,"saved":false}},{"kind":"t1","data":{"id":"c1","name":"t1_c1","author":"a","body":"x","score":1,"created_utc":1,"parent_id":"t3_p","link_id":"t3_p","saved":false,"score_hidden":false,"stickied":false}}]}}"#
        if let listing = try? JSONDecoder.reddit.decode(RedditListing.self, from: Data(json.utf8)) {
            let items = RedditListing.appending(listing.profileItems(), to: [])
            check("profile: posts and comments keep Reddit's order, deduped",
                  items.map(\.id) == ["t1_c1", "t3_p1"])
            check("profile: the next page's items append without repeats",
                  RedditListing.appending(listing.profileItems(), to: items).count == 2)
            check("listings decode posts through one Core helper", listing.posts().map(\.id) == ["p1"])
        } else {
            check("profile: the fixture listing decodes", false)
        }
    }

    // User-facing error messages.
    do {
        typealias U = UserFacingError
        check("errors: cancellations say nothing",
              U.message(for: CancellationError()) == nil && U.message(for: URLError(.cancelled)) == nil)
        check("errors: API failures read as sentences, not enum dumps",
              U.message(for: RedditAPIError.httpError(status: 403, body: "{}")) == "You don't have permission to do that."
                && U.message(for: URLError(.notConnectedToInternet)) == "You appear to be offline."
                && U.message(for: CommentRejectedError(code: "RATELIMIT", message: "you are doing that too much")) == "You are doing that too much.")
    }

    // Form body encoding.
    do {
        check("form bodies escape &, =, + and %",
              FormEncoding.encode(["text": "A & B = C+D 100%", "api_type": "json"]) == "api_type=json&text=A%20%26%20B%20%3D%20C%2BD%20100%25")
        check("form bodies keep unreserved characters", FormEncoding.escape("a-b_c.d~e") == "a-b_c.d~e")
        check("linkify leaves a link's target alone",
              RedditMarkdown.linkifySubredditsAndUsers("see [here](/r/swift)") == "see [here](/r/swift)")
        check("linkify leaves a link's text alone",
              RedditMarkdown.linkifySubredditsAndUsers("[r/swift](https://reddit.com/r/swift)") == "[r/swift](https://reddit.com/r/swift)")
        check("linkify still links a bare mention beside a link",
              RedditMarkdown.linkifySubredditsAndUsers("[a](/r/x) and r/y") == "[a](/r/x) and [r/y](https://reddit.com/r/y)")
        struct Probe: Codable, Equatable {
            var a = true, b = 3
            static let def = Probe()
            init() {}
            enum CodingKeys: String, CodingKey { case a, b }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: CodingKeys.self)
                a = try c.decode(.a, default: Probe.def, \.a)
                b = try c.decode(.b, default: Probe.def, \.b)
            }
        }
        let lenient = try? JSONDecoder().decode(Probe.self, from: Data(#"{"a":"oops","b":7}"#.utf8))
        check("settings: a wrong-typed field falls back alone instead of failing the struct",
              lenient?.a == true && lenient?.b == 7)
        let general = try? JSONDecoder().decode(GeneralSettings.self, from: Data(#"{"postDisplayStyle":"bogus","showUserProfilePictures":true}"#.utf8))
        check("settings: an unknown enum case keeps the other fields", general?.showUserProfilePictures == true)
    }

    // Reborn #1260: Google search in the Search tab.
    do {
        typealias G = GoogleSearch
        check("google: site:reddit.com added, trailing 'reddit' dropped, curly quotes straightened",
              G.composeQuery("best keyboard reddit") == "best keyboard site:reddit.com"
                && G.composeQuery("\u{201C}exact\u{201D} thing") == "\"exact\" thing site:reddit.com")
        check("google: r/name scopes the search; several are OR-ed; a user site: wins",
              G.composeQuery("tips r/buildapc") == "tips site:reddit.com/r/buildapc"
                && G.composeQuery("r/pics r/aww x") == "x (site:reddit.com/r/pics OR site:reddit.com/r/aww)"
                && G.composeQuery("x site:old.reddit.com") == "x site:old.reddit.com")
        let url = G.searchURL("c++ r/cpp", options: .init(timeRange: .week, exactWords: true), page: 2, language: "en")?.absoluteString ?? ""
        check("google: results URL has udm=14, tbs chips, paging, and a literal +",
              url.contains("udm=14") && url.contains("tbs=qdr:w,li:1") && url.contains("start=20") && url.contains("c%2B%2B"))
        let thread = G.result(for: URL(string: "https://old.reddit.com/r/buildapc/comments/abc123/slug/def456/?utm=x")!)
        check("google: a Reddit comment URL classifies with ids and a www canonical URL",
              thread?.kind == .comment && thread?.postID == "abc123" && thread?.commentID == "def456"
                && thread?.url?.host == "www.reddit.com")
        check("google: shorteners, galleries and subreddits map; search pages and other sites don't",
              G.result(for: URL(string: "https://redd.it/abc12")!)?.url?.absoluteString == "https://www.reddit.com/comments/abc12"
                && G.result(for: URL(string: "https://www.reddit.com/gallery/xyz99")!)?.postID == "xyz99"
                && G.result(for: URL(string: "https://www.reddit.com/r/pics/top")!)?.kind == .subreddit
                && G.result(for: URL(string: "https://www.reddit.com/r/pics/search")!) == nil
                && G.result(for: URL(string: "https://example.com/r/pics")!) == nil)
        check("google: title suffixes and prefixes are stripped",
              G.cleanTitle("Best keyboards? : r/buildapc") == "Best keyboards?" && G.cleanTitle("r/pics - Sunset") == "Sunset")
        let snip = G.parseMarkedSnippet("r/x - Some \u{1}best\u{2} \u{1}keyboard\u{2} here Read more")
        check("google: snippet bold runs merge; prefix and Read more drop",
              snip.text == "Some best keyboard here" && snip.bold == [NSRange(location: 5, length: 13)])
        check("google: forum line and breadcrumb subreddit",
              G.meta(fromLines: ["Reddit · r/buildapc", "30+ comments · 1 year ago"], title: "t") == "30+ comments · 1 year ago"
                && G.subreddit(fromLines: ["Reddit · r/buildapc"], title: "t") == "buildapc")
        let raw: [[String: Any]] = [["go": "https://www.google.com/goto?url=a", "title": "A : r/pics", "snippet": "", "lines": ["Reddit · r/pics"]],
                                    ["go": "https://www.google.com/goto?url=a", "title": "A : r/pics", "snippet": "", "lines": ["Reddit · r/pics"]],
                                    ["url": "https://example.com/", "title": "B"]]
        let parsed = G.results(fromRaw: raw)
        check("google: duplicates and non-Reddit results drop", parsed.count == 1 && parsed[0].subreddit == "pics" && !parsed[0].id.isEmpty)
        check("google: Read More text and compact numbers",
              G.plainText(fromMarkdown: "**bold** [link](http://x) &amp;") == "bold link &"
                && GoogleSearchRedditInfo.compactCount(1500) == "1.5k" && GoogleSearchRedditInfo.compactCount(2000) == "2k"
                && GoogleSearchRedditInfo.compactAge(Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 3 * 86400)) == "3d")
        let info = GoogleSearchRedditInfo.parse(Data(#"{"data":{"children":[{"kind":"t3","data":{"id":"abc","title":"T","num_comments":37,"score":18,"is_self":true,"selftext":"hi"}}]}}"#.utf8), postID: "abc", commentID: nil)
        check("google: Reddit's /api/info fills the card", info?.commentCount == 37 && info?.score == 18 && info?.body == "hi" && info?.media == GoogleSearchRedditInfo.Media.none)
        check("google: suggestions parse", G.parseSuggestions(Data(#"["q",["a","b"]]"#.utf8)) == ["a", "b"])
    }

    // Reborn #1278: Share as Image's Link menu.
    do {
        let d = UserDefaults(suiteName: "smoke.shareLinkMode")!
        d.removePersistentDomain(forName: "smoke.shareLinkMode")
        check("share link: nothing saved reads No Link", ShareLinkMode.read(d, hasComment: true) == .none)
        d.set(true, forKey: ShareLinkMode.legacyEnabledKey)
        check("share link: the old Include Link toggle reads as Post Link", ShareLinkMode.read(d, hasComment: true) == .post)
        ShareLinkMode.write(.comment, d)
        check("share link: a saved Comment reads as Post on a post share, and stays Comment",
              ShareLinkMode.read(d, hasComment: false) == .post && ShareLinkMode.read(d, hasComment: true) == .comment)
        check("share link: writing keeps Reborn's Boolean in step",
              d.bool(forKey: ShareLinkMode.legacyEnabledKey) && { ShareLinkMode.write(.none, d); return !d.bool(forKey: ShareLinkMode.legacyEnabledKey) }())
        check("share link: Comment Link is only offered with a comment",
              ShareLinkMode.options(hasComment: false) == [.none, .post] && ShareLinkMode.options(hasComment: true).last == .comment)
        let post = URL(string: "https://reddit.com/r/a/comments/1/x/")!, comment = URL(string: "https://reddit.com/r/a/comments/1/x/c2/")!
        check("share link: each mode picks its URL",
              ShareLinkMode.none.url(post: post, comment: comment) == nil
                && ShareLinkMode.post.url(post: post, comment: comment) == post
                && ShareLinkMode.comment.url(post: post, comment: comment) == comment
                && ShareLinkMode.comment.url(post: post, comment: nil) == post)
        d.removePersistentDomain(forName: "smoke.shareLinkMode")
    }

    // Reborn #1236: a rejected API key at sign-in is explained.
    do {
        let grant = URL(string: "https://www.reddit.com/svc/shreddit/oauth-grant")!
        let authorize = URL(string: "https://old.reddit.com/api/v1/authorize.compact?client_id=x")!
        check("sign-in: a failed consent grant is caught; a 200 and other pages load",
              OAuthConsentFailure.classify(url: grant, status: 400) == .grantRejected
                && OAuthConsentFailure.classify(url: grant, status: 200) == nil
                && OAuthConsentFailure.classify(url: URL(string: "https://www.reddit.com/login")!, status: 400) == nil
                && OAuthConsentFailure.classify(url: URL(string: "https://evil.com/svc/shreddit/oauth-grant")!, status: 400) == nil)
        check("sign-in: an authorize page error is caught", OAuthConsentFailure.classify(url: authorize, status: 400) == .authorizeRejected)
        check("sign-in: a 400 says the key wasn't accepted, other errors offer Old Reddit",
              OAuthConsentFailure.alert(status: 400, offerOldReddit: true, hasCustomKey: true).title == "Reddit Didn't Accept This API Key"
                && OAuthConsentFailure.alert(status: 500, offerOldReddit: true, hasCustomKey: false).message.contains("switch to Old Reddit"))
        check("sign-in: Switch to Old Reddit restarts the authorize request there",
              OAuthConsentFailure.oldRedditURL(URL(string: "https://www.reddit.com/api/v1/authorize?client_id=x")!).absoluteString
                == "https://old.reddit.com/api/v1/authorize?client_id=x")
        check("sign-in: pasted API keys are trimmed", CustomAPISettingsStore.trimmed("  abc \n") == "abc" && CustomAPISettingsStore.trimmed(" ") == nil)
    }

    // Reborn #1256: a RedGIFs token is bound to the IP that minted it.
    check("RedGIFs: a 401 counts as a rejected token, other failures don't",
          RedGifsClient.isRejectedToken(status: 401) && !RedGifsClient.isRejectedToken(status: 404)
            && !RedGifsClient.isRejectedToken(status: 200))

    // Floating in-app Picture in Picture.
    do {
        typealias P = PictureInPicturePolicy
        var on = PictureInPictureSettings(); on.inAppEnabled = true
        on.activation = .unmutedOnly
        check("PiP Unmuted Only: an unmuted video with sound, not a muted one",
              P.shouldActivate(settings: on, isPlaying: true, isMuted: false, isSilent: false)
                && !P.shouldActivate(settings: on, isPlaying: true, isMuted: true, isSilent: false))
        on.activation = .allVideos
        check("PiP All Videos: muted videos too, but no silent GIFs",
              P.shouldActivate(settings: on, isPlaying: true, isMuted: true, isSilent: false)
                && !P.shouldActivate(settings: on, isPlaying: true, isMuted: true, isSilent: true))
        on.activation = .allVideosAndGIFs
        check("PiP All Videos & GIFs admits silent GIFs",
              P.shouldActivate(settings: on, isPlaying: true, isMuted: true, isSilent: true))
        check("PiP never takes a paused video",
              !P.shouldActivate(settings: on, isPlaying: false, isMuted: false, isSilent: false))
        var system = PictureInPictureSettings(); system.systemEnabled = true; system.activation = .allVideos
        check("PiP When Leaving App arms a playing video under the same modes",
              P.armsSystemPiP(settings: system, isPlaying: true, isMuted: true, isSilent: false)
                && !P.armsSystemPiP(settings: PictureInPictureSettings(), isPlaying: true, isMuted: false, isSilent: false))
        var noLoop = PictureInPictureSettings(); noLoop.loopVideos = false
        check("PiP GIFs always loop; videos follow Loop Videos",
              P.loops(isGIF: true, settings: noLoop) && !P.loops(isGIF: false, settings: noLoop))
        check("PiP fullscreen entry: only with in-app PiP and no inline autoplay",
              P.showsFullscreenEntry(inAppEnabled: true, autoplaysInline: false, isSpoilerOrNSFW: false, isURLOpened: false)
                && P.showsFullscreenEntry(inAppEnabled: true, autoplaysInline: true, isSpoilerOrNSFW: true, isURLOpened: false)
                && P.showsFullscreenEntry(inAppEnabled: true, autoplaysInline: true, isSpoilerOrNSFW: false, isURLOpened: true)
                && !P.showsFullscreenEntry(inAppEnabled: true, autoplaysInline: true, isSpoilerOrNSFW: false, isURLOpened: false)
                && !P.showsFullscreenEntry(inAppEnabled: false, autoplaysInline: false, isSpoilerOrNSFW: true, isURLOpened: true))
        check("PiP back-pop: restore into a visible feed row, else close; a fullscreen card stays",
              P.backPop(homeVisible: true, fromFullscreen: false) == .restoreInline
                && P.backPop(homeVisible: false, fromFullscreen: false) == .close
                && P.backPop(homeVisible: false, fromFullscreen: true) == .keep)
    }

    // Push notifications: self-hosted apollo-backend + Bark.
    do {
        typealias P = PushNotificationClient
        check("backend URL parsing trims slashes and needs http(s)+host",
              P.parseHTTPURL(" http://h:4000/ ")?.absoluteString == "http://h:4000"
              && P.parseHTTPURL("ftp://h") == nil && P.parseHTTPURL("http://") == nil)
        let bark = NotificationBackendSettings(backendURL: "http://h:4000", registrationToken: nil, barkEnabled: true, barkPushURL: "https://api.day.app/KEY")
        check("Bark mode needs Bark AND a backend", P.barkModeActive(bark)
              && !P.barkModeActive(NotificationBackendSettings(backendURL: nil, registrationToken: nil, barkEnabled: true, barkPushURL: "https://api.day.app/K")))
        let d = UserDefaults(suiteName: "smoke.push")!
        d.removePersistentDomain(forName: "smoke.push")
        let t1 = P.syntheticTokenHex(defaults: d), t2 = P.syntheticTokenHex(defaults: d)
        check("the synthetic device token is 64 hex and stable", t1.count == 64 && t1.allSatisfy(\.isHexDigit) && t1 == t2)
        let dev = P.deviceBody(token: "ab", barkEndpoint: URL(string: "https://api.day.app/K")!)
        check("device body uses the backend's field names (APNSToken, transport=bark)",
              dev["APNSToken"] as? String == "ab" && dev["transport"] as? String == "bark"
              && dev["transport_endpoint"] as? String == "https://api.day.app/K"
              && dev["url_scheme"] as? String == "phoebus")
        check("the chosen sound is pinned as ?sound=",
              P.effectiveBarkURL(URL(string: "https://api.day.app/K")!, soundID: "diabolicalDoorbell").absoluteString
                  == "https://api.day.app/K?sound=diabolicalDoorbell")
        check("Bark sound ids are Apollo's camelCase names",
              NotificationSound.diabolicalDoorbell.barkSoundID == "diabolicalDoorbell" && NotificationSound.defaultSound.barkSoundID == nil && NotificationSound.none.barkSoundID == "silence")
        check("a Bark 200 needs code 200 in the body",
              P.barkAccepted(status: 200, body: Data(#"{"code":200,"message":"success"}"#.utf8)).0
              && !P.barkAccepted(status: 200, body: Data(#"{"code":400,"message":"failed"}"#.utf8)).0)
        let w = P.watcherBody(type: "subreddit", subreddit: "linux", user: nil, label: "linux", keyword: "kde")
        check("watcher body uses createWatcherRequest's capitalised names",
              w["Type"] as? String == "subreddit" && w["Subreddit"] as? String == "linux"
              && (w["Criteria"] as? [String: Any])?["Keyword"] as? String == "kde")
        check("backend apollo:// click URLs map to this app's scheme",
              P.appURL(fromApolloURL: URL(string: "apollo://reddit.com/r/a/comments/b/_/c/?context=1")!)?.absoluteString
                  == "phoebus://reddit.com/r/a/comments/b/_/c/?context=1")
        let target = RedditURLTarget.parseAppScheme(URL(string: "phoebus://reddit.com/r/a/comments/b/_/c/?context=1")!)
        check("a comment click URL opens that comment", target == .comment(subreddit: "a", postID: "b", commentID: "c"))

        // APNs when the signing has push, Bark otherwise.
        let a = UserDefaults(suiteName: "smoke.push.apns")!
        a.removePersistentDomain(forName: "smoke.push.apns")
        let noBark = NotificationBackendSettings(backendURL: "http://h:4000", registrationToken: nil, barkEnabled: false, barkPushURL: nil)
        check("without an APNs token or Bark there is nothing to register",
              PushDeviceIdentity.current(settings: noBark, defaults: a) == nil && !P.deliveryActive(noBark, defaults: a))
        check("without an APNs token, Bark's synthetic token registers",
              PushDeviceIdentity.current(settings: bark, defaults: a)?.transport == .bark && P.deliveryActive(bark, defaults: a))
        check("a stored APNs token is new the first time, not the second",
              PushDeviceIdentity.storeAPNSToken(Data([0xab, 0x01]), sandbox: true, defaults: a)
              && !PushDeviceIdentity.storeAPNSToken(Data([0xab, 0x01]), sandbox: true, defaults: a))
        let apns = PushDeviceIdentity.current(settings: noBark, defaults: a)
        check("without Bark an APNs token registers, hex-encoded",
              apns?.transport == .apns && apns?.token == "ab01" && PushDeviceIdentity.apnsSandbox(defaults: a)
              && P.deliveryActive(noBark, defaults: a) && PushDeviceIdentity.usesAPNS(settings: noBark, defaults: a))
        check("a Bark URL wins over an APNs token",
              PushDeviceIdentity.current(settings: bark, defaults: a)?.transport == .bark
              && !PushDeviceIdentity.usesAPNS(settings: bark, defaults: a))
        PushDeviceIdentity.clearAPNSToken(defaults: a)
        check("clearing the APNs token leaves nothing without Bark",
              PushDeviceIdentity.current(settings: noBark, defaults: a) == nil)
        let apnsBody = P.apnsDeviceBody(token: "ab01", sandbox: true)
        check("APNs device body: transport apns with the sandbox flag",
              apnsBody["transport"] as? String == "apns" && apnsBody["Sandbox"] as? Bool == true
              && apnsBody["APNSToken"] as? String == "ab01")
        let profile = Data("garbage<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Entitlements</key><dict><key>aps-environment</key><string>development</string></dict></dict></plist>trailer".utf8)
        check("aps-environment is read from a provisioning profile",
              PushDeviceIdentity.apsEnvironment(provisioningProfile: profile) == "development"
              && PushDeviceIdentity.apsEnvironment(provisioningProfile: Data("no plist".utf8)) == nil)

        // Taps on APNs notifications, as the backend's Bark click URLs.
        check("a reply push opens its comment in context",
              P.appURL(fromPushPayload: ["type": "comment", "subreddit": "swift", "post_id": "abc", "comment_id": "def"])?.absoluteString
                  == "phoebus://reddit.com/r/swift/comments/abc/_/def/?context=1")
        check("a watcher push opens the post",
              P.appURL(fromPushPayload: ["subreddit": "swift", "post_id": "abc", "post_title": "t"])?.absoluteString
                  == "phoebus://reddit.com/r/swift/comments/abc")
        check("a private message push opens the inbox",
              P.appURL(fromPushPayload: ["type": "private-message", "account_id": "x"])?.absoluteString == "phoebus://reborn/inbox")
        check("an unrelated notification opens nothing", P.appURL(fromPushPayload: ["foo": "bar"]) == nil)
    }

    // Watcher composer + user watchers.
    do {
        let w = PushNotificationClient.watcherBody(type: "subreddit", subreddit: "programming", user: nil, label: "Rust posts",
                                                   keyword: "rust", upvotes: 50, flair: "news", domain: "github.com", author: "someone")
        let c = w["Criteria"] as? [String: Any] ?? [:]
        check("watcher filters map onto the backend's Criteria",
              c["Keyword"] as? String == "rust" && c["Upvotes"] as? Int64 == 50 && c["Flair"] as? String == "news"
              && c["Domain"] as? String == "github.com" && c["Author"] as? String == "someone")
        let u = PushNotificationClient.watcherBody(type: "user", subreddit: nil, user: "spez", label: "spez")
        check("a user watcher names the user", u["Type"] as? String == "user" && u["User"] as? String == "spez")
    }

    // Chat unread -> Bark (Reborn's chat unread poller transitions).
    do {
        typealias C = ChatUnreadNotifier
        let m = C.Marks(unread: 2, requests: 0, latestTs: 100)
        check("a rise in unread pushes", C.decide(unread: 3, requests: 0, latestTs: 100, marks: m).pushUnread)
        check("a newer message at a steady total still pushes", C.decide(unread: 2, requests: 0, latestTs: 200, marks: m).pushUnread)
        check("a drop pushes nothing", C.decide(unread: 1, requests: 0, latestTs: 100, marks: m) == .init(pushUnread: false, pushRequests: false))
        check("the first-ever mark (ts 0) never announces history by timestamp",
              !C.decide(unread: 2, requests: 0, latestTs: 500, marks: .init(unread: 2, requests: 0, latestTs: 0)).pushUnread)
        check("new requests push", C.decide(unread: 2, requests: 1, latestTs: 100, marks: m).pushRequests)
        check("upstream's chat titles", C.unreadTitle(1) == "New Chat Message" && C.unreadTitle(3) == "3 Unread Chat Messages"
              && C.requestsTitle(2) == "2 New Chat Requests")
        check("a chat push link lands on the Inbox tab",
              QuickAction.parse(URL(string: "phoebus://reborn/chat/room/!abc")!) == .inbox)
    }

    // Dynamic Type + VoiceOver (Reborn #1165).
    do {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let said = AccessibilitySummary.post(title: "TIL a thing", subreddit: "todayilearned", author: "bob",
                                             score: 13_600, comments: 1, created: now.addingTimeInterval(-3 * 3600),
                                             flair: "Science", domain: "example.com", nsfw: true, saved: true, vote: true, now: now)
        check("a post reads in words, not glyphs",
              said == "NSFW, TIL a thing, Science, link to example.com, in todayilearned by bob, 13600 points, 1 comment, 3 hours ago, Upvoted, Saved")
        check("a collapsed comment reads its hidden replies instead of its body",
              AccessibilitySummary.comment(author: "amy", body: "long body", score: 1, scoreHidden: false,
                                           created: now.addingTimeInterval(-30), isOP: true, collapsed: true,
                                           hiddenReplies: 4, now: now)
              == "amy, original poster, 1 point, just now, Collapsed, 4 replies hidden")
        check("a hidden score is not spoken",
              !AccessibilitySummary.comment(author: "a", body: "b", score: 5, scoreHidden: true, created: now, now: now).contains("point"))
        check("comment markdown is spoken as prose",
              AccessibilitySummary.spoken(markdown: "**Do you** [Click here](https://x.y/z).\n\n> quoted &amp; ~~old~~")
              == "Do you Click here. quoted & old")
        check("an inbox message reads unread state, sender and subject first",
              AccessibilitySummary.message(author: "bob", subject: "comment reply", body: "**hi**", created: now,
                                           unread: true, isCommentReply: true, now: now)
              == "Unread, Reply from bob, comment reply, just now, hi")
        check("ages are spoken in full", AccessibilitySummary.age(now.addingTimeInterval(-2 * 86_400), now: now) == "2 days ago")
    }

    // An empty (pre-any-field) settings blob must decode to exactly the
    // shipped defaults, so no field's decode fallback drifts from `.default`.
    do {
        let sparse = try! JSONDecoder().decode(GeneralSettings.self, from: Data("{}".utf8))
        let a = Mirror(reflecting: sparse).children, b = Mirror(reflecting: GeneralSettings.default).children
        // The unmute modes migrate from the legacy unmuteVideosWhenOpened
        // (default "remember") when their own keys are absent.
        let migrated: Set<String> = ["unmuteFeedVideosMode", "unmuteCommentsVideosMode"]
        let drift = zip(a, b).compactMap { x, y in
            String(describing: x.value) == String(describing: y.value) || migrated.contains(x.label ?? "") ? nil : x.label
        }
        if !drift.isEmpty { print("      drift: \(drift)") }
        check("an empty GeneralSettings blob decodes to .default (\(drift.count) drifted)", drift.isEmpty)
    }

    // GeneralSettingsStore caches the decoded value by stored bytes: a save,
    // or any direct write to the key (backup restore), must be seen at once.
    do {
        let original = GeneralSettingsStore.load()
        var changed = original
        changed.memechineLearningEnabled.toggle()
        GeneralSettingsStore.save(changed)
        check("a save is visible to the next load", GeneralSettingsStore.load() == changed)
        UserDefaults.standard.set(try! JSONEncoder().encode(original), forKey: "com.pendo324.Phoebus.generalSettings")
        check("a direct write to the key (backup restore) bypasses the cache", GeneralSettingsStore.load() == original)
        GeneralSettingsStore.save(original)
    }

    // SettingsStore memoizes its decode by stored bytes; a save or any
    // direct write to the key must be seen by the very next load.
    do {
        let defaults = UserDefaults(suiteName: "smoke.jsondefaults")!
        defaults.removePersistentDomain(forName: "smoke.jsondefaults")
        let store = SettingsStore<[String]>(key: "memo") { ["default"] }
        check("a missing key loads the default", store.load(from: defaults) == ["default"])
        store.save(["a"], to: defaults)
        check("a save is seen by the next load", store.load(from: defaults) == ["a"])
        check("a repeated load returns the same value", store.load(from: defaults) == ["a"])
        defaults.set(try! JSONEncoder().encode(["b"]), forKey: "memo")
        check("a direct write to the key is seen by the next load", store.load(from: defaults) == ["b"])
        defaults.set(Data("not json".utf8), forKey: "memo")
        check("undecodable bytes fall back to the default", store.load(from: defaults) == ["default"])
        defaults.removeObject(forKey: "memo")
        check("a removed key falls back to the default", store.load(from: defaults) == ["default"])
    }

    // SettingsStore: one way to store every setting.
    do {
        let defaults = UserDefaults(suiteName: "smoke.settingsstore")!
        defaults.removePersistentDomain(forName: "smoke.settingsstore")
        struct Pair: Codable, Equatable, Sendable { var a = 1, b = 2 }
        let store = SettingsStore<Pair>(key: "pair") { Pair() }
        let heard = NSLock.Protected<[String]>([])
        let token = NotificationCenter.default.addObserver(forName: .apolloSettingsChanged, object: nil, queue: nil) { note in
            if let key = note.object as? String { heard.set(heard.get() + [key]) }
        }
        store.update(in: defaults) { $0.a = 5 }
        // Someone else changes b (a child screen, a restore)...
        defaults.set(try! JSONEncoder().encode(Pair(a: 5, b: 9)), forKey: "pair")
        // ...and an update to a from an older screen keeps it.
        store.update(in: defaults) { $0.a = 6 }
        check("settings: update changes one field of the stored value, keeping others' changes",
              store.load(from: defaults) == Pair(a: 6, b: 9))
        check("settings: every save announces its key", heard.get() == ["pair", "pair"])
        NotificationCenter.default.removeObserver(token)
        let migrating = SettingsStore<Pair>(key: "mig", migrate: { value, _ in
            guard value.b != 0 else { return false }; value.b = 0; return true }) { Pair() }
        // Stored bytes from before the migration existed.
        defaults.set(try! JSONEncoder().encode(Pair(a: 1, b: 7)), forKey: "mig")
        _ = migrating.load(from: defaults)
        check("settings: a migration runs on decode and is saved",
              (try? JSONDecoder().decode(Pair.self, from: defaults.data(forKey: "mig") ?? Data()))?.b == 0)
        defaults.removePersistentDomain(forName: "smoke.settingsstore")
    }

    // Share as Image keeps a post's text alongside its image; lines that are
    // only an image link are dropped, since the image is already shown.
    do {
        func sharePost(isSelf: Bool, selftext: String) -> RedditPost {
            let json = """
            {"id":"x","name":"t3_x","title":"t","author":"a","subreddit":"s","permalink":"/r/s/comments/x/",
             "score":1,"num_comments":0,"created_utc":0,"is_self":\(isSelf),"saved":false,"over_18":false,"spoiler":false,"stickied":false,
             "selftext":\(String(data: try! JSONEncoder().encode(selftext), encoding: .utf8)!),
             "url":"https://i.redd.it/x.jpg"}
            """.data(using: .utf8)!
            return try! JSONDecoder.reddit.decode(RedditPost.self, from: json)
        }
        check("an image post's own text is kept for the card",
              ShareCardFormatting.bodyText(of: sharePost(isSelf: false, selftext: "Look at this.")) == "Look at this.")
        check("a line that is only an image link is dropped",
              ShareCardFormatting.bodyText(of: sharePost(isSelf: true, selftext: "Caption\nhttps://i.redd.it/abc.jpg")) == "Caption")
        check("a body that is only an image link leaves no text",
              ShareCardFormatting.bodyText(of: sharePost(isSelf: true, selftext: "https://i.redd.it/abc.jpg")) == nil)
        check("an ordinary link line stays in the text",
              ShareCardFormatting.bodyText(of: sharePost(isSelf: true, selftext: "See https://example.com/page")) == "See https://example.com/page")
    }

    // Reddit's subreddit-less share links, and image-only lines in comments.
    do {
        check("reddit.com/comments/<id> opens the post",
              RedditURLTarget.parse(URL(string: "https://reddit.com/comments/1wpp5r8")!) == .post(subreddit: "", id: "1wpp5r8"))
        check("reddit.com/comments/<id>/_/<comment> opens the comment",
              RedditURLTarget.parse(URL(string: "https://reddit.com/comments/1wpp5r8/_/pbyi0sy")!)
                == .comment(subreddit: "", postID: "1wpp5r8", commentID: "pbyi0sy"))
        check("a markdown image link on its own line is dropped when the image is drawn",
              ShareCardFormatting.removingImageOnlyLines("Look\n[pic](https://i.imgur.com/a.jpg)") == "Look")
        check("an inline text link stays",
              ShareCardFormatting.removingImageOnlyLines("the other. [Like this](https://i.imgur.com/a.jpg).") == "the other. [Like this](https://i.imgur.com/a.jpg).")
    }

    // Reborn Confirm Favorite Changes (#1173) prompt copy.
    check("confirm favorite prompt: adding",
          FavoriteSubredditsStore.confirmPrompt(name: "swift", isFavorite: false) == ("Favorite r/swift?", "Favorite"))
    check("confirm favorite prompt: removing",
          FavoriteSubredditsStore.confirmPrompt(name: "swift", isFavorite: true) == ("Remove r/swift from Favorites?", "Unfavorite"))

    // Reborn #1200: a revoked refresh token is told apart from transient failures.
    check("refresh: 200 with a token is ok",
          TokenRefreshOutcome.classify(status: 200, body: Data(#"{"access_token":"a","token_type":"bearer","expires_in":86400,"scope":"*"}"#.utf8)) == .ok)
    check("refresh: 200 with invalid_grant is revoked",
          TokenRefreshOutcome.classify(status: 200, body: Data(#"{"error":"invalid_grant"}"#.utf8)) == .revoked)
    check("refresh: 400 is revoked", TokenRefreshOutcome.classify(status: 400, body: Data()) == .revoked)
    check("refresh: 401 is revoked", TokenRefreshOutcome.classify(status: 401, body: Data()) == .revoked)
    check("refresh: 429 is transient, not a sign-out", TokenRefreshOutcome.classify(status: 429, body: Data()) == .transient)
    check("refresh: 503 is transient", TokenRefreshOutcome.classify(status: 503, body: Data()) == .transient)

    // Reborn Action Menus (#1131): layout resolution and arrangement.
    do {
        let suite = UserDefaults(suiteName: "smoke.actionMenus")!
        suite.removePersistentDomain(forName: "smoke.actionMenus")
        let saved = ActionMenuLayoutStore.defaults
        ActionMenuLayoutStore.defaults = suite
        defer { ActionMenuLayoutStore.defaults = saved }

        let appIDs = ["upvote", "downvote", "reply", "quote", "save", "share", "copy-link", "report"]
        check("action menus: an untouched menu keeps the app's order",
              ActionMenuLayoutStore.arrange(appIDs, for: .comment) == appIDs)
        check("action menus: untouched summary is Default", ActionMenuLayoutStore.summary(.comment) == "Default")

        ActionMenuLayoutStore.setHidden(true, itemID: "downvote", for: .comment)
        check("action menus: a hidden item drops out, the rest keep order",
              ActionMenuLayoutStore.arrange(appIDs, for: .comment) == ["upvote", "reply", "quote", "save", "share", "copy-link", "report"])
        check("action menus: summary counts hidden", ActionMenuLayoutStore.summary(.comment) == "1 hidden")

        var order = ActionMenuLayoutStore.resolvedOrder(.comment)
        order.removeAll { $0 == "share" }
        order.insert("share", at: 0)
        ActionMenuLayoutStore.setOrder(order, for: .comment)
        check("action menus: a moved item leads, extras travel with their neighbour",
              // Apollo's comment order has Save before Reply; Quote rides with Reply.
              ActionMenuLayoutStore.arrange(appIDs, for: .comment) == ["share", "copy-link", "upvote", "save", "reply", "quote", "report"])
        check("action menus: summary shows both", ActionMenuLayoutStore.summary(.comment) == "Custom order · 1 hidden")
        check("action menus: interface summary names the menu",
              ActionMenuLayoutStore.interfaceSummary() == "Customized: Comment")

        ActionMenuLayoutStore.setHidden(true, itemID: "submit", for: .feed)
        check("action menus: a locked item cannot be hidden", ActionMenuLayoutStore.hiddenIDs(.feed).isEmpty)
        ActionMenuLayoutStore.setOrder(["share", "submit"], for: .feed)
        check("action menus: locked Submit Post stays first",
              ActionMenuLayoutStore.resolvedOrder(.feed).prefix(2) == ["submit", "share"])
        check("action menus: catalogue items missing from a saved order are appended",
              ActionMenuLayoutStore.resolvedOrder(.feed).count == ActionMenuCatalog.items(for: .feed).count)

        ActionMenuLayoutStore.resetAll()
        check("action menus: reset all clears every layout",
              !ActionMenuContext.allCases.contains(where: ActionMenuLayoutStore.isCustomized))
        check("action menus: every context's catalogue ids are unique",
              ActionMenuContext.allCases.allSatisfy { Set(ActionMenuCatalog.items(for: $0).map(\.id)).count == ActionMenuCatalog.items(for: $0).count })
    }

    // SHA-256 known answers, and Reborn chat drafts (#1207).
    check("sha256 of empty", SHA256Digest.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("sha256 of abc", SHA256Digest.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    check("sha256 across two blocks",
          SHA256Digest.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    do {
        let savedBackend = MessageDraftStore.backend, savedNow = MessageDraftStore.now
        defer { MessageDraftStore.backend = savedBackend; MessageDraftStore.now = savedNow }
        MessageDraftStore.backend = MessageDraftStore.MemoryBackend()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        MessageDraftStore.now = { clock }
        MessageDraftStore.save("hello", account: "Alice", conversation: "!room:reddit.com")
        check("drafts: restored for the same account and conversation",
              MessageDraftStore.load(account: "alice", conversation: "!room:reddit.com") == "hello")
        check("drafts: another account does not see it",
              MessageDraftStore.load(account: "bob", conversation: "!room:reddit.com") == nil)
        check("drafts: another conversation does not see it",
              MessageDraftStore.load(account: "alice", conversation: "!other:reddit.com") == nil)
        check("drafts: an unresolved account never reads or writes",
              MessageDraftStore.opaqueKey(account: "", conversation: "!room:reddit.com") == nil)
        check("drafts: the key never contains the username",
              !(MessageDraftStore.opaqueKey(account: "alice", conversation: "x") ?? "alice").contains("alice"))
        MessageDraftStore.save("  ", account: "alice", conversation: "!room:reddit.com")
        check("drafts: saving blank removes it", MessageDraftStore.load(account: "alice", conversation: "!room:reddit.com") == nil)
        MessageDraftStore.save("later", account: "alice", conversation: "!room:reddit.com")
        clock = clock.addingTimeInterval(MessageDraftStore.maximumAge + 1)
        check("drafts: a draft idle past 30 days expires",
              MessageDraftStore.load(account: "alice", conversation: "!room:reddit.com") == nil)
    }

    // Reborn #1196: a posted comment is read from /api/comment and inserted in place.
    do {
        let response = Data(#"{"json":{"errors":[],"data":{"things":[{"kind":"t1","data":{"id":"new1","name":"t1_new1","author":"me","body":"hi","score":1,"created_utc":1700000000,"parent_id":"t1_root","link_id":"t3_p","saved":false,"score_hidden":false,"stickied":false}}]}}}"#.utf8)
        let posted = PostedCommentResponse.comment(from: response)
        check("posted comment: decoded from the api_type=json envelope", posted?.id == "new1")
        check("posted comment: a RATELIMIT response throws",
              (try? PostedCommentResponse.throwIfRejected(Data(#"{"json":{"errors":[["RATELIMIT","slow down","ratelimit"]]}}"#.utf8))) == nil)
        check("posted comment: a refusal keeps Reddit's code and message",
              { do { try PostedCommentResponse.throwIfRejected(Data(#"{"json":{"errors":[["THREAD_LOCKED","that thread is locked","parent"]]}}"#.utf8)); return false }
                catch let e as CommentRejectedError { return e == CommentRejectedError(code: "THREAD_LOCKED", message: "that thread is locked") }
                catch { return false } }())
        typealias CSF = CommentSubmitFailure
        check("comment failure: Reborn #1275 copy for a locked thread",
              CSF.explain(CommentRejectedError(code: "THREAD_LOCKED", message: "x"))
                == .init(title: "Comments Locked", message: "This thread is locked, so it can't take new comments."))
        check("comment failure: archived and deleted parents get their own copy",
              CSF.explain(CommentRejectedError(code: "TOO_OLD", message: "")).title == "Post Archived"
                && CSF.explain(CommentRejectedError(code: "DELETED_COMMENT", message: "")).title == "Comment Deleted")
        check("comment failure: an unknown code quotes Reddit, capitalised with a full stop",
              CSF.explain(CommentRejectedError(code: "SOMETHING", message: "you can't do that")).message
                == "Reddit said: \u{201C}You can't do that.\u{201D}")
        check("posted comment: a clean response does not throw",
              (try? PostedCommentResponse.throwIfRejected(response)) != nil)
        check("posted comment: an error response yields nothing",
              PostedCommentResponse.comment(from: Data(#"{"json":{"errors":[["RATELIMIT","slow down","ratelimit"]]}}"#.utf8)) == nil)
        if let posted {
            let parent = CommentTreeNode(comment: makeComment(id: "root"), depth: 0,
                                         children: [CommentTreeNode(comment: makeComment(id: "old"), depth: 1)], isCollapsed: true)
            let updated = parent.inserting(reply: posted, under: "t1_root")
            check("posted comment: lands first under its parent", updated?.children.first?.id == "new1")
            check("posted comment: one level deeper than its parent", updated?.children.first?.depth == 1)
            check("posted comment: the parent is expanded to show it", updated?.isCollapsed == false)
            check("posted comment: a missing parent returns nil",
                  parent.inserting(reply: posted, under: "t1_elsewhere") == nil)
        }
    }

    // Reborn #1231: Reddit's footer is never a social link.
    check("social links: redditinc.com footer dropped",
          SocialLinkScraper.isRedditChromeLink("https://www.redditinc.com/policies", title: "Privacy Policy"))
    check("social links: reddithelp dropped",
          SocialLinkScraper.isRedditChromeLink("https://support.reddithelp.com/hc", title: "Accessibility"))
    check("social links: copyright line dropped",
          SocialLinkScraper.isRedditChromeLink("https://example.com", title: "Reddit, Inc. © 2026. All rights reserved."))
    check("social links: a user's own subreddit is kept",
          !SocialLinkScraper.isRedditChromeLink("https://www.reddit.com/r/mysub", title: "My sub"))
    check("social links: an ordinary link is kept",
          !SocialLinkScraper.isRedditChromeLink("https://twitter.com/me", title: "Twitter"))

    // Reborn #1215: old-reddit sprite flairs with no text show their class name.
    check("flair class: camelCase", RedditFlairOption.prettifiedClass("princessPeach") == "Princess Peach")
    check("flair class: numeric variant dropped", RedditFlairOption.prettifiedClass("Beerus-001") == "Beerus")
    check("flair class: separators", RedditFlairOption.prettifiedClass("dark_link") == "Dark Link")
    check("flair class: empty stays nil", RedditFlairOption.prettifiedClass("  ") == nil)

    // Old-reddit sprite flairs (Reborn #1215).
    // Rules trimmed from r/nintendo's stylesheet.
    do {
        let css = """
        /* 6.2 User Flair */
        .flair:before { content: ""; height: 28px; width: 28px; display: inline-block;
            background-repeat: no-repeat; background-image: url(%%ninFlair%%); border-radius: 100%; }
        .flair-kingBoo:before, a[href="#flair-kingBoo"]:before { background-position: -102px -69px }
        .flair-bigOne:before { background-position: 0 -10px; width: 40px }
        """
        let images = ["ninFlair": "http://b.thumbs.redditmedia.com/sheet.png"]
        let map = FlairSprites.parse(css: css, images: images)
        check("flair sprites: a class maps to its region of the one sheet",
              map["kingBoo"]?.rect == CGRect(x: 102, y: 69, width: 28, height: 28)
                && map["kingBoo"]?.sheetURL.absoluteString == "https://b.thumbs.redditmedia.com/sheet.png")
        check("flair sprites: border-radius on the base rule makes them round", map["kingBoo"]?.isRound == true)
        check("flair sprites: a rule's own width overrides the base size",
              map["bigOne"]?.rect == CGRect(x: 0, y: 10, width: 40, height: 28))
        let twoSheets = css + "\n.flair.alt { background-image: url(https://x.example/other.png); width: 20px; height: 20px }"
        check("flair sprites: more than one flair sheet is refused (names only)",
              FlairSprites.parse(css: twoSheets, images: images).isEmpty)
        check("flair sprites: no base rule, nothing to crop",
              FlairSprites.parse(css: ".flair-a { background-position: 0 0 }", images: [:]).isEmpty)
        check("flair sprites: only text-less templates draw a sprite",
              RedditFlairOption(flairTemplateID: "a", text: "", cssClass: "kingBoo").spriteClass == "kingBoo"
                && RedditFlairOption(flairTemplateID: "b", text: "suzuha amane", cssClass: "avatar").spriteClass == nil)
    }
    check("flair option: text wins over class",
          RedditFlairOption(flairTemplateID: "a", text: "Mario", cssClass: "luigi").displayText == "Mario")
    check("flair option: blank text falls back to class",
          RedditFlairOption(flairTemplateID: "a", text: "", cssClass: "kingBoo").displayText == "King Boo")

    // Apollo's PostCommentsSnapshots import (feed "+ N" pills).
    check("comment snapshots: Apollo's alternating id/object array decodes",
          NewCommentsTracker.decodeApolloSnapshots(Data(#"["1abc234",{"totalComments":43,"timestamp":807459304.8},"1def567",{"totalComments":20,"timestamp":1}]"#.utf8))
            == ["1abc234": 43, "1def567": 20])
    check("comment snapshots: garbage yields nothing", NewCommentsTracker.decodeApolloSnapshots(Data("{}".utf8)).isEmpty)

    // Reddit's native comment media tokens and query-carrying preview links.
    check("giphy token becomes the Giphy file",
          InlineMediaDetector.detect(in: "![gif](giphy|WprZBG08PpMHvkkwYu)") == [.gif(URL(string: "https://media.giphy.com/media/WprZBG08PpMHvkkwYu/giphy.gif")!)])
    check("giphy token with a size suffix still resolves",
          InlineMediaDetector.detect(in: "![gif](giphy|abc123|downsized)") == [.gif(URL(string: "https://media.giphy.com/media/abc123/giphy.gif")!)])
    check("an uploaded image token resolves to i.redd.it",
          InlineMediaDetector.detect(in: "![img](2044n5q2k4sh1)") == [.image(URL(string: "https://i.redd.it/2044n5q2k4sh1.jpeg")!)])
    check("a preview.redd.it link with a query is an image",
          InlineMediaDetector.detect(in: "https://preview.redd.it/2044n5q2k4sh1.jpeg?width=1290&format=pjpg&auto=webp&s=ce98") .count == 1)
    check("the drawn token line leaves only the prose",
          ShareCardFormatting.removingImageOnlyLines(RedditMediaTokens.expand("Uuuuck\n\n![gif](giphy|GhGPnlp2Gl3TG)")) == "Uuuuck")
    check("a GIF-only comment leaves no text",
          ShareCardFormatting.removingImageOnlyLines(RedditMediaTokens.expand("![gif](giphy|GhGPnlp2Gl3TG)")).isEmpty)
    check("format=mp4 previews are still not images",
          InlineMediaDetector.classify(URL(string: "https://preview.redd.it/x.gif?format=mp4&s=1")!) == nil)

    // Inbox tab badge counts.
    check("inbox badge: inbox_count from /api/v1/me",
          InboxUnreadCount.fromIdentity(Data(#"{"name":"x","inbox_count":3,"has_mail":true}"#.utf8)) == 3)
    check("inbox badge: inbox_count from the web session's /api/me.json",
          InboxUnreadCount.fromIdentity(Data(#"{"kind":"t2","data":{"inbox_count":2}}"#.utf8)) == 2)
    check("inbox badge: missing count falls back", InboxUnreadCount.fromIdentity(Data(#"{"name":"x"}"#.utf8)) == nil)
    check("inbox badge: chat unread is added", InboxUnreadCount.combined(inbox: 1, chat: 2) == 3)
    // Reborn's combined inbox badge and modern chat unread badge counts.
    check("inbox badge: an OAuth inbox already lists chats, so the larger count shows",
          InboxUnreadCount.combined(inbox: 1, chat: 2, inboxListsChat: true) == 2)
    check("inbox badge: a pending chat request badges when nothing is unread",
          InboxUnreadCount.chat(unread: 0, requests: 1) == 1)
    check("inbox badge: unread chat and requests are not summed",
          InboxUnreadCount.chat(unread: 2, requests: 1) == 2)
    check("chat: a room without Reddit's badge flag counts toward the badge",
          (try? RedditChatClient.parseSync(Data(#"{"rooms":{"join":{"!r":{"unread_notifications":{"notification_count":1}}}}}"#.utf8)))?
              .rooms.first?.countsTowardGlobalBadge == true)

    // Reborn's inline media box.
    do {
        let row: CGFloat = 370, screen: CGFloat = 874
        let wide = InlineMediaFrame.fit(ratio: 0.5, rowWidth: row, screenHeight: screen, size: .large)
        check("inline media: a wide GIF fills the row at its own shape",
              wide.width == row && wide.height == 185 && !wide.isLetterboxed)
        let tall = InlineMediaFrame.fit(ratio: 2, rowWidth: row, screenHeight: screen, size: .large)
        check("inline media: a tall image is capped square-high and shrinks to fit",
              tall.height == row && tall.width == row / 2 && !tall.isLetterboxed)
        let sliver = InlineMediaFrame.fit(ratio: 20, rowWidth: row, screenHeight: screen, size: .large)
        check("inline media: a very tall image pins to 85pt and letterboxes",
              sliver.width == 85 && abs(sliver.height - row) < 0.001 && sliver.isLetterboxed)
        let banner = InlineMediaFrame.fit(ratio: 0.05, rowWidth: row, screenHeight: screen, size: .large)
        check("inline media: a banner keeps a 0.18 box, letterboxed",
              banner.width == row && abs(banner.height - row * 0.18) < 0.001 && banner.isLetterboxed)
        let landscape = InlineMediaFrame.fit(ratio: 0.75, rowWidth: 800, screenHeight: 400, size: .large)
        check("inline media: height is capped at 60% of the screen",
              abs(landscape.height - 240) < 0.001)
        let half = InlineMediaFrame.fit(ratio: 0.5, rowWidth: row, screenHeight: screen, size: .small)
        check("inline media: Inline Media Size 50% halves the width, keeping the shape",
              half.width == row / 2 && half.height == row / 4)
        let portraitVideo = InlineMediaFrame.fit(ratio: 16.0 / 9.0, rowWidth: row, screenHeight: 1000,
                                                 size: .large, isVideo: true)
        check("inline media: a portrait video is a full-row card up to 3:2",
              portraitVideo.width == row && abs(portraitVideo.height - row * 1.5) < 0.001 && portraitVideo.isLetterboxed)
        let shortScreenVideo = InlineMediaFrame.fit(ratio: 16.0 / 9.0, rowWidth: row, screenHeight: screen,
                                                    size: .large, isVideo: true)
        check("inline media: ...and never taller than 60% of the screen",
              abs(shortScreenVideo.height - screen * 0.6) < 0.001)
        check("inline media: 8pt corners and 4pt insets",
              InlineMediaFrame.cornerRadius == 8 && InlineMediaFrame.verticalInset == 4)
        check("inline media: a preview link's shape is read from its query",
              InlineMediaFrame.ratio(fromQueryOf: URL(string: "https://preview.redd.it/a.jpeg?width=640&height=320&format=pjpg")!) == 0.5)
        check("inline media: no query, no guess",
              InlineMediaFrame.ratio(fromQueryOf: URL(string: "https://i.redd.it/a.jpeg")!) == nil)
    }

    // Reborn's inline GIF autoplay and badge per Autoplay Inline GIFs mode.
    check("GIF autoplay: Always plays anywhere",
          InlineGIFAutoplayMode.always.autoplays(isUnmetered: false))
    check("GIF autoplay: WiFi Only plays only off cellular",
          InlineGIFAutoplayMode.wifiOnly.autoplays(isUnmetered: true)
            && !InlineGIFAutoplayMode.wifiOnly.autoplays(isUnmetered: false))
    check("GIF autoplay: Tap to Play and Never hold the GIF",
          !InlineGIFAutoplayMode.tapToPlay.autoplays(isUnmetered: true)
            && !InlineGIFAutoplayMode.never.autoplays(isUnmetered: true))
    check("GIF badge: Tap to Play always shows it",
          InlineGIFAutoplayMode.tapToPlay.showsPlayBadge(isUnmetered: true))
    check("GIF badge: WiFi Only shows it only while held on cellular",
          InlineGIFAutoplayMode.wifiOnly.showsPlayBadge(isUnmetered: false)
            && !InlineGIFAutoplayMode.wifiOnly.showsPlayBadge(isUnmetered: true))
    check("GIF badge: Never is a plain still, Always has none",
          !InlineGIFAutoplayMode.never.showsPlayBadge(isUnmetered: false)
            && !InlineGIFAutoplayMode.always.showsPlayBadge(isUnmetered: false))

    // Behaviour pinned by running the code rather than by reading source text.
    do {
        let other = SubredditListCache.Snapshot(subscriptions: [], multireddits: [], moderated: [], accountUsername: "alice")
        SubredditListCache.save(other)
        check("the subreddit list cache refuses to serve another account's list",
              SubredditListCache.load(for: "bob") == nil && SubredditListCache.load(for: "alice") != nil)
        SubredditListCache.clear()
        SubredditListCache.save(.init(subscriptions: [], multireddits: [], moderated: [], accountUsername: ""))
        check("the subreddit list cache does not write a snapshot with no account",
              SubredditListCache.load(for: "") == nil && SubredditListCache.load(for: "alice") == nil)
        SubredditListCache.clear()

        check("Profile Style values are the real Immersive/Compact/Native",
              ProfileLayoutSettings.Style.allCases.map(\.displayName) == ["Immersive", "Compact", "Native"])
        check("poll options default to centred", !GeneralSettings.default.pollOptionAlignmentLeft)
        check("Memechine Learning defaults off", !GeneralSettings.default.memechineLearningEnabled)

        let table = String(RedditMarkdown.render("a | b\n--|--\n1 | 2").characters)
        check("a rendered table shows no pipes", !table.contains("|") && table.contains("1"))

        let commentsResponse = Data(#"""
        [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{"num_comments":7}}]}},
         {"kind":"Listing","data":{"children":[{"kind":"t1","data":{"id":"c1","name":"t1_c1","author":"u","body":"b",
          "score":0,"created_utc":0,"parent_id":"t3_p","link_id":"t3_p","saved":false,"score_hidden":false,"stickied":false,
          "replies":""}}]}}]
        """#.utf8)
        let parsedComments = try? CommentTreeBuilder.parseCommentsResponse(commentsResponse, postID: "p")
        check("a comments response parses into the tree and the post's comment count",
              parsedComments?.roots.map(\.comment.id) == ["c1"] && parsedComments?.postCommentCount == 7)
        check("a comments response of the wrong shape is rejected, not thrown",
              (try! CommentTreeBuilder.parseCommentsResponse(Data("[]".utf8), postID: "p")) == nil)

        // A keychain still locked at launch (before the first unlock) must
        // not be taken for an empty account list and saved over the real one.
        final class LockableAccountStore: AccountKeychainStore, @unchecked Sendable {
            var locked = true, saves = 0
            var stored: AccountStorePersisted?
            func save(_ persisted: AccountStorePersisted) { saves += 1; stored = persisted }
            func load() -> AccountStorePersisted? { locked ? nil : stored }
            func clear() { stored = nil }
            var isLocked: Bool { locked }
        }
        let lockable = LockableAccountStore()
        lockable.stored = AccountStorePersisted(accounts: [StoredAccount(username: "real")], activeIndex: 0)
        let lockedStore = AccountStore(store: lockable)
        lockedStore.addOrUpdate(StoredAccount(username: "ghost"))
        check("a locked keychain's placeholder list is never saved", lockable.saves == 0)
        lockable.locked = false
        check("the real accounts load once the keychain unlocks", lockedStore.accounts.map(\.username) == ["real"])

        // Concurrent refreshes share one token request.
        final class TokenStub: URLProtocol, @unchecked Sendable {
            nonisolated(unsafe) static var requests = 0
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                Self.requests += 1
                Thread.sleep(forTimeInterval: 0.2)
                let body = Data(#"{"access_token":"new","token_type":"bearer","expires_in":3600,"scope":"*"}"#.utf8)
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        let stubConfig = URLSessionConfiguration.ephemeral
        stubConfig.protocolClasses = [TokenStub.self]
        let expiredStore = InMemoryCredentialStore()
        try? expiredStore.save(RedditCredential(accessToken: "old", refreshToken: "rt", expiration: .distantPast, isPermanent: true))
        let refreshingAuth = RedditAuthClient(session: URLSession(configuration: stubConfig), credentialStore: expiredStore,
                                              webSessionStore: InMemoryWebSessionStore())
        let refreshDone = DispatchSemaphore(value: 0)
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<5 { group.addTask { try? await refreshingAuth.refreshIfNeeded() } }
            }
            refreshDone.signal()
        }
        refreshDone.wait()
        check("five concurrent refreshes send one token request (\(TokenStub.requests))", TokenStub.requests == 1)
        let refreshedToken = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var tokenAfter: String?
        Task.detached { tokenAfter = await refreshingAuth.credential?.accessToken; refreshedToken.signal() }
        refreshedToken.wait()
        check("the refreshed token is adopted", tokenAfter == "new")

        let awkwardName = "a \"quoted\" \\ name\nwith a newline"
        let multiModel = try? RedditRepository.multiModel(["display_name": awkwardName, "subreddits": [["name": "swift"]]])
        let decodedModel = multiModel.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        check("a multireddit model survives quotes, backslashes and newlines",
              decodedModel?["display_name"] as? String == awkwardName)

        let summaryDefaults = UserDefaults(suiteName: "smoke.aiSummaryTTL")!
        summaryDefaults.removePersistentDomain(forName: "smoke.aiSummaryTTL")
        let summaryDay = Date(timeIntervalSince1970: 1_000_000)
        AISummaryCache.store("cached", for: "t3_x.post.1", in: summaryDefaults, now: summaryDay)
        check("a cached AI summary is reused within seven days",
              AISummaryCache.summary(for: "t3_x.post.1", in: summaryDefaults, now: summaryDay.addingTimeInterval(6 * 86_400)) == "cached")
        check("...and dropped after",
              AISummaryCache.summary(for: "t3_x.post.1", in: summaryDefaults, now: summaryDay.addingTimeInterval(8 * 86_400)) == nil)

        check("a picked image's real type is read from its bytes",
              ImageFileType(sniffing: Data([0x89, 0x50, 0x4E, 0x47, 0, 0])) == .png
              && ImageFileType(sniffing: Data([0x47, 0x49, 0x46, 0x38])) == .gif
              && ImageFileType(sniffing: Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))) == .heic
              && ImageFileType(sniffing: Data(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8))) == .webp
              && ImageFileType(sniffing: Data([0xFF, 0xD8, 0xFF])) == .jpeg)
        check("HEIC is not sent to Reddit as-is", !ImageFileType.heic.isWebSafe && ImageFileType.png.isWebSafe)

        check("modmail sorts map onto the OAuth API's own values",
              ModmailSortOption.allCases.map(\.restValue) == ["recent", "unread", "mod", "reply", "recent"])

        // Live chat sync: an incremental response carries only what changed.
        var chatState = ChatSyncState()
        chatState.apply(try! ChatSyncDelta(parsing: Data(#"""
        {"next_batch":"s1","com.reddit.global_navigation_counter":2,"rooms":{"join":{"!a:r":{
          "state":{"events":[{"type":"m.room.name","content":{"name":"Group"}}]},
          "timeline":{"events":[{"type":"m.room.message","origin_server_ts":1000,"sender":"@x:r","content":{"body":"hi"}}]},
          "unread_notifications":{"notification_count":2,"com.reddit.is_counted_in_global_navigation_counter":true},
          "ephemeral":{"events":[{"type":"m.receipt","content":{"$e1":{"m.read":{"@x:r":{}}}}}]}}}}}
        """#.utf8)), replacing: true)
        let liveDelta = try! ChatSyncDelta(parsing: Data(#"""
        {"next_batch":"s2","rooms":{"join":{"!a:r":{
          "timeline":{"events":[{"type":"m.room.message","origin_server_ts":2000,"sender":"@x:r","content":{"body":"again"}}]},
          "unread_notifications":{"notification_count":3,"com.reddit.is_counted_in_global_navigation_counter":true},
          "ephemeral":{"events":[{"type":"m.typing","content":{"user_ids":["@x:r"]}},
                                 {"type":"m.receipt","content":{"$e2":{"m.read":{"@y:r":{}}}}}]}}}}}
        """#.utf8))
        chatState.apply(liveDelta)
        let liveRoom = chatState.rooms["!a:r"]
        check("a live sync keeps the room's name and takes the new preview",
              liveRoom?.name == "Group" && liveRoom?.preview == "again" && liveRoom?.notificationCount == 3)
        check("a live sync names the room whose timeline changed", liveDelta.timelineRoomIDs == ["!a:r"])
        check("the unread count follows the rooms when Reddit's counter is absent", chatState.unreadCount == 3)
        check("typing arrives and receipts accumulate",
              chatState.ephemeral["!a:r"]?.typingUserIDs == ["@x:r"]
              && chatState.ephemeral["!a:r"]?.readReceipts == ["@x:r": "$e1", "@y:r": "$e2"])
        chatState.apply(try! ChatSyncDelta(parsing: Data(#"""
        {"next_batch":"s3","rooms":{"join":{"!a:r":{"ephemeral":{"events":[{"type":"m.typing","content":{"user_ids":[]}}]}}}}}
        """#.utf8)))
        check("an empty typing event clears the indicator", chatState.ephemeral["!a:r"]?.typingUserIDs == [])
        check("an empty long-poll answer changes nothing",
              !(try! ChatSyncDelta(parsing: Data(#"{"next_batch":"s4"}"#.utf8))).hasChanges)

        let oddPost = try? JSONDecoder.reddit.decode(RedditPost.self, from: Data(#"""
        {"id":"p","name":"t3_p","title":"t","author":"u","subreddit":"s","permalink":"/r/s/comments/p/",
         "score":1,"num_comments":0,"created_utc":0,"is_self":false,"over_18":false,"spoiler":false,
         "stickied":false,"saved":false,"media":{"reddit_video":{"is_gif":false}},
         "poll_data":{"options":[{"id":"1","text":"a"},{"broken":true}]}}
        """#.utf8))
        check("a malformed video or poll no longer loses the whole post",
              oddPost != nil && oddPost?.media?.redditVideo == nil && oddPost?.pollData?.options.count == 1)
        check("one bad element doesn't lose the rest of an array",
              (try? JSONDecoder().decode(LossyArray<Int>.self, from: Data("[1,\"x\",3]".utf8)))?.elements == [1, 3])

        let brokenParent = Data(#"""
        [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{"num_comments":2}}]}},
         {"kind":"Listing","data":{"children":[{"kind":"t1","data":{"id":"bad","score":"not a number",
          "replies":{"kind":"Listing","data":{"children":[{"kind":"t1","data":{"id":"kid","name":"t1_kid","author":"u","body":"reply",
          "score":0,"created_utc":0,"parent_id":"t1_bad","link_id":"t3_p","saved":false,"score_hidden":false,"stickied":false,"replies":""}}]}}}}]}}]
        """#.utf8)
        let brokenTree = try? CommentTreeBuilder.parseCommentsResponse(brokenParent, postID: "p")
        check("an undecodable comment keeps its place and its replies",
              brokenTree?.roots.first?.comment.id == "bad" && brokenTree?.roots.first?.comment.author == "[unknown]" && brokenTree?.roots.first?.children.first?.comment.id == "kid")

        let lettered = SubredditIndexTitle.alphabetized(["swift", "4chan", "Apple", "art", "_x"], name: { $0 })
        check("subreddits group A-Z case-insensitively with '#' last, as the index draws it",
              lettered.map(\.letter) == ["A", "S", "#"] && lettered[0].items == ["Apple", "art"] && lettered[2].items.count == 2)

        func pipelinePost(_ id: String, sub: String, distinguished: String? = nil) -> RedditPost {
            var json = #"{"id":"\#(id)","name":"t3_\#(id)","title":"t","author":"u","subreddit":"\#(sub)","permalink":"/r/s/comments/\#(id)/","score":1,"num_comments":0,"created_utc":0,"is_self":false,"over_18":false,"spoiler":false,"stickied":false,"saved":false"#
            if let distinguished { json += #","distinguished":"\#(distinguished)""# }
            return try! JSONDecoder.reddit.decode(RedditPost.self, from: Data((json + "}").utf8))
        }
        let pipelined = FeedFilterPipeline.apply(
            [pipelinePost("a", sub: "pics"), pipelinePost("b", sub: "news", distinguished: "admin"), pipelinePost("c", sub: "Swift")],
            .init(isAggregateFeed: true, excludedSubreddits: ["swift"]))
        check("the feed pipeline keeps admin posts and drops subscribed subreddits (case-insensitively)",
              pipelined.map(\.id) == ["a", "b"])
        let subFilter = ContentFilter(kind: .subreddit, value: "pics")
        let wordFilter = ContentFilter(kind: .keyword, value: "cat")
        check("Filtered Subreddits apply only on All/Popular; other filters everywhere",
              ContentFilterStore.activeFilters([subFilter, wordFilter], isAllOrPopular: false) == [wordFilter]
                  && ContentFilterStore.activeFilters([subFilter, wordFilter], isAllOrPopular: true).count == 2)

        check("counts agree with their noun: 1 Comment, 2 Comments, 1.2K Comments",
          1.apolloCounted("Comment", "Comments") == "1 Comment"
          && 2.apolloCounted("Comment", "Comments") == "2 Comments"
          && 1_234.apolloCounted("Comment", "Comments") == "1.2K Comments")

    // Sideloaded installs rename the app group to <group>.<TEAMID> and list it
    // under ALTAppGroups.
    let sideloadedGroup = SharedFeedCache.resolveAppGroupID(
        infoDictionaries: [["ALTAppGroups": ["group.com.rileytestut.AltStore.ABCDE12345", "group.com.pendo324.Phoebus.ABCDE12345"]], nil],
        hasContainer: { $0.hasSuffix("ABCDE12345") })
    check("a sideloaded install finds its renamed app group", sideloadedGroup == "group.com.pendo324.Phoebus.ABCDE12345")
    check("a certificate-signed install uses its profile's group when the declared one has no container",
          SharedFeedCache.resolveAppGroupID(infoDictionaries: [nil], profileGroups: ["group.abc.2", "group.abc.1"],
                                            hasContainer: { $0.hasPrefix("group.abc") }) == "group.abc.1")
    let profileBlob = Data("junk<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>TeamIdentifier</key><array><string>TEAM123456</string></array><key>Entitlements</key><dict><key>com.apple.security.application-groups</key><array><string>group.abc.1</string></array></dict></dict></plist>junk".utf8)
    let parsedProfile = EmbeddedProfile(profileData: profileBlob)
    check("an embedded profile's App Groups are read out of its signed wrapper",
          parsedProfile?.appGroups == ["group.abc.1"])
    check("a subreddit header's member count is formatted as Reborn does",
          33_600_000.apolloMemberCount == "34M members" && 2_540_000.apolloMemberCount == "2.5M members"
          && 850_400.apolloMemberCount == "850k members" && 12_340.apolloMemberCount == "12.3k members"
          && 999.apolloMemberCount == "999 members" && 1.apolloMemberCount == "1 member")
    func subredditJSON(_ extra: String) -> RedditSubreddit? {
        try? JSONDecoder().decode(RedditSubreddit.self, from: Data(#"{"name":"t5_2qh0u","display_name":"pics","title":"Reddit Pics"\#(extra)}"#.utf8))
    }
    check("the header banner prefers banner_img, then the mobile crop, then the wide art",
          subredditJSON(#","banner_img":"","mobile_banner_image":"https://m.example/b.png","banner_background_image":"https://w.example/b.png?a=1&amp;b=2""#)?.headerBannerURL?.host == "m.example"
          && subredditJSON(#","banner_background_image":"https://w.example/b.png?a=1&amp;b=2""#)?.headerBannerURL?.absoluteString == "https://w.example/b.png?a=1&b=2"
          && subredditJSON("")?.headerBannerURL == nil)
    check("whether members may set their own flair is read from can_assign_user_flair",
          subredditJSON(#","can_assign_user_flair":false"#)?.canAssignUserFlair == false
          && subredditJSON("")?.canAssignUserFlair == nil)
    func profile(appID: String) -> EmbeddedProfile? {
        EmbeddedProfile(profileData: Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Entitlements</key><dict><key>application-identifier</key><string>TEAM123456.\(appID)</string></dict></dict></plist>".utf8))
    }
    check("a profile's App ID is read without its team prefix", profile(appID: "app.signer.slot1")?.appID == "app.signer.slot1")
    check("an install signed under another App ID is flagged",
          profile(appID: "app.signer.slot1")?.signsAsItself(bundleIdentifier: "com.pendo324.Phoebus") == false
          && profile(appID: "com.pendo324.Phoebus")?.signsAsItself(bundleIdentifier: "com.pendo324.Phoebus") == true)
    check("a wildcard App ID covers the bundles under it",
          profile(appID: "*")?.signsAsItself(bundleIdentifier: "com.pendo324.Phoebus") == true
          && profile(appID: "com.pendo324.*")?.signsAsItself(bundleIdentifier: "com.pendo324.Phoebus") == true
          && profile(appID: "org.other.*")?.signsAsItself(bundleIdentifier: "com.pendo324.Phoebus") == false)
    check("an unrenamed install keeps the declared group",
          SharedFeedCache.resolveAppGroupID(infoDictionaries: [nil], hasContainer: { _ in true }) == "group.com.pendo324.Phoebus")

    let coords0 = SunsetCoordinatesStore.load()
        var schedule = ThemeAutoSwitchSettings.default
        schedule.useSystemLightDarkMode = false
        schedule.switchMode = .schedule
        schedule.useLocationSunsetSunrise = true
        schedule.darkModeStartMinutes = 60
        schedule.lightModeStartMinutes = 23 * 60
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 0, minute: 30))!
        // London at 00:30: dark by the sun, light by a fixed 01:00-23:00 dark window.
        SunsetCoordinatesStore.save(.init(latitude: 51.5, longitude: 0))
        check("the theme schedule uses sunset/sunrise once located",
              ThemeAutoSwitchResolver.shouldUseDarkTheme(settings: schedule, systemIsDark: false, screenBrightness: 1,
                                                         now: midnight, calendar: utc) == true)
        SunsetCoordinatesStore.save(nil)
        check("...and the fixed times until then",
              ThemeAutoSwitchResolver.shouldUseDarkTheme(settings: schedule, systemIsDark: false, screenBrightness: 1,
                                                         now: midnight, calendar: utc) == false)
        SunsetCoordinatesStore.save(coords0)
    }

    if failures == 0 {
        print("ALL CHECKS PASSED")
        exit(0)
    } else {
        print("\(failures) CHECK(S) FAILED")
        exit(1)
    }
}

extension NSLock {
    /// A lock-guarded value for observer closures in checks.
    final class Protected<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ value: T) { self.value = value }
        func set(_ newValue: T) { lock.lock(); value = newValue; lock.unlock() }
        func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    }
}
