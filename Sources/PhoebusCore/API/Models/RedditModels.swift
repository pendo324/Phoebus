import Foundation

/// Validates a raw Reddit flair color string into a usable 6-digit hex
/// string, or `nil` when Reddit omitted it or sent a non-hex placeholder.
/// Lives in PhoebusCore (no SwiftUI dependency) so callers on both sides
/// can validate before constructing a `Color`.
public enum RedditFlairColor {
    public static func validHex(from raw: String?) -> String? {
        guard let raw, ThemeColorMath.parseHex(raw) != nil else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).filter { $0 != "#" }
    }
}

/// A submitted post (link or self-post).
public struct RedditPost: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String              // fullname, e.g. "t3_xxxxx"
    public let title: String
    public let author: String
    public let subreddit: String
    public let selftext: String?
    public let url: String?
    public let permalink: String
    public let score: Int
    public let upvoteRatio: Double?
    public let numComments: Int
    public let created: Date
    public let isSelf: Bool
    public let over18: Bool
    public let spoiler: Bool
    public var stickied: Bool
    public let saved: Bool
    public let likes: Bool?              // true = upvoted, false = downvoted, nil = none
    public let thumbnail: String?
    public let linkFlairText: String?
    /// The link flair as rich parts (`link_flair_richtext`), so its
    /// `:emoji:` codes draw as their images.
    public var linkFlairRichtext: [FlairPart]?
    public let authorFlairText: String?
    /// Reddit's per-subreddit flair colors: a moderator can assign a
    /// filled background + matching text color to any flair, distinct
    /// from its label text.
    public let linkFlairBackgroundColor: String?
    public let linkFlairTextColorRaw: String?
    public let authorFlairBackgroundColor: String?
    public let authorFlairTextColorRaw: String?
    public let totalAwardsReceived: Int?
    /// Reddit's `crosspost_parent` is a STRING fullname, not a boolean.
    /// `isCrosspost` is derived instead from `crosspostParentList`
    /// (`crosspost_parent_list`), Reddit's embedded-original-post payload.
    public let crosspostParentList: [RedditCrosspostParent]?
    public var isCrosspost: Bool { !(crosspostParentList?.isEmpty ?? true) }
    /// The original post this was crossposted from, if any.
    public var crosspostParent: RedditCrosspostParent? { crosspostParentList?.first }
    public let media: RedditMedia?
    public let isGallery: Bool?
    public let galleryData: GalleryData?
    public let mediaMetadata: [String: GalleryMediaItem]?
    /// Reddit's pre-resized copies of this post's image. See `RedditPreview`.
    public let preview: RedditPreview?
    /// Reddit's native poll payload (`data.poll_data`).
    public let pollData: RedditPollData?
    /// `author_cakeday`: present and true only on the post's own
    /// account-creation anniversary. Shows a cake icon next to the byline.
    public let authorCakeday: Bool?
    /// `"moderator"` / `"admin"` / `nil`.
    public var distinguished: String?
    /// True when a moderator has disabled new top-level comments.
    public var locked: Bool?
    /// A subreddit moderator can pin a specific comment sort; Reddit's own
    /// apps default to it over the user's global setting unless overridden.
    /// Treats the literal string `"null"` the same as an absent value.
    /// Backs `GeneralSettings.ignoreSuggestedSort`.
    /// Reddit's `post_hint` ("image", "hosted:video", "rich:video",
    /// "gallery", "animated_gif", "link", "self"...). `AIArticleDetector`
    /// needs it as the cheapest signal that a link post is media.
    public let postHint: String?
    public let suggestedSortRaw: String?
    public var suggestedSort: String? {
        guard let suggestedSortRaw, suggestedSortRaw != "null" else { return nil }
        return suggestedSortRaw
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, author, subreddit, selftext, url, permalink, score, saved, likes, thumbnail, media
        case upvoteRatio = "upvote_ratio"
        case numComments = "num_comments"
        case created = "created_utc"
        case isSelf = "is_self"
        case over18 = "over_18"
        case spoiler, stickied

        case linkFlairText = "link_flair_text"
        case linkFlairRichtext = "link_flair_richtext"
        case authorFlairText = "author_flair_text"
        case linkFlairBackgroundColor = "link_flair_background_color"
        case linkFlairTextColorRaw = "link_flair_text_color"
        case authorFlairBackgroundColor = "author_flair_background_color"
        case authorFlairTextColorRaw = "author_flair_text_color"
        case totalAwardsReceived = "total_awards_received"
        case crosspostParentList = "crosspost_parent_list"
        case isGallery = "is_gallery"
        case galleryData = "gallery_data"
        case mediaMetadata = "media_metadata"
        case preview
        case pollData = "poll_data"
        case authorCakeday = "author_cakeday"
        case distinguished
        case locked
        case suggestedSortRaw = "suggested_sort"
        case postHint = "post_hint"
    }

    /// Resolves this post's gallery images in display order, unescaping
    /// Reddit's HTML-entity-encoded URLs (`&amp;` -> `&`).
    public var galleryImageURLs: [URL] {
        guard isGallery == true, let galleryData, let mediaMetadata else { return [] }
        return galleryData.items.compactMap { item -> URL? in
            guard let metadata = mediaMetadata[item.mediaID], let sourceURL = metadata.source?.url else { return nil }
            let unescaped = sourceURL.replacingOccurrences(of: "&amp;", with: "&")
            return URL(string: unescaped)
        }
    }

    /// A self/text post's own feed thumbnail when Reddit gave it none
    /// (Reborn's `ApolloFeedTextPostThumbnails`): the first image embedded
    /// in the body, in body order (an asset's ID appears in its body
    /// link), the largest instead when the first is under 250px or none
    /// can be ordered, else the first direct image link in the selftext on
    /// a known media host. Galleries use `galleryImageURLs` instead.
    public var derivedSelfPostThumbnailURL: URL? {
        guard isSelf, isGallery != true else { return nil }
        let body = selftext ?? ""
        let images = (mediaMetadata ?? [:]).filter { _, item in
            (item.status == nil || item.status == "valid")
                && (item.kind == nil || item.kind == "Image" || item.kind == "AnimatedImage")
                && item.source?.url != nil
        }
        func area(_ item: GalleryMediaItem) -> Int { (item.source?.x ?? 0) * (item.source?.y ?? 0) }
        let largest = images.sorted { area($0.value) != area($1.value) ? area($0.value) > area($1.value) : $0.key < $1.key }.first
        let first = images.compactMap { key, item -> (Int, String, GalleryMediaItem)? in
            guard let range = body.range(of: key) else { return nil }
            return (body.distance(from: body.startIndex, to: range.lowerBound), key, item)
        }.min { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        var chosen = first.map { ($0.1, $0.2) } ?? largest.map { ($0.key, $0.value) }
        if let current = chosen, let largest, current.0 != largest.key {
            let side = max(current.1.source?.x ?? 0, current.1.source?.y ?? 0)
            if side > 0 && side < 250 { chosen = (largest.key, largest.value) }
        }
        if let url = chosen?.1.source?.url {
            return URL(string: url.replacingOccurrences(of: "&amp;", with: "&"))
        }
        return Self.firstDirectImageLink(in: body)
    }

    /// Hosts whose direct image links count as a text post's image.
    static let directImageHosts = ["redd.it", "imgur.com", "giphy.com", "tenor.com", "redgifs.com",
                                   "twimg.com", "discordapp.com", "discordapp.net", "imgchest.com"]

    static func firstDirectImageLink(in text: String) -> URL? {
        guard !text.isEmpty, let regex = try? NSRegularExpression(pattern: #"https?://[^\s)\]>"']+"#) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let url = URL(string: String(text[range])),
                  let host = url.host?.lowercased() else { continue }
            let string = url.absoluteString.lowercased()
            let path = url.path.lowercased()
            guard !string.contains("format=mp4"),
                  [".png", ".jpg", ".jpeg", ".webp", ".gif"].contains(where: { path.hasSuffix($0) }),
                  directImageHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { continue }
            return url
        }
        return nil
    }

    /// The best preview image for a card `displayWidth` points wide.
    ///
    /// `post.thumbnail` is only 140px wide, so a large card would upscale it
    /// ~3x. This picks the narrowest pre-resized copy from
    /// `preview.images.resolutions` that is still at least as wide as the space
    /// it fills, at the device's scale.
    ///
    /// Falls back to `source` when every rung is too small, and returns nil
    /// when there is no preview at all.
    public func previewImageURL(displayWidth: Double, scale: Double = 3) -> URL? {
        guard let image = preview?.images?.first else { return nil }
        let target = displayWidth * scale
        // `resolutions` arrives ascending, but sorting makes that an
        // assumption this code does not have to make.
        let ladder = (image.resolutions ?? []).sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        let chosen = ladder.first { Double($0.width ?? 0) >= target } ?? image.source
        guard let urlString = chosen?.url else { return nil }
        // Reddit HTML-escapes these in JSON; an un-unescaped URL 403s.
        return URL(string: urlString.replacingOccurrences(of: "&amp;", with: "&"))
    }
}

