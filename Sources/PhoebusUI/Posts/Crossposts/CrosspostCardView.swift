import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Apollo's crosspost node, the original post a crosspost carries:
///
/// - `.card` (post screen, Large rows): a #1A1A1A card with 12pt corners
///   and 16pt padding; the original's title in 15pt with its flair, three
///   lines of its body in grey, then the crosspost glyph, the
///   subreddit's icon and name, points and comments.
/// - `.chip` (Compact rows, under the info row): a 31pt pill with the
///   glyph, subreddit, points and comments in the info row's type.
///
/// Tapping opens the original; a long press previews its thread with
/// Apollo's post actions.
struct CrosspostCardView: View {
    enum Style { case card, chip }

    let parent: RedditCrosspostParent
    var style: Style = .card
    let repository: RedditRepository

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme

    var body: some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: style == .card ? 12 : 8, style: .continuous))
            .highPriorityGesture(TapGesture().onEnded { open() })
            .contextMenu { menu } preview: { preview }
            // The menu's rows in the label colour, as Apollo's.
            .tint(Color.primary)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the original post in r/\(parent.subreddit)")
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .card: card
        case .chip: chip
        }
    }

    private var fill: Color {
        colorScheme == .dark ? Color(hex: "1A1A1A") : Color(hex: "EEEEEF")
    }

    private var secondary: Color {
        Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleText
                .apolloFont(size: 15)
                .lineSpacing(2)
                .foregroundStyle(colorScheme == .dark ? Color(hex: "D5D5D5") : Color.primary)
            if let excerpt {
                Text(excerpt)
                    .apolloFont(size: 15)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .foregroundStyle(secondary)
                    .padding(.top, 12)
            }
            HStack(spacing: 0) {
                StockPNG.image("crosspost")
                    .padding(.trailing, 7)
                SubredditIconView(subreddit: parent.subreddit, repository: repository, size: 24)
                    .padding(.trailing, 10)
                Text(SubredditCapitalization.display(parent.subreddit))
                    .lineLimit(1)
                    .padding(.trailing, 8)
                stats
            }
            .apolloFont(size: 15)
            .foregroundStyle(secondary)
            .padding(.top, excerpt == nil ? 12 : 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
    }

    private var chip: some View {
        HStack(spacing: 0) {
            StockPNG.image("crosspost-small")
                .padding(.trailing, 8)
            Text(SubredditCapitalization.display(parent.subreddit))
                .lineLimit(1)
                .padding(.trailing, 8)
            stats
        }
        .apolloFont(size: 13)
        .foregroundStyle(secondary)
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
    }

    /// Points and comments, as the info row draws them.
    private var stats: some View {
        HStack(spacing: 4) {
            StockIcon("posts-points")
            Text(parent.score.apolloAbbreviated)
                .padding(.trailing, 5)
            StockIcon("posts-comments")
            Text(parent.numComments.apolloAbbreviated)
        }
        .lineLimit(1)
    }

    /// The title with its flair in grey after it.
    private var titleText: Text {
        var text = Text(titlePrefix + OpenGraphParser.decodeHTMLEntities(parent.title))
        if let flair = parent.linkFlairText?.trimmingCharacters(in: .whitespaces), !flair.isEmpty {
            text = text + Text("  " + flair).font(.system(size: 13)).foregroundColor(secondary)
        }
        return text
    }

    /// The body flattened to one paragraph, as Apollo's three-line excerpt.
    private var excerpt: String? {
        // Reddit escapes entities in `selftext` ("&#x200B;" for an empty
        // paragraph).
        guard let raw = parent.selftext else { return nil }
        let body = OpenGraphParser.decodeHTMLEntities(raw).replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return body.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var titlePrefix: String {
        if parent.over18 && parent.spoiler { return "Not safe for work and spoiler " }
        if parent.over18 { return "Not safe for work " }
        return ""
    }

    private var permalinkURL: URL? {
        URL(string: "https://www.reddit.com" + parent.permalink)
    }

    private func open() {
        RedditLinkNavigator.open(.post(subreddit: parent.subreddit, id: parent.id))
    }

    // MARK: - Long press

    /// The original's thread, as Apollo previews it.
    @ViewBuilder
    private var preview: some View {
        NavigationStack {
            CommentTreeScreen(subreddit: parent.subreddit, postID: parent.id, repository: repository)
                .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.isContextMenuPreview, true)
        .frame(width: 360, height: 520)
    }

    /// Apollo's crosspost menu: author, subreddit, Share, Share as Image…,
    /// Give Award, Report.
    @ViewBuilder
    private var menu: some View {
        if !parent.author.isEmpty, parent.author != "[deleted]" {
            Button {
                RedditLinkNavigator.open(.user(parent.author))
            } label: {
                Label { Text(parent.author) } icon: { StockIcon("option-author") }
            }
        }
        Button {
            RedditLinkNavigator.open(.subreddit(parent.subreddit))
        } label: {
            Label(SubredditCapitalization.display(parent.subreddit), systemImage: "tag")
        }
        if let permalinkURL {
            ShareLink(item: permalinkURL) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        do {
            let repository = repository
            Button {
                let parent = parent
                Task {
                    guard let post = try? await repository.fetchPost(subreddit: parent.subreddit, postID: parent.id) else { return }
                    RootSheet.present { ShareAsImageScreen(post: post, repository: repository) }
                }
            } label: {
                Label("Share as Image…", systemImage: "photo.on.rectangle")
            }
            Button {
                RootSheet.present { dismiss in
                    AwardGiftingScreen(fullname: parent.name, repository: repository) { dismiss() }
                }
            } label: {
                Label("Give Award", systemImage: "medal")
            }
            Button(role: .destructive) {
                RootSheet.present { dismiss in
                    ReportSheet(fullname: parent.name, repository: repository) { dismiss() }
                }
            } label: {
                Label("Report", systemImage: "flag")
            }
        }
    }
}

/// A sheet from the frontmost screen, for menus inside list rows, where a
/// `.sheet` attached to the row doesn't present.
@MainActor
enum RootSheet {
    static func present<Content: View>(@ViewBuilder _ content: @escaping (_ dismiss: @escaping () -> Void) -> Content) {
        #if canImport(UIKit)
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        weak var hosting: UIViewController?
        let controller = UIHostingController(rootView: content { hosting?.dismiss(animated: true) })
        hosting = controller
        top.present(controller, animated: true)
        #endif
    }

    static func present<Content: View>(@ViewBuilder _ content: @escaping () -> Content) {
        present { _ in content() }
    }
}
