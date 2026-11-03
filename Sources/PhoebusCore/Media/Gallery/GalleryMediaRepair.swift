import Foundation

/// Reddit marks every photo of a gallery made through its public API
/// (`media/asset.json` + `submit_gallery_post.json`, which is also how
/// Phoebus and Apollo Reborn post one) as `media_metadata` `"status":
/// "failed"` with no `s`, though the photos are served at
/// `i.redd.it/<media_id>.<ext>`. Reborn `Apollo-Reborn#1587`: rebuild such
/// entries as valid ones so the post shows its photos, not a bare link.
public enum GalleryMediaRepair {
    /// Reddit sends no dimensions with a failed entry; a square keeps the
    /// feed carousel's card sizing sane and grids crop to their tiles anyway.
    static let placeholderSide = 1080

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]

    /// `metadata` with each failed gallery item rebuilt. `items` is the
    /// post's `gallery_data.items`; `thumbnail` is the post's thumbnail,
    /// which carries the first photo's file extension.
    public static func repaired(_ metadata: [String: GalleryMediaItem],
                                items: [GalleryData.GalleryItem],
                                thumbnail: String?) -> [String: GalleryMediaItem] {
        guard metadata.values.contains(where: { $0.status == "failed" && $0.source?.url == nil }) else { return metadata }
        let thumb = thumbnailExtension(thumbnail)
        // The thumbnail's extension is exact for the first photo. Galleries
        // are usually uploaded in one format, so it stands in for the rest
        // unless it is a GIF; with no usable thumbnail, `.jpeg` (the name
        // Phoebus and Reborn give their uploads).
        let fallback = thumb.map { $0.ext != "gif" ? $0.ext : "jpeg" } ?? "jpeg"
        var result = metadata
        for item in items {
            guard isPlain(item.mediaID), let entry = metadata[item.mediaID],
                  entry.status == "failed", entry.source?.url == nil else { continue }
            let ext = thumb.flatMap { $0.mediaID == item.mediaID ? $0.ext : nil } ?? fallback
            let url = "https://i.redd.it/\(item.mediaID).\(ext)"
            let animated = ext == "gif"
            result[item.mediaID] = GalleryMediaItem(
                status: "valid",
                source: GalleryMediaItem.Source(url: url, x: placeholderSide, y: placeholderSide,
                              gifURL: animated ? url : nil, mp4URL: animated ? url : nil),
                kind: animated ? "AnimatedImage" : "Image",
                mimeType: mimeType(forExtension: ext))
        }
        return result
    }

    /// `https://preview.redd.it/<media_id>.<ext>?...` (or `i.redd.it`): the
    /// first photo's ID and extension.
    static func thumbnailExtension(_ thumbnail: String?) -> (mediaID: String, ext: String)? {
        guard let thumbnail, let url = URL(string: thumbnail),
              let host = url.host?.lowercased(), host == "preview.redd.it" || host == "i.redd.it" else { return nil }
        let name = url.lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        guard imageExtensions.contains(ext) else { return nil }
        return ((name as NSString).deletingPathExtension, ext)
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    /// A media ID is spliced into a URL, so only plain alphanumerics pass.
    static func isPlain(_ mediaID: String) -> Bool {
        !mediaID.isEmpty && mediaID.count <= 64 && mediaID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

extension RedditPost {
    /// `mediaMetadata` with failed gallery items rebuilt (`GalleryMediaRepair`);
    /// every gallery surface reads this instead of the raw payload.
    public var galleryMediaMetadata: [String: GalleryMediaItem]? {
        guard isGallery == true, let mediaMetadata else { return mediaMetadata }
        return GalleryMediaRepair.repaired(mediaMetadata, items: galleryData?.items ?? [], thumbnail: thumbnail)
    }
}