/// Manual, `id`-only Hashable/Equatable conformance: a post's real Reddit
/// fullname (`id`) is already a stable, unique identity.
extension RedditPost: Hashable {
    public static func == (lhs: RedditPost, rhs: RedditPost) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// The original post embedded in a crosspost's `crosspost_parent_list`
/// array: Reddit sends the entire original post's data inline. A
/// deliberately separate, smaller type rather than reusing `RedditPost`
/// recursively, since Reddit's own payload omits several `RedditPost`-only
/// fields and a nested crosspost's own list has never been observed.
public struct RedditCrosspostParent: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let title: String
    public let author: String
    public let subreddit: String
    public let permalink: String
    public let score: Int
    public let numComments: Int
    public let created: Date
    public let over18: Bool
    public let spoiler: Bool
    public let thumbnail: String?
    public let subredditIconImage: String?
    /// The original's body and flair, for the crosspost card's excerpt.
    public let selftext: String?
    public let linkFlairText: String?

    enum CodingKeys: String, CodingKey {
        case id, name, title, author, subreddit, permalink, score, thumbnail, selftext
        case linkFlairText = "link_flair_text"
        case numComments = "num_comments"
        case created = "created_utc"
        case over18 = "over_18"
        case spoiler
        case subredditIconImage = "sr_icon_img"
    }
}

