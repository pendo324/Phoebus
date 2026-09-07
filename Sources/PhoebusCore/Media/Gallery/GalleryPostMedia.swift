import Foundation

/// Reborn's "Gallery View": decides whether a post has viewable media (to
/// filter a feed down to a grid of images/GIFs/videos) and picks a
/// representative thumbnail URL for the grid cell. Pure logic; the SwiftUI
/// grid lives in PhoebusUI.
public enum GalleryPostMedia {
    /// Returns a representative thumbnail URL for the post if it has
    /// any viewable media, or `nil` if it's a text/link-only post with
    /// nothing to show in a gallery grid.
    public static func thumbnailURL(for post: RedditPost) -> URL? {
        if let first = post.galleryImageURLs.first {
            return first
        }
        // Reddit's preview at a tile's width (~200pt) before the 140px
        // `thumbnail`, which is too soft at tile size.
        if let preview = post.previewImageURL(displayWidth: 200) {
            return preview
        }
        if let thumbnail = post.thumbnail, thumbnail.hasPrefix("http"), let url = URL(string: thumbnail) {
            return url
        }
        // Direct image/gif posts (post.url pointing straight at media)
        // don't always have a populated `thumbnail` field, so fall
        // back to the URL itself when it looks like an image.
        if let urlString = post.url, let url = URL(string: urlString) {
            let lower = urlString.lowercased()
            if [".jpg", ".jpeg", ".png", ".webp", ".gif", ".gifv"].contains(where: lower.hasSuffix) {
                return url
            }
        }
        return nil
    }

    /// The full-resolution still shown by the fullscreen viewer, as distinct
    /// from `thumbnailURL`, the grid preview (which would look blurry blown up
    /// to full screen). Falls back to `thumbnailURL`'s source when Reddit gave
    /// no resolutions to pick from.
    ///
    /// For a video or GIF item this is the poster frame, shown while the
    /// stream spins up.
    public static func fullResolutionURL(for post: RedditPost) -> URL? {
        // A gallery post's own first image is already full-size.
        if let first = post.galleryImageURLs.first {
            return first
        }
        // A direct link to the media beats any preview copy of it.
        if let urlString = post.url, let url = URL(string: urlString) {
            let lower = urlString.lowercased()
            if [".jpg", ".jpeg", ".png", ".webp", ".gif"].contains(where: lower.hasSuffix) {
                return url
            }
        }
        // Reddit's own `preview.images.source` is the original upload.
        // A large display width asks the ladder for its top rung, and
        // `previewImageURL` falls back to `source` when every rung is
        // narrower.
        if let preview = post.previewImageURL(displayWidth: 4096, scale: 1) {
            return preview
        }
        if let embedded = post.derivedSelfPostThumbnailURL {
            return embedded
        }
        return thumbnailURL(for: post)
    }

    /// The playable stream for a video or GIF-as-mp4 item, nil for a
    /// still.
    ///
    /// Routes through `RedditVideoStream` for the same reason every
    /// other video surface does: `fallback_url` is the VIDEO-ONLY
    /// rendition, so playing it gives a silent clip.
    public static func videoURL(for post: RedditPost) -> URL? {
        if let redditVideo = post.media?.redditVideo {
            return RedditVideoStream.playbackURL(
                hlsURL: redditVideo.hlsURL,
                fallbackURL: redditVideo.fallbackURL,
                isGif: redditVideo.isGif)
        }
        // Non-Reddit hosts (redgifs, streamable, direct .mp4) are
        // classified and resolved by `PostMediaKind`, which the viewer
        // consults; only a directly-playable URL belongs here.
        if let urlString = post.url, urlString.lowercased().hasSuffix(".mp4") {
            return URL(string: urlString)
        }
        return nil
    }

    /// Filters a post list down to just those with viewable media, in
    /// their original order: the actual "Gallery View" filtering step.
    public static func filterMediaPosts(_ posts: [RedditPost]) -> [RedditPost] {
        posts.filter { thumbnailURL(for: $0) != nil }
    }

    /// The Gallery View media kinds (Photos / GIFs / Videos), with Reborn's
    /// menu titles and SF Symbols.
    public enum Kind: String, CaseIterable, Sendable {
        case photo
        case gif
        case video

        public var title: String {
            switch self {
            case .photo: return "Photos"
            case .gif: return "GIFs"
            case .video: return "Videos"
            }
        }

        public var systemImage: String {
            switch self {
            case .photo: return "photo"
            case .gif: return "square.stack.3d.forward.dottedline"
            case .video: return "play.rectangle"
            }
        }
    }

    public static func kind(for post: RedditPost) -> Kind {
        let raw = (post.url ?? "").lowercased()
        if raw.hasSuffix(".gif") || raw.hasSuffix(".gifv") || raw.contains("redgifs.com") {
            return .gif
        }
        if raw.contains("v.redd.it") || raw.hasSuffix(".mp4") || raw.contains("streamable.com") {
            return .video
        }
        return .photo
    }

    /// The media's aspect ratio (width / height) when known, so a waterfall
    /// grid can size cells to real proportions. Reads `media_metadata`
    /// (gallery), `reddit_video` dimensions, then `preview.images[0].source`.
    public static func aspectRatio(for post: RedditPost) -> Double? {
        if post.isGallery == true, let galleryData = post.galleryData, let mediaMetadata = post.mediaMetadata,
           let firstID = galleryData.items.first?.mediaID,
           let source = mediaMetadata[firstID]?.source,
           let width = source.x, let height = source.y, height > 0 {
            return Double(width) / Double(height)
        }
        // Reddit-hosted video carries its own dimensions, checked before
        // `preview`, whose poster frame can have a different aspect than the
        // actual clip.
        if let video = post.media?.redditVideo,
           let width = video.width, let height = video.height, height > 0 {
            return Double(width) / Double(height)
        }
        if let source = post.preview?.images?.first?.source,
           let width = source.width, let height = source.height, height > 0 {
            return Double(width) / Double(height)
        }
        return nil
    }

    /// Same lookup as `aspectRatio(for:)` but for a single flattened
    /// gallery image (see `GalleryTile`), since `aspectRatio(for:)` only
    /// reads the first gallery item.
    public static func aspectRatio(mediaID: String, in post: RedditPost) -> Double? {
        guard let mediaMetadata = post.mediaMetadata,
              let source = mediaMetadata[mediaID]?.source,
              let width = source.x, let height = source.y, height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}
