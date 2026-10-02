import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Album "Save All" capacity guard

// Reborn's constants. Saving an album downloads every original first, so a
// large album on a full device would fail halfway and leave a partial save;
// Reborn refuses up front instead.
@MainActor func checkAlbumSaveAllCapacityGuard() async throws {
    check("per-image ceiling is upstream's 50 MB",
          AlbumSaveCapacity.maximumItemBytes == 50 * 1024 * 1024)
    check("viewer ceiling is upstream's 150 MB",
          AlbumSaveCapacity.maximumViewerBytes == 150 * 1024 * 1024)
    check("safety margin is upstream's 50 MB",
          AlbumSaveCapacity.saveSafetyBytes == 50 * 1024 * 1024)

    // The min() against the viewer allowance is the subtle part: without
    // it a 100-image album would demand 5 GB, when the viewer itself never
    // holds more than 150 MB. Getting this wrong refuses saves that would
    // have succeeded.
    check("a huge album is capped by the viewer allowance, not per-item count",
          AlbumSaveCapacity.requiredBytes(storedBytes: 0, remainingCount: 100)
            == 150 * 1024 * 1024 + 50 * 1024 * 1024)
    check("a small album charges only what it needs",
          AlbumSaveCapacity.requiredBytes(storedBytes: 0, remainingCount: 1)
            == 50 * 1024 * 1024 + 50 * 1024 * 1024)
    // Bytes already on disk are deducted from the allowance.
    check("already-stored bytes reduce the requirement",
          AlbumSaveCapacity.requiredBytes(storedBytes: 140 * 1024 * 1024, remainingCount: 10)
            < AlbumSaveCapacity.requiredBytes(storedBytes: 0, remainingCount: 10))
    check("a viewer already at its ceiling requires only the safety margin",
          AlbumSaveCapacity.requiredBytes(storedBytes: 200 * 1024 * 1024, remainingCount: 5)
            == 50 * 1024 * 1024)

    check("a roomy volume permits the save",
          AlbumSaveCapacity.hasCapacity(
            availableBytes: 1024 * 1024 * 1024, storedBytes: 0, remainingCount: 10))
    check("a nearly-full volume refuses it",
          !AlbumSaveCapacity.hasCapacity(
            availableBytes: 10 * 1024 * 1024, storedBytes: 0, remainingCount: 10))
    // Nothing left to fetch means the bytes are already accounted for.
    check("nothing left to download always passes",
          AlbumSaveCapacity.hasCapacity(
            availableBytes: 0, storedBytes: 0, remainingCount: 0))

    // Reborn's copy.
    check("the Save All title matches upstream verbatim",
          AlbumSaveCapacity.saveAllTitle(count: 4) == "Save All 4 Images")
    check("a single save reports 'Saved'", AlbumSaveCapacity.savedToast(count: 1) == "Saved")
    check("a bulk save reports its count", AlbumSaveCapacity.savedToast(count: 7) == "Saved 7 images")
    check("the progress toast is singular for one image",
          AlbumSaveCapacity.downloadingToast(count: 1) == "Downloading original…")
    check("...and plural for several",
          AlbumSaveCapacity.downloadingToast(count: 3) == "Downloading originals…")
}

// MARK: - Share as Image card

// The Share as Image card's details line reads:
//     in Aww by [REDACTED]
//     ^ 57.0K  (comment) 365  (clock) 7h  (awards) 345
// The byline is "in <sub> by <user>", with no r/ prefix on the subreddit and
// no u/ on the author.
@MainActor func checkShareAsImageCard() async throws {
    check("the card byline matches the real card's wording",
          ShareCardFormatting.byline(subreddit: "Aww", author: "someone", hideUsername: false)
            == "in Aww by someone")
    // Hide Usernames REDACTS rather than omits: Apollo shows a filled bar where
    // the name was, with "in Aww by" still reading normally.
    check("hiding the username keeps the byline and drops only the name",
          ShareCardFormatting.byline(subreddit: "Aww", author: "someone", hideUsername: true)
            == "in Aww by ")

    // The tenth is kept even at .0 (57.0K).
    check("a large score abbreviates the way the real card does",
          ShareCardFormatting.abbreviated(57_000) == "57.0K")
    check("...keeping the tenth", ShareCardFormatting.abbreviated(57_400) == "57.4K")
    check("millions abbreviate too", ShareCardFormatting.abbreviated(2_500_000) == "2.5M")
    check("a small score is written out", ShareCardFormatting.abbreviated(345) == "345")
    check("...including zero", ShareCardFormatting.abbreviated(0) == "0")
    // Comment scores can be negative; a "-1.0K" is still correct but a
    // crash or a stray sign flip would not be.
    check("a negative score keeps its sign", ShareCardFormatting.abbreviated(-1_500) == "-1.5K")

    // The card has one line for everything, so the age is the short form
    // ("7h"), not "7 hours ago".
    let cardNow = Date(timeIntervalSince1970: 1_000_000)
    check("hours render compactly like the real card",
          ShareCardFormatting.compactAge(since: cardNow.addingTimeInterval(-7 * 3600), now: cardNow) == "7h")
    check("minutes render compactly",
          ShareCardFormatting.compactAge(since: cardNow.addingTimeInterval(-30 * 60), now: cardNow) == "30m")
    check("days render compactly",
          ShareCardFormatting.compactAge(since: cardNow.addingTimeInterval(-3 * 86400), now: cardNow) == "3d")
    check("months render compactly",
          ShareCardFormatting.compactAge(since: cardNow.addingTimeInterval(-90 * 86400), now: cardNow) == "3mo")
    check("years render compactly",
          ShareCardFormatting.compactAge(since: cardNow.addingTimeInterval(-800 * 86400), now: cardNow) == "2y")
    // A future timestamp (clock skew) must not produce a negative age.
    check("a future date does not render a negative age",
          ShareCardFormatting.compactAge(since: cardNow.addingTimeInterval(3600), now: cardNow) == "now")
}