/// Mirrors Reddit's `poll_data` payload (a post's native poll).
public struct RedditPollData: Codable, Sendable, Equatable {
    public let options: [RedditPollOption]
    public let totalVoteCount: Int
    /// Which option the signed-in user picked, if any; `nil` means they
    /// haven't voted yet.
    public let userSelection: String?
    public let votingEndTimestamp: Double

    enum CodingKeys: String, CodingKey {
        case options
        case totalVoteCount = "total_vote_count"
        case userSelection = "user_selection"
        case votingEndTimestamp = "voting_end_timestamp"
    }

    /// Lenient per field: a poll missing its count or end time still
    /// shows (and so does the post carrying it), rather than failing
    /// the whole decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        options = (try? container.decodeIfPresent(LossyArray<RedditPollOption>.self, forKey: .options))?.elements ?? []
        totalVoteCount = (try? container.decodeIfPresent(Int.self, forKey: .totalVoteCount)) ?? 0
        userSelection = try? container.decodeIfPresent(String.self, forKey: .userSelection)
        votingEndTimestamp = (try? container.decodeIfPresent(Double.self, forKey: .votingEndTimestamp)) ?? 0
    }

    /// Voting is closed once the end timestamp (ms since epoch) has passed.
    public var hasEnded: Bool {
        Date(timeIntervalSince1970: votingEndTimestamp / 1000) <= Date()
    }

    public var votingEndDate: Date {
        Date(timeIntervalSince1970: votingEndTimestamp / 1000)
    }
}

/// One option in a native poll.
public struct RedditPollOption: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    /// Only present once you've voted or the poll has ended; Reddit hides
    /// per-option counts from an open poll you haven't voted in.
    public let voteCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, text
        case voteCount = "vote_count"
    }
}

