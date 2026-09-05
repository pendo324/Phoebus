import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Apollo-Reborn's Imgur integration: uploads images/albums to Imgur
/// and fetches album/image metadata for rendering imgur.com links,
/// using the user's own registered Imgur API client ID (see
/// `CustomAPISettings.imgurClientID`).
public enum ImgurClient {
    /// Set from `CustomAPISettingsStore` when the user configures
    /// their own Imgur client ID (Settings > Custom API). `nil` means
    /// Imgur features are unavailable — see `ClientError.notConfigured`.
    public nonisolated(unsafe) static var clientID: String?

    public enum ClientError: Error, Sendable {
        /// No client ID configured (Settings > Custom API > Imgur
        /// Client ID). Distinct from a network/auth failure so call
        /// sites can show "configure your Imgur API key" rather than
        /// a generic error.
        case notConfigured
        case invalidResponse
    }

    private static let baseURL = "https://api.imgur.com/3"

    /// Anonymous (clientID-only, no user OAuth) image upload, matching
    /// Imgur's own "anonymous upload" tier.
    public static func uploadImage(data: Data, clientID: String? = ImgurClient.clientID, session: URLSession = .shared) async throws -> ImgurImage {
        guard let clientID, !clientID.isEmpty else { throw ClientError.notConfigured }
        var request = URLRequest(url: URL(string: "\(baseURL)/image")!)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, _) = try await session.data(for: request)
        let image = try parseImageResponse(responseData)
        // Every anonymous upload's delete hash is recorded locally so
        // the user can revisit and delete it, since an anonymous
        // Imgur upload has no other way to be attributed to the uploader.
        ImgurUploadHistoryStore.record(image)
        return image
    }

    /// Deletes a previously anonymously-uploaded image via its delete
    /// hash, using Imgur's REST delete endpoint.
    public static func deleteImage(deleteHash: String, clientID: String? = ImgurClient.clientID, session: URLSession = .shared) async throws {
        guard let clientID, !clientID.isEmpty else { throw ClientError.notConfigured }
        var request = URLRequest(url: URL(string: "\(baseURL)/image/\(deleteHash)")!)
        request.httpMethod = "DELETE"
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: request)
        ImgurUploadHistoryStore.remove(deleteHash: deleteHash)
    }

    /// Imgur's own public web client ID (imgur.com's), which album
    /// fallbacks use instead of the user's key, as Reborn does.
    public static let publicWebClientID = "546c25a59c58ad7"

    /// Fetches metadata for an existing Imgur album (for rendering an
    /// `imgur.com/a/<id>` or `imgur.com/gallery/<id>` link inline as a
    /// gallery). When the direct request fails, Reborn's fallback chain
    /// applies: a keyless retry with the public web client ID (if the first
    /// try used a personal key), then, with "Album Fallback Proxies" on,
    /// r.jina.ai, allorigins and codetabs, each given only the public-ID album
    /// URL.
    public static func fetchAlbum(id: String, clientID: String? = ImgurClient.clientID, session: URLSession = .shared) async throws -> ImgurAlbum {
        let personalKey = clientID.flatMap { $0.isEmpty ? nil : $0 }
        var request = URLRequest(url: URL(string: "\(baseURL)/album/\(id)?client_id=\(personalKey ?? publicWebClientID)")!)
        request.setValue("Client-ID \(personalKey ?? publicWebClientID)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ClientError.invalidResponse
            }
            return try parseAlbumResponse(data)
        } catch {
            for attempt in albumFallbacks(id: id, hadPersonalKey: personalKey != nil,
                                          proxies: GeneralSettingsStore.load().imgurAlbumFallbackProxies) {
                guard let url = URL(string: attempt.url) else { continue }
                var proxyRequest = URLRequest(url: url)
                proxyRequest.timeoutInterval = 12
                guard let (data, _) = try? await session.data(for: proxyRequest),
                      let body = attempt.extract(data),
                      let album = try? parseAlbumResponse(body) else { continue }
                return album
            }
            throw error
        }
    }

    public struct AlbumFallback {
        public let name: String
        public let url: String
        public let extract: (Data) -> Data?
    }

    /// The ordered fallback attempts for an album, as Reborn's chain.
    public static func albumFallbacks(id: String, hadPersonalKey: Bool, proxies: Bool) -> [AlbumFallback] {
        let publicURL = "\(baseURL)/album/\(id)?client_id=\(publicWebClientID)"
        let encoded = publicURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? publicURL
        var out: [AlbumFallback] = []
        if hadPersonalKey {
            out.append(AlbumFallback(name: "direct keyless retry", url: publicURL) { $0 })
        }
        if proxies {
            // jina takes the target appended verbatim and wraps the body.
            out.append(AlbumFallback(name: "r.jina.ai", url: "https://r.jina.ai/\(publicURL)", extract: extractJinaBody))
            out.append(AlbumFallback(name: "allorigins", url: "https://api.allorigins.win/raw?url=\(encoded)") { $0 })
            out.append(AlbumFallback(name: "codetabs", url: "https://api.codetabs.com/v1/proxy?quest=\(encoded)") { $0 })
        }
        return out
    }

    /// r.jina.ai wraps the proxied response as `"...Markdown
    /// Content:\n<raw body>"`; this extracts the JSON body.
    public static func extractJinaBody(_ data: Data) -> Data? {
        guard let body = String(data: data, encoding: .utf8),
              let markerRange = body.range(of: "Markdown Content:\n") else { return nil }
        let inner = body[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.hasPrefix("{") ? inner.data(using: .utf8) : nil
    }

    /// Parses `{"data": {"id":..., "link":..., "deletehash":...}, "success": true}`.
    public static func parseImageResponse(_ data: Data) throws -> ImgurImage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imageData = json["data"] as? [String: Any],
              let id = imageData["id"] as? String,
              let link = imageData["link"] as? String else {
            throw ClientError.invalidResponse
        }
        return ImgurImage(id: id, link: link, deleteHash: imageData["deletehash"] as? String)
    }

    /// Parses `{"data": {"id":..., "title":..., "images": [{"id":..., "link":...}, ...]}}`.
    public static func parseAlbumResponse(_ data: Data) throws -> ImgurAlbum {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let albumData = json["data"] as? [String: Any],
              let id = albumData["id"] as? String else {
            throw ClientError.invalidResponse
        }
        let imagesRaw = albumData["images"] as? [[String: Any]] ?? []
        let images: [ImgurImage] = imagesRaw.compactMap { imageDict in
            guard let imgID = imageDict["id"] as? String, let link = imageDict["link"] as? String else { return nil }
            return ImgurImage(id: imgID, link: link, deleteHash: nil)
        }
        return ImgurAlbum(id: id, title: albumData["title"] as? String, images: images)
    }

    /// Apollo's album/gallery regex:
    /// `^(?:(?:https?:)?//)?(?:[im]\.)?imgur\.(?:(?:com)|(?:io))/(?!gallery)(?:t/[\w-]+/)?([a-zA-Z0-9]{3,})`.
    /// Also matches Imgur's `imgur.io` TLD and a `t/<tag>/` prefix
    /// segment. Matches direct (non-album) links too, which is why
    /// `extractAlbumID` still gates on an explicit `a/`/`gallery/` segment.
    private static let realApolloImgurPattern =
        #"^(?:(?:https?:)?//)?(?:[im]\.)?imgur\.(?:(?:com)|(?:io))/(?!gallery)(?:t/[\w-]+/)?([a-zA-Z0-9]{3,})"#

    /// Extracts an Imgur album/gallery ID from an `imgur.com/a/<id>` or
    /// `imgur.com/gallery/<id>` URL, or `nil` for a direct
    /// `i.imgur.com/<id>.jpg`-style single-image link (which needs no
    /// API call at all — it's already a directly-loadable image URL).
    public static func extractAlbumID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              (host.contains("imgur.com") || host.contains("imgur.io")),
              !host.hasPrefix("i.") else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2, ["a", "gallery"].contains(components[0].lowercased()) else { return nil }
        return components[1]
    }

    /// Recognizes any Imgur host (`imgur.com`, `imgur.io`, `i.imgur.com`,
    /// `m.imgur.com`) using Apollo's host-matching alternation,
    /// for callers that only need to know "is this an Imgur URL" rather
    /// than extract a specific album ID.
    private static let imgurHostRegex = try! NSRegularExpression(pattern: realApolloImgurPattern)

    public static func matchesImgurHost(_ url: URL) -> Bool {
        let regex = imgurHostRegex
        let s = url.absoluteString
        return regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// "Proxy Imgur via DuckDuckGo" setting: rewrites a
    /// direct Imgur content URL to route through DuckDuckGo's image
    /// cache. Returns the original URL when the setting is off, the URL
    /// isn't an Imgur content host, or it's the `api.imgur.com` API host
    /// (DDG only proxies images, not JSON). `.mp4`/`.gifv` extensions
    /// are rewritten to `.gif` first since DDG can't serve those.
    public static func proxiedImageURL(for url: URL) -> URL {
        guard GeneralSettingsStore.load().proxyImgurViaDuckDuckGo,
              let host = url.host?.lowercased(),
              host == "imgur.com" || host.hasSuffix(".imgur.com"),
              host != "api.imgur.com" else {
            return url
        }
        var urlString = url.absoluteString
        if urlString.hasSuffix(".mp4") || urlString.hasSuffix(".gifv") {
            urlString = (urlString as NSString).deletingPathExtension + ".gif"
        }
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let proxyURL = URL(string: "https://external-content.duckduckgo.com/iu/?u=\(encoded)") else {
            return url
        }
        return proxyURL
    }
}

