import SwiftUI
import PhoebusCore

/// The Community Highlights carousel (Reborn).
///
/// See `CommunityHighlights` for the constants and rules. Rendered at
/// the top of a subreddit feed, scrolling away with the content like
/// Reborn's table header.
public struct CommunityHighlightsCarousel: View {
    let posts: [RedditPost]
    /// Full-mode scrape results. Empty in Partial mode, or whenever the
    /// scrape did not beat the REST result.
    let scraped: [ScrapedHighlight]
    /// Posts already loaded (the feed and the REST highlights): a scraped
    /// card matching one draws as that post, with its image and counts.
    let knownPosts: [RedditPost]
    let onSelect: (RedditPost) -> Void
    let onSelectScraped: (ScrapedHighlight) -> Void
    /// Which subreddit this carousel belongs to, so its collapsed
    /// state can be remembered per subreddit. Empty disables the
    /// memory (nothing to key on) rather than sharing one global flag.
    let subreddit: String

    /// The user can tap the "Community Highlights" header to collapse the
    /// carousel. Seeded from and written through to
    /// `HighlightsCollapseStore`, not instance-local: a push/pop rebuilds
    /// the feed's row tree, so local state would revert to expanded.
    @State private var collapsed: Bool
    @Environment(\.apolloTheme) private var apolloTheme

    public init(
        posts: [RedditPost],
        scraped: [ScrapedHighlight] = [],
        knownPosts: [RedditPost] = [],
        subreddit: String = "",
        onSelect: @escaping (RedditPost) -> Void,
        onSelectScraped: @escaping (ScrapedHighlight) -> Void = { _ in }
    ) {
        self.posts = posts
        self.scraped = scraped
        self.knownPosts = knownPosts
        self.subreddit = subreddit
        self.onSelect = onSelect
        self.onSelectScraped = onSelectScraped
        _collapsed = State(initialValue: HighlightsCollapseStore.isCollapsed(subreddit))
    }