/// Mirrors the `gallery_data` field on multi-image posts: an ordered
/// list of media item references (display order, not `media_metadata`'s
/// dictionary order).
public struct GalleryData: Codable, Sendable {
    public let items: [GalleryItem]

    public struct GalleryItem: Codable, Sendable {
        public let mediaID: String
        enum CodingKeys: String, CodingKey {
            case mediaID = "media_id"
        }
    }
}

/// Mirrors one entry in `media_metadata`: the actual image URL and
/// dimensions for a gallery item, keyed by media ID.
public struct GalleryMediaItem: Codable, Sendable {
    public let status: String?
    public let source: Source?
    /// Reddit's kind tag for this item: `"Image"` for a still,
    /// `"AnimatedImage"` for a GIF.
    public let kind: String?
    /// The file's MIME type (`"image/png"`), absent on some items.
    public let mimeType: String?

    enum CodingKeys: String, CodingKey {
        case status
        case source = "s"
        case kind = "e"
        case mimeType = "m"
    }

    public struct Source: Codable, Sendable {
        public let url: String?
        public let x: Int?
        public let y: Int?
        /// The animated file's own URL, present only for a GIF gallery item.
        public let gifURL: String?
        /// Reddit's silent mp4 rendition of an `AnimatedImage` gallery item,
        /// played by Gallery View grid autoplay instead of decoding the gif.
        public let mp4URL: String?

        enum CodingKeys: String, CodingKey {
            case url = "u"
            case x, y
            case gifURL = "gif"
            case mp4URL = "mp4"
        }
    }
}

/// Reddit's `preview` payload: the resized copies it generates for every
/// image post (`images`, `resolutions`, plus `variants.mp4`/`gif` for
/// animated posts). Without it, the feed falls back to `post.thumbnail`,
/// a 140px thumbnail blown up ~3x on a feed card.
public struct RedditPreview: Codable, Sendable {
    public let images: [PreviewImage]?

    public struct PreviewImage: Codable, Sendable {
        /// The full-size original.
        public let source: PreviewSource?
        /// Reddit's ladder of pre-resized copies, ascending by width.
        public let resolutions: [PreviewSource]?
        /// `variants.mp4` - present on animated image posts (i.redd.it
        /// .gif): Reddit's mp4 transcode, used for grid autoplay.
        public let variants: Variants?
    }

    public struct Variants: Codable, Sendable {
        public let mp4: Variant?
    }

    public struct Variant: Codable, Sendable {
        public let source: PreviewSource?
        public let resolutions: [PreviewSource]?
    }

    public struct PreviewSource: Codable, Sendable {
        public let url: String?
        public let width: Int?
        public let height: Int?
    }
}

/// The `media` field on a post, present for
/// v.redd.it-hosted native Reddit video posts. Reddit stores the playable
/// stream URLs here rather than in `post.url` (the human-facing watch page).
public struct RedditMedia: Codable, Sendable {
    public let redditVideo: RedditVideo?

    enum CodingKeys: String, CodingKey {
        case redditVideo = "reddit_video"
    }

    /// Lenient: a malformed `reddit_video` (no `fallback_url`) loses the
    /// video, not the whole post.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        redditVideo = try? container.decodeIfPresent(RedditVideo.self, forKey: .redditVideo)
    }

    public struct RedditVideo: Codable, Sendable {
        public let fallbackURL: String
        public let hlsURL: String?
        public let dashURL: String?
        public let isGif: Bool
        /// Reddit's own runtime in seconds. Gallery View's video badge
        /// and the fullscreen counter both need it up front, without
        /// waiting on an HLS manifest round-trip.
        public let duration: Double?
        /// Reddit's own pixel dimensions for the rendition, available on
        /// the same listing response, so the correct aspect ratio is known
        /// on the first layout pass without a manifest round-trip.
        public let width: Int?
        public let height: Int?

        /// `width / height`, or nil when Reddit omitted or zeroed
        /// either one.
        public var aspectRatio: Double? {
            guard let width, let height, width > 0, height > 0 else { return nil }
            return Double(width) / Double(height)
        }

        enum CodingKeys: String, CodingKey {
            case fallbackURL = "fallback_url"
            case hlsURL = "hls_url"
            case dashURL = "dash_url"
            case isGif = "is_gif"
            case duration
            case width
            case height
        }
    }
}