public struct ImgurImage: Sendable, Equatable {
    public let id: String
    public let link: String
    public let deleteHash: String?

    public init(id: String, link: String, deleteHash: String?) {
        self.id = id
        self.link = link
        self.deleteHash = deleteHash
    }
}

public struct ImgurAlbum: Sendable, Equatable {
    public let id: String
    public let title: String?
    public let images: [ImgurImage]
}

/// A locally-recorded anonymous Imgur upload, backing the "Manage Uploads"
/// screen.
public struct ImgurUploadRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { image.id }
    public let image: ImgurImage
    public let uploadedAt: Date

    public init(image: ImgurImage, uploadedAt: Date = Date()) {
        self.image = image
        self.uploadedAt = uploadedAt
    }
}

extension ImgurImage: Codable {}

/// Local persistence for anonymous-upload history ("Manage Uploads"). The
/// delete hash returned at upload time is the only way to manage an
/// anonymous upload afterward, so this record is the only way to delete it
/// later.
public enum ImgurUploadHistoryStore {
    private static let key = "com.pendo324.Phoebus.imgurUploadHistory"

    public static func load() -> [ImgurUploadRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([ImgurUploadRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.uploadedAt > $1.uploadedAt }
    }

    public static func record(_ image: ImgurImage) {
        var records = load()
        records.insert(ImgurUploadRecord(image: image), at: 0)
        save(records)
    }

    public static func remove(deleteHash: String) {
        var records = load()
        records.removeAll { $0.image.deleteHash == deleteHash }
        save(records)
    }

    private static func save(_ records: [ImgurUploadRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