// MARK: - SpongeText

// Apollo's composer option: the menu row is titled "Highlight sOmE TeXt",
// itself a worked example of the transform.
@MainActor func checkSpongeText() async throws {
    check("the SpongeText menu title is Apollo's",
          SpongeText.menuTitle == "Highlight sOmE TeXt")

    // The title constrains the rule exactly: "some text" must produce
    // "sOmE TeXt". Note the capital T right after the space: alternation is by
    // ABSOLUTE INDEX, so the space consumes a turn.
    check("the transform reproduces the title's own example",
          SpongeText.transform("some text") == "sOmE TeXt")
    // Guards against the two plausible-but-wrong rules that both yield
    // "sOmE tExT": skipping non-letters, and resetting per word.
    check("...not the letters-only alternation",
          SpongeText.transform("some text") != "sOmE tExT")
    check("a space really does consume a turn",
          SpongeText.transform("ab cd") == "aB Cd")

    check("an empty string transforms to nothing", SpongeText.transform("") == "")
    // Non-letters take their turn in the alternation and then pass
    // through unchanged, so the letter after one keeps whatever case its
    // own index dictates - here index 2 is even, so "b" stays lowercase.
    check("punctuation consumes a turn without changing case",
          SpongeText.transform("a,b") == "a,b")
    // Digits have no case; they must pass through rather than be dropped.
    check("digits survive the transform", SpongeText.transform("a1b2") == "a1b2")
    check("the transform preserves length",
          SpongeText.transform("hello world").count == "hello world".count)

    // Refusal copy.
    check("the no-selection message is Apollo's own wording",
          SpongeText.noSelectionMessage.hasPrefix("The SpongeText option requires you to select some text"))
}

// MARK: - X/Twitter client deep links

// Apollo's client list, in order:
// twitterrific, twitter, aviary, spring, inAppSafari, externalBrowser,
// plus tweetbot.
@MainActor func checkXTwitterClientDeepLinks() async throws {
    check("the X client list includes Twitterrific",
          TwitterLinkDestination.allCases.contains(.twitterrific))
    check("...and Tweetbot", TwitterLinkDestination.allCases.contains(.tweetbot))
    check("...and Aviary and Spring",
          TwitterLinkDestination.allCases.contains(.aviary)
            && TwitterLinkDestination.allCases.contains(.spring))

    // Every template takes an ID or a HANDLE, never a web URL, which is why the
    // target has to be parsed out first.
    let tweetURL = URL(string: "https://twitter.com/someone/status/1234567890")!
    let profileURL = URL(string: "https://x.com/someone")!
    check("a tweet URL yields its status id",
          LinkRouter.twitterTarget(for: tweetURL) == .status(id: "1234567890"))
    check("a profile URL yields its handle",
          LinkRouter.twitterTarget(for: profileURL) == .profile(handle: "someone"))
    // x.com/i/... and friends are not profiles; treating them as one
    // would deep-link to a user named "i".
    check("a non-profile path is not mistaken for a handle",
          LinkRouter.twitterTarget(for: URL(string: "https://x.com/i/flow/login")!) == nil)
    check("a non-Twitter URL has no target",
          LinkRouter.twitterTarget(for: URL(string: "https://example.com/a/status/1")!) == nil)

    // Templates.
    check("the X app gets twitter://status?id=",
          LinkRouter.twitterAppURL(for: tweetURL, client: .twitterApp)?.absoluteString
            == "twitter://status?id=1234567890")
    check("...and twitter://user?screen_name= for a profile",
          LinkRouter.twitterAppURL(for: profileURL, client: .twitterApp)?.absoluteString
            == "twitter://user?screen_name=someone")
    check("Twitterrific gets its own tweet template",
          LinkRouter.twitterAppURL(for: tweetURL, client: .twitterrific)?.absoluteString
            == "twitterrific:///tweet?id=1234567890")
    check("...and Twitterrific its own profile template",
          LinkRouter.twitterAppURL(for: profileURL, client: .twitterrific)?.absoluteString
            == "twitterrific:///profile?screen_name=someone")
    check("Tweetbot gets its own tweet template",
          LinkRouter.twitterAppURL(for: tweetURL, client: .tweetbot)?.absoluteString
            == "tweetbot:///status/1234567890")
    check("...and Tweetbot its own profile template",
          LinkRouter.twitterAppURL(for: profileURL, client: .tweetbot)?.absoluteString
            == "tweetbot:///user_profile/someone")

    // A naive string-swap implementation would produce
    // twitter://twitter.com/... - not valid in ANY of these schemes, so
    // it could never open a specific tweet.
    check("the deep link is not the old host-swapped form",
          LinkRouter.twitterAppURL(for: tweetURL, client: .twitterApp)?.absoluteString
            != "twitter://twitter.com/someone/status/1234567890")
    // No template is known for Aviary or Spring, so they must return
    // nil and fall back rather than invent a scheme that opens nothing.
    check("a client with no known template falls back instead of guessing",
          LinkRouter.twitterAppURL(for: tweetURL, client: .aviary) == nil)
}

// MARK: - Notification sounds

