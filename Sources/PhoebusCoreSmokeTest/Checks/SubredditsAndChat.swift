import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Subreddit Sections: Enhancements / Modern Dividers
//
// Reborn's Options section has four switches; both new ones default to YES.
@MainActor func checkSubredditSectionsEnhancementsModernDividers() async throws {
    check("Subreddit List Enhancements defaults ON, like the real registered default",
          SubredditSectionsSettings.default.subredditListEnhancements)
    check("Modern Subreddit Dividers defaults ON too",
          SubredditSectionsSettings.default.modernSubredditDividers)
    check("so the default preview draws MODERN accent bands",
          SubredditSectionsSettings.default.usesModernDividers
            && sectionsBlocks.first { $0.key == "band.favorites" }?.modern == true)

    // Modern requires both switches, so turning Enhancements off drops the
    // accent bands even with dividers still on.
    var sectionsNoEnhancements = SubredditSectionsSettings.default
    sectionsNoEnhancements.subredditListEnhancements = false
    check("Enhancements off collapses the bands to classic even with Modern Dividers on",
          sectionsNoEnhancements.modernSubredditDividers
            && !sectionsNoEnhancements.usesModernDividers
            && SubredditSectionsPreview.blocks(for: sectionsNoEnhancements)
                 .first { $0.key == "band.favorites" }?.modern == false)
    var sectionsNoModern = SubredditSectionsSettings.default
    sectionsNoModern.modernSubredditDividers = false
    check("...and so does turning only Modern Dividers off",
          !sectionsNoModern.usesModernDividers)

    // The band signature carries the modern flag, so a style change
    // cross-fades the band in place rather than leaving it stale.
    check("a band's signature changes with its divider style",
          sectionsBlocks.first { $0.key == "band.favorites" }?.signature
            != SubredditSectionsPreview.blocks(for: sectionsNoModern)
                 .first { $0.key == "band.favorites" }?.signature)

    // Payloads written without these fields decode to the YES defaults, not
    // false.
    let sectionsLegacy = try! JSONDecoder().decode(
        SubredditSectionsSettings.self,
        from: Data("{\"separateFollowedUsers\":true}".utf8))
    check("a legacy payload decodes both new switches to their real ON defaults",
          sectionsLegacy.subredditListEnhancements && sectionsLegacy.modernSubredditDividers
            && sectionsLegacy.separateFollowedUsers)
}

// MARK: - Open in App / dedicated-app link routing

// Host matching accepts subdomains of a claimed host.
@MainActor func checkOpenInAppDedicatedAppLink() async throws {
    check("a registrable domain matches itself",
          DedicatedAppLink.host("github.com", matches: ["github.com"]))
    check("...and any subdomain, per the real gist.github.com example",
          DedicatedAppLink.host("gist.github.com", matches: ["github.com"]))
    check("...and hosts case-insensitively",
          DedicatedAppLink.host("GitHub.COM", matches: ["github.com"]))
    // The suffix check must not match a different registrable domain that
    // ends with the same text: notgithub.com is not GitHub.
    check("a lookalike domain does NOT match",
          !DedicatedAppLink.host("notgithub.com", matches: ["github.com"]))
    check("an empty host does not match",
          !DedicatedAppLink.host("", matches: ["github.com"]))

    check("a github URL is claimed by the github service",
          DedicatedAppLink.service(for: URL(string: "https://github.com/apollo/app")!) == .github)
    check("a bsky URL is claimed by the bluesky service",
          DedicatedAppLink.service(for: URL(string: "https://bsky.app/profile/x")!) == .bluesky)
    check("an unrelated URL is claimed by nobody",
          DedicatedAppLink.service(for: URL(string: "https://example.com/")!) == nil)

    // The defaults keys are used verbatim.
    check("the real defaults keys are used verbatim",
          DedicatedAppLink.Service.github.defaultsKey == "OpenLinksInGitHubApp"
            && DedicatedAppLink.Service.bluesky.defaultsKey == "OpenLinksInBlueskyApp")

    // A Universal Link only resolves for https, so an http:// link is
    // upgraded or it would never open the app.
    check("an http URL is upgraded to https for the Universal Link",
          DedicatedAppLink.universalLinkURL(for: URL(string: "http://github.com/a/b")!)?.absoluteString
            == "https://github.com/a/b")
    check("...and the path and query survive the upgrade",
          DedicatedAppLink.universalLinkURL(for: URL(string: "http://github.com/a/b?c=d")!)?.absoluteString
            == "https://github.com/a/b?c=d")

    // These per-service routes are opt-in: a claimed URL is not routed until
    // the toggle is on.
    let ghURL = URL(string: "https://github.com/apollo/app")!
    UserDefaults.standard.removeObject(forKey: DedicatedAppLink.Service.github.defaultsKey)
    check("a claimed URL is not routed while the toggle is off (opt-in default)",
          DedicatedAppLink.shouldOpenInApp(ghURL) == nil)
    UserDefaults.standard.set(true, forKey: DedicatedAppLink.Service.github.defaultsKey)
    check("...and IS routed once the toggle is on",
          DedicatedAppLink.shouldOpenInApp(ghURL) == .github)
    check("...without affecting another service's toggle",
          DedicatedAppLink.shouldOpenInApp(URL(string: "https://bsky.app/profile/x")!) == nil)
    UserDefaults.standard.removeObject(forKey: DedicatedAppLink.Service.github.defaultsKey)

    // The four rows the screen shows, in alphabetical order. X/Twitter is
    // absent: Apollo already ships a native "Open Tweets in" picker.
    check("the Open in App screen offers the real four services in order",
          OpenInAppToggle.allCases.map(\.displayName) == ["Bluesky", "GitHub", "Steam", "YouTube"])
    check("X/Twitter is deliberately not among them",
          !OpenInAppToggle.allCases.contains { $0.displayName.contains("Twitter") || $0.displayName == "X" })

    // YouTube has no raw defaults key: it persists inside the GeneralSettings
    // JSON blob, and a second key would be a competing source of truth for
    // one switch.
    check("YouTube routes through GeneralSettings, not a second raw key",
          OpenInAppToggle.youtube.rawDefaultsKey == nil)
    check("...and reads back what GeneralSettings holds",
          OpenInAppToggle.youtube.isEnabled == GeneralSettingsStore.load().openVideosInYouTubeApp)
    let youtubeBefore = OpenInAppToggle.youtube.isEnabled
    OpenInAppToggle.youtube.isEnabled = !youtubeBefore
    check("...and writing it through the toggle updates GeneralSettings itself",
          GeneralSettingsStore.load().openVideosInYouTubeApp == !youtubeBefore)
    OpenInAppToggle.youtube.isEnabled = youtubeBefore
}

