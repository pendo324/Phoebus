import Foundation

/// Reborn's hold menus on media inside a post (`Apollo-Reborn#1400`,
/// `#1435`): holding an inline comment image or GIF, or the image, GIF,
/// video or album tile in a post's header, offers the actions that fit that
/// one item. Which actions, in which order, and which are greyed out lives
/// here so it can be asserted; the views only draw the result.
public enum MediaHoldMenu {
    public enum Kind: Sendable, Equatable {
        case image
        case gif
        case video
    }

    public enum Action: Sendable, Equatable {
        case copyImage
        case copyGIF
        case copyLink
        case saveImage
        case saveGIF
        case saveVideo
        case saveAllMedia
        case share

        public var title: String {
            switch self {
            case .copyImage: return "Copy Image"
            case .copyGIF: return "Copy GIF"
            case .copyLink: return "Copy Link"
            case .saveImage: return "Save Image"
            case .saveGIF: return "Save GIF"
            case .saveVideo: return "Save Video"
            case .saveAllMedia: return SaveAllMediaSummary.menuTitle
            case .share: return "Share"
            }
        }

        public var symbol: String {
            switch self {
            case .copyImage, .copyGIF: return "doc.on.doc"
            case .copyLink: return "link"
            case .saveImage, .saveGIF, .saveVideo: return "square.and.arrow.down"
            case .saveAllMedia: return SaveAllMediaSummary.menuSymbol
            case .share: return "square.and.arrow.up"
            }
        }
    }

    public struct Item: Sendable, Equatable {
        public let action: Action
        public let isEnabled: Bool

        public init(_ action: Action, isEnabled: Bool = true) {
            self.action = action
            self.isEnabled = isEnabled
        }
    }

    /// The one item a hold landed on.
    public struct Subject: Sendable, Equatable {
        public var kind: Kind
        /// The file the item draws. For a video, the file or stream to save.
        public var mediaURL: URL
        /// What Copy Link and a video's Share hand out, when it is not
        /// `mediaURL` itself (a RedGIFs watch page rather than its CDN file).
        public var linkURL: URL?
        /// Images in the album this item belongs to; more than one adds
        /// Save All Media.
        public var albumCount: Int
        /// The item could not be loaded, so there is nothing to copy or save.
        public var loadFailed: Bool

        public init(kind: Kind, mediaURL: URL, linkURL: URL? = nil, albumCount: Int = 1, loadFailed: Bool = false) {
            self.kind = kind
            self.mediaURL = mediaURL
            self.linkURL = linkURL
            self.albumCount = albumCount
            self.loadFailed = loadFailed
        }

        /// The link Copy Link copies and Share sends for a video.
        public var shareURL: URL { linkURL ?? MediaHoldMenu.shareableLink(for: mediaURL) }
    }

    /// The menu for `subject`, in Reborn's order: image and GIF get Copy,
    /// Save, Save All Media (an album) and Share; a video gets Copy Link,
    /// Save Video and Share (the link), as its bytes are a stream, not a file
    /// to put on the pasteboard.
    public static func items(for subject: Subject) -> [Item] {
        switch subject.kind {
        case .image:
            return stillItems(subject, copy: .copyImage, save: .saveImage, copiesBytes: true)
        case .gif:
            // Only a real `.gif` file copies as a GIF: an Imgur `.gifv` is an
            // MP4 page, so its copy is the link.
            return stillItems(subject, copy: .copyGIF, save: .saveGIF, copiesBytes: hasGIFFile(subject.mediaURL))
        case .video:
            return [
                Item(.copyLink),
                Item(.saveVideo, isEnabled: canSaveVideo(subject.mediaURL)),
                Item(.share),
            ]
        }
    }

    private static func stillItems(_ subject: Subject, copy: Action, save: Action, copiesBytes: Bool) -> [Item] {
        let loaded = !subject.loadFailed
        var items = [copiesBytes ? Item(copy, isEnabled: loaded) : Item(.copyLink)]
        items.append(Item(save, isEnabled: loaded))
        if subject.albumCount > 1 { items.append(Item(.saveAllMedia, isEnabled: loaded)) }
        items.append(Item(.share))
        return items
    }

    /// A GIF whose bytes are a GIF (not an `.gifv` or `format=mp4` page).
    public static func hasGIFFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "gif" && url.query?.lowercased().contains("format=mp4") != true
    }

    /// Whether Save Video can put this video in Photos: a progressive MP4/MOV
    /// as is, or a v.redd.it video, whose progressive tracks the saver looks
    /// up itself. An HLS or DASH manifest of any other host, and WebM, which
    /// Photos does not take, cannot.
    public static func canSaveVideo(_ url: URL) -> Bool {
        if RedditVideoStream.assetID(fromVRedditURL: url) != nil { return true }
        return ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased())
    }

    /// The link to a video worth copying: a v.redd.it stream (HLS playlist,
    /// DASH file or manifest) is `https://v.redd.it/<id>`, the shape people
    /// paste; anything else is the URL itself.
    public static func shareableLink(for url: URL) -> URL {
        if let id = RedditVideoStream.assetID(fromVRedditURL: url), let link = URL(string: "https://v.redd.it/\(id)") {
            return link
        }
        return url
    }

    /// The watch page of a RedGIFs (or legacy Gfycat) id.
    public static func redGifsPage(id: String) -> URL? {
        URL(string: "https://www.redgifs.com/watch/\(id.lowercased())")
    }

    /// The page of a Streamable video id.
    public static func streamablePage(id: String) -> URL? {
        URL(string: "https://streamable.com/\(id)")
    }
}
