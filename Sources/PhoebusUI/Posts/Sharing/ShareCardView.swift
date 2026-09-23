import SwiftUI
import PhoebusCore

/// The rendered card for Share as Image. Shared rather than post-only: it renders
/// a comment (with its parents above it) as readily as a post.
public struct ShareCardView: View {
    public struct Options {
        public var includePostDetails = true
        public var includePostTextPollOrImage = true
        public var hideUsernames = false
        public var hideSubreddit = false
        public var includeWatermark = true
        /// How many parent comments to show above the shared comment.
        public var parentComments = 0
        /// Draws images linked in the shared comments inline, as the
        /// comment tree does.
        public var includeCommentImages = true

        public init() {}
    }

    let post: RedditPost
    /// The comment being shared, if this is a comment share.
    let comment: RedditComment?
    /// Ancestors, nearest parent last.
    let parents: [RedditComment]
    let options: Options
    let colors: ApolloThemeColors
    /// Post media, already fetched; a gallery arrives pre-composed.
    let postImage: Image?
    /// The image's aspect ratio (w/h).
    /// Needed because a SwiftUI `Image` inside a fixed-width card has no intrinsic
    /// size to lay out against; a 3-image collage would otherwise render as a sliver.
    let postImageAspect: CGFloat?
    /// Author avatars by username, pre-loaded because the exported image
    /// is rendered detached and cannot wait on network images. Empty when
    /// "Show User Profile Pictures" is off.
    let avatars: [String: Image]
    /// Images linked in each comment body, keyed by comment id, already
    /// loaded (with aspect ratio) for the detached export.
    let commentImages: [String: [ShareCardImageLoader.Result]]
    /// The comment tree's depth bar colours.
    let depthColors: [Color]

    static func bodyText(of post: RedditPost) -> String? { ShareCardFormatting.bodyText(of: post) }

    public init(
        post: RedditPost,
        comment: RedditComment? = nil,
        parents: [RedditComment] = [],
        options: Options,
        colors: ApolloThemeColors,
        postImage: Image? = nil,
        postImageAspect: CGFloat? = nil,
        avatars: [String: Image] = [:],
        commentImages: [String: [ShareCardImageLoader.Result]] = [:],
        depthColors: [Color] = []
    ) {
        self.post = post
        self.comment = comment
        self.parents = parents
        self.options = options
        self.colors = colors
        self.postImage = postImage
        self.postImageAspect = postImageAspect
        self.avatars = avatars
        self.commentImages = commentImages
        self.depthColors = depthColors
    }

