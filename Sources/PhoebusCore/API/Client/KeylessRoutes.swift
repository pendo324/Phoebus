import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reborn "Keyless route fallback" (`Apollo-Reborn#1403` and the route
/// commits after it): since late October 2026 www.reddit.com answers some
/// reads for a session cookie with its 403 block page, so an API-Key-Free
/// account sends those reads by an ordered list of routes and resends a
/// refused one on the next route. The table is built in; unlike Reborn there
/// is no remote route file (docs/intentional-differences.md).
public enum KeylessRoute: String, CaseIterable, Sendable {
    /// `www.reddit.com`, the path as the app writes it.
    case www
    /// `www.reddit.com` with the endpoint written `/api/<endpoint>/.json`.
    case wwwDotJSON = "www-dotjson"
    case old
    case api
    /// `oauth.reddit.com` carrying the cookie and no bearer.
    case oauth

    public var host: String {
        switch self {
        case .www, .wwwDotJSON: "www.reddit.com"
        case .old: "old.reddit.com"
        case .api: "api.reddit.com"
        case .oauth: "oauth.reddit.com"
        }
    }

    /// The path this route sends for `path` (already carrying the `.json`
    /// the web transport needs).
    public func path(for path: String) -> String {
        switch self {
        case .wwwDotJSON: KeylessRouteTable.endpointKey(path) + "/.json"
        case .www, .old, .api, .oauth: path
        }
    }
}

public struct KeylessRouteEntry: Sendable, Equatable {
    public let method: String
    /// `/`-separated segments: a lowercase literal, `*` for one name, `+` for
    /// two or more names joined with `+` (a multireddit).
    public let pattern: String
    public let routes: [KeylessRoute]

    var segments: [String] { KeylessRouteTable.segments(of: pattern) }
}

public enum KeylessRouteTable {
    private static let info: [KeylessRoute] = [.wwwDotJSON, .old]
    private static let moreChildren: [KeylessRoute] = [.oauth, .wwwDotJSON, .old]
    private static let search: [KeylessRoute] = [.oauth, .old]
    private static let rAll: [KeylessRoute] = [.oauth, .api, .old]
    private static let hotNewRising: [KeylessRoute] = [.oauth, .www]

    /// Reads www refuses at their usual path. `/api/morechildren` is a POST
    /// that only reads; no write is ever listed, so none is ever resent.
    /// The hot, new and rising sorts name the sort, so they beat a wildcard
    /// entry such as `/r/all/*` only where it is less specific.
    public static let builtIn: [KeylessRouteEntry] = [
        KeylessRouteEntry(method: "GET", pattern: "/api/info", routes: info),
        KeylessRouteEntry(method: "GET", pattern: "/api/morechildren", routes: moreChildren),
        KeylessRouteEntry(method: "POST", pattern: "/api/morechildren", routes: moreChildren),
        KeylessRouteEntry(method: "GET", pattern: "/r/all", routes: rAll),
        KeylessRouteEntry(method: "GET", pattern: "/r/all/*", routes: rAll),
        KeylessRouteEntry(method: "GET", pattern: "/search", routes: search),
        KeylessRouteEntry(method: "GET", pattern: "/subreddits/search", routes: search),
        KeylessRouteEntry(method: "GET", pattern: "/r/*/search", routes: search),
        KeylessRouteEntry(method: "GET", pattern: "/r/+/search", routes: search),
    ] + ["hot", "new", "rising"].flatMap { sort in
        ["/\(sort)", "/r/*/\(sort)", "/r/+/\(sort)"].map { KeylessRouteEntry(method: "GET", pattern: $0, routes: hotNewRising) }
    }

    /// `/api/info` for `api/info.json`, `/api/info/.json?id=…`, `/API/Info/`
    /// and so on: lowercased, one leading slash, no query, `.json` or
    /// trailing slash.
    public static func endpointKey(_ path: String) -> String {
        var p = path.lowercased()
        if let query = p.firstIndex(of: "?") { p = String(p[..<query]) }
        while p.hasSuffix("/") { p.removeLast() }
        if p.hasSuffix(".json") { p.removeLast(5) }
        while p.hasSuffix("/") { p.removeLast() }
        while p.hasPrefix("/") { p.removeFirst() }
        return "/" + p
    }

    static func segments(of key: String) -> [String] {
        key.count > 1 ? key.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init) : []
    }

    /// r/all's filter forms (`r/all-<sub>`, `r/all+<sub>`) match as `all`.
    private static func matchSegments(_ path: String) -> [String] {
        var parts = segments(of: endpointKey(path))
        if parts.count >= 2, parts[0] == "r", parts[1].hasPrefix("all-") || parts[1].hasPrefix("all+") {
            parts[1] = "all"
        }
        return parts
    }

    private static func isWildcard(_ segment: String) -> Bool { segment == "*" || segment == "+" }

    private static func isJoinedList(_ segment: String) -> Bool {
        if segment == "+" { return true }
        let names = segment.split(separator: "+", omittingEmptySubsequences: false)
        return names.count >= 2 && names.allSatisfy { !$0.isEmpty }
    }

    private static func matches(_ pattern: [String], _ segments: [String]) -> Bool {
        guard pattern.count == segments.count else { return false }
        for (want, have) in zip(pattern, segments) {
            switch want {
            case "*": if have.isEmpty || have.contains("+") { return false }
            case "+": if !isJoinedList(have) { return false }
            default: if want != have { return false }
            }
        }
        return true
    }

    /// Whether `a` is more specific than `b`: the first segment where one is
    /// a literal and the other a wildcard decides, so `/r/all/*` beats
    /// `/r/*/search` for `/r/all/search`.
    private static func isMoreSpecific(_ a: [String], than b: [String]) -> Bool {
        for (x, y) in zip(a, b) where isWildcard(x) != isWildcard(y) { return !isWildcard(x) }
        return false
    }

    public static func entry(method: String, path: String) -> KeylessRouteEntry? {
        let upper = method.uppercased()
        let wanted = matchSegments(path)
        var best: KeylessRouteEntry?
        for candidate in builtIn where candidate.method == upper && matches(candidate.segments, wanted) {
            if best == nil || isMoreSpecific(candidate.segments, than: best!.segments) { best = candidate }
        }
        return best
    }

    /// The routes to try in order; `www` alone for everything not listed.
    public static func routes(method: String, path: String) -> [KeylessRoute] {
        entry(method: method, path: path)?.routes ?? [.www]
    }

    /// Only reads have a second route, so only reads may be resent.
    public static func mayResend(method: String, path: String) -> Bool {
        routes(method: method, path: path).count > 1
    }
}

