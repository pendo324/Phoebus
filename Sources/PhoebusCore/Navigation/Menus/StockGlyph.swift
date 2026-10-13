import Foundation

/// How each named interface glyph is drawn.
///
/// The names are Apollo's asset names (`posts-points`, `slide-save-hollow`,
/// `option-sort-top`), kept so call sites say which Apollo glyph they stand
/// in for. None of Apollo's artwork is shipped: most glyphs are SF Symbols,
/// a few are open-source kit icons bundled as vector PDFs in
/// `Resources/Glyphs` (licences in `Resources/Glyphs/LICENSES.md`), and the
/// rest are drawn in code.
///
/// `frame` is the slot Apollo's glyph occupied, so rows keep their layout.
/// Symbol point sizes fit each symbol's ink to Apollo's ink box at that
/// frame; a caller that passes another size scales the whole glyph.
public enum StockGlyph {
    public enum Weight: Sendable {
        case thin, light, regular, semibold, bold
    }

    /// Glyphs drawn in code from SF Symbols, paths and text.
    public enum Composition: Sendable, CaseIterable {
        /// `arrow.up` / `arrow.down` with a slash cut like SF's `.slash`
        /// variants: un-upvote and un-downvote.
        case slashedUpArrow, slashedDownArrow
        /// `bubble` with a `chevron.up` inside: jump to the parent comment.
        case parentComment
        /// `chevron.up` under a bar: collapse to the root comment.
        case collapseToRoot
        /// `eye` under a `chevron.up` and a bar: hide the posts above.
        case hideAbove
        /// `circle.fill` with a lower-case m knocked out.
        case multireddit
        /// `book.closed.fill` with an outlined serif W knocked out.
        case subredditWiki
        /// A smiling face on SF `circle`: the upvote ratio. iOS 26 draws SF
        /// `face.smiling` filled, so the face is drawn in code.
        case smiley
        /// A tag outline around a lower-case r: a subreddit.
        case subredditTag
        /// The same tag filled, with the r knocked out.
        case subredditTagSolid
    }

    public indirect enum Recipe: Equatable, Sendable {
        /// An SF Symbol, centred in the frame.
        case symbol(String, size: Double, weight: Weight, rotation: Double = 0)
        /// A vector PDF in `Resources/Glyphs`, fitted into an `ink` box
        /// centred in the frame.
        case asset(String, ink: CGSize)
        /// Drawn in code; `size` is the base symbol's point size, or the
        /// tag's side for the subreddit tags.
        case composed(Composition, size: Double)
        /// A string drawn as a glyph.
        case text(String, size: Double, weight: Weight, rounded: Bool)
        /// One of the Subreddits list's feed badges: a white glyph centred on
        /// a full-colour disc.
        case orb(Recipe, rgb: UInt32)
    }

    public struct Glyph: Equatable, Sendable {
        public let frame: CGSize
        public let recipe: Recipe

        init(_ width: Double, _ height: Double, _ recipe: Recipe) {
            self.frame = CGSize(width: width, height: height)
            self.recipe = recipe
        }

        /// Full-colour artwork rather than a tintable template.
        public var isColored: Bool {
            if case .orb = recipe { return true }
            return false
        }
    }

    /// The bundle subdirectory holding the vector assets.
    public static let assetDirectory = "Glyphs"

    public static func glyph(_ name: String) -> Glyph? { table[name] }

    /// Every glyph name.
    public static var names: [String] { table.keys.sorted() }

    /// The PDFs (without extension) the recipes draw from `assetDirectory`.
    public static var assetNames: Set<String> {
        Set(table.values.flatMap { assets(in: $0.recipe) })
    }

    private static func assets(in recipe: Recipe) -> [String] {
        switch recipe {
        case .asset(let name, _): return [name]
        case .orb(let inner, _): return assets(in: inner)
        default: return []
        }
    }

