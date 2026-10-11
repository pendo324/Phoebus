import Foundation

/// Reddit's answer to `/api/submit` (`api_type=json`):
/// `{"json": {"errors": [], "data": {"url": …, "id": "abc", "name": "t3_abc"}}}`.
/// Image, video and gallery submissions answer differently (the post appears
/// once Reddit has processed the upload) and yield nothing here.
public enum SubmittedPostResponse {
    public static func fullname(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let json = root["json"] as? [String: Any],
              (json["errors"] as? [Any])?.isEmpty ?? true,
              let payload = json["data"] as? [String: Any] else { return nil }
        if let name = payload["name"] as? String, name.hasPrefix("t3_") { return name }
        if let id = payload["id"] as? String, !id.isEmpty { return id.hasPrefix("t3_") ? id : "t3_\(id)" }
        return nil
    }
}

/// A post the user just submitted, and when.
public struct SubmittedPost: Sendable {
    public let post: RedditPost
    public let at: Date

    public init(post: RedditPost, at: Date) {
        self.post = post
        self.at = at
    }

    /// How long a submitted post is kept for a listing that does not have it
    /// yet. Reddit's listings trail a submission by seconds to a minute.
    public static let lifetime: TimeInterval = 120
}

extension Array where Element == RedditPost {
    /// Puts back posts the user just submitted that a freshly fetched first
    /// page doesn't list yet, under any pinned posts. Ones the page has, and
    /// ones older than `SubmittedPost.lifetime`, are left out.
    public func restoringSubmitted(_ submitted: [SubmittedPost], now: Date = Date()) -> [RedditPost] {
        var result = self
        let present = Set(result.map(\.id))
        for entry in submitted.sorted(by: { $0.at < $1.at })
        where !present.contains(entry.post.id) && now.timeIntervalSince(entry.at) < SubmittedPost.lifetime {
            let pinned = result.prefix { $0.stickied }.count
            result.insert(entry.post, at: pinned)
        }
        return result
    }
}