/// How a route's answer is told from a real one.
public enum KeylessRouteResponse {
    /// Reddit's block page: 403 with a ~190 KB `text/html` body. A 403 with a
    /// JSON body (a private community) is a normal answer.
    public static func isBlockPage(status: Int, contentType: String?) -> Bool {
        status == 403 && (contentType?.lowercased().contains("text/html") ?? false)
    }

    /// What old.reddit.com gives an account it won't serve: a redirect to its
    /// sign-in page (200, `text/html`, at `/login`). No read asks for `/login`
    /// itself, so ending up there means a redirect.
    public static func isSignInGate(finalURL: URL?, contentType: String?) -> Bool {
        guard let host = finalURL?.host?.lowercased(), host == "reddit.com" || host.hasSuffix(".reddit.com") else { return false }
        let path = finalURL?.path.lowercased() ?? ""
        guard path == "/login" || path.hasPrefix("/login/") else { return false }
        return contentType?.lowercased().contains("text/html") ?? false
    }

    /// Whether an error's body is a web page rather than Reddit's JSON, so a
    /// 403 with it is the block page and not a private community. The block
    /// page is a fragment that opens with `<body`, with no `<html` or doctype,
    /// and Reddit's JSON never starts with `<`.
    public static func isPageBody(_ body: String) -> Bool {
        let head = body.prefix(512).lowercased()
        return head.contains("<html") || head.contains("<!doctype html")
            || head.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" }).first == "<"
    }

    /// The `reason` of a JSON error body (`{"reason": "private", "message":
    /// "Forbidden", "error": 403}`), lowercased; nil for a page or no reason.
    public static func jsonReason(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reason = object["reason"] as? String else { return nil }
        return reason.lowercased()
    }

    public static func isRefusal(status: Int, contentType: String?, finalURL: URL?) -> Bool {
        isBlockPage(status: status, contentType: contentType) || isSignInGate(finalURL: finalURL, contentType: contentType)
    }

    public static func isRefusal(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return isRefusal(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"), finalURL: http.url)
    }
}

/// One route's record for one account and endpoint. Three refusals in a row
/// put it on a one-hour cooldown that doubles, up to eight hours, while the
/// first try after a cooldown keeps failing; a success clears it.
public struct KeylessRouteRecord: Sendable, Equatable {
    public static let refusalsBeforeCooldown = 3
    public static let firstCooldown: TimeInterval = 60 * 60
    public static let longestCooldown: TimeInterval = 8 * 60 * 60

    public private(set) var consecutiveRefusals = 0
    public private(set) var cooldownUntil: TimeInterval = 0
    /// 0 after a success.
    public private(set) var cooldownLength: TimeInterval = 0
    public private(set) var refusals = 0
    public private(set) var successes = 0

    public init() {}