    /// A small round avatar, or nothing when none was loaded or names
    /// are hidden.
    @ViewBuilder
    private func avatar(_ username: String, size: CGFloat) -> some View {
        if !options.hideUsernames, let image = avatars[username] {
            image.resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }

    /// Explicit colours, never `.primary`/`.secondary`: the exported image
    /// is rendered detached from the window, where those resolve for light
    /// mode regardless of the app, giving dark text on the dark card.
    private var isDark: Bool { colors.mode == .dark }
    private var labelColor: Color {
        colors.color(.label) ?? Color(hex: isDark ? ApolloTextPalette.primaryDark : ApolloTextPalette.primaryLight)
    }
    private var secondaryColor: Color {
        colors.color(.secondaryLabel) ?? Color(hex: isDark ? ApolloTextPalette.secondaryDark : ApolloTextPalette.secondaryLight)
    }

    /// Apollo's card width.
    private static let cardWidth: CGFloat = 320
    private static let cardPadding: CGFloat = 14
    /// The width available to the card's content.
    private var contentWidth: CGFloat { Self.cardWidth - Self.cardPadding * 2 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The post title, always present, even on a comment share,
            // which is what gives a shared comment its context.
            Text(post.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(labelColor)
                .fixedSize(horizontal: false, vertical: true)

            if options.includePostDetails {
                detailsBlock
                    .padding(.top, 10)
            }

            if options.includePostTextPollOrImage {
                if let postImage {
                    // An explicit size, not `.aspectRatio` inside a `maxWidth: .infinity` frame: that
                    // combination proposes an unbounded width to a resizable image and collapses it
                    // to a sliver even with the correct aspect ratio.
                    postImage
                        .resizable()
                        .frame(
                            width: contentWidth,
                            height: contentWidth / max(0.2, postImageAspect ?? 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, 10)
                }
                // The body follows the image, so a post with both keeps
                // its text. Image and gallery posts can carry a body too.
                if let text = Self.bodyText(of: post) {
                    Text(RedditMarkdown.render(text))
                        .font(.system(size: 12))
                        .foregroundStyle(labelColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }

            // Comment separators + parent comments + the shared
            // comment: the hairline under the post details is
            // what visually separates post context from the comment.
            if comment != nil {
                Rectangle()
                    .fill(secondaryColor.opacity(0.25))
                    .frame(height: 0.5)
                    .padding(.top, 10)

                // Nested like the comment tree: each level steps in with
                // its depth colour bar, relative to the first comment shown.
                ForEach(Array(parents.enumerated()), id: \.offset) { index, parent in
                    nested(commentBlock(parent, isParent: true), level: index)
                }
                if let comment {
                    nested(commentBlock(comment, isParent: false), level: parents.count)
                }
            }

            if options.includeWatermark {
                watermark
                    .padding(.top, 12)
            }
        }
        .padding(Self.cardPadding)
        .frame(width: Self.cardWidth, alignment: .leading)
        // The card is darker than the sheet behind it (card #000000 against sheet
        // #202020), so it reads as inset rather than raised.
        .background(colors.color(.background) ?? (isDark ? .black : .white))
        .environment(\.colorScheme, isDark ? .dark : .light)
    }

    /// `in <sub> by <user>` plus the stats line.
    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                if options.hideSubreddit {
                    Text("in ").foregroundStyle(secondaryColor)
                    RedactionBar(width: 54, color: secondaryColor)
                    Text(" by ").foregroundStyle(secondaryColor)
                } else {
                    Text("in \(post.subreddit) by ").foregroundStyle(secondaryColor)
                }
                // Hide Usernames redacts rather than omits: a filled gray bar replaces the name
                // with "in Aww by" still reading normally.
                if options.hideUsernames {
                    RedactionBar(width: 60, color: secondaryColor)
                } else {
                    avatar(post.author, size: 12).padding(.trailing, 3)
                    Text(post.author).foregroundStyle(secondaryColor)
                }
            }
            .font(.system(size: 11))

            HStack(spacing: 8) {
                statistic("arrow.up", ShareCardFormatting.abbreviated(post.score))
                statistic("bubble.right", ShareCardFormatting.abbreviated(post.numComments))
                statistic("clock", ShareCardFormatting.compactAge(since: post.created))
                if let awards = post.totalAwardsReceived, awards > 0 {
                    statistic("rosette", ShareCardFormatting.abbreviated(awards))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(secondaryColor)
        }
    }

    private func statistic(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
            Text(value)
        }
    }

    private func commentBlock(_ comment: RedditComment, isParent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if options.hideUsernames {
                    RedactionBar(width: 52, color: secondaryColor)
                } else {
                    avatar(comment.author, size: 14)
                    Text(comment.author)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryColor)
                }
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text(ShareCardFormatting.abbreviated(comment.score))
                }
                .font(.system(size: 11))
                .foregroundStyle(secondaryColor)
                Spacer()
                Text(ShareCardFormatting.compactAge(since: comment.created))
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryColor)
            }
            // Rendered markdown, not raw source, so a shared comment looks as it does in the
            // app.
            let images = options.includeCommentImages ? (commentImages[comment.id] ?? []) : []
            let body = images.isEmpty ? comment.body : ShareCardFormatting.removingImageOnlyLines(comment.body)
            if !body.isEmpty {
                Text(RedditMarkdown.render(body))
                    .font(.system(size: 12))
                    .foregroundStyle(labelColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                // Explicit size: an unbounded `.fit` frame collapses in the
                // detached export. Capped so a tall image stays reasonable.
                let width = contentWidth - 20
                let height = min(width / max(0.2, image.aspect), 320)
                image.image
                    .resizable()
                    .scaledToFill()
                    .frame(width: height < 320 ? width : 320 * image.aspect, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.top, 2)
            }
        }
        // Parents are dimmed so the shared comment is the one that
        // reads as the subject.
        .opacity(isParent ? 0.65 : 1)
        .padding(.top, 10)
    }

    /// Indents a comment by `level`, with the depth bar colour for that
    /// level, as a reply is drawn in the comment tree.
    @ViewBuilder
    private func nested(_ content: some View, level: Int) -> some View {
        if level == 0 || depthColors.isEmpty {
            content
        } else {
            content
                .padding(.leading, 10)
                // The bar spans exactly the comment's own height.
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(depthColors[level % depthColors.count])
                        .frame(width: 2)
                        .padding(.top, 10)
                }
                .padding(.leading, CGFloat(level - 1) * 10)
        }
    }

    /// The watermark: icon + text.
    private var watermark: some View {
        HStack(spacing: 4) {
            Image(systemName: "app.badge")
                .font(.system(size: 10))
            Text("Phoebus")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(secondaryColor.opacity(0.8))
    }
}

/// The filled bar drawn over a hidden username. Redaction rather than omission
/// keeps the layout intact ("in Aww by ███████") and shows that something was
/// hidden.
struct RedactionBar: View {
    let width: CGFloat
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color.opacity(0.55))
            .frame(width: width, height: 11)
    }
}