// MARK: - Theme gallery + token compiler (Reborn's theme system)
@MainActor func checkThemeGalleryTokenCompilerApolloReborn() async throws {
    check("all 50 gallery themes are present",
          ThemeGallery.all.count == 50)
    check("every gallery theme has a unique slug",
          Set(ThemeGallery.all.map(\.slug)).count == ThemeGallery.all.count)
    check("every gallery theme ships BOTH modes, so previewing either compiles nothing extra",
          ThemeGallery.all.allSatisfy { $0.input[.light] != nil && $0.input[.dark] != nil })
    check("every gallery theme supplies all eight input colors",
          ThemeGallery.all.allSatisfy { theme in
              ThemeMode.allCases.allSatisfy { mode in
                  ThemeInputKey.allCases.allSatisfy { theme.input[mode]?[$0] != nil }
              }
          })
    // 23 tokens since Reborn #1166 appended `rowHighlight`; the count comes
    // from `ThemeToken.allCases`, so this means "all of them".
    check("every gallery theme compiles all 22 tokens in both modes",
          ThemeGallery.all.allSatisfy { theme in
              let c = theme.compiled()
              return ThemeMode.allCases.allSatisfy { mode in
                  (c.tokens[mode]?.count ?? 0) == ThemeToken.allCases.count
              }
          })

    // Reborn #1186: profile banners open at their uncropped original.
    do {
        let crop = URL(string: "https://styles.redditmedia.com/t5_2abc/styles/profileBanner_xyz.png?width=1280&height=384&crop=1280:384,smart&s=abc123")!
        check("a known profile-banner crop maps to its original",
              ProfileBannerURL.originalCandidate(crop).absoluteString == "https://styles.redditmedia.com/t5_2abc/styles/profileBanner_xyz.png")
        let unknown = URL(string: "https://styles.redditmedia.com/t5_2abc/styles/profileBanner_xyz.png?width=1280&token=secret")!
        check("an unknown parameter keeps the URL intact", ProfileBannerURL.originalCandidate(unknown) == unknown)
        let other = URL(string: "https://i.redd.it/banner.png?width=100")!
        check("non-banner hosts are untouched", ProfileBannerURL.originalCandidate(other) == other)
        let unsized = URL(string: "https://styles.redditmedia.com/t5_2abc/styles/profileBanner_xyz.png?s=abc")!
        check("a signature-only URL is not a crop", ProfileBannerURL.originalCandidate(unsized) == unsized)
    }

    // Reborn #1166: an independent, softer press-feedback token.
    do {
        func dist(_ a: UInt32, _ b: UInt32) -> Int {
            let ca = [(a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF].map(Int.init)
            let cb = [(b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF].map(Int.init)
            return zip(ca, cb).map { abs($0 - $1) }.reduce(0, +)
        }
        check("rowHighlight sits between the card and the selection tint (half the accent)",
              ThemeGallery.all.allSatisfy { theme in
                  let c = theme.compiled()
                  return ThemeMode.allCases.allSatisfy { m in
                      let card = c.rgb(.secondaryBackground, mode: m)
                      return dist(c.rgb(.rowHighlight, mode: m), card) <= dist(c.rgb(.selection, mode: m), card)
                  }
              })
    }

    // Color math.
    check("luminance uses the PROPER sRGB-linearised WCAG formula",
          abs(ThemeColorMath.luminance(0xFFFFFF) - 1.0) < 0.0001
            && abs(ThemeColorMath.luminance(0x000000)) < 0.0001)
    check("black-on-white contrast is the WCAG 21:1",
          abs(ThemeColorMath.contrastRatio(0x000000, 0xFFFFFF) - 21.0) < 0.01)
    // The threshold is 0.4, not the 0.5 midpoint; mid-grey sits between the
    // two and distinguishes them.
    check("the light-background threshold is the real 0.4, not 0.5",
          ThemeColorMath.luminance(0x808080) < 0.5
            && ThemeColorMath.backgroundIsLight(0x808080) == (ThemeColorMath.luminance(0x808080) > 0.4))
    check("mix endpoints are exact",
          ThemeColorMath.mix(0x000000, 0xFFFFFF, 0) == 0x000000
            && ThemeColorMath.mix(0x000000, 0xFFFFFF, 1) == 0xFFFFFF)
    check("a 50% mix of black and white rounds to the real 808080",
          ThemeColorMath.mix(0x000000, 0xFFFFFF, 0.5) == 0x808080)
    check("HSL round-trips a saturated color exactly",
          ThemeColorMath.fromHSL(ThemeColorMath.toHSL(0xBD93F9)) == 0xBD93F9)
    check("...and a pure grey, which has no hue to preserve",
          ThemeColorMath.fromHSL(ThemeColorMath.toHSL(0x808080)) == 0x808080)
    check("contrast repair actually reaches its target",
          ThemeColorMath.contrastRatio(
              ThemeColorMath.repairContrast(0x777777, against: 0xFFFFFF, target: 4.5),
              0xFFFFFF) >= 4.5)
    check("...and leaves an already-passing color untouched",
          ThemeColorMath.repairContrast(0x000000, against: 0xFFFFFF, target: 4.5) == 0x000000)

    // Bold is the only variant with a raisedBoost, which gives it clearer
    // elevation.
    check("only Bold boosts raised away from card",
          ThemeCompiler.tuning(for: .bold).raisedBoost > 0
            && ThemeCompiler.tuning(for: .subtle).raisedBoost == 0
            && ThemeCompiler.tuning(for: .balanced).raisedBoost == 0)
    check("the real variant separator mixes are 0.10 / 0.14 / 0.18",
          ThemeCompiler.tuning(for: .subtle).separatorMix == 0.10
            && ThemeCompiler.tuning(for: .balanced).separatorMix == 0.14
            && ThemeCompiler.tuning(for: .bold).separatorMix == 0.18)
    // selectionMix is inverted: higher is subtler, because it is the fraction
    // mixed toward the card.
    check("Subtle has the HIGHEST selection mix, because higher means subtler",
          ThemeCompiler.tuning(for: .subtle).selectionMix
            > ThemeCompiler.tuning(for: .bold).selectionMix)

    // Dracula's dark mode, compiled. The values match Reborn's theme compiler
    // across all 50 themes in both modes.
    let dracula = ThemeGallery.theme(slug: "dracula")!
    let draculaDark = dracula.compiled()
    check("a gallery theme's surfaces come through unmodified",
          draculaDark.hex(.background, mode: .dark) == "21222C"
            && draculaDark.hex(.secondaryBackground, mode: .dark) == "262834")
    check("elevated background deliberately equals card",
          draculaDark.rgb(.elevatedBackground, mode: .dark)
            == draculaDark.rgb(.secondaryBackground, mode: .dark))
    check("an explicit separator override is trusted EXACTLY, no contrast floor",
          draculaDark.hex(.separator, mode: .dark) == "4F505A"
            && draculaDark.hex(.opaqueSeparator, mode: .dark) == "4F505A")
    check("balanced leaves the accent's saturation alone",
          draculaDark.hex(.accent, mode: .dark) == "BD93F9")
    check("placeholder text aliases tertiary label, and disabled aliases quaternary",
          draculaDark.rgb(.placeholderText, mode: .dark) == draculaDark.rgb(.tertiaryLabel, mode: .dark)
            && draculaDark.rgb(.disabled, mode: .dark) == draculaDark.rgb(.quaternaryLabel, mode: .dark))
    check("the four fill tiers step monotonically away from the background",
          ThemeColorMath.contrastRatio(draculaDark.rgb(.quaternaryFill, mode: .dark),
                                       draculaDark.rgb(.background, mode: .dark))
            > ThemeColorMath.contrastRatio(draculaDark.rgb(.fill, mode: .dark),
                                           draculaDark.rgb(.background, mode: .dark)))

    // Advanced-off strips the overrides rather than mutating the theme's
    // stored input, so turning Advanced back on restores the user's values.
    let advancedOff = ThemeCompiler.compile(input: dracula.input, variant: dracula.variant, advancedEnabled: false)
    check("Advanced off ignores the separator override and derives one instead",
          advancedOff.hex(.separator, mode: .dark) != "4F505A")
    check("...without touching the theme's stored input",
          dracula.input[.dark]?[.separator] == "4F505A")
    check("...and Advanced on still honours it, so the strip was non-destructive",
          dracula.compiled().hex(.separator, mode: .dark) == "4F505A")

    // Every compiled theme must be legible: body text against the background
    // at the WCAG AA 4.5 floor the compiler targets.
    var illegible: [String] = []
    for galleryTheme in ThemeGallery.all {
        let c = galleryTheme.compiled()
        for mode in ThemeMode.allCases {
            let ratio = ThemeColorMath.contrastRatio(c.rgb(.label, mode: mode), c.rgb(.background, mode: mode))
            if ratio < 4.5 { illegible.append("\(galleryTheme.slug)/\(mode.rawValue) \(ratio)") }
        }
    }
    check("every one of the 100 theme/mode combinations has legible body text (AA 4.5)",
          illegible.isEmpty)

    // Opposite-mode derivation.
    let lightInput = dracula.input[.light]!
    let derivedDark = ThemeCompiler.generateOppositeModeInput(from: lightInput, sourceMode: .light)
    check("deriving the opposite mode turns light surfaces genuinely DARK, not mid-grey",
          ThemeColorMath.luminance(ThemeColorMath.parseHex(derivedDark[.background]!)!) < 0.1)
    check("...and keeps the accent's hue",
          abs(ThemeColorMath.toHSL(ThemeColorMath.parseHex(derivedDark[.accent]!)!).h
              - ThemeColorMath.toHSL(ThemeColorMath.parseHex(lightInput[.accent]!)!).h) < 0.01)
    check("an unset input stays unset rather than being invented",
          ThemeCompiler.generateOppositeModeInput(from: [.accent: "BD93F9"], sourceMode: .light).count == 1)

    // Bridging into the app's own Theme model.
    let draculaTheme = dracula.asTheme(mode: .dark)
    check("a gallery theme bridges to a dark Theme with the compiled accent",
          draculaTheme.isDark && draculaTheme.accentColorHex == "BD93F9")
    // Must be marked generated, or ThemeStore would write the id and then
    // fail to resolve it on next launch, reverting to Default.
    check("a gallery theme is marked generated so it PERSISTS across launches",
          draculaTheme.isGenerated)
    check("it carries its own comment rails rather than borrowing a named palette",
          draculaTheme.commentPaletteName == nil && draculaTheme.commentDepthColorHexes.count == 6)
    check("the rails keep the accent's saturation and lightness, so they match the scheme",
          ThemeColorMath.toHSL(ThemeColorMath.parseHex(draculaTheme.commentDepthColorHexes[0])!).l
            == ThemeColorMath.toHSL(0xBD93F9).l)
    check("the first rail IS the accent, so depth 0 matches the theme exactly",
          draculaTheme.commentDepthColorHexes[0] == "BD93F9")
    check("light and dark bridges produce distinct ids",
          dracula.asTheme(mode: .light).id != draculaTheme.id)

    // The index generator's link regex must match a destination written with
    // only a trailing closure (`ThemeGalleryScreen { ... }`) as well as the
    // parenthesized call form `SomeScreen(...)`.
    check("a trailing-closure destination is indexed",
          SettingsSearch.index.contains { $0.title == "Theme Gallery" && $0.rowTitle == nil })
    check("...and is findable by name",
          SettingsSearch.results(for: "theme gallery").first?.title == "Theme Gallery")

    // A gallery-bridged theme's id must be traceable back to its slug, or its
    // compiled tokens cannot be recovered after a relaunch.
    let galleryIDs = ThemeGallery.all.map { $0.asTheme(mode: .dark).id }
    check("every gallery theme's bridged id is unique",
          Set(galleryIDs).count == galleryIDs.count)
    check("a bridged id round-trips back to its slug",
          galleryIDs.allSatisfy { id in
              var slug = String(id.dropFirst("gallery_".count))
              for suffix in ["_light", "_dark"] where slug.hasSuffix(suffix) {
                  slug = String(slug.dropLast(suffix.count))
              }
              return ThemeGallery.theme(slug: slug) != nil
          })
    // Slugs containing the mode words would break a naive suffix strip.
    check("no slug ends in _light or _dark, which would break the strip",
          ThemeGallery.all.allSatisfy { !$0.slug.hasSuffix("_light") && !$0.slug.hasSuffix("_dark") })
    check("a built-in theme is NOT mistaken for a gallery theme",
          !Theme.defaultLight.id.hasPrefix("gallery_"))

    // `Color.accentColor` resolves the AccentColor asset and does not follow
    // `.tint()`, so UI reflecting the theme's accent must use
    // `Color.apolloAccent`, which reads the active theme. The smoke test links
    // PhoebusCore only, so the value it reads is what is asserted.
    check("the active theme exposes an accent hex for the shim to read",
          ThemeColorMath.parseHex(ThemeStore.load().accentColorHex) != nil)
    check("a gallery theme's accent hex is its compiled accent token",
          ThemeGallery.theme(slug: "dracula")!.asTheme(mode: .dark).accentColorHex
            == ThemeGallery.compiled(slug: "dracula")!.hex(.accent, mode: .dark))
}

// MARK: - Reddit Chat over Matrix

// The fixture matches the shape of a Matrix /sync response, with
// identifiers and message text replaced.
@MainActor func checkRedditChatOverMatrix() async throws {
    let chatSyncFixture = """
    {"next_batch": "s_FIXTURE_TOKEN", "com.reddit.global_navigation_counter": 3, "com.reddit.invites_counter": 1, "rooms": {"join": {"!room0": {"summary": {"m.heroes": ["@t2_hero0:reddit.com"]}, "state": {"events": [{"type": "m.room.member", "state_key": "@t2_other0:reddit.com", "content": {"membership": "join"}}, {"type": "com.reddit.chat.type", "content": {"type": "direct", "participants": ["@t2_me:reddit.com", "@t2_other0:reddit.com"]}}, {"type": "m.room.member", "state_key": "@t2_other0:reddit.com", "content": {"membership": "join"}}]}, "timeline": {"events": [{"type": "m.room.message", "sender": "@t2_other0:reddit.com", "origin_server_ts": 1700000000000, "content": {"body": "message 0"}}]}, "unread_notifications": {"highlight_count": 0, "notification_count": 35, "com.reddit.is_counted_in_global_navigation_counter": false}}, "!room1": {"summary": {"m.heroes": ["@t2_hero1:reddit.com"]}, "state": {"events": [{"type": "m.room.member", "state_key": "@t2_other1:reddit.com", "content": {"membership": "join"}}, {"type": "com.reddit.chat.type", "content": {"type": "direct", "participants": ["@t2_me:reddit.com", "@t2_other1:reddit.com"]}}, {"type": "m.room.member", "state_key": "@t2_other1:reddit.com", "content": {"membership": "join"}}]}, "timeline": {"events": [{"type": "m.room.message", "sender": "@t2_other1:reddit.com", "origin_server_ts": 1700000001000, "content": {"body": "message 1"}}]}, "unread_notifications": {"highlight_count": 0, "notification_count": 0, "com.reddit.is_counted_in_global_navigation_counter": false}}, "!room2": {"summary": {"m.heroes": ["@t2_hero2:reddit.com"]}, "state": {"events": [{"type": "m.room.member", "state_key": "@t2_other2:reddit.com", "content": {"membership": "join"}}, {"type": "com.reddit.chat.type", "content": {"type": "direct", "participants": ["@t2_me:reddit.com", "@t2_other2:reddit.com"]}}, {"type": "m.room.member", "state_key": "@t2_other2:reddit.com", "content": {"membership": "join"}}]}, "timeline": {"events": [{"type": "m.room.message", "sender": "@t2_other2:reddit.com", "origin_server_ts": 1700000002000, "content": {"body": "message 2"}}]}, "unread_notifications": {"highlight_count": 0, "notification_count": 0, "com.reddit.is_counted_in_global_navigation_counter": false}}, "!noisy": {"state": {"events": [{"type": "m.room.name", "content": {"name": "Announcements"}}]}, "timeline": {"events": [{"type": "m.room.message", "sender": "@t2_bot:reddit.com", "origin_server_ts": 1700009999000, "content": {"body": "newest"}}]}, "unread_notifications": {"notification_count": 35, "com.reddit.is_counted_in_global_navigation_counter": false}}}, "invite": {"!invited": {"invite_state": {"events": [{"type": "m.room.name", "content": {"name": "Group chat"}}, {"type": "m.room.member", "state_key": "@t2_inviter:reddit.com", "content": {"membership": "invite"}}]}}}}}
    """
    let chatSync = try! RedditChatClient.parseSync(Data(chatSyncFixture.utf8))

    // Reddit's pre-computed counters: the numbers reddit.com badges its chat
    // bubble with.
    check("Reddit's own unread and request counters are read",
          chatSync.unreadCount == 3 && chatSync.requestsCount == 1)
    check("the incremental sync token is captured",
          chatSync.nextBatch == "s_FIXTURE_TOKEN")

    // Invited rooms carry `invite_state`, not `state`; reading only `state`
    // would leave pending chat requests nameless.
    let chatInvite = chatSync.rooms.first { $0.isInvite }
    check("a pending chat request is parsed from invite_state, not state",
          chatInvite?.name == "Group chat")
    check("...and is marked as an invite rather than a joined room",
          chatInvite?.isInvite == true)
    check("joined rooms are not marked as invites",
          chatSync.rooms.filter { !$0.isInvite }.count == chatSync.rooms.count - 1)

    // Newest first, as a chat list is read.
    let chatJoined = chatSync.rooms.filter { !$0.isInvite }
    check("rooms are ordered newest-first",
          chatJoined.first?.name == "Announcements")

    // A room can carry a notification_count of 35 while contributing nothing
    // to the global badge, so summing notification_count would badge wrongly.
    let chatNoisy = chatSync.rooms.first { $0.name == "Announcements" }
    check("a room's raw notification count is kept",
          chatNoisy?.notificationCount == 35)
    check("...but Reddit's own 'counts toward the badge' flag is respected",
          chatNoisy?.countsTowardGlobalBadge == false)

    // A direct room has no m.room.name; its title comes from participants.
    let chatDirect = chatJoined.first { $0.chatType == "direct" }
    check("a direct room is identified by com.reddit.chat.type",
          chatDirect != nil && chatDirect?.name == nil)
    check("...and its participants are collected",
          (chatDirect?.participants.count ?? 0) >= 2)
    check("...excluding yourself, or every DM would be titled with your own name",
          chatDirect?.otherParticipants(excluding: "@t2_me:reddit.com").contains("@t2_me:reddit.com") == false)
    check("a message preview and its sender are captured",
          chatDirect?.preview != nil && chatDirect?.previewSender != nil)

    // Matrix user id <-> Reddit account id.
    check("a Matrix user id yields its Reddit account id",
          RedditChatClient.accountID(fromMatrixUserID: "@t2_1a2b3c:reddit.com") == "t2_1a2b3c")
    check("a malformed user id yields nothing rather than garbage",
          RedditChatClient.accountID(fromMatrixUserID: "t2_1a2b3c") == nil)

    // Token handling. Reading `exp` before sending avoids replaying a stored
    // token_v2 that has expired.
    check("a JWT's expiry is read",
          RedditChatClient.expiry(ofJWT: makeChatJWT(expiringIn: 3600)) != nil)
    check("a token expiring within the margin is treated as expired",
          RedditChatClient.isExpired(makeChatJWT(expiringIn: 30)))
    check("a fresh token is not",
          !RedditChatClient.isExpired(makeChatJWT(expiringIn: 3600)))
    check("a non-JWT is not claimed to be expired, since its expiry is unknown",
          !RedditChatClient.isExpired("not-a-jwt"))
    let freshToken = makeChatJWT(expiringIn: 3600)
    check("the session's own token_v2 is used while it lasts",
          RedditChatClient.storedBearer(cookieHeader: "loid=1; token_v2=\(freshToken); reddit_session=x") == freshToken
          && RedditChatClient.storedBearer(cookieHeader: "token_v2=\(makeChatJWT(expiringIn: 30))") == nil
          && RedditChatClient.storedBearer(cookieHeader: "token_v2=not-a-jwt") == nil
          && RedditChatClient.storedBearer(cookieHeader: "reddit_session=x") == nil)

    // Set-Cookie parsing. Repeated headers fold into one comma-joined string,
    // and a cookie's own Expires date contains a comma ("Expires=Mon, 14 Sep..."),
    // so splitting on commas corrupts the value.
    let chatSetCookie = "session_tracker=abc; path=/; expires=Mon, 14-Sep-2026 17:32:52 GMT, "
        + "token_v2=eyJhbGciOiJSUzI1NiJ9.payload.sig; path=/; expires=Tue, 15-Sep-2026 00:00:00 GMT; secure"
    check("token_v2 survives a Set-Cookie header whose dates contain commas",
          RedditChatClient.extractTokenV2(fromSetCookie: chatSetCookie) == "eyJhbGciOiJSUzI1NiJ9.payload.sig")
    check("a Set-Cookie with no token_v2 yields nothing",
          RedditChatClient.extractTokenV2(fromSetCookie: "foo=bar; path=/") == nil)

    // Endpoint constants.
    check("the real homeserver is used",
          RedditChatClient.homeserver == "https://matrix.redditspace.com")
    check("the real counter keys are used verbatim",
          RedditChatClient.unreadCounterKey == "com.reddit.global_navigation_counter"
            && RedditChatClient.requestsCounterKey == "com.reddit.invites_counter")

    // A DM must not be titled "you, them": the exclusion needs the account's
    // own Matrix id, from /account/whoami.
    check("excluding yourself leaves only the other participant",
          ChatRoom(id: "!r", name: nil, chatType: "direct",
                   participants: ["@t2_me:reddit.com", "@t2_them:reddit.com"],
                   isInvite: false, lastMessageTimestamp: 0, preview: nil,
                   previewSender: nil, notificationCount: 0, countsTowardGlobalBadge: false)
            .otherParticipants(excluding: "@t2_me:reddit.com") == ["@t2_them:reddit.com"])

    // Room messages. `dir=b` walks backwards from the newest event, so the
    // chunk arrives newest-first and is reversed for display.
    let chatMessagesFixture = """
    {"start":"t1","end":"t2","chunk":[
     {"type":"m.room.message","event_id":"$c","sender":"@t2_a:reddit.com","origin_server_ts":3000,
      "content":{"body":"newest","msgtype":"m.text"}},
     {"type":"m.room.message","event_id":"$b","sender":"@t2_b:reddit.com","origin_server_ts":2000,
      "content":{"body":"middle","msgtype":"m.text"}},
     {"type":"m.room.member","event_id":"$x","sender":"@t2_a:reddit.com","origin_server_ts":2500,
      "content":{"membership":"join"}},
     {"type":"m.room.message","event_id":"$a","sender":"@t2_a:reddit.com","origin_server_ts":1000,
      "content":{"body":"oldest","msgtype":"m.text"}}
    ]}
    """
    let chatMessages = RedditChatClient.parseMessages(Data(chatMessagesFixture.utf8))
    check("a backwards chunk is flipped into conversation order",
          chatMessages.map(\.body) == ["oldest", "middle", "newest"])
    check("non-message events are skipped",
          chatMessages.count == 3)
    check("the message's sender, id and msgtype are kept",
          chatMessages.last?.sender == "@t2_a:reddit.com"
            && chatMessages.last?.id == "$c"
            && chatMessages.last?.msgtype == "m.text")
    check("a malformed payload yields no messages rather than throwing",
          RedditChatClient.parseMessages(Data("{}".utf8)).isEmpty)

    // Bundled aggregations.
    //
    // Reddit attaches `com.reddit.profile` to messages, carrying the sender's
    // username and avatar, so most senders need no separate /profile request.
    // Matrix's own `m.thread` bundle carries a reply count.
    let chatBundledFixture = """
    {"chunk":[
     {"type":"m.room.message","event_id":"$p","sender":"@t2_a:reddit.com","origin_server_ts":1000,
      "content":{"body":"parent","msgtype":"m.text"},
      "unsigned":{"m.relations":{
        "m.thread":{"count":3},
        "com.reddit.profile":{"username":"realhandle","displayname":"Display Label",
          "icon_url":"https://example.com/a.png"}}}},
     {"type":"m.room.message","event_id":"$q","sender":"@t2_b:reddit.com","origin_server_ts":2000,
      "content":{"body":"no bundle","msgtype":"m.text"}}
    ]}
    """
    let chatBundled = RedditChatClient.parseMessages(Data(chatBundledFixture.utf8))
    check("a thread's reply count is read from the m.thread bundle",
          chatBundled.first?.threadReplyCount == 3)
    check("a message with no thread reports zero replies, so no affordance is shown",
          chatBundled.last?.threadReplyCount == 0)
    // `username` is the handle; `displayname` can be a chosen label (for
    // example "MSI_Tech Support" for u/CND_CEM), so the handle identifies someone.
    check("the bundled profile's USERNAME is preferred over its display label",
          chatBundled.first?.senderUsername == "realhandle")
    check("the bundled avatar is captured",
          chatBundled.first?.senderAvatarURL == "https://example.com/a.png")
    check("a sender with no bundled profile still needs resolving",
          chatBundled.last?.senderUsername == nil)
}

// MARK: - Chat send queue (design ported from the Rust SDK)
//
// Matrix deduplicates on the transaction id, not the body: replaying the
// same txn id returns the same event_id, while a different id with identical
// content creates a second event. A retry must reuse the original id.
@MainActor func checkChatSendQueueDesignPortedFrom() async throws {
    let chatQueue = ChatSendQueue()
    await chatQueue.removeAll()

    let chatEntry1 = await chatQueue.enqueue(roomID: "!r1", body: "first")
    let chatEntry2 = await chatQueue.enqueue(roomID: "!r1", body: "second")

    check("a queued message carries a transaction id assigned at ENQUEUE",
          !chatEntry1.transactionID.isEmpty)
    check("...which is its identity, so a retry cannot regenerate it",
          chatEntry1.id == chatEntry1.transactionID)
    check("two messages get distinct transaction ids",
          chatEntry1.transactionID != chatEntry2.transactionID)

    let chatNext1 = await chatQueue.nextToSend(roomID: "!r1")
    let chatOtherRoom = await chatQueue.nextToSend(roomID: "!other")
    check("the queue is FIFO: the oldest message is sent first", chatNext1?.body == "first")
    check("...and another room's queue is independent", chatOtherRoom == nil)

    // A recoverable failure keeps the message queued and retryable.
    await chatQueue.markFailed(id: chatEntry1.id, message: "network", isRecoverable: true)
    let chatAfterRecoverable = await chatQueue.nextToSend(roomID: "!r1")
    check("a recoverable failure leaves the message queued for another attempt",
          chatAfterRecoverable?.id == chatEntry1.id)

    // An unrecoverable message parks itself and blocks everything behind it,
    // so later messages cannot overtake a stuck one.
    await chatQueue.markFailed(id: chatEntry1.id, message: "rejected", isRecoverable: false)
    let chatParked = await chatQueue.pendingEntries(roomID: "!r1").first
    let chatBlocked = await chatQueue.nextToSend(roomID: "!r1")
    check("an unrecoverable failure parks the message", chatParked?.isParked == true)
    check("...and BLOCKS the queue, so message 2 cannot overtake message 1", chatBlocked == nil)

    // The two ways out, both from SendHandle.
    await chatQueue.retry(id: chatEntry1.id)
    let chatUnparked = await chatQueue.nextToSend(roomID: "!r1")
    let chatCleared = await chatQueue.pendingEntries(roomID: "!r1").first
    check("retrying un-parks the message and unblocks the queue",
          chatUnparked?.id == chatEntry1.id)
    check("...and clears the stale failure message", chatCleared?.failureMessage == nil)

    await chatQueue.markFailed(id: chatEntry1.id, message: "rejected", isRecoverable: false)
    await chatQueue.abort(id: chatEntry1.id)
    let chatAfterAbort = await chatQueue.nextToSend(roomID: "!r1")
    check("aborting a wedged message lets the next one through",
          chatAfterAbort?.body == "second")

    await chatQueue.markSent(id: chatEntry2.id, eventID: "$evt")
    let chatDrained = await chatQueue.pendingEntries(roomID: "!r1")
    check("a sent message leaves the outbox", chatDrained.isEmpty)

    // Persistence: the queue outlives a force-quit, or the txn id it protects
    // is lost and the retry duplicates the message.
    let chatEntry3 = await chatQueue.enqueue(roomID: "!r2", body: "survives")
    let chatQueueReloaded = ChatSendQueue()
    let chatRestored = await chatQueueReloaded.pendingEntries(roomID: "!r2").first
    check("the outbox survives a restart, preserving the transaction id",
          chatRestored?.transactionID == chatEntry3.transactionID)
    await chatQueueReloaded.removeAll()

    // A drain claims its message, and entries belong to an account.
    do {
        let q = ChatSendQueue()
        await q.removeAll()
        let mine = await q.enqueue(roomID: "!q", body: "hi", account: "Alice")
        let claimed = await q.claimNext(roomID: "!q", account: "alice")
        let second = await q.claimNext(roomID: "!q", account: "alice")
        check("chat queue: a second drain can't take a message already being sent",
              claimed?.id == mine.id && second == nil)
        await q.markFailed(id: mine.id, message: "net", isRecoverable: true)
        let again = await q.claimNext(roomID: "!q", account: "alice")
        check("chat queue: a failed send is given back for the next drain", again?.id == mine.id)
        let other = await q.claimNext(roomID: "!q", account: "bob")
        let otherPending = await q.pendingEntries(roomID: "!q", account: "bob")
        check("chat queue: another account never sends or sees it", other == nil && otherPending.isEmpty)
        await q.removeAll()
    }

    // Recoverability classification decides retry vs park.
    check("a dead bearer is recoverable - re-mint and try again",
          RedditChatClient.isRecoverable(RedditChatClient.ChatError.unauthorized))
    check("a transport failure is recoverable",
          RedditChatClient.isRecoverable(RedditChatClient.ChatError.httpError(status: 0)))
    check("a 5xx is recoverable",
          RedditChatClient.isRecoverable(RedditChatClient.ChatError.httpError(status: 502)))
    // Retrying an identical request the server already rejected just
    // repeats the rejection, so a 4xx parks instead.
    check("a 4xx is NOT recoverable, since retrying repeats the rejection",
          !RedditChatClient.isRecoverable(RedditChatClient.ChatError.httpError(status: 400)))
}

// MARK: - Chat media + date headers

// mxc:// resolution: the legacy unauthenticated download path
// 308-redirects to the CDN URL. The authenticated variant 404s on this
// homeserver, and the legacy one needs no bearer token so it can use the
// ordinary cache.
@MainActor func checkChatMediaDateHeaders() async throws {
    check("an mxc URI resolves to the legacy download path",
          RedditChatClient.downloadURL(forMXC: "mxc://reddit.com/abc123")?.absoluteString
            == "https://matrix.redditspace.com/_matrix/media/v3/download/reddit.com/abc123")
    check("a non-mxc string resolves to nothing rather than a broken URL",
          RedditChatClient.downloadURL(forMXC: "https://example.com/a.png") == nil)
    check("an empty mxc resolves to nothing",
          RedditChatClient.downloadURL(forMXC: "mxc://") == nil)
    check("a thumbnail URL carries the scale parameters",
          RedditChatClient.thumbnailURL(forMXC: "mxc://reddit.com/abc123", width: 400, height: 400)?
            .absoluteString.contains("width=400&height=400&method=scale") == true)

    // The m.image event shape: body/msgtype/url plus an info block carrying
    // w, h and size.
    let chatImageFixture = """
    {"chunk":[
     {"type":"m.room.message","event_id":"$i","sender":"@t2_a:reddit.com","origin_server_ts":5000,
      "content":{"body":"probe.png","msgtype":"m.image","url":"mxc://reddit.com/xyz",
                 "info":{"mimetype":"image/png","w":1,"h":1,"size":70}}},
     {"type":"m.room.message","event_id":"$t","sender":"@t2_a:reddit.com","origin_server_ts":6000,
      "content":{"body":"just text","msgtype":"m.text"}}
    ]}
    """
    let chatImages = RedditChatClient.parseMessages(Data(chatImageFixture.utf8))
    let chatImageMsg = chatImages.first { $0.id == "$i" }
    let chatTextMsg = chatImages.first { $0.id == "$t" }
    check("an m.image message is recognised as media",
          chatImageMsg?.isMedia == true)
    check("...and carries its mxc URI and declared dimensions",
          chatImageMsg?.mediaURI == "mxc://reddit.com/xyz"
            && chatImageMsg?.mediaWidth == 1 && chatImageMsg?.mediaHeight == 1)
    check("...which resolve to a download URL",
          chatImageMsg?.mediaDownloadURL != nil)
    check("a plain text message is NOT treated as media",
          chatTextMsg?.isMedia == false && chatTextMsg?.mediaDownloadURL == nil)

    // Date headers use exactly Apollo's two date formats.
    check("the two real date formats are used verbatim",
          ChatDateFormatter.fullFormat == "MMM d, yyyy, h:mm a"
            && ChatDateFormatter.recentFormat == "E, d MMM, h:mm a")
    check("today reads as Today",
          ChatDateFormatter.headerText(for: Date()) == "Today")
    check("yesterday reads as Yesterday",
          ChatDateFormatter.headerText(for: Date().addingTimeInterval(-24 * 60 * 60)) == "Yesterday")
    // Within a week: the weekday form. Beyond it: the full date with the
    // year, which is the distinction Apollo's two formats encode.
    let chatOld = Date().addingTimeInterval(-40 * 24 * 60 * 60)
    let chatOldHeader = ChatDateFormatter.headerText(for: chatOld)
    check("an old message's header includes the year, per the full format",
          chatOldHeader.contains(",") && chatOldHeader.rangeOfCharacter(from: .decimalDigits) != nil)

    // A header appears when the day changes, so the first message in a room
    // always gets one.
    let chatDay1 = Date(timeIntervalSince1970: 1_700_000_000)
    let chatDay2 = chatDay1.addingTimeInterval(48 * 60 * 60)
    check("the first message always gets a header",
          ChatDateFormatter.needsHeader(previous: nil, current: chatDay1))
    check("a later message on the SAME day does not",
          !ChatDateFormatter.needsHeader(previous: chatDay1, current: chatDay1.addingTimeInterval(60)))
    check("a message on a new day does",
          ChatDateFormatter.needsHeader(previous: chatDay1, current: chatDay2))
}

// MARK: - Ephemeral events (typing + read receipts)

// m.typing is {"user_ids":[...]} and m.receipt is keyed by event id, then
// receipt type, then user; parsing inverts it into user -> event, which is
// how a UI asks the question.
@MainActor func checkEphemeralEventsTypingReadReceipts() async throws {
    let chatEphemeralFixture = """
    {"rooms":{"join":{
     "!room1":{"ephemeral":{"events":[
       {"type":"m.typing","content":{"user_ids":["@t2_me:reddit.com","@t2_them:reddit.com"]}},
       {"type":"m.receipt","content":{"$evt1":{"m.read":{"@t2_them:reddit.com":{"ts":1700000000}}}}}
     ]}},
     "!quiet":{"ephemeral":{"events":[]}}
    }}}
    """
    let chatEphemeral = RedditChatClient.parseEphemeral(Data(chatEphemeralFixture.utf8))
    let chatRoom1 = chatEphemeral["!room1"]

    check("typing user ids are parsed",
          chatRoom1?.typingUserIDs.count == 2)
    // Your own typing notice is not shown back to you.
    check("your own typing notice is excluded",
          chatRoom1?.othersTyping(excluding: "@t2_me:reddit.com") == ["@t2_them:reddit.com"])
    check("a receipt is inverted to user -> event",
          chatRoom1?.readReceipts["@t2_them:reddit.com"] == "$evt1")
    check("someone else's read receipt is reported",
          chatRoom1?.isReadByOthers(eventID: "$evt1", excluding: "@t2_me:reddit.com") == true)
    check("...and an unread event is not",
          chatRoom1?.isReadByOthers(eventID: "$other", excluding: "@t2_me:reddit.com") == false)
    // Your own receipt is not evidence that anyone else read it.
    let chatOwnReceipt = RedditChatClient.RoomEphemeral(readReceipts: ["@t2_me:reddit.com": "$evt1"])
    check("your OWN receipt does not count as someone having read it",
          chatOwnReceipt.isReadByOthers(eventID: "$evt1", excluding: "@t2_me:reddit.com") == false)
    check("a room with no ephemeral events is omitted rather than stored empty",
          chatEphemeral["!quiet"] == nil)

    // Video and GIF. Reddit serves chat media with no file extension, so
    // msgtype and mimetype are the only signals.
    let chatMediaKinds = """
    {"chunk":[
     {"type":"m.room.message","event_id":"$g","sender":"@a:reddit.com","origin_server_ts":1,
      "content":{"body":"a.gif","msgtype":"m.image","url":"mxc://reddit.com/g",
                 "info":{"mimetype":"image/gif","w":100,"h":80}}},
     {"type":"m.room.message","event_id":"$v","sender":"@a:reddit.com","origin_server_ts":2,
      "content":{"body":"v.mp4","msgtype":"m.video","url":"mxc://reddit.com/v",
                 "info":{"mimetype":"video/mp4","w":640,"h":480}}},
     {"type":"m.room.message","event_id":"$s","sender":"@a:reddit.com","origin_server_ts":3,
      "content":{"body":"s.png","msgtype":"m.image","url":"mxc://reddit.com/s",
                 "info":{"mimetype":"image/png","w":10,"h":10}}}
    ]}
    """
    let chatKinds = RedditChatClient.parseMessages(Data(chatMediaKinds.utf8))
    let chatGIF = chatKinds.first { $0.id == "$g" }
    let chatVideo = chatKinds.first { $0.id == "$v" }
    let chatStill = chatKinds.first { $0.id == "$s" }
    check("a GIF is detected by MIMETYPE, since the URL has no extension",
          chatGIF?.isAnimatedGIF == true)
    check("a still image is not treated as animated",
          chatStill?.isAnimatedGIF == false)
    check("a video is detected and is also media",
          chatVideo?.isVideo == true && chatVideo?.isMedia == true)
    check("a still image is not a video",
          chatStill?.isVideo == false)
}

// MARK: - Chat reactions

// Reddit does not accept unicode reactions. A key is an image filename
// from Reddit's CDN; name-style keys from third-party lists are rejected
// with M_INVALID_ARGUMENT_VALUE "reaction key is not supported".
@MainActor func checkChatReactions() async throws {
    check("Reddit's reaction set has all 48 keys", RedditChatReactions.keys.count == 48)
    check("...with no duplicates", Set(RedditChatReactions.keys).count == 48)
    check("...every key is a CDN filename, not an emoji",
          RedditChatReactions.keys.allSatisfy { $0.hasSuffix(".gif") || $0.hasSuffix(".png") })
    check("a live-verified key is present", RedditChatReactions.isSupported("foyijyyga7081.gif"))
    // Name-style keys are rejected by the server, so they must not appear in
    // the picker.
    check("emoji are not offered", !RedditChatReactions.isSupported("👍"))
    check("name-style keys are not offered", !RedditChatReactions.isSupported("upvote"))
    check("...including snoo names", !RedditChatReactions.isSupported("snoo_cry"))

    check("a reaction image resolves to Reddit's CDN",
          RedditChatReactions.imageURL(forKey: "foyijyyga7081.gif")?.absoluteString
            == "https://i.redd.it/foyijyyga7081.gif")
    // Keys are opaque filenames; a slash would escape the path.
    check("a key containing a path separator is refused",
          RedditChatReactions.imageURL(forKey: "../secret") == nil)
    check("an empty key is refused", RedditChatReactions.imageURL(forKey: "") == nil)

    // /relations payload. Reddit's own client sends the relation flattened
    // into content while sync delivers it nested; both must parse.
    let reactionFixture = """
    {"chunk":[
     {"type":"m.reaction","event_id":"$r1","sender":"@me:reddit.com",
      "content":{"m.relates_to":{"rel_type":"m.annotation","event_id":"$t","key":"foyijyyga7081.gif"}}},
     {"type":"m.reaction","event_id":"$r2","sender":"@them:reddit.com",
      "content":{"rel_type":"m.annotation","event_id":"$t","key":"foyijyyga7081.gif"}},
     {"type":"m.reaction","event_id":"$r3","sender":"@them:reddit.com",
      "content":{"m.relates_to":{"rel_type":"m.annotation","event_id":"$t","key":"jvuspmbga7081.gif"}}},
     {"type":"m.reaction","event_id":"$r4","sender":"@me:reddit.com",
      "content":{"m.relates_to":{"rel_type":"m.annotation","event_id":"$t","key":"k7ry7t1ga7081.gif"}},
      "unsigned":{"redacted_because":{"type":"m.room.redaction"}}}
    ]}
    """
    let parsedReactions = RedditChatClient.parseReactions(
        Data(reactionFixture.utf8), myUserID: "@me:reddit.com")

    check("reactions group by key", parsedReactions.count == 2)
    check("...counting every sender of that key",
          parsedReactions.first { $0.key == "foyijyyga7081.gif" }?.count == 2)
    // If only the nested form parsed, reactions from Reddit's web client
    // would vanish.
    check("the flattened form Reddit's client sends also parses",
          parsedReactions.first { $0.key == "foyijyyga7081.gif" }?
            .senders.contains("@them:reddit.com") == true)
    // Removal redacts the adding event, so its id is retained.
    check("your own reaction keeps the event id needed to remove it",
          parsedReactions.first { $0.key == "foyijyyga7081.gif" }?.myEventID == "$r1")
    check("someone else's reaction is not attributed to you",
          parsedReactions.first { $0.key == "jvuspmbga7081.gif" }?.myEventID == nil)
    // A removed reaction keeps its content and is marked only by
    // unsigned.redacted_because, unlike a redacted message whose content is
    // emptied; checking content would leave removed reactions on screen.
    check("a removed reaction is dropped despite keeping its content",
          !parsedReactions.contains { $0.key == "k7ry7t1ga7081.gif" })
    check("reaction images come from the CDN",
          parsedReactions.first?.imageURL?.host == "i.redd.it")

    // An edit's top-level body is Matrix's legacy fallback ("* edited"); the
    // room preview uses the new content instead.
    let editedRoomFixture = """
    {"rooms":{"join":{"!r":{"timeline":{"events":[
     {"type":"m.room.message","event_id":"$a","sender":"@a:reddit.com","origin_server_ts":1000,
      "content":{"body":"original","msgtype":"m.text"}},
     {"type":"m.room.message","event_id":"$b","sender":"@a:reddit.com","origin_server_ts":2000,
      "content":{"body":"* corrected","msgtype":"m.text",
                 "m.new_content":{"body":"corrected","msgtype":"m.text"},
                 "m.relates_to":{"rel_type":"m.replace","event_id":"$a"}}}
    ]}}}}}
    """
    let editedRooms = try! RedditChatClient.parseSync(Data(editedRoomFixture.utf8))
    check("the room preview shows edited text, not the '* ' wire fallback",
          editedRooms.rooms.first?.preview == "corrected")

    // A deleted last message has no body at all.
    let redactedRoomFixture = """
    {"rooms":{"join":{"!r":{"timeline":{"events":[
     {"type":"m.room.message","event_id":"$a","sender":"@a:reddit.com","origin_server_ts":1000,
      "content":{"body":"still here","msgtype":"m.text"}},
     {"type":"m.room.message","event_id":"$b","sender":"@a:reddit.com","origin_server_ts":2000,
      "content":{},"unsigned":{"redacted_because":{"type":"m.room.redaction"}}}
    ]}}}}}
    """
    let redactedRooms = try! RedditChatClient.parseSync(Data(redactedRoomFixture.utf8))
    check("a deleted last message does not blank the room preview",
          redactedRooms.rooms.first?.preview == "still here")

    // Reacting to an edited message must attach to the original event: the
    // edit event's id is folded away, so the reaction would render nowhere.
    // The message exposes both ids.
    check("an edited message exposes its edit event id for reactions",
          chatEdited.first { $0.id == "$orig" }?.editEventIDs == ["$edit"])
    check("...so reactions are looked up on both the original and the edit",
          chatEdited.first { $0.id == "$orig" }?.reactionEventIDs == ["$orig", "$edit"])
    check("an unedited message looks up only its own id",
          chatEdited.first { $0.id == "$keep" }?.reactionEventIDs == ["$keep"])
}