    private var accent: Color { apolloTheme.color(.accent) ?? .accentColor }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
                // Persist on every toggle so the choice survives the pop that
                // rebuilds this view.
                HighlightsCollapseStore.setCollapsed(collapsed, for: subreddit)
            } label: {
                // Reborn's title row: pin glyph, the title, and a chevron at
                // the trailing edge (up while expanded).
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                    Text(CommunityHighlights.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                // The title row carries the side inset itself. See the
                // note at the end of `body`.
                .padding(.horizontal, CommunityHighlights.Metrics.sidePadding)
                .frame(height: CommunityHighlights.Metrics.titleRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("highlights.header")

            if !collapsed {
                cardStrip
                    .padding(.top, CommunityHighlights.Metrics.topPadding)
                    .padding(.bottom, CommunityHighlights.Metrics.bottomPadding)
            }
        }
        // No horizontal padding on the container: the scroller must run the
        // full width so cards scroll out to the screen edge, so it insets its
        // own content instead. Padding the container too would offset the
        // cards from the title, which carries its own inset above.
    }

    /// The scrolling row of cards, hosted in a real `UIScrollView` with
    /// `isDirectionalLockEnabled` so a drag that starts horizontally can't
    /// turn vertical mid-gesture, which SwiftUI's `ScrollView(.horizontal)`
    /// allows. See `DirectionalLockScrollView`.
    @ViewBuilder
    private var cardStrip: some View {
        let row = HStack(spacing: CommunityHighlights.Metrics.cardSpacing) {
            // Full mode replaces the REST cards wholesale when it found more
            // ("replace, don't merge"): the sets overlap, so showing both would
            // duplicate the stickied posts.
            if scraped.isEmpty {
                ForEach(posts) { post in
                    Button {
                        onSelect(post)
                    } label: {
                        card(for: post)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("highlights.card.\(post.id)")
                }
            } else {
                ForEach(scraped) { highlight in
                    if let post = CommunityHighlights.matchingPost(forPermalink: highlight.permalink, in: knownPosts) {
                        Button {
                            onSelect(post)
                        } label: {
                            card(for: post)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("highlights.card.\(post.id)")
                    } else {
                        Button {
                            onSelectScraped(highlight)
                        } label: {
                            scrapedCard(for: highlight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("highlights.scrapedCard")
                    }
                }
            }
        }
        // The scroller runs full-width; its content carries the side inset so
        // cards scroll out to the screen edge while the first lines up with
        // the title.
        .padding(.horizontal, CommunityHighlights.Metrics.sidePadding)

        #if canImport(UIKit)
        DirectionalLockScrollView(height: CommunityHighlights.Metrics.cardHeight) {
            // Leading, not centred, when the cards are narrower than the screen.
            HStack(spacing: 0) { row; Spacer(minLength: 0) }
        }
        .frame(height: CommunityHighlights.Metrics.cardHeight)
        #else
        ScrollView(.horizontal, showsIndicators: false) { row }
            .frame(height: CommunityHighlights.Metrics.cardHeight)
        #endif
    }

    private func scrapedCard(for highlight: ScrapedHighlight) -> some View {
        // The scrape has no post id, so no read or New state.
        HighlightCard(title: highlight.title, flair: nil, comments: nil,
                      thumbnailURL: highlight.thumbnailURL, isNew: false, isRead: true)
    }

    private func card(for post: RedditPost) -> some View {
        let thumbnail = post.previewImageURL(displayWidth: CommunityHighlights.Metrics.cardWidth)
            ?? post.thumbnail.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }
        return HighlightCard(title: post.title, flair: post.linkFlairText, comments: post.numComments,
                             thumbnailURL: post.spoiler == true ? nil : thumbnail,
                             isNew: CommunityHighlights.isNew(createdAt: post.created),
                             isRead: ReadPostStore.isRead(post.name))
    }
}

/// One highlight card, as in Reborn: the post's image filling the card
/// under a frosted, darkened scrim (a plain 10% fill without one), the
/// title in up to four 13pt semibold lines, the comment count above the
/// flair, and the New pill or unread dot at bottom right. Read cards
/// dim their text.
struct HighlightCard: View {
    let title: String
    let flair: String?
    let comments: Int?
    let thumbnailURL: URL?
    let isNew: Bool
    let isRead: Bool
    @Environment(\.apolloTheme) private var apolloTheme
    @Environment(\.colorScheme) private var colorScheme

    private typealias M = CommunityHighlights.Metrics
    private var accent: Color { apolloTheme.color(.accent) ?? .accentColor }
    private var hasImage: Bool { thumbnailURL != nil }
    private var content: Color {
        hasImage ? Color(white: isRead ? 0.72 : 1) : (isRead ? .secondary : .primary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "bubble.right").font(.system(size: 11))
                Text(comments.map { $0.apolloAbbreviated } ?? "—")
            }
            .font(.system(size: 11.5, weight: .semibold))
            .frame(height: 16)
            HStack(spacing: 6) {
                Text(flair ?? "")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isNew {
                    HStack(spacing: 3) {
                        if !isRead { Circle().fill(Color.black).frame(width: 5, height: 5) }
                        Text(CommunityHighlights.newBadgeText).font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.black)
                    .frame(width: isRead ? 32 : 44, height: 17)
                    .background(RoundedRectangle(cornerRadius: 5).fill(accent))
                    .accessibilityLabel(CommunityHighlights.newAccessibilityDescription)
                } else if !isRead {
                    Circle().fill(accent).frame(width: 7, height: 7).accessibilityLabel("Unread")
                }
            }
            .frame(height: 16)
        }
        .foregroundStyle(content)
        .shadow(color: hasImage ? .black.opacity(0.85) : .clear, radius: 1.5, y: 1)
        .padding(M.cardPadding)
        .frame(width: M.cardWidth, height: M.cardHeight, alignment: .topLeading)
        .background {
            if let thumbnailURL {
                ZStack {
                    Color(white: 0.16)
                    CachedAsyncImage(url: thumbnailURL, contentMode: .fill)
                    Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark).opacity(0.8)
                    LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0),
                                           .init(color: .black.opacity(0.08), location: 0.5),
                                           .init(color: .black.opacity(0.38), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            } else {
                colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: M.cardCornerRadius, style: .continuous))
    }
}

/// Subreddit Layout's preview of the carousel, with Reborn's sample
/// posts: two cards in Partial, six in Full, and a note in Off.
struct CommunityHighlightsPreview: View {
    let mode: SubredditLayoutSettings.CommunityHighlightsMode

    private static let samples: [(String, String, Int, Bool)] = [
        ("Welcome to Apollo Reborn!", "Discussion", 314, false),
        ("v3.0.0 - A new chapter: Apollo Reborn", "Release", 823, true),
        ("Help wanted: Apollo Reborn is looking for artists!", "Discussion", 612, false),
        ("We have flairs! Let us know if you have contributed to Apollo for a special flair!", "Guide", 1219, false),
        ("Thank you to all the developers that keep this going!", "Discussion", 69, false),
        ("FULL DISPLAY SHOWS UP TO 6 COMMUNITY HIGHLIGHTS", "Sneek Peak", 420, false),
    ]

    var body: some View {
        if mode == .off {
            Text("Pinned posts appear normally in the subreddit feed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill").font(.system(size: 11))
                    Text(CommunityHighlights.title).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .frame(height: CommunityHighlights.Metrics.titleRowHeight)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CommunityHighlights.Metrics.cardSpacing) {
                        ForEach(Array(Self.samples.prefix(mode == .partial ? 2 : 6).enumerated()), id: \.offset) { _, s in
                            HighlightCard(title: s.0, flair: s.1, comments: s.2, thumbnailURL: nil,
                                          isNew: s.3, isRead: false)
                        }
                    }
                }
                .padding(.top, CommunityHighlights.Metrics.topPadding)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mode == .partial
                ? "Partial Community Highlights preview with two posts"
                : "Full Community Highlights preview with a carousel")
        }
    }
}


