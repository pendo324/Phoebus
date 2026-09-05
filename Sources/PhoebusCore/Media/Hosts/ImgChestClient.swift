import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Img Chest, an alternative Imgur-style upload host added by Reborn:
/// "Img Chest API Key" sits between Imgur API Key and Giphy API Key in the
/// Custom API field list. `CustomAPISettings.imgChestAPIKey` persists the
/// user's own key (registered at imgchest.com; Apollo's own credentials are
/// never reused, as with Imgur/Giphy).
public enum ImgChestClient {
    /// Set from `CustomAPISettingsStore` when the user configures
    /// their own Img Chest API key (Settings > Custom API). `nil`
    /// means Img Chest features are unavailable.
    public nonisolated(unsafe) static var apiKey: String?

    public enum ClientError: Error, Sendable {
        case notConfigured
        case invalidResponse
    }

    private static let baseURL = "https://api.imgchest.com/v1"

    /// `GeneralSettings.mediaUploadHost` / `commentLinkHost` ("Media Upload
    /// Host" / "Comment Link Host") pickers route an Image Chest selection
    /// here. Request shape: `POST /v1/post`, multipart `images[]` parts plus
    /// `privacy=hidden` (unlisted), `Authorization: Bearer <token>`, response
    /// `data.images[0].link` for a single-image post.
    public static func uploadImage(data: Data, filename: String = "upload.jpg", mimeType: String = "image/jpeg", apiKey: String? = ImgChestClient.apiKey, session: URLSession = .shared) async throws -> ImgChestImage {
        guard let apiKey, !apiKey.isEmpty else { throw ClientError.notConfigured }
        var request = URLRequest(url: URL(string: "\(baseURL)/post")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let boundary = "apollo-imgchest-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        // "hidden" = unlisted: reachable by link, not listed publicly.
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"privacy\"\r\n\r\nhidden\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"images[]\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ClientError.invalidResponse
        }
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let post = json["data"] as? [String: Any],
              let postID = post["id"] as? String,
              let images = post["images"] as? [[String: Any]],
              let firstLink = images.first?["link"] as? String else {
            throw ClientError.invalidResponse
        }
        return ImgChestImage(postID: postID, link: firstLink)
    }
}

/// A single Image Chest upload result — `link` is the direct image
/// URL (`images[0].link`); `postID` (`imgchest.com/p/<id>`) is the
/// unlisted post it belongs to, for building a shareable page URL if
/// ever needed.
public struct ImgChestImage: Sendable, Equatable {
    public let postID: String
    public let link: String

    public init(postID: String, link: String) {
        self.postID = postID
        self.link = link
    }
}

