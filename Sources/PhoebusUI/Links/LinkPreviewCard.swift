import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Which surface a `LinkPreviewCard` is rendering into — a post's own
/// top-level link or a link in a self post (`.body`), or a link in a
/// comment (`.comments`). Reborn configures these independently.
public enum LinkPreviewContext: Sendable {
    case body
    case comments
}

/// Rich Link Previews: one card for every link. `LinkPreviewFetcher`
/// resolves the link into a `LinkPreview`; the layout follows from its
/// kind and the area's mode (Off / Compact / Full):
///
/// - Off, or nothing to show: Apollo's link button (type icon, address,
///   chevron).
/// - Ordinary links: Reborn's compact card, or its full card when the
///   link has an image (a full card without one is drawn compact).
/// - Reddit profiles and subreddits: Reborn's avatar card, either mode.
/// - Bluesky and X posts: a post card, compact or full.
///
/// Long-press is iOS's own link preview with Apollo's actions
/// (`LinkMenuOverlay`); a tap opens the link.
public struct LinkPreviewCard: View {
    let url: URL
    let context: LinkPreviewContext
    /// Reddit's own preview of the link, used when the page gives no
    /// image or cannot be scraped (bot walls, AMP redirects).
    let fallbackImageURL: URL?
    /// The post title, standing in for a page title that cannot be read.
    let fallbackTitle: String?
    /// Comments with more than one link show every card compact,
    /// Bluesky and X posts included (Reborn keeps its Bluesky card full).
    let forceCompact: Bool
    /// What a tap does; the app's link handling when nil.
    let onOpen: (() -> Void)?

    @Setting(LinkPreviewSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var preview: LinkPreview?
    @State private var loaded = false

    public init(url: URL, context: LinkPreviewContext = .body,
                fallbackImageURL: URL? = nil, fallbackTitle: String? = nil,
                forceCompact: Bool = false, onOpen: (() -> Void)? = nil) {
        self.url = url
        self.context = context
        self.fallbackImageURL = fallbackImageURL
        self.fallbackTitle = fallbackTitle
        self.forceCompact = forceCompact
        self.onOpen = onOpen
    }

    private var mode: LinkPreviewDisplayMode {
        context == .body ? settings.bodyDisplayMode : settings.commentsDisplayMode
    }

    /// The fetched preview, with Reddit's image filling a missing one; or,
    /// when the page gave nothing, a card from Reddit's data alone.
    private var effectivePreview: LinkPreview? {
        if var preview {
            if preview.kind == .standard, preview.imageURL == nil, let fallbackImageURL {
                preview.imageURL = fallbackImageURL
            }
            return preview
        }
        guard loaded, fallbackImageURL != nil || fallbackTitle != nil else { return nil }
        return LinkPreview(siteName: LinkPreviewHosts.displayHost(url), title: fallbackTitle, imageURL: fallbackImageURL)
    }

    private var layout: LinkPreviewCardContent.Layout {
        switch effectivePreview?.kind ?? .standard {
        case .redditUser, .redditSubreddit: return .profile
        case .socialPost: return mode == .full && !forceCompact ? .postFull : .postCompact
        case .standard: return mode == .full && !forceCompact && effectivePreview?.imageURL != nil ? .full : .compact
        }
    }

    public var body: some View {
        Group {
            if mode == .off {
                ApolloLinkButton(url: url)
            } else if let preview = effectivePreview {
                LinkPreviewCardContent(preview: preview, url: url, layout: layout, cardColorHex: settings.cardColorHex)
            } else if loaded {
                ApolloLinkButton(url: url)
            } else {
                LinkPreviewCardContent(preview: LinkPreview(siteName: LinkPreviewHosts.displayHost(url),
                                                            title: "Loading the link's preview",
                                                            description: "A line of description"),
                                       url: url, layout: .compact, cardColorHex: settings.cardColorHex)
                    .redacted(reason: .placeholder)
            }
        }
        .task(id: "\(url.absoluteString)|\(mode.rawValue)|\(settings.twitterFallback.rawValue)") {
            guard mode != .off else { return }
            let cached = await LinkPreviewCache.shared.cached(for: url)
            if cached.isKnown {
                preview = cached.preview
            } else {
                preview = await LinkPreviewFetcher.preview(for: url, twitterFallback: settings.twitterFallback)
            }
            loaded = true
        }
        // Apollo's long-press on a link card: iOS's link preview with Copy Link,
        // Share…, Open in Safari. It also takes the tap, which opens the link.
        #if canImport(UIKit)
        .overlay {
            LinkMenuOverlay(url: url) {
                if let onOpen { onOpen() } else { openURL(url) }
            }
        }
        #endif
    }
}

/// Draws a `LinkPreview` in one of the card layouts, following Reborn's
/// card specs.
struct LinkPreviewCardContent: View {
    enum Layout {
        /// 84pt image left of the site name, title and description.
        case compact
        /// Image on top, then the site name, a larger title, one line.
        case full
        /// 44pt round avatar beside name, handle and about text.
        case profile
        /// Author row and post text beside an 84pt image.
        case postCompact
        /// The post's image on top, then the author row and the full text.
        case postFull
    }

