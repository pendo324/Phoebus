import Foundation

/// A Gallery View video tile whose stream Reddit did not attach: a
/// sports-clip or Streamable link (Reborn `Apollo-Reborn#1389`). Reddit gives
/// such posts no usable preview stream, so the tile asks the host for the clip
/// once it is on screen. Redgifs and Gfycat are not listed: a lookup mints a
/// token each time, so they stay viewer-only.
public enum GalleryHostedVideo: Equatable, Sendable {
    case sportsClip(pageURL: URL)
    case streamable(id: String)

    /// Same key for the grid tile and the viewer, so they share one lookup.
    public var key: String {
        switch self {
        case .sportsClip(let pageURL): return "clip:\(pageURL.absoluteString)"
        case .streamable(let id): return "streamable:\(id)"
        }
    }

    /// nil for a post with its own Reddit video or a Redgifs/Gfycat/other link.
    public static func of(_ post: RedditPost) -> GalleryHostedVideo? {
        guard post.media?.redditVideo == nil, post.isGallery != true,
              let urlString = post.url, let url = URL(string: urlString) else { return nil }
        if url.host?.contains("redgifs.com") == true || url.host?.contains("gfycat.com") == true { return nil }
        if url.host?.contains("streamable.com") == true, let id = StreamableClient.extractID(from: url) {
            return .streamable(id: id)
        }
        if SportsClipHost.matches(url) { return .sportsClip(pageURL: url) }
        return nil
    }
}
