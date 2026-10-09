import Foundation

/// Phoebus-only "Sign In to YouTube": the player runs as the user's Google
/// account (YouTube Premium, watch history, age-restricted videos). Pure
/// logic here; the web views and the cookie store are in PhoebusUI.
public enum YouTubeSession {
    /// Google's sign-in page for YouTube; it returns to youtube.com once the
    /// user is signed in.
    public static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/")!

    /// Cookies Google sets only for a signed-in session. A visitor has
    /// `VISITOR_INFO1_LIVE`, `PREF` and the like, which don't count.
    public static let sessionCookieNames: Set<String> = ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID", "LOGIN_INFO"]

    public static func hasSession(cookieNames: some Sequence<String>) -> Bool {
        cookieNames.contains { sessionCookieNames.contains($0) }
    }

    /// True for a host the YouTube player's session lives on.
    public static func isSessionDomain(_ domain: String) -> Bool {
        var host = domain.lowercased()
        while host.hasPrefix(".") { host.removeFirst() }
        return ["youtube.com", "google.com"].contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

/// One cookie read from pasted text, ready for `HTTPCookie`.
public struct YouTubeImportedCookie: Equatable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var isSecure: Bool
    public var isHTTPOnly: Bool
    /// Nil for a session cookie.
    public var expires: Date?

    public init(name: String, value: String, domain: String, path: String, isSecure: Bool, isHTTPOnly: Bool, expires: Date?) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.expires = expires
    }
}

/// Reads a browser's YouTube cookies from pasted text: a Netscape
/// `cookies.txt` export (tab-separated, `#HttpOnly_` lines included) or a
/// `Cookie:` request header (`a=b; c=d`). Cookies for other sites are left out.
public enum YouTubeCookieImport {
    public struct Result: Equatable, Sendable {
        public var cookies: [YouTubeImportedCookie]
        /// Cookies read but not for youtube.com or google.com.
        public var skipped: Int
        public var hasSession: Bool { YouTubeSession.hasSession(cookieNames: cookies.map(\.name)) }
    }

    public static func parse(_ text: String) -> Result {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let isNetscape = lines.contains { $0.split(separator: "\t", omittingEmptySubsequences: false).count >= 7 }
        let all = isNetscape ? lines.compactMap(netscapeCookie) : headerCookies(text)
        let kept = all.filter { YouTubeSession.isSessionDomain($0.domain) }
        return Result(cookies: kept, skipped: all.count - kept.count)
    }

    private static let httpOnlyPrefix = "#HttpOnly_"

    private static func netscapeCookie(_ line: String) -> YouTubeImportedCookie? {
        var line = line.trimmingCharacters(in: .whitespaces)
        var httpOnly = false
        if line.hasPrefix(httpOnlyPrefix) {
            httpOnly = true
            line.removeFirst(httpOnlyPrefix.count)
        } else if line.hasPrefix("#") {
            return nil
        }
        let fields = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7, !fields[5].isEmpty else { return nil }
        let seconds = TimeInterval(fields[4]) ?? 0
        return YouTubeImportedCookie(
            name: fields[5], value: fields[6], domain: fields[0],
            path: fields[2].isEmpty ? "/" : fields[2],
            isSecure: fields[3].uppercased() == "TRUE", isHTTPOnly: httpOnly,
            expires: seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil)
    }

    /// A header carries no domain, so its cookies go on youtube.com.
    private static func headerCookies(_ text: String) -> [YouTubeImportedCookie] {
        var header = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if header.lowercased().hasPrefix("cookie:") { header.removeFirst("cookie:".count) }
        return header.split(separator: ";").compactMap { pair in
            guard let equals = pair.firstIndex(of: "=") else { return nil }
            let name = pair[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return YouTubeImportedCookie(name: name, value: value, domain: ".youtube.com", path: "/",
                                         isSecure: true, isHTTPOnly: false, expires: nil)
        }
    }
}