// Apollo's notification sound names, one .wav per sound.
@MainActor func checkNotificationSounds() async throws {
    check("all 25 real sounds are offered, plus Default and None",
          NotificationSound.allCases.count == 27)
    check("a real sound name is present",
          NotificationSound.allCases.contains(.bubblesAndBotany))
    check("...including the animal set",
          [NotificationSound.cat, .cow, .dog, .horse, .sheep, .chicken, .turkey, .penguin]
            .allSatisfy { NotificationSound.allCases.contains($0) })
    check("the invented placeholder sounds are gone",
          !NotificationSound.allCases.contains { $0.displayName == "Chime" || $0.displayName == "Bell" })

    // The raw value IS the filename stem, which is what
    // UNNotificationSound(named:) resolves against the bundle.
    check("a sound's filename matches the bundled asset",
          NotificationSound.bubblesAndBotany.filename == "bubbles-and-botany.wav")
    check("hyphenated names are preserved verbatim",
          NotificationSound.clickityClickerson.rawValue == "clickity-clickerson")
    check("...and single-word ones too", NotificationSound.wow.rawValue == "wow")
    // Default and None are ours, not Apollo assets, so they must not
    // claim a filename.
    check("Default names no file", NotificationSound.defaultSound.filename == nil)
    check("None names no file", NotificationSound.none.filename == nil)

    check("display names are humanised",
          NotificationSound.curiousCuttlefish.displayName == "Curious Cuttlefish")
    check("every sound has a non-empty display name",
          NotificationSound.allCases.allSatisfy { !$0.displayName.isEmpty })
    // Persisted as raw values, so a collision would silently load the
    // wrong sound.
    check("sound raw values are unique",
          Set(NotificationSound.allCases.map(\.rawValue)).count == NotificationSound.allCases.count)

    // Eleven display names are Apollo's, and two of them are not what
    // title-casing the filename produces, which is why to check rather than
    // derive.
    check("'and' stays lowercase, as Apollo wrote it",
          NotificationSound.bubblesAndBotany.displayName == "Bubbles and Botany")
    check("...and Honerva's Harp keeps its curly apostrophe",
          NotificationSound.honervasHarp.displayName == "Honerva\u{2019}s Harp")
    // A straight apostrophe would be the obvious guess and is wrong.
    check("the apostrophe is not the ASCII one",
          !NotificationSound.honervasHarp.displayName.contains("'"))
    // Names that DO match title-casing, as controls.
    check("Curious Cuttlefish matches the real name",
          NotificationSound.curiousCuttlefish.displayName == "Curious Cuttlefish")
    check("Drop of Deliberation matches the real name",
          NotificationSound.dropOfDeliberation.displayName == "Drop of Deliberation")
    check("Developer Saying Beep matches the real name",
          NotificationSound.developerSayingBeep.displayName == "Developer Saying Beep")
}

// MARK: - Cache explainer