    let preview: LinkPreview
    let url: URL
    let layout: Layout
    let cardColorHex: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch layout {
            case .compact: compact
            case .full: full
            case .profile: profile
            case .postCompact: postCompact
            case .postFull: postFull
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var palette: LinkCardPalette { LinkCardPalette(cardColorHex: cardColorHex, colorScheme: colorScheme) }
    private var title: String? { LinkPreviewRules.displayTitle(preview.title, url: url) }
    private var siteName: String { (preview.siteName ?? LinkPreviewHosts.displayHost(url)).uppercased() }

    private func image(_ url: URL?, width: CGFloat, height: CGFloat, corner: CGFloat) -> some View {
        CachedAsyncImage(url: url, contentMode: .fill)
            .frame(width: width, height: height)
            .background(palette.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }

    private func avatar(_ url: URL?, size: CGFloat) -> some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, contentMode: .fill)
            } else {
                palette.secondary.opacity(0.25)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// Reborn's compact card: 10pt in all round, 84pt image with 8pt
    /// corners, 10pt to the text; site 11pt semibold caps, title 15pt
    /// semibold over two lines, then 13pt description, 3pt apart.
    private var compact: some View {
        HStack(alignment: .top, spacing: 10) {
            if let imageURL = preview.imageURL {
                image(imageURL, width: 84, height: 84, corner: 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(siteName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                if let title {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(2)
                }
                let lines = LinkPreviewRules.compactDescriptionLines(titleLength: title?.count ?? 0)
                if lines > 0, let description = preview.description {
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(lines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
    }

    /// Reborn's full card: the image (16:9 for YouTube, otherwise its own
    /// shape held to 0.45–0.6 tall), then 9/12/11pt-inset text 4pt apart:
    /// site 11pt, title 17pt semibold over two lines, one 13pt line.
    private var full: some View {
        let shape = LinkPreviewRules.fullImageAspect(for: url, preview: preview)
        let youTube = LinkPreviewHosts.isYouTube(url)
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1 / shape.ratio, contentMode: .fit)
                .overlay {
                    CachedAsyncImage(url: preview.imageURL, contentMode: shape.fits ? .fit : .fill)
                }
                .background(palette.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(siteName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                if let title {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(2)
                }
                if LinkPreviewRules.fullDescriptionLines(titleLength: title?.count ?? 0) > 0,
                   let description = preview.description {
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(EdgeInsets(top: youTube ? 8 : 9, leading: 12, bottom: youTube ? 10 : 11, trailing: 12))
        }
    }

    /// Reborn's profile and subreddit card: 44pt round avatar, 10pt to a
    /// 15pt semibold name, the 12pt handle (with the member count for a
    /// subreddit), and two 13pt lines of about text, 2pt apart.
    private var profile: some View {
        let handle = [preview.authorHandle, preview.members].compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: 10) {
            avatar(preview.avatarURL ?? preview.imageURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.authorName ?? title ?? handle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                if !handle.isEmpty {
                    Text(handle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                if let about = preview.description, about != handle {
                    Text(about)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
    }

    private var postBody: String? {
        let text = (preview.postText ?? preview.description)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// A compact post: the compact card's frame and 84pt image, with a
    /// one-line author row (20pt avatar, name, handle) over three lines
    /// of post text.
    private var postCompact: some View {
        HStack(alignment: .top, spacing: 10) {
            if let imageURL = preview.imageURL {
                image(imageURL, width: 84, height: 84, corner: 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    avatar(preview.avatarURL, size: 20)
                    Text(preview.authorName ?? preview.authorHandle ?? siteName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if preview.authorName != nil, let handle = preview.authorHandle {
                        Text(handle)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                }
                if let postBody {
                    Text(postBody)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.primary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
    }

    /// Reborn's Bluesky card: the post image (0.45–0.75 tall) on top,
    /// then, inset 11/12/12pt, a 36pt avatar 9pt from the 15pt semibold
    /// name over the 13pt handle, and 9pt below the whole post in 15pt.
    private var postFull: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL = preview.imageURL {
                Color.clear
                    .aspectRatio(1 / LinkPreviewRules.postImageAspect(preview), contentMode: .fit)
                    .overlay { CachedAsyncImage(url: imageURL, contentMode: .fill) }
                    .background(palette.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 9) {
                    avatar(preview.avatarURL, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preview.authorName ?? preview.authorHandle ?? siteName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                        if let handle = preview.authorHandle {
                            Text(handle)
                                .font(.system(size: 13))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                if let postBody {
                    Text(postBody)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EdgeInsets(top: 11, leading: 12, bottom: 12, trailing: 12))
        }
    }
}

/// A card's fill and text colours. Default is Reborn's neutral card
/// (0.72 grey at 14% over the secondary background in dark, 8% over white
/// in light: #333333 / #F9F9F9) with the system label colours. A custom
/// colour fills the card exactly, with black or white text for contrast.
struct LinkCardPalette {
    let background: Color
    let primary: Color
    let secondary: Color

    init(cardColorHex: String?, colorScheme: ColorScheme) {
        if let cardColorHex, !cardColorHex.isEmpty {
            let light = HexContrast.needsDarkText(onHex: cardColorHex)
            let ink: Color = light ? .black : .white
            background = Color(hex: cardColorHex)
            primary = ink
            secondary = ink.opacity(light ? 0.62 : 0.78)
        } else {
            background = colorScheme == .dark ? Color(hex: "333333") : Color(hex: "F9F9F9")
            primary = .primary
            secondary = .secondary
        }
    }
}

/// Apollo's own link button, shown when previews are Off or a link has
/// nothing to preview: a 49pt #1A1A1A bar with the link type's icon in a
/// 50pt column, a hairline, then the host in grey and the rest of the
/// address darker, and a chevron.
struct ApolloLinkButton: View {
    let url: URL

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private var path: String {
        var rest = url.path
        if let query = url.query { rest += "?" + query }
        return rest == "/" ? "" : rest
    }

    var body: some View {
        HStack(spacing: 0) {
            StockPNG.image(LinkButtonIcon.forURL(url).rawValue)
                .foregroundStyle(Color(hex: colorScheme == .dark ? "75787F" : "9A9DA3"))
                .frame(width: 50)
            Rectangle()
                .fill(Color.apolloSeparator(colorScheme: colorScheme))
                .frame(width: 1 / displayScale)
                .padding(.vertical, 7)
            (Text(LinkPreviewHosts.displayHost(url))
                .foregroundColor(Color.apolloSecondaryText(colorScheme: colorScheme))
             + Text(path)
                .foregroundColor(Color.apolloTertiaryText(colorScheme: colorScheme)))
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 12)
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.apolloTertiaryText(colorScheme: colorScheme))
                .padding(.trailing, 11)
        }
        .frame(height: 49)
        .frame(maxWidth: .infinity)
        .background(Color.apolloFlairFill(colorScheme: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Apollo's template PNGs in `StockIcons`, at their own point size.
enum StockPNG {
    static func image(_ name: String) -> Image {
        #if canImport(UIKit)
        if let url = Bundle.module.url(forResource: "\(name)@3x", withExtension: "png", subdirectory: "StockIcons"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data, scale: 3) {
            return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
        }
        #endif
        return Image(systemName: "safari")
    }
}
