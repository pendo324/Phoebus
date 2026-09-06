import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Photos)
import Photos
#endif

/// Saves a post's video to the user's photo library (Apollo's "Download
/// Video…" post action).
///
/// Reddit serves v.redd.it video and audio as SEPARATE DASH streams, so a
/// naive single-file download yields silent video. The two are muxed with
/// `AVMutableComposition`, as Reborn's gallery export does.
public enum VideoDownloader {
    public enum DownloadError: LocalizedError {
        case unsupportedURL
        case photosAccessDenied
        case exportFailed

        public var errorDescription: String? {
            switch self {
            case .unsupportedURL: return "This post has no downloadable video."
            case .photosAccessDenied: return "Phoebus needs permission to save to your photo library."
            case .exportFailed: return "Couldn't save the video."
            }
        }
    }

    /// Reddit's DASH video URLs look like
    /// `https://v.redd.it/<id>/DASH_720.mp4`; the matching audio track
    /// is `DASH_audio.mp4` beside it.
    public static func audioURL(forRedditVideo videoURL: URL) -> URL? {
        let string = videoURL.absoluteString
        guard string.contains("v.redd.it"), let range = string.range(of: "DASH_", options: .backwards) else {
            return nil
        }
        let base = String(string[string.startIndex..<range.lowerBound])
        return URL(string: base + "DASH_audio.mp4")
    }

    /// The directory a v.redd.it stream lives in (`https://v.redd.it/<id>/`).
    static func streamBase(forRedditVideo videoURL: URL) -> String? {
        let string = videoURL.absoluteString
        guard string.contains("v.redd.it"),
              let range = string.range(of: "/DASH_", options: .backwards)
                ?? string.range(of: "/CMAF_", options: .backwards)
                ?? string.range(of: "/HLSPlaylist", options: .backwards) else { return nil }
        return String(string[string.startIndex...range.lowerBound])
    }

    /// Audio file names in a DASH manifest, best first.
    ///
    /// The name has changed over time (`DASH_audio.mp4`, `DASH_AUDIO_128.mp4`,
    /// `CMAF_AUDIO_128.mp4`), so one is never guessed; the manifest names the
    /// real file.
    public static func audioFileNames(fromManifest xml: String) -> [String] {
        fileNames(fromManifest: xml, kind: "audio").sorted { $0.bandwidth > $1.bandwidth }.map(\.name)
    }

    /// The video file in a DASH manifest to read a poster frame from: the
    /// sharpest one up to 720p, as only its first frame is fetched.
    public static func posterFileName(fromManifest xml: String) -> String? {
        let videos = fileNames(fromManifest: xml, kind: "video").sorted { $0.bandwidth < $1.bandwidth }
        return (videos.last { (1...720).contains($0.height) } ?? videos.first)?.name
    }