// Apollo's "Is Apollo Still Taking up Storage?" screen. It exists because iOS
// counts WKWebView's website data against the app while the app cannot delete
// it, so clearing the app's own cache does not shrink the reported figure.
@MainActor func checkCacheExplainer() async throws {
    check("the explainer title is Apollo's",
          CacheExplainer.title == "Is Phoebus Still Taking up Storage?")
    check("the intro paragraph is verbatim",
          CacheExplainer.introduction.hasPrefix("If you\u{2019}ve done the normal \u{201C}Clear Cache\u{201D} action in Phoebus"))
    // Apollo uses typographic quotes and apostrophes throughout; ASCII
    // substitutes would be a visible difference in body copy.
    check("the intro uses curly quotes, not ASCII ones",
          !CacheExplainer.introduction.contains("'") && !CacheExplainer.introduction.contains("\""))

    // The instructions are built from THREE fragments - the
    // parenthetical is its own string between two halves of the
    // sentence - so the reassembly is what needs checking, not just
    // the presence of the text.
    check("the instruction fragments reassemble in order",
          CacheExplainer.instructions.contains("Website Data \u{2794} Remove All Website Data (note: this will clear all open tabs). Approximately 15 minutes later"))
    // The arrows are U+2794 HEAVY WIDE-HEADED RIGHTWARDS ARROW, not "->".
    check("the arrows are the real glyph",
          CacheExplainer.instructions.contains("\u{2794}"))
    check("there are four arrows, one per Settings step",
          CacheExplainer.instructions.filter { $0 == "\u{2794}" }.count == 4)
    check("the listing intro is verbatim",
          CacheExplainer.listingIntroduction.hasSuffix("(let me know if anything seems too large):"))

    // The listing measures real directories. Pointed at a known tree so
    // the result is checkable rather than machine-dependent.
    let cacheProbeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("apollo-cache-probe-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(
        at: cacheProbeRoot.appendingPathComponent("Big"), withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(
        at: cacheProbeRoot.appendingPathComponent("Small"), withIntermediateDirectories: true)
    try? Data(repeating: 0, count: 300_000)
        .write(to: cacheProbeRoot.appendingPathComponent("Big/blob.bin"))
    try? Data(repeating: 0, count: 16)
        .write(to: cacheProbeRoot.appendingPathComponent("Small/tiny.bin"))
    // A loose file at the root must NOT appear: the listing is of folders.
    try? Data(repeating: 0, count: 64)
        .write(to: cacheProbeRoot.appendingPathComponent("loose.bin"))

    let cacheEntries = CacheExplainer.folderListing(containerURL: cacheProbeRoot)
    check("the listing finds the container's directories", cacheEntries.count == 2)
    check("...and ignores loose files", !cacheEntries.contains { $0.name == "loose.bin" })
    // Largest first, because the copy invites spotting anything "too
    // large" and an alphabetical list buries it.
    check("the listing is ordered largest first", cacheEntries.first?.name == "Big")
    check("a directory's size includes its contents",
          (cacheEntries.first?.byteCount ?? 0) >= 300_000)
    check("sizes are human-formatted", cacheEntries.first?.formattedSize.contains("KB") == true
          || cacheEntries.first?.formattedSize.contains("MB") == true)
    try? FileManager.default.removeItem(at: cacheProbeRoot)

    // Settings Search must index NavigationLink rows, not just controls
    // (Toggle/Picker/...), and must match the link pattern whether or not
    // it uses parentheses.
    for linkRow in ["Is Phoebus Still Taking up Storage?", "Phoebus AI",
                    "Subreddit Sections", "Backup & Restore"] {
        check("Settings Search can reach the \(linkRow) row",
              SettingsSearch.index.contains { $0.title == linkRow })
    }
}

// MARK: - Automatic theme switching

// ThemeAutoSwitchSettings must wire up every row of Apollo's "Automatic
// Switch Threshold" section, so each control changes behaviour.

// Manual means manual: returning a value here would fight the user's
// own choice on every evaluation.
@MainActor func checkAutomaticThemeSwitching() async throws {
    var themeManual = ThemeAutoSwitchSettings()
    themeManual.useSystemLightDarkMode = false
    themeManual.switchMode = .manual
    check("manual mode leaves the theme alone",
          ThemeAutoSwitchResolver.shouldUseDarkTheme(
            settings: themeManual, systemIsDark: true, screenBrightness: 0.1) == nil)

    // The system toggle outranks the switch mode; Apollo presents it above that
    // section as a master control.
    var themeSystem = ThemeAutoSwitchSettings()
    themeSystem.useSystemLightDarkMode = true
    themeSystem.switchMode = .brightness
    check("following the system wins over the switch mode",
          ThemeAutoSwitchResolver.shouldUseDarkTheme(
            settings: themeSystem, systemIsDark: true, screenBrightness: 1.0) == true)
    check("...and follows it into light too",
          ThemeAutoSwitchResolver.shouldUseDarkTheme(
            settings: themeSystem, systemIsDark: false, screenBrightness: 0.0) == false)

    // A DIM screen implies a dark room, so dark applies at or below the 0.4
    // threshold.
    var themeBrightness = ThemeAutoSwitchSettings()
    themeBrightness.useSystemLightDarkMode = false
    themeBrightness.switchMode = .brightness
    themeBrightness.brightnessThreshold = 0.4
    check("a dim screen selects the dark theme",
          ThemeAutoSwitchResolver.shouldUseDarkTheme(
            settings: themeBrightness, systemIsDark: false, screenBrightness: 0.2) == true)
    check("a bright screen selects the light theme",
          ThemeAutoSwitchResolver.shouldUseDarkTheme(
            settings: themeBrightness, systemIsDark: true, screenBrightness: 0.9) == false)
    check("the threshold itself counts as dark",
          ThemeAutoSwitchResolver.shouldUseDarkTheme(
            settings: themeBrightness, systemIsDark: false, screenBrightness: 0.4) == true)

    // THE WRAPPING WINDOW IS THE WHOLE POINT. Apollo's defaults are dark
    // at 20:00 and light at 07:00, so the dark period crosses midnight. A
    // naive `minutes >= darkStart && minutes < lightStart` is false all
    // night for exactly the configuration most people use.
    check("evening is dark under the default schedule",
          ThemeAutoSwitchResolver.isDarkPeriod(minutes: 21 * 60, darkStart: 20 * 60, lightStart: 7 * 60))
    check("after midnight is still dark",
          ThemeAutoSwitchResolver.isDarkPeriod(minutes: 2 * 60, darkStart: 20 * 60, lightStart: 7 * 60))
    check("mid-morning is light",
          !ThemeAutoSwitchResolver.isDarkPeriod(minutes: 10 * 60, darkStart: 20 * 60, lightStart: 7 * 60))
    check("the moment dark starts is dark",
          ThemeAutoSwitchResolver.isDarkPeriod(minutes: 20 * 60, darkStart: 20 * 60, lightStart: 7 * 60))
    check("the moment light starts is light",
          !ThemeAutoSwitchResolver.isDarkPeriod(minutes: 7 * 60, darkStart: 20 * 60, lightStart: 7 * 60))
    // A non-wrapping window must still work, e.g. dark 07:00 -> light 20:00.
    check("a same-day window works too",
          ThemeAutoSwitchResolver.isDarkPeriod(minutes: 12 * 60, darkStart: 7 * 60, lightStart: 20 * 60))
    check("...and is light outside it",
          !ThemeAutoSwitchResolver.isDarkPeriod(minutes: 22 * 60, darkStart: 7 * 60, lightStart: 20 * 60))
    // Equal times would otherwise make every instant "dark".
    check("identical start times switch nothing",
          !ThemeAutoSwitchResolver.isDarkPeriod(minutes: 5 * 60, darkStart: 8 * 60, lightStart: 8 * 60))

    // A switch must keep the user's chosen theme FAMILY rather than
    // dropping them onto a stock default.
    let switchLight = Theme(id: "acme-light", name: "Acme", accentColorHex: "#FF0000",
                            commentDepthColorHexes: ["#111111"], isDark: false)
    let switchDark = Theme(id: "acme-dark", name: "Acme", accentColorHex: "#FF0000",
                           commentDepthColorHexes: ["#222222"], isDark: true)
    let otherDark = Theme(id: "other-dark", name: "Other", accentColorHex: "#00FF00",
                          commentDepthColorHexes: ["#333333"], isDark: true)
    let switchPool = [switchLight, switchDark, otherDark]
    check("switching to dark finds the same theme's dark variant",
          ThemeAutoSwitchResolver.counterpart(for: switchLight, wantsDark: true, in: switchPool)?.id
            == "acme-dark")
    check("switching back finds the light variant",
          ThemeAutoSwitchResolver.counterpart(for: switchDark, wantsDark: false, in: switchPool)?.id
            == "acme-light")
    check("a theme already in the wanted mode is left alone",
          ThemeAutoSwitchResolver.counterpart(for: switchDark, wantsDark: true, in: switchPool) == nil)
    // A theme with no counterpart must not be swapped for someone else's.
    check("a theme with no pair is not replaced by an unrelated one",
          ThemeAutoSwitchResolver.counterpart(for: otherDark, wantsDark: false, in: switchPool) == nil)

    // A GALLERY theme is persisted only in the mode the user picked, so
    // its counterpart is never in the available-themes list. A list-only
    // lookup would leave switching while on
    // gallery_catppuccin-mocha_dark doing nothing at all.
    let galleryDark = Theme(id: "gallery_catppuccin-mocha_dark", name: "Catppuccin Mocha",
                            accentColorHex: "#CBA6F7", commentDepthColorHexes: ["#444444"],
                            isDark: true, isGenerated: true)
    let galleryLight = ThemeAutoSwitchResolver.counterpart(
        for: galleryDark, wantsDark: false, in: [galleryDark])
    check("a gallery theme's counterpart is derived, not looked up",
          galleryLight != nil)
    check("...and is the LIGHT variant of the same slug",
          galleryLight?.id == "gallery_catppuccin-mocha_light")
    check("...and really is light", galleryLight?.isDark == false)
    check("a gallery theme already in the wanted mode is left alone",
          ThemeAutoSwitchResolver.counterpart(for: galleryDark, wantsDark: true, in: [galleryDark]) == nil)
    // An unknown slug must not fabricate a theme.
    let bogusGallery = Theme(id: "gallery_not-a-real-slug_dark", name: "Nope",
                             accentColorHex: "#FFFFFF", commentDepthColorHexes: ["#000000"],
                             isDark: true, isGenerated: true)
    check("an unrecognised gallery slug yields nothing",
          ThemeAutoSwitchResolver.counterpart(for: bogusGallery, wantsDark: false, in: []) == nil)
}

// MARK: - Inline Media in Messages

// Reborn's "Enable Chat Media" toggle for Inline Media, separate from the
// post/comment master switch.
@MainActor func checkInlineMediaInMessages() async throws {
    check("message media defaults ON, matching the real registered default",
          InlineMediaSettings.default.enabledInMessages)
    // The master toggle's default is OFF, so a shared default would be wrong in
    // one direction or the other.
    check("...and the post/comment master is on by default too",
          InlineMediaSettings.default.enabled)

    // Settings persisted without this row must keep the default.
    let legacyInlineMedia = Data("""
    {"enabled":true,"alignment":"center","size":100,"tapToPlayGIFs":false}
    """.utf8)
    let decodedInlineMedia = try? JSONDecoder().decode(InlineMediaSettings.self, from: legacyInlineMedia)
    check("older persisted settings still decode", decodedInlineMedia != nil)
    check("...and pick up the real default for the new row",
          decodedInlineMedia?.enabledInMessages == true)
    check("...without disturbing the values they did store",
          decodedInlineMedia?.enabled == true)

    // The two toggles are independent: turning the master off must not
    // silence message media, which is the whole point of the separate row.
    var splitInlineMedia = InlineMediaSettings.default
    splitInlineMedia.enabled = false
    splitInlineMedia.enabledInMessages = true
    let roundTrippedSplit = try? JSONDecoder().decode(
        InlineMediaSettings.self, from: JSONEncoder().encode(splitInlineMedia))
    check("the two toggles round-trip independently",
          roundTrippedSplit?.enabled == false && roundTrippedSplit?.enabledInMessages == true)
}

// MARK: - Private message threads

// Apollo decodes `data.replies` and its thread screen holds ARRAYS of
// messages. A PM is a conversation, so both are decoded.

// THE DECODING TRAP: Reddit sends "replies": "" when there are none,
// and a nested Listing when there are. A plain [RedditMessage]? fails
// on the empty STRING and takes the whole message down with it.
@MainActor func checkPrivateMessageThreads() async throws {
    let pmNoReplies = Data("""
    {"id":"a1","name":"t4_a1","author":"alice","subject":"Hi","body":"Hello",
     "created_utc":1700000000,"new":true,"replies":""}
    """.utf8)
    let decodedNoReplies = try? JSONDecoder.reddit.decode(RedditMessage.self, from: pmNoReplies)
    check("a message with \"replies\": \"\" still decodes", decodedNoReplies != nil)
    check("...with no replies", decodedNoReplies?.replies.isEmpty == true)
    check("...and its own fields intact", decodedNoReplies?.author == "alice")

    // The nested shape.
    let pmWithReplies = Data("""
    {"id":"a1","name":"t4_a1","author":"alice","subject":"Hi","body":"First",
     "created_utc":1700000000,
     "replies":{"kind":"Listing","data":{"children":[
       {"kind":"t4","data":{"id":"b2","name":"t4_b2","author":"bob","subject":"re: Hi",
         "body":"Second","created_utc":1700000100,"first_message_name":"t4_a1",
         "replies":{"kind":"Listing","data":{"children":[
           {"kind":"t4","data":{"id":"c3","name":"t4_c3","author":"alice","subject":"re: Hi",
             "body":"Third","created_utc":1700000200,"first_message_name":"t4_a1","replies":""}}
         ]}}}}
     ]}}}
    """.utf8)
    let decodedThread = try? JSONDecoder.reddit.decode(RedditMessage.self, from: pmWithReplies)
    check("a nested replies Listing decodes", decodedThread?.replies.count == 1)
    check("...and nests further down", decodedThread?.replies.first?.replies.count == 1)
    check("the root carries no first_message_name", decodedThread?.firstMessageName == nil)
    check("...while a reply points back at the root",
          decodedThread?.replies.first?.firstMessageName == "t4_a1")

    // Reddit nests arbitrarily deep, but a PM reads as a LINEAR
    // conversation - which is what MessageKit renders - so the tree is
    // flattened rather than indented.
    check("the thread flattens root-first",
          decodedThread?.thread.map(\.body) == ["First", "Second", "Third"])
    check("a message with no replies is a thread of one",
          decodedNoReplies?.thread.count == 1)
    // Ordering is what makes a conversation readable; oldest must lead.
    check("the thread reads oldest to newest",
          decodedThread?.thread.map(\.created) == decodedThread?.thread.map(\.created).sorted())

    // A PM with replies opens as a conversation; a lone PM and a comment
    // reply do not. Pushing a one-message thread would be worse than the
    // expandable row, and a comment reply must keep jumping to the comment
    // it refers to.
    let lonePM = RedditMessage(id: "x1", name: "t4_x1", author: "alice", subject: "Hi",
                               body: "Only one", created: Date())
    let threadedPM = RedditMessage(id: "x2", name: "t4_x2", author: "alice", subject: "Hi",
                                   body: "First", created: Date(),
                                   replies: [RedditMessage(id: "x3", name: "t4_x3", author: "bob",
                                                           subject: "re", body: "Second",
                                                           created: Date())])
    let commentReply = RedditMessage(id: "x4", name: "t1_x4", author: "carol", subject: "reply",
                                     body: "Nice", created: Date(), wasComment: true)
    check("a lone PM is not a thread", lonePM.replies.isEmpty)
    check("a PM with replies is a thread", !threadedPM.replies.isEmpty)
    check("...whose flattened form holds both messages", threadedPM.thread.count == 2)
    check("a comment reply is not a PM thread", commentReply.wasComment)

    // The DEBUG-only PM thread fixture's SHAPE is asserted here so it cannot
    // drift from what the screen expects.
    let debugThreadRoot = RedditMessage(
        id: "dbg1", name: "t4_dbg1", author: "pendo324", subject: "Test conversation",
        body: "mine", created: Date(),
        replies: [RedditMessage(id: "dbg2", name: "t4_dbg2", author: "apollo_tester",
                                subject: "Test conversation", body: "theirs",
                                created: Date(), firstMessageName: "t4_dbg1")])
    check("the forced PM fixture is a two-sided conversation",
          debugThreadRoot.thread.count == 2)
    check("...with two DIFFERENT authors, so both bubble sides render",
          Set(debugThreadRoot.thread.map(\.author)).count == 2)
    check("...and the reply points back at the root",
          debugThreadRoot.replies.first?.firstMessageName == debugThreadRoot.name)
}

// --- Inline media: a bare link is not media ---
//
// A post body must not produce an "inline media" item for every URL. Reborn
// renders inline IMAGES/VIDEOS only, replacing the URL text in place, gated on
// BOTH an image extension AND a curated host allowlist, to keep "random
// tracker pixels and arbitrary image-extensioned URLs out".
@MainActor func checkInlineMediaABareLinkIs() async throws {
    check("a plain article link is not treated as inline media",
          InlineMediaDetector.classify(URL(string: "https://www.nhc.noaa.gov/text/refresh/MIATCPEP3.shtml")!) == nil)
    check("an image-extensioned URL on an unlisted host is not inline media",
          InlineMediaDetector.classify(URL(string: "https://tracker.example.com/pixel.png")!) == nil)
    // Reddit's pseudo-MP4 GIFs: path ends .gif but the bytes are MP4.
    check("a preview.redd.it format=mp4 pseudo-GIF is excluded",
          InlineMediaDetector.classify(URL(string: "https://preview.redd.it/abc.gif?format=mp4")!) == nil)
    if case .image = InlineMediaDetector.classify(URL(string: "https://i.redd.it/abc123.jpg")!) {
        check("an i.redd.it image IS still inline media", true)
    } else {
        check("an i.redd.it image IS still inline media", false)
    }
}

// --- Markdown blockquotes ---
//
// The parser must accept two real Reddit spellings a strict parser
// rejects: `&gt;` (the API returns HTML-escaped bodies on several
// paths) and `>text` with no space (Reddit's own guide omits the
// space CommonMark wants).
@MainActor func checkMarkdownBlockquotes() async throws {
    check("a plain quote marker is preserved",
          RedditMarkdown.normalizeQuoteLine("> quoted") == "> quoted")
    check("a no-space quote gains the space CommonMark requires",
          RedditMarkdown.normalizeQuoteLine(">quoted") == "> quoted")
    check("an HTML-escaped quote marker is decoded",
          RedditMarkdown.normalizeQuoteLine("&gt; quoted") == "> quoted")
    check("...including the escaped no-space form",
          RedditMarkdown.normalizeQuoteLine("&gt;quoted") == "> quoted")
    check("nesting depth is preserved",
          RedditMarkdown.normalizeQuoteLine(">> nested") == ">> nested")
    check("...and mixed escaped nesting collapses to markers",
          RedditMarkdown.normalizeQuoteLine("&gt;&gt;nested") == ">> nested")
    check("an empty quote line keeps no trailing space",
          RedditMarkdown.normalizeQuoteLine(">") == ">")
    check("indentation before a quote is preserved",
          RedditMarkdown.normalizeQuoteLine("  > quoted") == "  > quoted")
    // A line that merely CONTAINS ">" is not a quote.
    check("a greater-than mid-line is left alone",
          RedditMarkdown.normalizeQuoteLine("a > b") == "a > b")
    check("multi-line bodies normalize per line",
          RedditMarkdown.normalizeBlockquotes(">one\n>two") == "> one\n> two")

    // Image links open the app's own viewer, not a web view, reusing the
    // inline host allowlist and extension rules so a URL behaves the
    // same whether rendered inline or tapped.
    check("a preview.redd.it image link opens the viewer",
          InlineMediaDetector.isViewableImageURL(URL(string: "https://preview.redd.it/hweviej68iph1.png?width=1642&format=png&auto=webp&s=abc")!))
    check("an i.redd.it image link opens the viewer",
          InlineMediaDetector.isViewableImageURL(URL(string: "https://i.redd.it/abc.jpg")!))
    // The extension must come from the PATH: Reddit preview URLs always
    // carry a query string, which would defeat a whole-string check.
    check("a query string does not defeat the extension check",
          InlineMediaDetector.isViewableImageURL(URL(string: "https://preview.redd.it/a.jpeg?width=9")!))
    check("an article link still opens the browser",
          !InlineMediaDetector.isViewableImageURL(URL(string: "https://www.nhc.noaa.gov/article.shtml")!))
    // Inherits the format=mp4 exclusion: those bytes are video.
    check("a pseudo-GIF that is really mp4 does not open the image viewer",
          !InlineMediaDetector.isViewableImageURL(URL(string: "https://preview.redd.it/a.gif?format=mp4")!))
    check("an image-extensioned URL on an unlisted host does not either",
          !InlineMediaDetector.isViewableImageURL(URL(string: "https://tracker.example.com/pixel.png")!))

    // Quote detection drives the indent, and must accept every spelling the
    // normalizer canonicalizes.
    check("a plain quote paragraph is detected",
          RedditMarkdown.isBlockQuote("> quoted"))
    check("a no-space quote paragraph is detected",
          RedditMarkdown.isBlockQuote(">quoted"))
    check("an escaped quote paragraph is detected",
          RedditMarkdown.isBlockQuote("&gt; quoted"))
    check("a nested quote paragraph is detected",
          RedditMarkdown.isBlockQuote(">> nested"))
    check("an ordinary paragraph is not a quote",
          !RedditMarkdown.isBlockQuote("not a quote"))
    check("a greater-than mid-paragraph is not a quote",
          !RedditMarkdown.isBlockQuote("a > b"))
}

// MARK: - Collapse Navigation Actions (Reborn)
//
// Action-pill collapsing is OPT-IN: key CollapseNavigationActions, default off.
@MainActor func checkApolloReborn371Collapse() async throws {
    check("collapse-navigation-actions defaults OFF, matching Tweak.xm:3801",
          !GeneralSettings.default.collapseNavigationActions)
    do {
        var round = GeneralSettings.default
        round.collapseNavigationActions = true
        let data = try! JSONEncoder().encode(round)
        let back = try! JSONDecoder().decode(GeneralSettings.self, from: data)
        check("the preference round-trips", back.collapseNavigationActions)
        // An older saved blob predates the key and must land on the default rather
        // than failing to decode.
        let sparse = try! JSONDecoder().decode(GeneralSettings.self,
                                               from: Data("{}".utf8))
        check("an older saved blob defaults Collapse Navigation Actions off", !sparse.collapseNavigationActions)
    }
}

// MARK: - Header Style "Hidden" (Reborn #1074)
//
// "Hidden removes the header edge effect entirely", alongside
// automatic/soft/hard/blur.
@MainActor func checkHeaderStyleHiddenReborn1074Documented() async throws {
    check("Hidden is a real HeaderStyle case",
          HeaderStyle(rawValue: "hidden") == .hidden)
    check("Hidden's display name matches the real picker option",
          HeaderStyle.hidden.displayName == "Hidden")
    // Picker order is Soft, Hard, [Blur], Hidden: "Blur is optional, while Hidden
    // always remains the last choice". CaseIterable drives our pickers, so Hidden
    // must be declared last.
    check("Hidden is last in the picker order, as the real source requires",
          HeaderStyle.allCases.last == .hidden)
    check("Hidden round-trips through the store's raw value",
          HeaderStyle(rawValue: HeaderStyle.hidden.rawValue) == .hidden)
}

// MARK: - Following section manual order (Reborn)
//
// Key FollowedUsersOrder: "saved order first (case-insensitive name match),
// then any new followed users in their natural (alphabetical) order."
@MainActor func checkFollowingSectionManualOrderReborn3() async throws {
    do {
        // No saved order: natural order is preserved untouched.
        check("an empty saved order changes nothing",
              FollowedUsersOrderStore.apply(savedOrder: [], to: ["u_a", "u_b", "u_c"]) == ["u_a", "u_b", "u_c"])
        // A full saved order wins over alphabetical.
        check("a saved order is applied",
              FollowedUsersOrderStore.apply(savedOrder: ["u_c", "u_a", "u_b"],
                                            to: ["u_a", "u_b", "u_c"]) == ["u_c", "u_a", "u_b"])
        // The dictionary is keyed by lowercased name and Reddit preserves username
        // casing, so a case-sensitive match would drop saved positions whenever the
        // API's casing differed. Casing must differ on BOTH sides for this to bite:
        // matching lowercase names alone would pass even with a broken
        // case-SENSITIVE comparator.
        check("matching is case-insensitive, as the real comparator is",
              FollowedUsersOrderStore.apply(savedOrder: ["u_alicea", "u_bobb"],
                                            to: ["u_BobB", "u_AliceA"]) == ["u_AliceA", "u_BobB"])
        // An unsaved entry sorts after EVERY saved one rather than interleaving
        // into a hand-arranged list.
        check("a newly followed user goes to the end, not the middle",
              FollowedUsersOrderStore.apply(savedOrder: ["u_z", "u_y"],
                                            to: ["u_a", "u_y", "u_z"]) == ["u_z", "u_y", "u_a"])
        // Several new arrivals keep alphabetical order among themselves.
        check("multiple new users stay in natural order after the saved ones",
              FollowedUsersOrderStore.apply(savedOrder: ["u_z"],
                                            to: ["u_a", "u_b", "u_z"]) == ["u_z", "u_a", "u_b"])
        // A stale name (un-followed) never matches and is not pruned, so
        // re-following restores the old position.
        check("a stale saved name is harmless",
              FollowedUsersOrderStore.apply(savedOrder: ["u_gone", "u_b"],
                                            to: ["u_a", "u_b"]) == ["u_b", "u_a"])
    }
}

// MARK: - Chat "Show in Messages" filter (Reborn)
//
// Keys ChatMessagesFilter / ChatMessagesUnreadOnly.
@MainActor func checkChatShowInMessagesFilterReborn() async throws {
    do {
        // Persisted spelling: the stored strings are "group" and "all", with direct
        // as the fall-through.
        check("filter raw values match the real persisted spelling",
              ChatMessagesFilter.group.rawValue == "group"
                && ChatMessagesFilter.all.rawValue == "all"
                && ChatMessagesFilter.direct.rawValue == "direct")
        // Direct is the DEFAULT, not merely the first case: it is what an unset or
        // unrecognised value reads as.
        check("an unrecognised stored value falls through to direct",
              ChatMessagesFilter(rawValue: "nonsense") == nil)
        // Menu titles.
        check("menu titles are the real ones",
              ChatMessagesFilter.direct.displayName == "Direct Chats"
                && ChatMessagesFilter.group.displayName == "Group Chats"
                && ChatMessagesFilter.all.displayName == "All Chats")
        // Direct-vs-group keys off Reddit's own chat type field.
        check("direct admits only direct rooms",
              ChatMessagesFilter.direct.admits(chatType: "direct")
                && !ChatMessagesFilter.direct.admits(chatType: "group"))
        check("group admits everything that is not direct",
              ChatMessagesFilter.group.admits(chatType: "group")
                && !ChatMessagesFilter.group.admits(chatType: "direct"))
        // A room with no recorded type counts as group, matching the web
        // UI's two-box split where "not direct" is what group selects.
        check("an untyped room counts as group",
              ChatMessagesFilter.group.admits(chatType: nil)
                && !ChatMessagesFilter.direct.admits(chatType: nil))
        // "'All' leaves every box clear - an unfiltered list is Reddit's
        // default".
        check("all admits everything",
              ChatMessagesFilter.all.admits(chatType: "direct")
                && ChatMessagesFilter.all.admits(chatType: "group")
                && ChatMessagesFilter.all.admits(chatType: nil))
    }
    do {
        func room(_ id: String, _ type: String?, unread: Int) -> ChatRoom {
            ChatRoom(id: id, name: nil, chatType: type, participants: [],
                     isInvite: false, lastMessageTimestamp: 0, preview: nil,
                     previewSender: nil, notificationCount: unread,
                     countsTowardGlobalBadge: false)
        }
        let rooms = [room("a", "direct", unread: 0),
                     room("b", "group", unread: 3),
                     room("c", "direct", unread: 2)]
        check("the filter narrows the room list",
              ChatMessagesFilterStore.apply(filter: .direct, unreadOnly: false, to: rooms).map(\.id) == ["a", "c"])
        check("unread-only narrows further",
              ChatMessagesFilterStore.apply(filter: .direct, unreadOnly: true, to: rooms).map(\.id) == ["c"])
        check("unread-only composes with all",
              ChatMessagesFilterStore.apply(filter: .all, unreadOnly: true, to: rooms).map(\.id) == ["b", "c"])
    }
}

// MARK: - Center Title Between Buttons (Reborn)
//
// The title centres between the actual controls of the bar.
@MainActor func checkCenterTitleBetweenButtonsReborn3() async throws {
    do {
        // Constants.
        check("capsule padding is the real 14pt",
              NavigationBarGeometry.capsuleHorizontalPadding == 14)
        check("title/button spacing is the real 8pt",
              NavigationBarGeometry.titleButtonSpacing == 8)

        // Back label ends at 120.7pt and trailing icons start at 319.3pt on a 402pt
        // bar: the gap midpoint (220pt) is 19pt past the bar midpoint (201pt).
        let shift = NavigationBarGeometry.offset(
            barWidth: 402, leadingSafeArea: 0,
            leftLimit: 120.7, rightLimit: 319.3, hasTrailingActions: true)
        check("the title shifts toward the wider side",
              shift != nil && abs(shift! - 19.0) < 0.1)

        // "The preference centers between actual controls, never an empty
        // edge. Settings screens with only Back keep their title at the
        // bar midpoint." A screen with a back button but NO trailing
        // actions must not centre.
        check("no trailing actions means no centring",
              NavigationBarGeometry.offset(
                barWidth: 402, leadingSafeArea: 0,
                leftLimit: 120.7, rightLimit: 402, hasTrailingActions: false) == nil)

        // A bar with no leading control must not centre either.
        check("no leading control means no centring",
              NavigationBarGeometry.offset(
                barWidth: 402, leadingSafeArea: 0,
                leftLimit: 0, rightLimit: 319.3, hasTrailingActions: true) == nil)

        // A symmetric bar should not move the title at all, which is the
        // sanity check that the formula reduces to the bar midpoint.
        let symmetric = NavigationBarGeometry.offset(
            barWidth: 400, leadingSafeArea: 0,
            leftLimit: 100, rightLimit: 300, hasTrailingActions: true)
        check("a symmetric bar leaves the title where it is",
              symmetric != nil && abs(symmetric!) < 0.001)

        // maximumContentWidth = gap - 2 * (capsulePadding + edgePadding)
        //                     = 198.6 - 2 * 22 = 154.6
        let width = NavigationBarGeometry.maximumContentWidth(leftLimit: 120.7, rightLimit: 319.3)
        check("the centred title's width budget matches the real formula",
              abs(width - 154.6) < 0.1)
        // Never negative.
        check("a negative budget clamps to zero",
              NavigationBarGeometry.maximumContentWidth(leftLimit: 200, rightLimit: 210) == 0)
    }
}
