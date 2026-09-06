import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

/// Push notifications through Apollo-Reborn's two delivery paths:
///
///  - **Self-hosted backend.** The server polls Reddit for each
///    registered account and pushes inbox replies, mentions, private
///    messages and watcher hits. This build has no `aps-environment`
///    entitlement, so the backend always delivers through Bark.
///  - **Bark.** The free "Bark - Custom Notifications" App Store app
///    owns a real push entitlement; its push URL
///    (`https://api.day.app/<key>` or a self-hosted `bark-server`)
///    accepts a JSON POST and shows the notification. Tapping it opens
///    `url`, which deep-links back here.
///
/// The device identity on the backend is a synthetic 64-hex token,
/// generated once with `SecRandomCopyBytes` and kept.
public enum PushNotificationClient {
    // MARK: Configuration parsing

    /// http(s) with a host, trimmed, trailing slashes dropped; else nil.
    public static func parseHTTPURL(_ raw: String?) -> URL? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", !(url.host ?? "").isEmpty else { return nil }
        return url
    }

    public static func backendURL(_ settings: NotificationBackendSettings) -> URL? { parseHTTPURL(settings.backendURL) }

    public static func barkURL(_ settings: NotificationBackendSettings) -> URL? {
        settings.barkEnabled ? parseHTTPURL(settings.barkPushURL) : nil
    }

    /// Bark mode: Bark configured AND a backend.
    public static func barkModeActive(_ settings: NotificationBackendSettings) -> Bool {
        barkURL(settings) != nil && backendURL(settings) != nil
    }

    // MARK: Synthetic device token

    private static let tokenKey = "BarkSyntheticDeviceToken"

    public static func syntheticTokenHex(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: tokenKey), existing.count == 64,
           existing.allSatisfy(\.isHexDigit) {
            return existing.lowercased()
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        #else
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        #endif
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        defaults.set(hex, forKey: tokenKey)
        return hex
    }

    // MARK: Bark payloads

    /// This app's deep-link scheme. The backend's own `apollo://`
    /// click URLs are rewritten to it by `appClickURL(forBackend:)`.
    public static let scheme = "phoebus"

    /// Bark's JSON body.
    public struct BarkMessage: Encodable, Equatable, Sendable {
        public var title: String
        public var body: String
        public var url: String?
        public var group: String?
        public var icon: String?
        public var sound: String?
        public var level: String?

        public init(title: String, body: String, url: String? = nil, group: String? = "apollo",
                    icon: String? = nil, sound: String? = nil, level: String? = nil) {
            self.title = title; self.body = body; self.url = url; self.group = group
            self.icon = icon; self.sound = sound; self.level = level
        }
    }

    /// The test notification, with this app's settings link.
    public static func testMessage(sound: String?) -> BarkMessage {
        BarkMessage(title: "Phoebus",
                    body: "Bark delivery works! Notifications from your backend will arrive like this one.",
                    url: "\(scheme)://reborn/settings",
                    group: "apollo",
                    icon: defaultIconURL,
                    sound: sound ?? "traloop")
    }

    /// Stock Apollo icon, hosted by Apollo-Reborn for Bark.
    public static let defaultIconURL = "https://raw.githubusercontent.com/Apollo-Reborn/Apollo-Reborn/main/assets/bark-icons/default.png"

    /// The push URL the backend should POST to: the Bark URL, with
    /// `?sound=` pinned to the chosen notification sound when one is
    /// set (bark-server lets the query win over the body). Bark sound ids
    /// are camelCase without extension.
    public static func effectiveBarkURL(_ base: URL, soundID: String?) -> URL {
        guard let soundID, !soundID.isEmpty,
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        var items = (comps.queryItems ?? []).filter { $0.name != "sound" }
        items.append(URLQueryItem(name: "sound", value: soundID))
        comps.queryItems = items
        return comps.url ?? base
    }

    /// Bark's reply: `{"code":200,"message":"success"}`. A 200 with any
    /// other code (bad device key) is still a failure.
    public static func barkAccepted(status: Int, body: Data) -> (Bool, String?) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let code = (json?["code"] as? NSNumber)?.intValue ?? 0
        let message = json?["message"] as? String
        return (status == 200 && code == 200, message)
    }

    public static func sendBark(_ message: BarkMessage, to url: URL, session: URLSession = .shared) async -> (ok: Bool, message: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(message)
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let (ok, barkMessage) = barkAccepted(status: status, body: data)
            if ok { return (true, "Test notification sent. Check for a Bark notification, then tap it to reopen Phoebus.") }
            return (false, "Bark server answered HTTP \(status)\(barkMessage.map { ": \($0)" } ?? ""). Check the push URL / device key.")
        } catch {
            return (false, "Could not reach the Bark server: \(error.localizedDescription)")
        }
    }

    // MARK: Backend

    public struct BackendError: LocalizedError, Sendable {
        public let status: Int
        public let body: String
        public var errorDescription: String? {
            status == 0 ? body : "Backend answered HTTP \(status)\(body.isEmpty ? "" : ": \(body)")"
        }
    }

    /// `GET /v1/health` (5s timeout).
    public static func testBackend(_ base: URL, session: URLSession = .shared) async -> (ok: Bool, message: String) {
        var request = URLRequest(url: base.appendingPathComponent("v1/health"))
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? (true, "Connected. The backend is reachable.")
                                 : (false, "Backend answered HTTP \(status).")
        } catch {
            return (false, "Request failed: \(error.localizedDescription)")
        }
    }

    /// `POST /v1/device` body: the backend decodes `domain.Device`, whose
    /// token/sandbox fields have no json tags (Go's default names) and
    /// whose transport fields are snake_case. Headers carry the
    /// transport too (`X-Apollo-Transport`), which the backend prefers.
    public static func deviceBody(token: String, barkEndpoint: URL) -> [String: Any] {
        ["APNSToken": token, "Sandbox": false, "transport": "bark", "transport_endpoint": barkEndpoint.absoluteString]
    }

    /// `POST /v1/device/{token}/accounts` item: the backend refreshes the
    /// token itself with these OAuth details.
    public static func accountBody(username: String, accessToken: String, refreshToken: String,
                                   clientID: String, clientSecret: String, redirectURI: String, userAgent: String) -> [String: Any] {
        ["username": username, "access_token": accessToken, "refresh_token": refreshToken,
         "reddit_client_id": clientID, "reddit_client_secret": clientSecret,
         "reddit_redirect_uri": redirectURI, "reddit_user_agent": userAgent]
    }

    public struct Account: Sendable {
        public var username: String
        public var accessToken: String
        public var refreshToken: String
        public init(username: String, accessToken: String, refreshToken: String) {
            self.username = username; self.accessToken = accessToken; self.refreshToken = refreshToken
        }
    }

    static func send(_ method: String, _ base: URL, _ path: String, json: Any?, token: String?,
                     headers: [String: String] = [:], session: URLSession) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token, !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Registration-Token") }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BackendError(status: status, body: String(text.prefix(300)))
        }
        return data
    }

    /// Registers this device (Bark transport) and every OAuth account.
    /// Web-session (API-key-free) accounts are skipped: the backend
    /// needs a refresh token to poll Reddit on its own.
    @discardableResult
    public static func register(settings: NotificationBackendSettings, accounts: [Account], soundID: String?,
                                clientID: String, clientSecret: String, redirectURI: String, userAgent: String,
                                session: URLSession = .shared) async throws -> Int {
        guard let base = backendURL(settings) else { throw BackendError(status: 0, body: "Enter a Backend URL first.") }
        guard let bark = barkURL(settings) else {
            throw BackendError(status: 0, body: "This build can't receive Apple push notifications, so it needs Bark Delivery turned on with a push URL.")
        }
        let token = syntheticTokenHex()
        let endpoint = effectiveBarkURL(bark, soundID: soundID)
        _ = try await send("POST", base, "v1/device", json: deviceBody(token: token, barkEndpoint: endpoint),
                           token: settings.registrationToken,
                           headers: ["X-Apollo-Transport": "bark", "X-Apollo-Transport-Endpoint": endpoint.absoluteString],
                           session: session)
        let items = accounts.map {
            accountBody(username: $0.username, accessToken: $0.accessToken, refreshToken: $0.refreshToken,
                        clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI, userAgent: userAgent)
        }
        _ = try await send("POST", base, "v1/device/\(token)/accounts", json: items, token: settings.registrationToken,
                           headers: ["X-Apollo-Reddit-Client-Id": clientID, "X-Apollo-Reddit-Client-Secret": clientSecret,
                                     "X-Apollo-Reddit-Redirect-Uri": redirectURI, "X-Apollo-Reddit-User-Agent": userAgent],
                           session: session)
        return items.count
    }

    /// Re-registers only the device row with the current Bark endpoint and
    /// sound, flipping it in place, for a changed sound or push URL. The
    /// accounts already registered stay as they are.
    public static func syncDevice(settings: NotificationBackendSettings, soundID: String?,
                                  session: URLSession = .shared) async throws {
        guard let base = backendURL(settings), let bark = barkURL(settings) else { return }
        let token = syntheticTokenHex()
        let endpoint = effectiveBarkURL(bark, soundID: soundID)
        _ = try await send("POST", base, "v1/device", json: deviceBody(token: token, barkEndpoint: endpoint),
                           token: settings.registrationToken,
                           headers: ["X-Apollo-Transport": "bark", "X-Apollo-Transport-Endpoint": endpoint.absoluteString],
                           session: session)
    }

    /// `DELETE /v1/device/{token}`: stop all pushes to this device.
    public static func unregister(settings: NotificationBackendSettings, session: URLSession = .shared) async throws {
        guard let base = backendURL(settings) else { return }
        _ = try await send("DELETE", base, "v1/device/\(syntheticTokenHex())", json: nil, token: nil, session: session)
    }

    /// `POST /v1/device/{token}/test`: the backend sends its own
    /// "📣 Hello, is this thing on?" through Bark, proving the whole path.
    public static func sendBackendTest(settings: NotificationBackendSettings, session: URLSession = .shared) async throws {
        guard let base = backendURL(settings) else { throw BackendError(status: 0, body: "Enter a Backend URL first.") }
        _ = try await send("POST", base, "v1/device/\(syntheticTokenHex())/test", json: nil, token: nil, session: session)
    }

    /// `PATCH /v1/device/{token}/account/{redditID}/notifications`.
    public static func setAccountNotifications(settings: NotificationBackendSettings, redditID: String,
                                               inbox: Bool, watchers: Bool, globalMute: Bool,
                                               session: URLSession = .shared) async throws {
        guard let base = backendURL(settings) else { return }
        _ = try await send("PATCH", base, "v1/device/\(syntheticTokenHex())/account/\(redditID)/notifications",
                           json: ["inbox_notifications": inbox, "watcher_notifications": watchers, "global_mute": globalMute],
                           token: nil, session: session)
    }

    /// `GET .../notifications`: (inbox, watchers, globalMute).
    public static func accountNotifications(settings: NotificationBackendSettings, redditID: String,
                                            session: URLSession = .shared) async throws -> (inbox: Bool, watchers: Bool, globalMute: Bool) {
        guard let base = backendURL(settings) else { return (false, false, false) }
        let data = try await send("GET", base, "v1/device/\(syntheticTokenHex())/account/\(redditID)/notifications",
                                  json: nil, token: nil, session: session)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((json["inbox_notifications"] as? Bool) ?? false, (json["watcher_notifications"] as? Bool) ?? false,
                (json["global_mute"] as? Bool) ?? false)
    }

    // MARK: Watchers

    public struct Watcher: Decodable, Identifiable, Equatable, Sendable {
        public let id: Int64
        public let type: String
        public let label: String
        public let sourceLabel: String
        public let keyword: String?
        public let upvotes: Int64?
        public let flair: String?
        public let domain: String?
        public let author: String?
        public let hits: Int64

        enum CodingKeys: String, CodingKey {
            case id, type, label, keyword, upvotes, hits, flair, domain, author
            case sourceLabel = "source_label"
        }
    }

    /// `POST .../watcher` body (Go default capitalised names). Type is
    /// "subreddit", "trending" or "user".
    public static func watcherBody(type: String, subreddit: String?, user: String?, label: String,
                                   keyword: String? = nil, upvotes: Int64? = nil,
                                   flair: String? = nil, domain: String? = nil, author: String? = nil) -> [String: Any] {
        var criteria: [String: Any] = [:]
        if let subreddit { criteria["Subreddit"] = subreddit }
        if let keyword, !keyword.isEmpty { criteria["Keyword"] = keyword }
        if let upvotes, upvotes > 0 { criteria["Upvotes"] = upvotes }
        if let flair, !flair.isEmpty { criteria["Flair"] = flair }
        if let domain, !domain.isEmpty { criteria["Domain"] = domain }
        if let author, !author.isEmpty { criteria["Author"] = author }
        var body: [String: Any] = ["Type": type, "Label": label, "Criteria": criteria]
        if let subreddit { body["Subreddit"] = subreddit }
        if let user { body["User"] = user }
        return body
    }

    public static func listWatchers(settings: NotificationBackendSettings, redditID: String,
                                    session: URLSession = .shared) async throws -> [Watcher] {
        guard let base = backendURL(settings) else { return [] }
        let data = try await send("GET", base, "v1/device/\(syntheticTokenHex())/account/\(redditID)/watchers",
                                  json: nil, token: nil, session: session)
        return try JSONDecoder().decode([Watcher].self, from: data)
    }

    @discardableResult
    public static func createWatcher(settings: NotificationBackendSettings, redditID: String, body: [String: Any],
                                     session: URLSession = .shared) async throws -> Int64? {
        guard let base = backendURL(settings) else { throw BackendError(status: 0, body: "Enter a Backend URL first.") }
        let data = try await send("POST", base, "v1/device/\(syntheticTokenHex())/account/\(redditID)/watcher",
                                  json: body, token: nil, session: session)
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap { ($0["id"] as? NSNumber)?.int64Value }
    }

    public static func deleteWatcher(settings: NotificationBackendSettings, redditID: String, id: Int64,
                                     session: URLSession = .shared) async throws {
        guard let base = backendURL(settings) else { return }
        _ = try await send("DELETE", base, "v1/device/\(syntheticTokenHex())/account/\(redditID)/watcher/\(id)",
                           json: nil, token: nil, session: session)
    }

    // MARK: Deep links

    /// Maps the backend's click URLs onto this app's scheme:
    /// `apollo://reborn/inbox` -> `phoebus://reborn/inbox`, and
    /// `apollo://reddit.com/r/...` -> `phoebus://reddit.com/r/...`.
    public static func appURL(fromApolloURL url: URL) -> URL? {
        guard url.scheme?.lowercased() == "apollo",
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = scheme
        return comps.url
    }
}
