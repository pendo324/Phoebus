import Foundation
import PhoebusCore

// Local crash reports: only the allowlisted fields of a KSCrash report
// survive.
@MainActor func checkCrashReportSanitizer() async throws {
    let raw: [String: Any] = [
        "report": ["timestamp": NSNumber(value: 1_700_000_000_000_000 as Int64)],
        "crash": [
            "error": [
                "type": "nsexception",
                "address": NSNumber(value: 0x1234),
                "reason": "secret u/someone r/private",
                "nsexception": ["name": "NSRangeException", "reason": "index 5 beyond bounds"],
            ],
            "threads": [
                ["index": 0, "crashed": true, "current_thread": true, "name": "com.apple.main-thread",
                 "registers": ["x0": 1],
                 "backtrace": ["contents": [
                    ["instruction_addr": NSNumber(value: 0x10), "object_addr": NSNumber(value: 0x1),
                     "object_name": "/private/var/containers/Phoebus.app/Phoebus", "symbol_name": "main"],
                 ], "skipped": 0]],
                ["index": 1, "crashed": false, "name": "queue-with-user-data",
                 "backtrace": ["contents": [["instruction_addr": NSNumber(value: 0x20), "object_name": "/usr/lib/libobjc.A.dylib"]]]],
            ],
        ],
        "binary_images": [
            ["name": "/usr/lib/unrelated.dylib", "image_addr": NSNumber(value: 0x9), "uuid": "U2"],
            ["name": "/private/var/containers/Phoebus.app/Phoebus", "image_addr": NSNumber(value: 0x1), "uuid": "U1"],
        ],
        "system": ["system_version": "27.0", "machine": "iPhone16,1", "CFBundleName": "Phoebus"],
        "user": ["phoebus": ["version": "0.1.0", "build": "1", "recent_actions": [
            ["event": "opened_post", "age_seconds": 3],
            ["event": "opened r/private", "age_seconds": 2],
        ]]],
    ]
    guard let report = CrashReportSanitizer.sanitized(raw) else {
        check("a KSCrash report sanitizes", false)
        return
    }
    let json = CrashReportSanitizer.jsonString(report)
    check("free-form reasons, thread names and registers never survive",
          !json.contains("secret") && !json.contains("beyond bounds") && !json.contains("main-thread")
              && !json.contains("queue-with-user-data") && !json.contains("registers"))
    check("a system exception name, category and frame addresses are kept",
          CrashReportSanitizer.exceptionName(report) == "NSRangeException"
              && CrashReportSanitizer.category(report) == "nsexception" && json.contains("0x0000000000000010"))
    check("paths collapse to file names, and referenced images come first",
          (report["binary_images"] as? [[String: Any]])?.first?["uuid"] as? String == "U1" && !json.contains("/private/var"))
    check("only enumerated recent actions travel",
          (report["recent_actions"] as? [[String: Any]])?.map { $0["event"] as? String } == ["opened_post"])
    check("the crash date reads back from the microsecond timestamp",
          CrashReportSanitizer.crashDate(report).map { Int($0.timeIntervalSince1970) } == 1_700_000_000)
    var custom = raw
    custom["crash"] = ["error": ["type": "nsexception", "nsexception": ["name": "MyAccountException"]]]
    check("a custom exception name is left out",
          CrashReportSanitizer.sanitized(custom).flatMap(CrashReportSanitizer.exceptionName) == nil)
    check("capture defaults on (absent key), as Reborn", CrashCaptureSettings.isEnabled(UserDefaults(suiteName: "phoebus.smoke.crash")!))
}

// "Open in App" routing for every non-Reddit link.
@MainActor func checkOpenInAppTargets() async throws {
    let defaults = UserDefaults(suiteName: "phoebus.smoke.openinapp")!
    defaults.removePersistentDomain(forName: "phoebus.smoke.openinapp")
    let steam = URL(string: "http://steampowered.com/app/620")!
    check("Steam is off by default", DedicatedAppLink.appTarget(for: steam, defaults: defaults, youTubeEnabled: false) == nil)
    defaults.set(true, forKey: "OpenLinksInSteamApp")
    check("Steam opens its store host over https Universal Links",
          DedicatedAppLink.appTarget(for: steam, defaults: defaults, youTubeEnabled: false).map { ($0.url.absoluteString, $0.universalLinksOnly) }
              .map { $0 == ("https://store.steampowered.com/app/620", true) } == true)
    defaults.set(true, forKey: "OpenLinksInGitHubApp")
    check("GitHub subdomains open in the app",
          DedicatedAppLink.appTarget(for: URL(string: "https://gist.github.com/x")!, defaults: defaults, youTubeEnabled: false)?.universalLinksOnly == true)
    check("YouTube videos open vnd.youtube:// when enabled",
          DedicatedAppLink.appTarget(for: URL(string: "https://youtu.be/dQw4w9WgXcQ")!, defaults: defaults, youTubeEnabled: true)?.url.absoluteString
              == "vnd.youtube://dQw4w9WgXcQ")
}

