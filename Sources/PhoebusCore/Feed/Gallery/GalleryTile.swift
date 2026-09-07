import Foundation

/// One displayable piece of media in Gallery View, the flattened unit the
/// grid and fullscreen viewer both operate on. A gallery post yields N
/// tiles (one per image), so the viewer and its "N / M" counter page
/// per-image rather than per-post.
public struct GalleryTile: Identifiable, Sendable {
    /// Same three kinds as the filter (`GalleryPostMedia.Kind`), as its own
    /// type so a tile's kind is never built from a post-level classification
    /// that ignores which gallery image the tile is.
    public typealias Kind = GalleryPostMedia.Kind

    /// Stable across the tile's lifetime: the post's fullname plus the
    /// gallery media ID (or nothing, for a non-gallery post's single
    /// tile) — two DIFFERENT posts never collide, and two images
    /// within the SAME gallery post never collide either.
    public let id: String
    public let post: RedditPost
    /// nil for an ordinary (non-gallery) post's single tile; the
    /// gallery media ID this tile renders for a multi-image post.
    public let galleryMediaID: String?
    /// 0-based position within the source gallery post; always 0 for a
    /// non-gallery tile.
    public let galleryIndex: Int
    /// Always 1 for a non-gallery tile.
    public let galleryCount: Int
    public let kind: Kind
    public let thumbnailURL: URL
    public let fullResolutionURL: URL
    public let videoURL: URL?
    public let aspectRatio: Double?
    /// Runtime in seconds, 0 when unknown; only meaningful for `.video`.
    public let duration: Double
    /// What a muted grid tile plays for a GIF: Reddit's mp4 rendition (gallery
    /// `s.mp4` or `preview.images[0].variants.mp4`), nil for a real .gif with no
    /// transcode. Grid-only: the viewer still opens `fullResolutionURL`
    /// (Reborn `gifMP4URL`).
    public var gifMP4URL: URL? = nil

    public var isNSFW: Bool { post.over18 }
    public var isSpoiler: Bool { post.spoiler }
    public var subreddit: String { post.subreddit }

    /// "0:42" / "1:23:45", or nil when the duration is unknown, via the shared
    /// formatter the viewer's transport clock uses.
    public var durationText: String? {
        guard duration > 0 else { return nil }
        return GalleryTimeFormat.string(duration)
    }

    /// `preview.images[0].variants.mp4`: smallest rendition at least
    /// 320 wide (tiles are ~200pt), else the source.
    static func previewMP4(for post: RedditPost) -> URL? {
        guard let mp4 = post.preview?.images?.first?.variants?.mp4 else { return nil }
        let pick = mp4.resolutions?.first(where: { ($0.width ?? 0) >= 320 }) ?? mp4.source
        return pick?.url.flatMap { URL(string: GalleryTile.unescaped($0)) }
    }

    /// Builds every tile a post contributes to the grid: N tiles for a
    /// gallery post (Reddit's own `gallery_data` order), one otherwise.
    /// Empty for a text/link post with no viewable media.
    public static func tiles(for post: RedditPost) -> [GalleryTile] {
        if post.isGallery == true, let galleryData = post.galleryData,
           let mediaMetadata = post.mediaMetadata, !galleryData.items.isEmpty {
            var tiles: [GalleryTile] = []
            let count = galleryData.items.count
            for (index, item) in galleryData.items.enumerated() {
                guard let media = mediaMetadata[item.mediaID],
                      let source = media.source,
                      let rawURL = source.url else { continue }
                let stillURL = GalleryTile.unescaped(rawURL)
                // "Image" and "AnimatedImage" are pictures; anything else (e.g. a
                // video gallery entry) is skipped, as in Reborn.
                if let kindTag = media.kind, kindTag != "Image", kindTag != "AnimatedImage" { continue }
                let animated = media.kind == "AnimatedImage" || source.gifURL != nil
                guard let stillFullURL = URL(string: stillURL) else { continue }
                let gifFullURL = source.gifURL.flatMap { URL(string: GalleryTile.unescaped($0)) }
                let aspect = GalleryPostMedia.aspectRatio(mediaID: item.mediaID, in: post)
                tiles.append(GalleryTile(
                    id: "\(post.id):\(item.mediaID)",
                    post: post,
                    galleryMediaID: item.mediaID,
                    galleryIndex: index,
                    galleryCount: count,
                    kind: animated ? .gif : .photo,
                    thumbnailURL: stillFullURL,
                    fullResolutionURL: gifFullURL ?? stillFullURL,
                    videoURL: nil,
                    aspectRatio: aspect,
                    duration: 0,
                    gifMP4URL: source.mp4URL.flatMap { URL(string: GalleryTile.unescaped($0)) }))
            }
            if !tiles.isEmpty { return tiles }
        }

        // Non-gallery: at most one tile, resolved like every other media surface.
        guard let thumbnail = GalleryPostMedia.thumbnailURL(for: post) else { return [] }
        let full = GalleryPostMedia.fullResolutionURL(for: post) ?? thumbnail
        let video = GalleryPostMedia.videoURL(for: post)
        let kind: Kind
        switch GalleryPostMedia.kind(for: post) {
        case .photo: kind = .photo
        case .gif: kind = .gif
        case .video: kind = .video
        }
        let duration = post.media?.redditVideo?.duration ?? 0
        return [GalleryTile(
            id: post.id,
            post: post,
            galleryMediaID: nil,
            galleryIndex: 0,
            galleryCount: 1,
            kind: kind,
            thumbnailURL: thumbnail,
            fullResolutionURL: full,
            videoURL: video,
            aspectRatio: GalleryPostMedia.aspectRatio(for: post),
            duration: duration,
            gifMP4URL: kind == .gif ? GalleryTile.previewMP4(for: post) : nil)]
    }

    /// Flattens a post array into tiles, in order.
    public static func tiles(for posts: [RedditPost]) -> [GalleryTile] {
        posts.flatMap { tiles(for: $0) }
    }

    public static func unescaped(_ urlString: String) -> String {
        urlString.replacingOccurrences(of: "&amp;", with: "&")
    }
}