/// A comment. Comment trees are recursive: `replies` is either
/// an empty string (no replies) or a nested RedditListing.
public struct RedditComment: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let author: String
    public let body: String
    public let bodyHTML: String?
    public let score: Int
    public let created: Date
    public let parentID: String
    public let linkID: String
    public let depth: Int?
    public let likes: Bool?
    public let saved: Bool
    public let scoreHidden: Bool
    /// Reddit's `controversiality` (0 or 1): set when a comment has
    /// substantial votes both ways. `AICommentSelector.rank` uses it to
    /// find disagreement rather than just top-scoring consensus.
    public let controversiality: Int?
    public let stickied: Bool
    public let authorFlairText: String?
    public let authorFlairBackgroundColor: String?
    public let authorFlairTextColorRaw: String?
    /// True when this commenter is the post's original poster; real
    /// Reddit clients show an "OP" badge for this.
    public let isSubmitter: Bool?
    /// `"moderator"` / `"admin"` / `nil`: real clients color-distinguish
    /// mod/admin comments.
    public let distinguished: String?
    /// Present on user-listing responses: the post the comment belongs to.
    public let linkTitle: String?
    public let subreddit: String?
    public let numComments: Int?
    /// Same as `RedditPost.authorCakeday`; comment listings carry it too.
    public let authorCakeday: Bool?
    /// A locked comment can't be replied to; Apollo shows a lock in its
    /// byline.
    public let locked: Bool?
    /// The flair as Reddit's rich parts (`author_flair_richtext`):
    /// custom emoji images and text runs, e.g. a state flag + "Maine".
    public let authorFlairRichtext: [FlairPart]?
    /// Uploaded images and GIFs in the body (`![img](<id>)` tokens), keyed
    /// by asset id, with their pixel size and file type. Lets an inline
    /// image reserve its final shape before it loads (Reborn #1273) and
    /// name the right file extension.
    public let mediaMetadata: [String: GalleryMediaItem]?
    /// The author's `t2_` id, for the batched avatar lookup.
    public let authorFullname: String?

    enum CodingKeys: String, CodingKey {
        case id, name, author, body, score, saved, likes, depth, stickied, subreddit
        case mediaMetadata = "media_metadata"
        case authorFullname = "author_fullname"
        case linkTitle = "link_title"
        case numComments = "num_comments"
        case bodyHTML = "body_html"
        case created = "created_utc"
        case parentID = "parent_id"
        case linkID = "link_id"
        case scoreHidden = "score_hidden"
        case controversiality
        case authorFlairText = "author_flair_text"
        case authorFlairBackgroundColor = "author_flair_background_color"
        case authorFlairTextColorRaw = "author_flair_text_color"
        case isSubmitter = "is_submitter"
        case distinguished
        case authorCakeday = "author_cakeday"
        case locked
        case authorFlairRichtext = "author_flair_richtext"
    }
}