@MainActor func checkDefaultRedditToLoadChoice() async throws {
    let choices: [DefaultRedditToLoadChoice] = [.redditsList, .home, .popular, .all, .subreddit("apple"),
                                                .multireddit(path: "/user/me/m/tech", name: "tech")]
    check("Default Reddit to Load choices round-trip through storage",
          choices.allSatisfy { DefaultRedditToLoadChoice(stored: $0.stored) == $0 })
    check("an older typed value still reads as a subreddit",
          DefaultRedditToLoadChoice(stored: "r/pics") == .subreddit("pics"))
}

@MainActor func checkAICustomHeaders() async throws {
    check("a reserved header is refused with Reborn's reason",
          AICustomHeaders.problem(name: "Authorization", value: "x")?.contains("Authorization header") == true)
    check("a header value with a line break is refused",
          AICustomHeaders.problem(name: "x-a", value: "a\nb") != nil)
    let kept = AICustomHeaders.sanitized([["name": "x-opencode-session", "value": "1"],
                                          ["name": "X-OpenCode-Session", "value": "2"],
                                          ["name": "Host", "value": "evil"]])
    check("stored headers keep the first of each name and drop reserved ones",
          kept == [AICustomHeaders.Header(name: "x-opencode-session", value: "1")])
}

@MainActor func checkAIArticleExtraction() async throws {
    let para = String(repeating: "The council voted on the new transit plan today. ", count: 6)
    let html = """
    <html><head><title>x</title><meta property="og:description" content="Short &amp; sweet"></head>
    <body><nav><p>\(String(repeating: "Menu item link ", count: 5))</p></nav>
    <article><p>\(para)</p><p>tiny</p></article><footer><p>Copyright notice for the whole website here.</p></footer></body></html>
    """
    let text = AIArticleExtractor.extractText(html) ?? ""
    check("article prose comes from <article> paragraphs, not nav or footer",
          text.hasPrefix("The council voted") && !text.contains("Menu item") && !text.contains("Copyright"))
    let ld = """
    <script type="application/ld+json">{"@graph":[{"@type":"NewsArticle","articleBody":"\(para)\(para)"}]}</script>
    <p>Short paragraph that is long enough to count as prose here.</p>
    """
    check("JSON-LD articleBody wins when it is longer",
          (AIArticleExtractor.extractText(ld) ?? "").count > 400)
    check("a thin page falls back to its meta description",
          AIArticleExtractor.extractText(#"<meta name="description" content="A summary of the page">"#)?.contains("A summary of the page") == true)
    check("numeric entities decode", AIArticleExtractor.decodeEntities("caf&#233; &amp; tea") == "café & tea")
}

@MainActor func checkShareHostIndependence() async throws {
    var s = GeneralSettings.default
    s.shareOldRedditLinks = true
    check("Share old.reddit Links alone gives old.reddit links", s.effectiveShareLinkHost == .oldReddit)
    s.shareLinkHost = .fxReddit
    check("a Share Link Host other than Reddit wins over old.reddit", s.effectiveShareLinkHost == .fxReddit)
    s.shareOldRedditLinks = false
    check("turning old.reddit off keeps the chosen host", s.effectiveShareLinkHost == .fxReddit)
}

@MainActor func checkTranslationFallback() async throws {
    var s = TranslationSettings.default
    check("Google falls back to LibreTranslate only when it needs no key",
          BulkTranslationClient.fallbackProvider(after: .google, settings: s) == nil)
    s.libreTranslateURL = "https://translate.example.org/translate"
    check("...and to a self-hosted LibreTranslate",
          BulkTranslationClient.fallbackProvider(after: .google, settings: s) == .libreTranslate)
    s.microsoftAPIKey = "k"
    check("a Microsoft key is the preferred fallback",
          BulkTranslationClient.fallbackProvider(after: .google, settings: s) == .microsoft)
    check("Microsoft falls back to Google",
          BulkTranslationClient.fallbackProvider(after: .microsoft, settings: s) == .google)
    check("Apple never falls back",
          BulkTranslationClient.fallbackProvider(after: .apple, settings: s) == nil)
}

@MainActor func checkFloatingTabPiles() async throws {
    var piles = FloatingTabPiles()
    piles.join(["a"], onto: "b")
    check("joining two free tabs makes a pile, the dragged one in front", piles.members(of: "b") == ["a", "b"])
    piles.join(["c"], onto: "a")
    check("joining a pile puts the newcomer at its front", piles.members(of: "b") == ["c", "a", "b"] && piles.order(of: "b") == 2)
    piles.prune(keeping: ["c", "a"])
    check("closing a tab leaves the rest of its pile", piles.members(of: "c") == ["c", "a"])
    piles.prune(keeping: ["c"])
    check("a pile of one is no pile", !piles.isStacked("c") && piles.members(of: "c") == ["c"])
    piles.regather(["x", "y", "z"])
    let stack = piles.stackID(of: "y")!
    check("fanning out returns the members in order", piles.disband(stack) == ["x", "y", "z"] && !piles.isStacked("x"))
}


@MainActor func checkInboxRowText() async throws {
    check("inbox quote strips markdown and cuts at 50",
          InboxRowText.quoteSnippet("When [this kernel patch](https://x.org/a) gets merged, it'll probably land in 7.2") ==
          "When this kernel patch gets merged, it'll probably\u{2026}")
    let reply = RedditMessage(id: "a", name: "t1_a", author: "bob", subject: "post reply", body: "hi",
                              created: Date(), wasComment: true, linkTitle: "My post")
    check("a post reply reads \"bob replied to your post My post\"",
          InboxRowText.overview(for: reply, parentSnippet: nil).map(\.text).joined() == "bob replied to your post My post")
}

@MainActor func checkLongSwipeTriggerValues() async throws {
    check("Long Swipe Trigger Point offers stock's two values", LongSwipeTriggerPoint.allCases == [.normal, .later])
    let old = try JSONDecoder().decode([LongSwipeTriggerPoint].self, from: Data(#"["late","early","later"]"#.utf8))
    check("earlier stored late/early still decode", old == [.later, .normal, .later])
}

@MainActor func checkOpenGraphNumericEntities() async throws {
    let meta = OpenGraphParser.parse(html: #"<meta property="og:title" content="US road rage killer&amp;#x27;s sentence &#8212; quashed">"#)
    check("OpenGraph titles decode numeric entities, even double-escaped", meta.title == "US road rage killer's sentence — quashed")
}

@MainActor func checkCustomThemes() async throws {
    var theme = CustomTheme(name: "  My Theme  ")
    check("custom theme names are trimmed", theme.name == "My Theme")
    check("a blank theme starts from Reborn's starter colours", theme.hex(.background, mode: .dark) == "000000")
    let parsed = CustomTheme.parse(themeID: theme.themeID(mode: .dark))
    check("a bridged id parses back to the theme and mode", parsed?.id == theme.id && parsed?.mode == .dark)
    theme.setHex("#336699", for: .accent, mode: .light)
    check("set colours are stored as bare uppercase hex", theme.hex(.accent, mode: .light) == "336699")
    theme.setHex(nil, for: .card, mode: .light)
    check("clearing a required surface restores the starter", theme.hex(.card, mode: .light) == "FFFFFF")
    theme.setHex("112233", for: .text, mode: .light)
    theme.setHex(nil, for: .text, mode: .light)
    check("clearing an advanced override leaves it to the compiler", theme.hex(.text, mode: .light) == nil)
    theme.generate(.dark, from: .light)
    check("generating the other mode fills its surfaces", theme.hex(.background, mode: .dark) != nil)
    theme.font = .serif
    theme.advancedOptionsEnabled = true
    theme.setHex("ABCDEF", for: .separator, mode: .light)
    guard let data = theme.exportData() else { check("theme exports", false); return }
    let back = try CustomTheme.parse(fileData: data)
    check("a theme file round-trips colours, font and advanced flag",
          back.hex(.separator, mode: .light) == "ABCDEF" && back.font == .serif && back.advancedOptionsEnabled
          && back.origin == .imported && back.id != theme.id)
    let reborn = ##"{"schemaVersion":3,"name":"Mint","variant":"bold","input":{"light":{"accent":"2EC4A0"},"dark":{"accent":"#2EC4A0"}}}"##
    let mint = try CustomTheme.parse(fileData: Data(reborn.utf8))
    check("a Reborn theme file imports, missing surfaces from the starter",
          mint.name == "Mint" && mint.themeVariant == .bold && mint.hex(.accent, mode: .dark) == "2EC4A0"
          && mint.hex(.card, mode: .light) == "FFFFFF")
    check("a newer schema is refused", (try? CustomTheme.parse(fileData: Data(#"{"schemaVersion":9,"input":{}}"#.utf8))) == nil)
    check("unique names count up", CustomThemeStore.uniqueName("My Theme", among: [theme]) == "My Theme 2")
}

@MainActor func checkRebornBackupArchive() async throws {
    let defaults = UserDefaults.standard
    defaults.set("archived", forKey: "com.pendo324.Phoebus.smokeArchiveProbe")
    defer { defaults.removeObject(forKey: "com.pendo324.Phoebus.smokeArchiveProbe") }
    let accounts = AccountStorePersisted(accounts: [StoredAccount(username: "Alice"), StoredAccount(username: "bob")], activeIndex: 1)
    let data = try RebornBackupArchive.make(defaults: defaults, accounts: accounts)
    let payload = try ApolloBackupImport.read(zipData: data)
    check("an exported .apollobackup reads back through the backup importer",
          payload.preferences["com.pendo324.Phoebus.smokeArchiveProbe"] as? String == "archived")
    check("it is recognised as Phoebus's own backup", payload.isPhoebusBackup)
    check("its accounts round-trip through keychain.plist",
          payload.phoebusAccounts?.accounts.map(\.username) == ["alice", "bob"] && payload.phoebusAccounts?.activeIndex == 1)
    check("the archive names accounts.txt's usernames", String(decoding: data, as: UTF8.self).contains("alice\nbob"))
    check("ZipWriter's CRC is the standard one", ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    check("export names follow Reborn's", RebornBackupArchive.filename().hasPrefix("Apollo_Backup_")
          && RebornBackupArchive.filename().hasSuffix(".apollobackup"))
    let day = RebornBackupArchive.stamp(Date(), "yyyy-MM-dd")
    check("automatic archives count up within the day",
          AutomaticBackupArchive.filename(kind: .automatic, date: Date(),
                                          existing: ["Apollo_Manual_Backup_\(day)_002.apollobackup"])
          == "Apollo_Auto_Backup_\(day)_003.apollobackup")
    check("a Manual archive reads back as manual",
          AutomaticBackupArchive.kind(of: URL(fileURLWithPath: "/x/Apollo_Manual_Backup_\(day)_001.apollobackup")) == .manual)
}

@MainActor func checkScrollPastTracker() async throws {
    let tracker = ScrollPastTracker()
    tracker.appeared("a", at: 0); tracker.appeared("b", at: 1); tracker.appeared("c", at: 2)
    check("a row scrolled off the top counts as scrolled past", tracker.disappearedAbove("a"))
    tracker.appeared("a", at: 0)
    check("a row leaving at the bottom doesn't", !tracker.disappearedAbove("c"))
    check("an unknown row doesn't", !tracker.disappearedAbove("zz"))
}

@MainActor func checkMarkdownFormatting() async throws {
    func run(_ a: MarkdownAction, _ t: String, _ loc: Int, _ len: Int) -> MarkdownFormatting.Edit? {
        MarkdownFormatting.apply(a, to: t, selection: NSRange(location: loc, length: len))
    }
    check("bold wraps the selection and keeps it selected",
          run(.bold, "a word here", 2, 4) == .init(text: "a **word** here", selection: NSRange(location: 4, length: 4)))
    check("italic with no selection leaves the cursor between the stars",
          run(.italic, "ab", 2, 0) == .init(text: "ab**", selection: NSRange(location: 3, length: 0)))
    check("ordered list numbers each selected line",
          run(.orderedList, "one\ntwo", 0, 7)?.text == "1. one\n2. two")
    check("quote prefixes the cursor's line only", run(.quote, "a\nb\nc", 2, 0)?.text == "a\n> b\nc")
    check("link around a selected URL puts it in the parentheses",
          run(.link, "https://x.io", 0, 12) == .init(text: "[](https://x.io)", selection: NSRange(location: 1, length: 0)))
    check("link around text leaves the cursor in the parentheses",
          run(.link, "site", 0, 4) == .init(text: "[site]()", selection: NSRange(location: 7, length: 0)))
    check("subreddit token is spaced from the previous word", run(.subreddit, "see", 3, 0)?.text == "see /r/")
    check("multi-line code is indented four spaces", run(.code, "a\nb", 0, 3)?.text == "    a\n    b")
    check("inline code uses backticks", run(.code, "x", 0, 1)?.text == "`x`")
    check("horizontal line sits on its own paragraph", run(.horizontalRule, "text", 4, 0)?.text == "text\n\n---\n\n")
    check("spoiler and superscript use Reddit's markers",
          run(.spoiler, "s", 0, 1)?.text == ">!s!<" && run(.superscript, "s", 0, 1)?.text == "^(s)")
    check("SpongeText needs a selection", run(.spongeText, "abc", 1, 0) == nil)
}

@MainActor func checkStandardIconPacks() async throws {
    let packs = StandardIconPack.all
    check("standard packs hold Apollo's counts", packs.map(\.iconCount) == [32, 19, 90, 22])
    let ids = packs.flatMap(\.iconIDs)
    check("no icon sits in two packs", Set(ids).count == ids.count)
    check("every pack icon is a known icon", packs.allSatisfy { $0.icons.count == $0.iconCount })
    check("packs keep Apollo's names and credits",
          AppIconOption.all.first { $0.id == "morty" }?.displayName == "Wubalubadubdub"
          && AppIconOption.all.first { $0.id == "the-adventurer" }?.artist == "David Lanham")
}