    private static func fileNames(fromManifest xml: String, kind: String) -> [(bandwidth: Int, height: Int, name: String)] {
        var found: [(bandwidth: Int, height: Int, name: String)] = []
        for set in xml.components(separatedBy: "<AdaptationSet").dropFirst() {
            let header = set.prefix { $0 != ">" }
            guard header.contains(kind) else { continue }
            for representation in set.components(separatedBy: "<Representation").dropFirst() {
                guard let open = representation.range(of: "<BaseURL>"),
                      let close = representation.range(of: "</BaseURL>", range: open.upperBound..<representation.endIndex)
                else { continue }
                let name = representation[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let bandwidth = attribute("bandwidth", in: representation)
                let height = attribute("height", in: representation)
                if !name.isEmpty { found.append((bandwidth, height, name)) }
            }
        }
        return found
    }

    /// A representation's numeric attribute, or 0.
    private static func attribute(_ name: String, in representation: String) -> Int {
        representation.range(of: name + #"="(\d+)""#, options: .regularExpression)
            .map { Int(representation[$0].filter(\.isNumber)) ?? 0 } ?? 0
    }

    /// Names tried when the manifest can't be read, newest scheme first.
    public static let fallbackAudioFileNames = [
        "CMAF_AUDIO_128.mp4", "DASH_AUDIO_128.mp4", "CMAF_AUDIO_64.mp4", "DASH_AUDIO_64.mp4", "DASH_audio.mp4",
    ]

    /// Names tried for a poster when the manifest can't be read, sharpest
    /// first.
    public static let fallbackPosterFileNames = [
        "CMAF_720.mp4", "DASH_720.mp4", "CMAF_480.mp4", "DASH_480.mp4", "CMAF_360.mp4", "DASH_360.mp4",
    ]

    /// A progressive file of the same video, for its poster frame: a frame
    /// can't be read from an HLS playlist, which is what an inline
    /// v.redd.it video plays.
    public static func resolvePosterURL(forRedditVideo videoURL: URL, session: URLSession = .shared) async -> URL? {
        guard let base = streamBase(forRedditVideo: videoURL) else { return nil }
        if let manifestURL = URL(string: base + "DASHPlaylist.mpd"),
           let (data, response) = try? await session.data(from: manifestURL),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let name = posterFileName(fromManifest: String(decoding: data, as: UTF8.self)) {
            return URL(string: base + name)
        }
        for name in fallbackPosterFileNames {
            guard let url = URL(string: base + name) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            if let (_, response) = try? await session.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return url
            }
        }
        return nil
    }

    /// The video's real audio track, or nil if it has none.
    public static func resolveAudioURL(forRedditVideo videoURL: URL, session: URLSession = .shared) async -> URL? {
        guard let base = streamBase(forRedditVideo: videoURL) else { return nil }
        if let manifestURL = URL(string: base + "DASHPlaylist.mpd"),
           let (data, response) = try? await session.data(from: manifestURL),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            // A readable manifest is authoritative: no audio set means
            // a silent clip, not a file to guess at.
            return audioFileNames(fromManifest: String(decoding: data, as: UTF8.self)).first
                .flatMap { URL(string: base + $0) }
        }
        for name in fallbackAudioFileNames {
            guard let url = URL(string: base + name) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            if let (_, response) = try? await session.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return url
            }
        }
        return nil
    }
}

/// Per-listing failure copy from Apollo's posts-list empty state. Lives
/// here rather than in the view so it's directly testable, and so every
/// listing screen shares one source instead of surfacing raw thrown-error
/// descriptions.
public enum FeedErrorCopy {
    public static func message(status: Int, body: String, subreddit: String) -> String {
        let name = subreddit.isEmpty ? "This feed" : "r/\(subreddit)"
        if body.contains("quarantined") {
            return "\(name) has been quarantined by Reddit Administrators for offensive content"
        }
        switch status {
        case 403:
            return "\(name) has been set to private by its subreddit moderators"
        case 404:
            return "\(name) has been banned by Reddit Administrators for breaking Reddit rules"
        default:
            return "Couldn't load posts."
        }
    }
}


/// Row model for Apollo's flair action sheet, kept in PhoebusCore so its
/// structure (the "✓ " prefix on the applied flair, and when "Remove Flair"
/// appears) is directly testable.
public enum FlairActionRows {
    public struct Row: Equatable, Sendable {
        public let title: String
        public let isDestructive: Bool

        public init(title: String, isDestructive: Bool) {
            self.title = title
            self.isDestructive = isDestructive
        }
    }

    /// `options` are (templateID, text) pairs in display order.
    public static func build(
        options: [(id: String, text: String)],
        currentFlairID: String?,
        isModerator: Bool
    ) -> [Row] {
        var rows = options.map { option in
            Row(
                title: option.id == currentFlairID ? "\u{2713} \(option.text)" : option.text,
                isDestructive: false
            )
        }
        if isModerator || currentFlairID != nil {
            rows.append(Row(title: "Remove Flair", isDestructive: true))
        }
        return rows
    }
}