/// A subreddit.
public struct RedditSubreddit: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let displayName: String
    public let title: String
    public let publicDescription: String?
    public let subscribers: Int?
    /// Reddit's `active_user_count`.
    public let activeUserCount: Int?
    public let over18: Bool
    public let userIsSubscriber: Bool?
    public let userIsModerator: Bool?
    public let iconImage: String?
    /// Reddit's modern per-community icon, preferred over the legacy
    /// `icon_img`.
    public let communityIcon: String?
    /// The modern per-community banner shown at the top of a subreddit's
    /// page (distinct from the legacy `banner_img`); used by
    /// `SubredditSidebarScreen`'s full-screen banner viewer.
    public let bannerImage: String?
    /// The legacy `banner_img` and the `mobile_banner_image` crop; see
    /// `headerBannerURL`.
    public let legacyBannerImage: String?
    public let mobileBannerImage: String?
    /// Reddit's `can_assign_user_flair`: whether members may set their
    /// own flair here. Nil when the response didn't say.
    public let canAssignUserFlair: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, title, subscribers
        case displayName = "display_name"
        case activeUserCount = "active_user_count"
        case publicDescription = "public_description"
        case over18 = "over_18"
        // Both `over18`/`over_18` are genuine real Reddit API key spellings
        // for the same field, used by different endpoints.
        case over18Alt = "over18"
        case userIsSubscriber = "user_is_subscriber"
        case userIsModerator = "user_is_moderator"
        case iconImage = "icon_img"
        case communityIcon = "community_icon"
        case bannerImage = "banner_background_image"
        case legacyBannerImage = "banner_img"
        case mobileBannerImage = "mobile_banner_image"
        case canAssignUserFlair = "can_assign_user_flair"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Some subreddit responses omit `id` and only carry `name`
        // (the `t5_xxxxx` fullname); fall back to stripping the `t5_`
        // prefix, which equals the real `id` whenever both are present.
        let name = try container.decode(String.self, forKey: .name)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? name.replacingOccurrences(of: "t5_", with: "")
        self.name = name
        displayName = try container.decode(String.self, forKey: .displayName)
        title = try container.decode(String.self, forKey: .title)
        publicDescription = try container.decodeIfPresent(String.self, forKey: .publicDescription)
        subscribers = try container.decodeIfPresent(Int.self, forKey: .subscribers)
        over18 = try container.decodeIfPresent(Bool.self, forKey: .over18)
            ?? container.decodeIfPresent(Bool.self, forKey: .over18Alt)
            ?? false
        userIsSubscriber = try container.decodeIfPresent(Bool.self, forKey: .userIsSubscriber)
        userIsModerator = try container.decodeIfPresent(Bool.self, forKey: .userIsModerator)
        activeUserCount = try container.decodeIfPresent(Int.self, forKey: .activeUserCount)
        iconImage = try container.decodeIfPresent(String.self, forKey: .iconImage)
        communityIcon = try container.decodeIfPresent(String.self, forKey: .communityIcon)
        bannerImage = try container.decodeIfPresent(String.self, forKey: .bannerImage)
        legacyBannerImage = try container.decodeIfPresent(String.self, forKey: .legacyBannerImage)
        mobileBannerImage = try container.decodeIfPresent(String.self, forKey: .mobileBannerImage)
        canAssignUserFlair = try container.decodeIfPresent(Bool.self, forKey: .canAssignUserFlair)
    }

    /// The subreddit header's banner, in Reborn's order: `banner_img`, then
    /// `mobile_banner_image`, then `banner_background_image`. The first two are
    /// the phone-shaped crops; the last is the wide desktop art.
    public var headerBannerURL: URL? {
        for raw in [legacyBannerImage, mobileBannerImage, bannerImage] {
            guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
                  let url = URL(string: raw.replacingOccurrences(of: "&amp;", with: "&")) else { continue }
            return url
        }
        return nil
    }

    /// Written by hand rather than synthesized: `CodingKeys` carries
    /// `over18Alt`, a second spelling with no property behind it, so
    /// synthesis cannot produce a matching `encode(to:)`. Also this needs
    /// to round-trip through `init(from:)` for disk caching, so it always
    /// writes the canonical key of each pair.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(publicDescription, forKey: .publicDescription)
        try container.encodeIfPresent(subscribers, forKey: .subscribers)
        try container.encodeIfPresent(activeUserCount, forKey: .activeUserCount)
        try container.encode(over18, forKey: .over18)
        try container.encodeIfPresent(userIsSubscriber, forKey: .userIsSubscriber)
        try container.encodeIfPresent(userIsModerator, forKey: .userIsModerator)
        try container.encodeIfPresent(iconImage, forKey: .iconImage)
        try container.encodeIfPresent(communityIcon, forKey: .communityIcon)
        try container.encodeIfPresent(bannerImage, forKey: .bannerImage)
        try container.encodeIfPresent(legacyBannerImage, forKey: .legacyBannerImage)
        try container.encodeIfPresent(mobileBannerImage, forKey: .mobileBannerImage)
        try container.encodeIfPresent(canAssignUserFlair, forKey: .canAssignUserFlair)
    }
}