    /// Returns true when this refusal starts (or extends) a cooldown.
    @discardableResult
    public mutating func noteRefusal(now: TimeInterval) -> Bool {
        refusals += 1
        // Sent before the cooldown began.
        if now < cooldownUntil { return false }
        consecutiveRefusals += 1
        let wasCooling = cooldownLength > 0
        if !wasCooling && consecutiveRefusals < Self.refusalsBeforeCooldown { return false }
        cooldownLength = wasCooling ? min(cooldownLength * 2, Self.longestCooldown) : Self.firstCooldown
        cooldownUntil = now + cooldownLength
        consecutiveRefusals = 0
        return true
    }

    public mutating func noteSuccess() {
        successes += 1
        consecutiveRefusals = 0
        cooldownLength = 0
        cooldownUntil = 0
    }

    public func cooldownRemaining(now: TimeInterval) -> TimeInterval {
        max(0, cooldownUntil - now)
    }
}

/// Per-account, per-endpoint route health, in memory.
public final class KeylessRouteHealth: @unchecked Sendable {
    public static let shared = KeylessRouteHealth()

    /// Paths group by their table entry, and an account's records start over
    /// if the store ever outgrows this.
    private static let maxRecords = 512

    private let lock = NSLock()
    private var records: [String: KeylessRouteRecord] = [:]

    public init() {}

    private func key(_ account: String, _ entry: KeylessRouteEntry, _ route: KeylessRoute) -> String {
        "\(account.lowercased())|\(entry.pattern)|\(route.rawValue)"
    }

    /// A refusal for `route`; true when it starts a cooldown.
    @discardableResult
    public func noteRefusal(account: String, method: String, path: String, route: KeylessRoute,
                            now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard !account.isEmpty, let entry = KeylessRouteTable.entry(method: method, path: path) else { return false }
        lock.lock(); defer { lock.unlock() }
        let k = key(account, entry, route)
        if records[k] == nil, records.count >= Self.maxRecords { records.removeAll() }
        return records[k, default: KeylessRouteRecord()].noteRefusal(now: now)
    }

    public func noteSuccess(account: String, method: String, path: String, route: KeylessRoute) {
        guard !account.isEmpty, let entry = KeylessRouteTable.entry(method: method, path: path) else { return }
        lock.lock(); defer { lock.unlock() }
        let k = key(account, entry, route)
        if records[k] == nil, records.count >= Self.maxRecords { records.removeAll() }
        records[k, default: KeylessRouteRecord()].noteSuccess()
    }

    public func cooldownRemaining(account: String, method: String, path: String, route: KeylessRoute,
                                  now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval {
        guard !account.isEmpty, let entry = KeylessRouteTable.entry(method: method, path: path) else { return 0 }
        lock.lock(); defer { lock.unlock() }
        return records[key(account, entry, route)]?.cooldownRemaining(now: now) ?? 0
    }

    /// The route to send by: the first untried one that isn't cooling down.
    /// When all are cooling the first untried is still sent, so an endpoint
    /// is never left without a try; a resend (something already tried) stops
    /// instead.
    public func choose(account: String, method: String, path: String, tried: Set<KeylessRoute>,
                       now: TimeInterval = Date().timeIntervalSince1970) -> KeylessRoute? {
        var firstUntried: KeylessRoute?
        for route in KeylessRouteTable.routes(method: method, path: path) where !tried.contains(route) {
            if firstUntried == nil { firstUntried = route }
            if cooldownRemaining(account: account, method: method, path: path, route: route, now: now) <= 0 { return route }
        }
        return tried.isEmpty ? firstUntried : nil
    }

    /// Test-facing.
    public func reset() {
        lock.lock(); records.removeAll(); lock.unlock()
    }
}

#if DEBUG
/// DEBUG-only switch that makes chosen routes count as refused by Reddit's block page
/// without sending anything to them, so the fallback can be driven while Reddit
/// still serves every route. `PHOEBUS_KEYLESS_BLOCK_ROUTES` names routes
/// separated by commas (`www-dotjson,oauth`). Compiled out of release builds.
public enum KeylessRouteDebug {
    nonisolated(unsafe) public static var blockedRoutes: Set<KeylessRoute> = {
        let raw = ProcessInfo.processInfo.environment["PHOEBUS_KEYLESS_BLOCK_ROUTES"] ?? ""
        return Set(raw.split(separator: ",").compactMap { KeylessRoute(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }()

    static func blocks(_ route: KeylessRoute) -> Bool { blockedRoutes.contains(route) }
    static let blockPage = "<html><body>whoa there, pardner!</body></html>"
}
#else
enum KeylessRouteDebug {
    static func blocks(_ route: KeylessRoute) -> Bool { false }
    static let blockPage = ""
}
#endif