    private static let table: [String: Glyph] = [
        // Tab bar.
        "tab-bar-posts": .init(20, 24, .symbol("doc.text", size: 21, weight: .light)),
        "tab-bar-inbox": .init(26, 17, .symbol("envelope", size: 22, weight: .light)),
        "tab-bar-profile": .init(25, 25, .symbol("person.crop.circle", size: 22, weight: .light)),
        "tab-bar-search": .init(23, 24, .symbol("magnifyingglass", size: 21.5, weight: .light)),
        "tab-bar-settings": .init(26, 26, .symbol("gear", size: 23, weight: .light)),

        // Subreddits list feed badges, in Apollo's orb colours.
        "orb-home": .init(28, 28, .orb(.symbol("house.fill", size: 15, weight: .regular), rgb: 0xFF0062)),
        "orb-popular": .init(28, 28, .orb(.symbol("chart.line.uptrend.xyaxis", size: 15, weight: .regular), rgb: 0x008FFD)),
        "orb-all": .init(28, 28, .orb(.symbol("tray.and.arrow.up.fill", size: 15, weight: .regular), rgb: 0x00D633)),
        "orb-moderator": .init(28, 28, .orb(.asset("tabler-shield-star-orb", ink: CGSize(width: 16, height: 16)), rgb: 0x535353)),

        // Post info row and comment byline.
        "posts-points": .init(10, 12.01, .symbol("arrow.up", size: 10.5, weight: .regular)),
        "posts-comments": .init(14, 13, .symbol("bubble", size: 13, weight: .regular)),
        "posts-clock": .init(13, 13, .symbol("clock", size: 11.5, weight: .regular)),
        "posts-liked": .init(13, 13, .composed(.smiley, size: 11.5)),
        "inline-upvote": .init(14.75, 18.19, .symbol("arrow.up", size: 15.5, weight: .regular)),
        "inline-downvote": .init(14.75, 18.19, .symbol("arrow.down", size: 15.5, weight: .regular)),
        "inline-more-options": .init(18, 4, .symbol("ellipsis", size: 15, weight: .bold)),
        "inline-sticky": .init(12, 18, .symbol("pin.fill", size: 13.5, weight: .regular)),
        "inline-locked": .init(11, 14, .symbol("lock.fill", size: 12, weight: .regular)),

        // Post detail quick bar.
        "option-upvote": .init(19, 24, .symbol("arrow.up", size: 20.5, weight: .light)),
        "option-downvote": .init(19, 24, .symbol("arrow.down", size: 20.5, weight: .light)),
        "option-save": .init(16, 21.79822, .symbol("bookmark", size: 19, weight: .light)),
        "option-reply": .init(24.9635, 21.23779, .symbol("arrowshape.turn.up.left", size: 22, weight: .light)),
        "option-share": .init(20, 26, .symbol("square.and.arrow.up", size: 22.5, weight: .light)),

        // Row swipe actions.
        "slide-upvote-hollow": .init(34, 30, .symbol("arrow.up", size: 21.5, weight: .light)),
        "slide-unupvote-hollow": .init(34, 30, .composed(.slashedUpArrow, size: 21.5)),
        "slide-downvote-hollow": .init(34, 30, .symbol("arrow.down", size: 21.5, weight: .light)),
        "slide-undownvote-hollow": .init(34, 30, .composed(.slashedDownArrow, size: 21.5)),
        "slide-save-hollow": .init(34, 30, .symbol("bookmark", size: 21, weight: .light)),
        "slide-unsave-hollow": .init(34, 30, .symbol("bookmark.slash", size: 21, weight: .light)),
        "slide-reply-solid": .init(34, 30, .symbol("arrowshape.turn.up.left.fill", size: 23, weight: .regular)),
        "slide-share-hollow": .init(34, 30, .symbol("square.and.arrow.up", size: 25, weight: .light)),
        "slide-hide-hollow": .init(34, 30, .symbol("eye.slash", size: 25.5, weight: .light)),
        "slide-collapse-hollow": .init(34, 30, .symbol("chevron.up", size: 21.5, weight: .light)),
        "slide-collapse-root-hollow": .init(34, 30, .composed(.collapseToRoot, size: 24)),
        "slide-read-hollow": .init(34, 30, .symbol("envelope.open", size: 28.5, weight: .light)),
        "slide-unread-hollow": .init(34, 30, .symbol("envelope.badge", size: 28, weight: .light)),
        "slide-author-hollow": .init(34, 30, .symbol("person.crop.circle", size: 22, weight: .light)),
        "slide-hide-above-hollow": .init(34, 30, .composed(.hideAbove, size: 22)),
        "slide-parent-comment-hollow": .init(34, 30, .composed(.parentComment, size: 23)),
        "slide-select-mode-hollow": .init(34, 30, .symbol("selection.pin.in.out", size: 24.5, weight: .light)),
        "slide-subreddit-hollow": .init(34, 30, .composed(.subredditTag, size: 26)),

        // Sort menu and the nav-bar sort button.
        "option-sort-best": .init(24.51562, 24, .symbol("trophy", size: 21, weight: .light)),
        "option-sort-hot": .init(21, 27, .symbol("flame", size: 23, weight: .light)),
        "option-sort-new": .init(24, 24, .symbol("clock", size: 21, weight: .light)),
        "option-sort-top": .init(29, 21, .asset("lucide-arrow-up-wide-narrow", ink: CGSize(width: 28, height: 19.5))),
        "option-sort-rising": .init(28, 24, .symbol("chart.line.uptrend.xyaxis", size: 25.5, weight: .light)),
        "option-sort-controversial": .init(25, 22, .asset("lucide-swords", ink: CGSize(width: 24, height: 21.5))),
        "option-more": .init(25, 7, .symbol("ellipsis", size: 22, weight: .regular)),

        // Inbox boxes, menus and profile rows.
        "option-inbox": .init(23, 21, .symbol("tray", size: 21, weight: .light)),
        "option-unread-box": .init(20, 20, .symbol("circle", size: 17.5, weight: .light)),
        "option-posts": .init(21, 25, .symbol("doc.text", size: 22, weight: .light)),
        "option-comments": .init(24, 22, .symbol("bubble", size: 22, weight: .light)),
        "option-author": .init(24, 24, .symbol("person.crop.circle", size: 21, weight: .light)),
        "option-mail": .init(26, 17, .symbol("envelope", size: 22, weight: .light)),
        "option-moderator": .init(29, 27, .asset("tabler-shield-star", ink: CGSize(width: 23, height: 25.5))),
        "option-mark-all-read": .init(27, 19, .asset("phosphor-checks", ink: CGSize(width: 27, height: 17.5))),
        "option-hide-read": .init(32, 22, .symbol("eye.slash", size: 26.5, weight: .light)),
        "option-friends": .init(28, 27, .symbol("person.2", size: 24.5, weight: .light)),
        "option-hide": .init(28, 21, .symbol("eye.slash", size: 23.5, weight: .light)),
        "option-trophy": .init(24.67, 24, .symbol("trophy", size: 21, weight: .light)),

        // Comment composer toolbar and its More menu.
        "option-bold": .init(15, 21, .asset("lucide-bold", ink: CGSize(width: 14, height: 20))),
        "option-italic": .init(12, 21, .asset("lucide-italic", ink: CGSize(width: 12, height: 20.5))),
        "option-link": .init(28, 28, .symbol("link", size: 20.5, weight: .regular)),
        "option-photo": .init(26, 21, .symbol("photo", size: 23.5, weight: .regular)),
        "option-subreddit": .init(25, 25, .composed(.subredditTag, size: 24.5)),
        "option-code": .init(32, 21, .symbol("chevron.left.forwardslash.chevron.right", size: 23, weight: .regular)),
        "option-header": .init(15, 21, .asset("lucide-heading", ink: CGSize(width: 15, height: 21))),
        "option-horizontal-rule": .init(27, 2, .symbol("minus", size: 36, weight: .thin)),
        "option-ordered-list": .init(23, 22, .symbol("list.number", size: 21.5, weight: .regular)),
        "option-unordered-list": .init(22, 20, .symbol("list.bullet", size: 21, weight: .regular)),
        "option-preview": .init(28, 23, .symbol("doc.text.magnifyingglass", size: 20.5, weight: .regular)),
        "option-quote": .init(29, 22, .asset("lucide-quote", ink: CGSize(width: 28.5, height: 20.5))),
        "option-spoiler": .init(30, 29, .symbol("exclamationmark.bubble", size: 24, weight: .regular)),
        "option-spongetext": .init(24, 20, .text("aAa", size: 15, weight: .light, rounded: true)),
        "option-strikethrough": .init(21, 23, .symbol("strikethrough", size: 25, weight: .regular)),
        "option-superscript": .init(27, 22, .symbol("textformat.superscript", size: 19, weight: .regular)),
        "option-text-faces": .init(30, 18, .text("ಠ_ಠ", size: 17, weight: .regular, rounded: false)),

        // Link buttons under comments and self posts.
        "link-button-message": .init(30, 20, .symbol("envelope.fill", size: 25.5, weight: .regular)),
        "link-button-multireddit": .init(30, 30, .composed(.multireddit, size: 26.5)),
        "link-button-profile": .init(30, 30, .symbol("person.crop.circle", size: 26.5, weight: .regular)),
        "link-button-reddit": .init(36, 31, .asset("phosphor-reddit-logo-light", ink: CGSize(width: 34.5, height: 30))),
        "link-button-safari": .init(30, 30, .symbol("location.north.circle.fill", size: 26.5, weight: .regular)),
        "link-button-search": .init(27.67, 28, .symbol("magnifyingglass", size: 25.5, weight: .regular)),
        "link-button-subreddit": .init(28, 28, .composed(.subredditTagSolid, size: 27.5)),
        "link-button-subreddit-wiki": .init(25, 29, .composed(.subredditWiki, size: 25)),
        "link-button-twitter": .init(30, 25, .asset("fontawesome-twitter", ink: CGSize(width: 29, height: 25))),
        "link-button-wikipedia": .init(33, 21, .asset("simpleicons-wikipedia", ink: CGSize(width: 33, height: 21))),
        "link-button-xkcd": .init(27, 29, .symbol("figure.2", size: 23, weight: .regular)),

        // Inbox row type glyphs.
        "inbox-comment-type-comment-reply": .init(15, 15, .symbol("bubble.fill", size: 14, weight: .regular)),
        "inbox-comment-type-message": .init(17, 11, .symbol("envelope.fill", size: 14, weight: .regular)),
        "inbox-comment-type-post-reply": .init(13, 16, .symbol("doc.text.fill", size: 13.5, weight: .regular)),
        "inbox-comment-type-username-mention": .init(16, 16, .symbol("person.crop.circle.fill", size: 14, weight: .regular)),
        "inbox-highlighted": .init(13, 17, .symbol("exclamationmark.shield.fill", size: 13.5, weight: .regular)),

        // Automatic theme brightness slider.
        "low-brightness": .init(17, 17, .symbol("sun.min", size: 15, weight: .regular)),
        "high-brightness": .init(24, 24, .symbol("sun.max.fill", size: 21, weight: .regular)),
        "brightness-pin": .init(12, 17, .symbol("drop.fill", size: 14.5, weight: .regular, rotation: 180)),

        // Feed rows and chrome.
        "self-post-indicator": .init(28, 26, .symbol("text.aligncenter", size: 26, weight: .regular)),
        "hide-read-posts-button-eye": .init(48, 48, .symbol("eye.slash", size: 23.5, weight: .regular)),
        "crosspost": .init(15, 17, .symbol("arrow.triangle.branch", size: 14.5, weight: .regular, rotation: 90)),
        "crosspost-small": .init(11.67, 13.67, .symbol("arrow.triangle.branch", size: 11, weight: .regular, rotation: 90)),
        "safari-vc-comments": .init(25, 23, .symbol("bubble", size: 23, weight: .light)),
    ]
}
