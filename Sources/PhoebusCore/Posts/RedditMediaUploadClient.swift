import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reborn's "Native Reddit media upload support": uploads an image/video
/// through Reddit's own media pipeline (`/api/media/asset.json` for a
/// presigned S3 lease, then a multipart POST to that bucket) rather than a
/// third-party image host. Needs no credential beyond the OAuth token.
public enum RedditMediaKind: String, Sendable {
    case image
    case video
    case gif
}

public struct RedditMediaUploadField: Sendable, Equatable {
    public let name: String
    public let value: String
}

public struct RedditMediaUploadLease: Sendable, Equatable {
    /// The S3 upload endpoint to POST the file to.
    public let uploadURL: String
    /// Form fields (`key`, `policy`, `x-amz-*`, etc.) that must be
    /// included, in order, ahead of the file field in the multipart
    /// body — S3 presigned-POST uploads require exact field order.
    public let fields: [RedditMediaUploadField]
    /// The final asset URL Reddit will serve the media from once
    /// uploaded (used as the post's `url` for a link/image post).
    public let assetURL: String
    /// Reddit's internal websocket URL for tracking video/gif
    /// processing completion (images are available immediately after
    /// upload; video/gif needs this to know when transcoding finishes).
    public let websocketURL: String?
    /// `asset_id` from the lease response. This, not the S3 key or asset URL,
    /// is the `media_id` a gallery submission's `items` array requires. A
    /// non-gallery post just embeds `assetURL` as its `url`.
    public let assetID: String?

    public init(uploadURL: String, fields: [RedditMediaUploadField], assetURL: String, websocketURL: String?, assetID: String? = nil) {
        self.uploadURL = uploadURL
        self.fields = fields
        self.assetURL = assetURL
        self.websocketURL = websocketURL
        self.assetID = assetID
    }
}

public enum RedditMediaUploadClient {
    public enum ClientError: Error, Sendable {
        case invalidLeaseResponse
        case uploadFailed(statusCode: Int)
        /// S3 returned 2xx but its XML body describes an actual error (presigned
        /// POST uploads can return 200, 201 or 204 with an `<Error>` body, so the
        /// HTTP status alone is not enough).
        case s3Error(code: String, message: String)
    }

    /// Requests a presigned S3 upload lease from Reddit for a file of the
    /// given kind/mime-type/filename (`/api/media/asset.json`).
    public static func requestUploadLease(kind: RedditMediaKind, filename: String, mimeType: String, client: RedditAPIClient) async throws -> RedditMediaUploadLease {
        let data = try await client.post(path: "/api/media/asset.json", parameters: [
            "filepath": filename,
            "mimetype": mimeType,
        ])
        return try parseLeaseResponse(data)
    }

    /// Parses Reddit's `/api/media/asset.json` response shape:
    /// `{"args": {"action": "//bucket.s3...", "fields": [{"name":...,"value":...}, ...]}, "asset": {"asset_id":..., "websocket_url":...}}`.
    public static func parseLeaseResponse(_ data: Data) throws -> RedditMediaUploadLease {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let args = json["args"] as? [String: Any],
              let action = args["action"] as? String,
              let fieldsRaw = args["fields"] as? [[String: Any]] else {
            throw ClientError.invalidLeaseResponse
        }
        let fields: [RedditMediaUploadField] = fieldsRaw.compactMap { field in
            guard let name = field["name"] as? String, let value = field["value"] as? String else { return nil }
            return RedditMediaUploadField(name: name, value: value)
        }
        // Reddit's action URL is protocol-relative ("//reddit-uploaded-media.s3-accelerate.amazonaws.com/...").
        let uploadURL = action.hasPrefix("//") ? "https:\(action)" : action
        // The final asset URL is the upload URL plus the "key" field's
        // value (the S3 object key Reddit assigned).
        let key = fields.first(where: { $0.name == "key" })?.value ?? ""
        let assetURL = "\(uploadURL)/\(key)"
        let asset = json["asset"] as? [String: Any]
        let websocketURL = asset?["websocket_url"] as? String
        let assetID = asset?["asset_id"] as? String
        return RedditMediaUploadLease(uploadURL: uploadURL, fields: fields, assetURL: assetURL, websocketURL: websocketURL, assetID: assetID)
    }

    /// Performs the multipart/form-data POST to S3 using a previously obtained
    /// lease. The request is unauthenticated (the lease's policy/signature
    /// fields authorize it), so it uses a bare `URLSession`, not
    /// `RedditAPIClient`.
    public static func upload(fileData: Data, filename: String, mimeType: String, lease: RedditMediaUploadLease, session: URLSession = .shared) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for field in lease.fields {
            body.append(multipartField(name: field.name, value: field.value, boundary: boundary))
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // The lease URL is Reddit's; a malformed one fails the upload, not the app.
        guard let uploadURL = URL(string: lease.uploadURL) else { throw ClientError.invalidLeaseResponse }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.uploadFailed(statusCode: statusCode)
        }
        if let s3Error = parseS3XMLError(data) {
            throw s3Error
        }
    }

    /// Parses S3's XML error body (`<Error><Code>...</Code><Message>...</Message></Error>`)
    /// returned even on some 2xx responses. A small hand-rolled scan rather
    /// than a full XML parser, sufficient for the code and message.
    public static func parseS3XMLError(_ data: Data) -> ClientError? {
        guard !data.isEmpty, let xml = String(data: data, encoding: .utf8), xml.contains("<Error>") else {
            return nil
        }
        let code = extractXMLTagValue(xml, tag: "Code") ?? "UnknownError"
        let message = extractXMLTagValue(xml, tag: "Message") ?? "Upload failed."
        return .s3Error(code: code, message: message)
    }

    private static func extractXMLTagValue(_ xml: String, tag: String) -> String? {
        guard let openRange = xml.range(of: "<\(tag)>"), let closeRange = xml.range(of: "</\(tag)>"), openRange.upperBound <= closeRange.lowerBound else {
            return nil
        }
        return String(xml[openRange.upperBound..<closeRange.lowerBound])
    }

    private static func multipartField(name: String, value: String, boundary: String) -> Data {
        var field = "--\(boundary)\r\n"
        field += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        field += "\(value)\r\n"
        return field.data(using: .utf8)!
    }
}