/// A user account (`about` payloads and `/me`).
public struct RedditUser: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let commentKarma: Int
    public let linkKarma: Int
    public let created: Date
    public let isGold: Bool
    public let isMod: Bool
    public let hasVerifiedEmail: Bool
    public let iconImage: String?
    /// The profile header banner image, from the user's profile subreddit
    /// (`data.subreddit.banner_img`), a separate nested object from the
    /// top-level user fields.
    public let bannerImage: String?
    /// The profile's display name and about text, from the same nested
    /// profile subreddit (`title`, `public_description`).
    public let profileTitle: String?
    public let publicDescription: String?
    /// The account's "Blur mature (18+) images and media" pref; only
    /// present on the signed-in user's own `/me`.
    public let blursMatureMedia: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name
        case blursMatureMedia = "pref_no_profanity"
        case commentKarma = "comment_karma"
        case linkKarma = "link_karma"
        case created = "created_utc"
        case isGold = "is_gold"
        case isMod = "is_mod"
        case hasVerifiedEmail = "has_verified_email"
        case iconImage = "icon_img"
        case subreddit
    }

    private enum SubredditCodingKeys: String, CodingKey {
        case bannerImage = "banner_img"
        case mobileBannerImage = "mobile_banner_image"
        case bannerBackgroundImage = "banner_background_image"
        case title
        case publicDescription = "public_description"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        commentKarma = try container.decode(Int.self, forKey: .commentKarma)
        linkKarma = try container.decode(Int.self, forKey: .linkKarma)
        created = try container.decode(Date.self, forKey: .created)
        isGold = try container.decodeIfPresent(Bool.self, forKey: .isGold) ?? false
        isMod = try container.decodeIfPresent(Bool.self, forKey: .isMod) ?? false
        hasVerifiedEmail = try container.decodeIfPresent(Bool.self, forKey: .hasVerifiedEmail) ?? false
        iconImage = try container.decodeIfPresent(String.self, forKey: .iconImage)
        blursMatureMedia = try? container.decodeIfPresent(Bool.self, forKey: .blursMatureMedia)
        if let subredditContainer = try? container.nestedContainer(keyedBy: SubredditCodingKeys.self, forKey: .subreddit) {
            func field(_ key: SubredditCodingKeys) -> String? {
                let raw = (try? subredditContainer.decodeIfPresent(String.self, forKey: key)) ?? nil
                guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
                return value.replacingOccurrences(of: "&amp;", with: "&")
            }
            // Reborn's order: many profiles only set the mobile banner.
            bannerImage = field(.bannerImage) ?? field(.mobileBannerImage) ?? field(.bannerBackgroundImage)
            profileTitle = field(.title)
            publicDescription = field(.publicDescription)
        } else {
            bannerImage = nil
            profileTitle = nil
            publicDescription = nil
        }
    }
}


/// One run of a rich flair: an emoji image or plain text.
public struct FlairPart: Codable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case text(String), emoji(URL) }
    public let kind: Kind

    private enum Keys: String, CodingKey { case e, t, u }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .e)
        if type == "emoji", let raw = try c.decodeIfPresent(String.self, forKey: .u), let url = URL(string: raw) {
            kind = .emoji(url)
        } else {
            kind = .text(try c.decodeIfPresent(String.self, forKey: .t) ?? "")
        }
    }

    public init(kind: Kind) { self.kind = kind }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch kind {
        case .emoji(let url):
            try c.encode("emoji", forKey: .e)
            try c.encode(url.absoluteString, forKey: .u)
        case .text(let value):
            try c.encode("text", forKey: .e)
            try c.encode(value, forKey: .t)
        }
    }
}


extension RedditSubreddit {
    /// A placeholder for a subreddit known only by name (a favorite the
    /// account is not subscribed to), decoded through the normal path.
    public static func named(_ name: String) -> RedditSubreddit? {
        let json: [String: Any] = ["id": name, "name": "t5_\(name)", "display_name": name, "title": name, "over18": false]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder.reddit.decode(RedditSubreddit.self, from: data)
    }
}
