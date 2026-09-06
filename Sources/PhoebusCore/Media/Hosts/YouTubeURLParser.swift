import Foundation

/// URL parsing for YouTube video IDs — pure logic, kept in PhoebusCore
/// (like `RedGifsClient.extractID`/`StreamableClient.extractID`) so it
/// can be exercised by the Linux-hosted smoke test, separate from the
/// SwiftUI/WebKit playback view in PhoebusUI (`YouTubePlayerView`).
public enum YouTubeURLParser {
    /// Extracts an 11-character YouTube video ID from any common
    /// YouTube URL shape (youtube.com/watch?v=, youtu.be/,
    /// youtube.com/shorts/).
    public static func extractVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), host.contains("youtube.com") || host.contains("youtu.be") else {
            return nil
        }
        if host.contains("youtu.be") {
            let id = url.lastPathComponent
            return id.isEmpty ? nil : id
        }
        if url.path.hasPrefix("/shorts/") {
            let id = url.lastPathComponent
            return id.isEmpty ? nil : id
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return videoID
        }
        return nil
    }

    /// Builds the URL to open a video in the native YouTube app when
    /// installed (Apollo's "Open Videos in YouTube App" setting). Uses the
    /// regular `https://` watch URL rather than a `youtube://` scheme: iOS
    /// routes it to the installed app via Universal Links and falls back to
    /// Safari, avoiding an `LSApplicationQueriesSchemes` entry.
    public static func nativeAppURL(forVideoID videoID: String) -> URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    /// Poster image for a video, from YouTube's public thumbnail host.
    ///
    /// A YouTube link shows the video's thumbnail rather than a text
    /// placeholder that never resolves; Apollo's loading view is a poster
    /// frame with a play control.
    ///
    /// `hqdefault` rather than `maxresdefault`: every video has the former,
    /// while the latter 404s for anything never published at 1080p.
    public static func thumbnailURL(forVideoID videoID: String) -> URL? {
        guard !videoID.isEmpty else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }
}
