import Foundation
import PhoebusCore

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
