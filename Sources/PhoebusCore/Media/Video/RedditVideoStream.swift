import Foundation

/// Picks the right stream URL for a Reddit-hosted (`v.redd.it`) video.
///
/// `reddit_video.fallback_url` is the VIDEO-ONLY MP4 rendition: Reddit
/// stores v.redd.it audio as a separate track, so a `fallback_url` player
/// is silent. The muxed stream is `hls_url`, which Apollo (and Reborn, for
/// video comments) plays via `…/HLSPlaylist.m3u8`.
///
/// `fallback_url` is still the right choice for a GIF-style post
/// (`is_gif`), which has no audio track to lose and where a progressive
/// MP4 starts faster than an HLS manifest.
public enum RedditVideoStream {
    /// The URL to hand to `AVPlayer`.
    ///
    /// HLS when there is audio to gain, the fallback MP4 otherwise.
    public static func playbackURL(hlsURL: String?, fallbackURL: String, isGif: Bool) -> URL? {
        // A silent GIF-style video gains nothing from HLS.
        if !isGif, let hls = normalizedHLS(hlsURL) {
            return hls
        }
        return URL(string: fallbackURL)
    }

    /// Cleans up Reddit's `hls_url`: Reddit appends a `?f=sd,hd,…` query
    /// listing available renditions, and Apollo normalises the URL back to the
    /// bare playlist before playing.
    public static func normalizedHLS(_ raw: String?) -> URL? {
        guard var value = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        // Reddit HTML-escapes the ampersands in JSON.
        value = value.replacingOccurrences(of: "&amp;", with: "&")
        // Keep everything up to and including `HLSPlaylist.m3u8`,
        // dropping the query. Matching Apollo's pattern rather than
        // a blind `?`-split, so an unexpected URL shape is left alone
        // instead of being silently truncated.
        if let range = value.range(of: "/HLSPlaylist.m3u8") {
            value = String(value[value.startIndex..<range.upperBound])
        }
        return URL(string: value)
    }

    /// The HLS playlist for a bare `v.redd.it` asset id.
    ///
    /// Used when a link points at a video but the post JSON carried no
    /// `reddit_video` block, a crosspost or a video comment.
    public static func hlsURL(forAssetID assetID: String) -> URL? {
        guard !assetID.isEmpty else { return nil }
        return URL(string: "https://v.redd.it/\(assetID)/HLSPlaylist.m3u8")
    }

    /// The URL to DOWNLOAD or re-encode, which is not the URL to play.
    ///
    /// Playback wants the muxed HLS stream; the download and share-video
    /// paths want the progressive `DASH_*.mp4`, because they pair it with
    /// `DASH_audio.mp4` and mux the two themselves
    /// (`VideoDownloader.audioURL(forRedditVideo:)` looks for `DASH_` in the
    /// URL).
    public static func downloadURL(hlsURL: String?, fallbackURL: String) -> URL? {
        // Always the progressive rendition, never the playlist.
        URL(string: fallbackURL)
    }

    /// The asset id in a `v.redd.it` URL, or nil.
    public static func assetID(fromVRedditURL url: URL) -> String? {
        guard url.host?.lowercased().hasSuffix("v.redd.it") == true else { return nil }
        let id = url.pathComponents.first { $0 != "/" && !$0.isEmpty }
        guard let id, !id.isEmpty, !id.hasSuffix(".mp4"), id != "HLSPlaylist.m3u8" else {
            return nil
        }
        return id
    }
}