/// Loads a post from its subreddit + id, for links that carry no post
/// object.
///
/// Mirrors `PostLinkLoader` in the app target, which this module can't
/// reach. The post is fetched before presenting because
/// `PostDetailScreen` resolves its initial comment sort from the post
/// when it is created, so it can't start from a placeholder.
public struct PostPermalinkLoader: View {
    let subreddit: String
    let postID: String
    let repository: RedditRepository
    /// Shown while the post is in flight. A scraped card always knows its
    /// title, and showing it keeps the pushed screen identifiable.
    let placeholderTitle: String?

    @State private var post: RedditPost?
    @State private var errorMessage: String?

    public init(
        subreddit: String,
        postID: String,
        repository: RedditRepository,
        placeholderTitle: String? = nil
    ) {
        self.subreddit = subreddit
        self.postID = postID
        self.repository = repository
        self.placeholderTitle = placeholderTitle
    }

    public var body: some View {
        Group {
            if let post {
                PostDetailScreen(post: post, repository: repository)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            } else {
                loadingState
            }
        }
        .task {
            do {
                let data = try await repository.fetchComments(subreddit: subreddit, postID: postID)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                      let listing = json.first as? [String: Any],
                      let listingData = listing["data"] as? [String: Any],
                      let children = listingData["children"] as? [Any],
                      let first = children.first as? [String: Any],
                      let childData = first["data"] as? [String: Any] else {
                    errorMessage = "Couldn't load this post."
                    return
                }
                let payload = try JSONSerialization.data(withJSONObject: childData)
                post = try JSONDecoder.reddit.decode(RedditPost.self, from: payload)
            } catch {
                errorMessage = "Couldn't load this post."
            }
        }
    }

    /// The post's own title, plus a spinner, under a real navigation
    /// title - so the push looks like it went somewhere.
    @ViewBuilder
    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let placeholderTitle, !placeholderTitle.isEmpty {
                Text(placeholderTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading post\u{2026}")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("r/\(subreddit)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
