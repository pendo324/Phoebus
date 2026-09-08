import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Tweet previews (Apollo's TweetBuddy and Reborn's equivalent, PR #215/#873).
///
/// Reborn swaps Apollo's dead tweet-card backend for X's own guest-token
/// GraphQL: `POST api.x.com/1.1/guest/activate.json` with the public web
/// bearer, then `GET api.x.com/graphql/<id>/TweetResultByRestId` with
/// `x-guest-token`. The token lives 9000s and is dropped on 401/403.
/// Reborn also removes Apollo's "score > 40" gate so every tweet link
/// previews.
///
/// The public `cdn.syndication.twimg.com/tweet-result` endpoint (no token)
/// is the fallback when the guest flow fails. X withholds some tweets from
/// both on purpose; Rich Link Previews' Twitter fallback provider
/// (FxTwitter or VxTwitter) is asked last.
public struct TweetInfo: Sendable, Equatable {
    public let name: String
    public let username: String
    public let text: String
    public let profilePictureURL: URL?
    public let mediaThumbnailURL: URL?
    public let isVerified: Bool
    /// The first photo's (or video poster's) pixel size, when reported.
    public var mediaWidth: Double? = nil
    public var mediaHeight: Double? = nil
}

/// A third-party service asked for a tweet X won't give out.
public enum TwitterFallbackProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case fxTwitter
    case vxTwitter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "None"
        case .fxTwitter: return "FxTwitter"
        case .vxTwitter: return "VxTwitter"
        }
    }

    /// The provider's JSON endpoint for a status.
    public func apiURL(statusID: String) -> URL? {
        switch self {
        case .none: return nil
        case .fxTwitter: return URL(string: "https://api.fxtwitter.com/status/\(statusID)")
        case .vxTwitter: return URL(string: "https://api.vxtwitter.com/Twitter/status/\(statusID)")
        }
    }

    public func parse(_ data: Data) -> TweetInfo? {
        switch self {
        case .none: return nil
        case .fxTwitter: return TweetClient.parseFxTwitter(data)
        case .vxTwitter: return TweetClient.parseVxTwitter(data)
        }
    }
}

public enum TweetURL {
    static let hosts = ["twitter.com", "x.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com", "fixvx.com"]

    /// x.com, twitter.com (any subdomain, e.g. mobile.) and their fx/vx
    /// mirrors.
    public static func isTwitterHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The status ID of an x.com / twitter.com (incl. mobile., fx/vx
    /// mirrors) `/<user>/status/<id>` URL.
    public static func statusID(from url: URL) -> String? {
        guard isTwitterHost(url) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let i = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }), parts.count > i + 1 else { return nil }
        let id = parts[i + 1].prefix(while: \.isNumber)
        return id.isEmpty ? nil : String(id)
    }
}

