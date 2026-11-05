import Foundation
import PhoebusCore

// MARK: - Inline YouTube Player
//
// Media > YouTube: with the switch off a YouTube video is a thumbnail that
// opens YouTube, and nothing creates the embedded player.
@MainActor func checkInlineYouTubePlayerSetting() async throws {
    typealias Policy = YouTubeInlinePolicy
    let watch = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    var settings = GeneralSettings.default

    check("Inline YouTube Player defaults on", settings.inlineYouTubePlayer)
    check("on, a YouTube link plays inline", Policy.presentation(for: watch, settings: settings) == .inlinePlayer
          && Policy.presentation(for: watch, settings: settings)?.createsPlayer == true)
    settings.inlineYouTubePlayer = false
    check("off, it is a thumbnail that opens the link and creates no player",
          Policy.presentation(for: watch, settings: settings) == .thumbnailOpensLink
            && Policy.presentation(for: watch, settings: settings)?.createsPlayer == false)
    check("off covers youtu.be, Shorts and mobile links alike",
          ["https://youtu.be/dQw4w9WgXcQ", "https://www.youtube.com/shorts/dQw4w9WgXcQ",
           "https://m.youtube.com/watch?v=dQw4w9WgXcQ"]
            .allSatisfy { Policy.presentation(for: URL(string: $0)!, settings: settings) == .thumbnailOpensLink })
    check("a link that isn't a YouTube video has no YouTube presentation",
          ["https://example.com/watch?v=dQw4w9WgXcQ", "https://www.youtube.com/@channel",
           "https://www.youtube.com/", "https://notyoutube.com/watch?v=dQw4w9WgXcQ"]
            .allSatisfy { Policy.presentation(for: URL(string: $0)!, settings: .default) == nil })
    settings.openVideosInYouTubeApp = true
    check("Open Videos in YouTube App stays a thumbnail for the app, whatever the inline switch says",
          Policy.presentation(for: watch, settings: settings) == .thumbnailOpensYouTubeApp
            && Policy.presentation(inlinePlayerEnabled: true, openInYouTubeApp: true) == .thumbnailOpensYouTubeApp)
    check("only the inline player uses the YouTube sign-in",
          Policy.usesYouTubeSignIn(.inlinePlayer) && !Policy.usesYouTubeSignIn(.thumbnailOpensLink)
            && !Policy.usesYouTubeSignIn(.thumbnailOpensYouTubeApp))

    // Stored with the neighbouring Media switches: in the settings blob and backups, per account.
    let decoded = try JSONDecoder().decode(GeneralSettings.self, from: Data("{}".utf8))
    check("a settings blob or an old backup without the key reads on", decoded.inlineYouTubePlayer)
    let saved = GeneralSettingsStore.load()
    var off = saved
    off.inlineYouTubePlayer = false
    GeneralSettingsStore.save(off)
    let backup = try BackupBundle.decode(from: try BackupBundle.captureCurrent().encoded())
    check("Inline YouTube Player round-trips through a settings backup",
          backup.generalSettings.inlineYouTubePlayer == false)
    GeneralSettingsStore.save(saved)
    check("a per-account override names the field",
          AccountSettingsOverrides.field(of: \GeneralSettings.inlineYouTubePlayer, in: .default) == "inlineYouTubePlayer")
    check("the Media screen lists a YouTube section",
          SettingsCategory.media.sections.contains { $0.title == "YouTube" })
}

// MARK: - Sign in to YouTube
//
// The player runs as the user's Google account once its web views hold a
// signed-in session: which cookies mean a session, and how a pasted cookie
// export becomes cookies.
@MainActor func checkSignInToYouTube() async throws {
    do {
        check("a signed-in Google session is told by its API-hash or login cookie",
              YouTubeSession.hasSession(cookieNames: ["PREF", "SAPISID"])
                && YouTubeSession.hasSession(cookieNames: ["__Secure-3PAPISID"])
                && YouTubeSession.hasSession(cookieNames: ["LOGIN_INFO"]))
        check("a visitor's cookies are not a session",
              !YouTubeSession.hasSession(cookieNames: ["PREF", "VISITOR_INFO1_LIVE", "YSC", "CONSENT"])
                && !YouTubeSession.hasSession(cookieNames: [String]()))
        check("only youtube.com and google.com hosts hold the session",
              YouTubeSession.isSessionDomain(".youtube.com") && YouTubeSession.isSessionDomain("accounts.google.com")
                && YouTubeSession.isSessionDomain("WWW.YouTube.com")
                && !YouTubeSession.isSessionDomain("notyoutube.com") && !YouTubeSession.isSessionDomain(".reddit.com")
                && !YouTubeSession.isSessionDomain("youtube.com.example.org"))
        check("the sign-in page is Google's YouTube sign-in, returning to youtube.com",
              YouTubeSession.signInURL.host == "accounts.google.com"
                && YouTubeSession.signInURL.absoluteString.hasSuffix("continue=https://www.youtube.com/"))

        let netscape = """
        # Netscape HTTP Cookie File
        .youtube.com\tTRUE\t/\tTRUE\t1893456000\tSAPISID\tabc/def
        #HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN_INFO\tx=y=z
        .google.com\tTRUE\t/\tFALSE\t1893456000\tNID\tn1
        .reddit.com\tTRUE\t/\tTRUE\t1893456000\treddit_session\tnope

        """
        let fromFile = YouTubeCookieImport.parse(netscape)
        check("a cookies.txt export keeps the youtube.com and google.com cookies and counts the rest",
              fromFile.cookies.map(\.name) == ["SAPISID", "LOGIN_INFO", "NID"] && fromFile.skipped == 1)
        check("a cookies.txt line carries its domain, path, flags and expiry",
              fromFile.cookies.first == YouTubeImportedCookie(
                name: "SAPISID", value: "abc/def", domain: ".youtube.com", path: "/", isSecure: true,
                isHTTPOnly: false, expires: Date(timeIntervalSince1970: 1_893_456_000)))
        check("a #HttpOnly_ line is an HttpOnly cookie, and a zero expiry is a session cookie",
              fromFile.cookies[1].isHTTPOnly && fromFile.cookies[1].expires == nil && fromFile.cookies[1].domain == ".youtube.com")
        check("a cookie value keeps its own equals signs and a file with a session is recognised",
              fromFile.cookies[1].value == "x=y=z" && fromFile.hasSession)

        let header = YouTubeCookieImport.parse("Cookie: PREF=f6=40000000; SAPISID=abc/def ; ; bare; VISITOR_INFO1_LIVE=v=1")
        check("a Cookie header is split on semicolons, keeping equals signs in values",
              header.cookies.map(\.name) == ["PREF", "SAPISID", "VISITOR_INFO1_LIVE"]
                && header.cookies.map(\.value) == ["f6=40000000", "abc/def", "v=1"])
        check("header cookies go on youtube.com, secure",
              header.cookies.allSatisfy { $0.domain == ".youtube.com" && $0.path == "/" && $0.isSecure } && header.hasSession)
        check("a bare name=value list works without the Cookie: prefix",
              YouTubeCookieImport.parse("SAPISID=1; LOGIN_INFO=2").cookies.count == 2)
        check("text that has no cookies imports nothing",
              YouTubeCookieImport.parse("").cookies.isEmpty
                && YouTubeCookieImport.parse("hello world").cookies.isEmpty
                && !YouTubeCookieImport.parse("PREF=1").hasSession)
    }
}