public actor TweetClient {
    public static let shared = TweetClient()

    static let guestActivateURL = URL(string: "https://api.x.com/1.1/guest/activate.json")!
    static let graphQLURL = "https://api.x.com/graphql/zy39CwTyYhU-_0LP7dljjg/TweetResultByRestId"
    /// X's public web-client bearer, the value Reborn ships.
    static let bearer = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    static let guestTokenMaxAge: TimeInterval = 9000

    private var guestToken: String?
    private var tokenDate: Date?
    private var cache: [String: TweetInfo] = [:]
    private var misses: Set<String> = []
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func tweet(id: String, fallback: TwitterFallbackProvider = .none) async -> TweetInfo? {
        if let hit = cache[id] { return hit }
        let missKey = "\(id)|\(fallback.rawValue)"
        if misses.contains(missKey) { return nil }
        var info = try? await viaGraphQL(id: id)
        if info == nil { info = try? await viaSyndication(id: id) }
        if info == nil, let url = fallback.apiURL(statusID: id),
           let (data, response) = try? await session.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            info = fallback.parse(data)
        }
        if let info { cache[id] = info } else { misses.insert(missKey) }
        return info
    }

    private func token() async throws -> String {
        if let guestToken, let tokenDate, Date().timeIntervalSince(tokenDate) < Self.guestTokenMaxAge {
            return guestToken
        }
        var request = URLRequest(url: Self.guestActivateURL)
        request.httpMethod = "POST"
        request.setValue(Self.bearer, forHTTPHeaderField: "authorization")
        request.httpShouldHandleCookies = false
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["guest_token"] else { throw URLError(.badServerResponse) }
        let value = "\(raw)"
        guestToken = value
        tokenDate = Date()
        return value
    }

    private func viaGraphQL(id: String) async throws -> TweetInfo? {
        let token = try await token()
        var components = URLComponents(string: Self.graphQLURL)!
        components.queryItems = [
            URLQueryItem(name: "variables", value: #"{"tweetId":"\#(id)","withCommunity":false,"includePromotedContent":false,"withVoice":false}"#),
            URLQueryItem(name: "features", value: #"{"creator_subscriptions_tweet_preview_api_enabled":true,"view_counts_everywhere_api_enabled":true}"#),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(Self.bearer, forHTTPHeaderField: "authorization")
        request.setValue(token, forHTTPHeaderField: "x-guest-token")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("https://x.com", forHTTPHeaderField: "Origin")
        request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
            guestToken = nil; tokenDate = nil
            return nil
        }
        return Self.parseGraphQL(data)
    }

    /// Reads legacy.full_text, core.user_results.result.{core.name,
    /// core.screen_name, avatar.image_url, is_blue_verified}.
    public static func parseGraphQL(_ data: Data) -> TweetInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var result = ((json["data"] as? [String: Any])?["tweetResult"] as? [String: Any])?["result"] as? [String: Any]
        else { return nil }
        // Tweets with visibility wrappers nest the real result one deeper.
        if let inner = result["tweet"] as? [String: Any] { result = inner }
        guard let legacy = result["legacy"] as? [String: Any] else { return nil }
        let user = (((result["core"] as? [String: Any])?["user_results"] as? [String: Any])?["result"] as? [String: Any]) ?? [:]
        let userCore = user["core"] as? [String: Any] ?? [:]
        let userLegacy = user["legacy"] as? [String: Any] ?? [:]
        let avatar = ((user["avatar"] as? [String: Any])?["image_url"] as? String)
            ?? userLegacy["profile_image_url_https"] as? String
        let firstMedia = ((legacy["extended_entities"] as? [String: Any])?["media"] as? [[String: Any]])?.first
        let media = firstMedia?["media_url_https"] as? String
        let size = firstMedia?["original_info"] as? [String: Any]
        return TweetInfo(
            name: userCore["name"] as? String ?? userLegacy["name"] as? String ?? "",
            username: userCore["screen_name"] as? String ?? userLegacy["screen_name"] as? String ?? "",
            text: cleanText(legacy["full_text"] as? String ?? ""),
            profilePictureURL: avatar.flatMap(URL.init(string:)),
            mediaThumbnailURL: media.flatMap(URL.init(string:)),
            isVerified: user["is_blue_verified"] as? Bool ?? false,
            mediaWidth: jsonNumber(size?["width"]), mediaHeight: jsonNumber(size?["height"]))
    }

    private func viaSyndication(id: String) async throws -> TweetInfo? {
        var components = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        components.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "token", value: "a")]
        let (data, _) = try await session.data(from: components.url!)
        return Self.parseSyndication(data)
    }

    public static func parseSyndication(_ data: Data) -> TweetInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String,
              let user = json["user"] as? [String: Any] else { return nil }
        let firstPhoto = (json["photos"] as? [[String: Any]])?.first
        let firstDetail = (json["mediaDetails"] as? [[String: Any]])?.first
        let photo = firstPhoto?["url"] as? String ?? firstDetail?["media_url_https"] as? String
        let detailSize = firstDetail?["original_info"] as? [String: Any]
        let width = jsonNumber(firstPhoto?["width"]) ?? jsonNumber(detailSize?["width"])
        let height = jsonNumber(firstPhoto?["height"]) ?? jsonNumber(detailSize?["height"])
        return TweetInfo(
            name: user["name"] as? String ?? "",
            username: user["screen_name"] as? String ?? "",
            text: cleanText(text),
            profilePictureURL: (user["profile_image_url_https"] as? String).flatMap(URL.init(string:)),
            mediaThumbnailURL: photo.flatMap(URL.init(string:)),
            isVerified: user["is_blue_verified"] as? Bool ?? user["verified"] as? Bool ?? false,
            mediaWidth: width, mediaHeight: height)
    }

    /// `api.fxtwitter.com/status/<id>`: tweet.{text, author{name,
    /// screen_name, avatar_url}, media.all[0]{url|thumbnail_url, width,
    /// height}}.
    public static func parseFxTwitter(_ data: Data) -> TweetInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tweet = json["tweet"] as? [String: Any],
              let author = tweet["author"] as? [String: Any] else { return nil }
        let media = ((tweet["media"] as? [String: Any])?["all"] as? [[String: Any]])?.first
        let image = media.flatMap { ($0["type"] as? String) == "photo" ? $0["url"] as? String : $0["thumbnail_url"] as? String }
        return TweetInfo(
            name: author["name"] as? String ?? "",
            username: author["screen_name"] as? String ?? "",
            text: cleanText(tweet["text"] as? String ?? ""),
            profilePictureURL: (author["avatar_url"] as? String).flatMap(URL.init(string:)),
            mediaThumbnailURL: image.flatMap(URL.init(string:)),
            isVerified: ((author["verification"] as? [String: Any])?["verified"] as? Bool) ?? false,
            mediaWidth: jsonNumber(media?["width"]), mediaHeight: jsonNumber(media?["height"]))
    }

    /// `api.vxtwitter.com/Twitter/status/<id>`: text, user_name,
    /// user_screen_name, user_profile_image_url, media_extended[0]
    /// {thumbnail_url, size{width,height}}.
    public static func parseVxTwitter(_ data: Data) -> TweetInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let username = json["user_screen_name"] as? String else { return nil }
        let media = (json["media_extended"] as? [[String: Any]])?.first
        let size = media?["size"] as? [String: Any]
        // The API hands out the 48pt "_normal" avatar; "_200x200" is the same file larger.
        let avatar = (json["user_profile_image_url"] as? String)?.replacingOccurrences(of: "_normal.", with: "_200x200.")
        return TweetInfo(
            name: json["user_name"] as? String ?? "",
            username: username,
            text: cleanText(json["text"] as? String ?? ""),
            profilePictureURL: avatar.flatMap(URL.init(string:)),
            mediaThumbnailURL: (media?["thumbnail_url"] as? String).flatMap(URL.init(string:)),
            isVerified: false,
            mediaWidth: jsonNumber(size?["width"]), mediaHeight: jsonNumber(size?["height"]))
    }

    static func jsonNumber(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    /// Drops the trailing t.co media link and decodes the three HTML
    /// entities X leaves in `full_text`.
    public static func cleanText(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        if let r = t.range(of: #"\s*https://t\.co/\w+\s*$"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        return t
    }
}
