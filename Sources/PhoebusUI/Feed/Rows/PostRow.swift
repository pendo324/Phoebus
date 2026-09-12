import SwiftUI
import PhoebusCore

struct PostRow: View {
    /// "Translate Post Titles" result for this row, nil when off or
    /// pending (see `TitleTranslation`).
    @State var translatedTitle: String?
    let post: RedditPost
    let repository: RedditRepository
    /// Passed explicitly from `FeedScreen` rather than re-read
    /// internally, so SwiftUI re-renders already-visible rows when
    /// the toolbar display-style toggle flips.
    let displayStyle: PostDisplayStyle
    /// True on the aggregate feeds (Home/Popular/All) and other mixed
    /// listings, where the real cell shows the subreddit's icon.
    var isAggregateFeed: Bool = true
    /// Apollo navigates to a post's subreddit when its name is tapped
    /// in a feed row rather than opening the post. Lets the subreddit
    /// label opt out of the shared row tap target with its own nested
    /// `Button`.
    let onSubredditTap: () -> Void
    /// Same behavior for tapping a post's author name: navigates to
    /// that user's profile instead of opening the post.
    let onAuthorTap: () -> Void
    /// Reborn Info Row tap actions: tapping the comments count opens
    /// the post scrolled to comments when `InfoRowSettings.tapToComments`
    /// is on. `nil` preserves the default whole-row tap-to-open.
    var onCommentsTap: (() -> Void)?
    /// Info Row "Translation" marker action - see the 🌐 marker
    /// in the stats row.
    var onTranslateTap: (() -> Void)?
    /// The post's action menu, opened by the row's •••. Nil leaves the •••
    /// decorative (screens without a post menu).
    var moreMenu: (() -> AnyView)?
    /// Vote state comes from the shared store, NOT from private
    /// `@State`, so a swipe-to-vote gesture handled by the parent can
    /// update the arrow highlight and score too. See `VoteStateStore`.
    @ObservedObject var voteStore = VoteStateStore.shared
    /// Read state, refreshed when this post is marked read elsewhere
    /// (opening it), so the row dims on return without a reload.
    @State var isRead = false
    @Environment(\.colorScheme) var colorScheme
    /// Scales the measured 15pt title with Dynamic Type (`apolloFont`).
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.apolloTheme) var themeColors

    var voteState: Bool? { voteStore.vote(for: post.name, serverValue: post.likes) }
    var displayScore: Int { post.score + voteStore.scoreDelta(for: post.name) }
    @State var ageDetail: AgeDetail?
    @State var ageOverlay: AgeDetail?

    struct AgeDetail: Identifiable {
        let id = UUID()
        let title: String
        let message: String?
    }
    /// Drives the fullscreen pager for a VIDEO post in the large feed
    /// row.
    @State var showingFullscreenMedia = false
    init(post: RedditPost, repository: RedditRepository, displayStyle: PostDisplayStyle, isAggregateFeed: Bool = true, onSubredditTap: @escaping () -> Void, onAuthorTap: @escaping () -> Void, onCommentsTap: (() -> Void)? = nil, onTranslateTap: (() -> Void)? = nil, moreMenu: (() -> AnyView)? = nil) {
        self.post = post
        self.repository = repository
        self.displayStyle = displayStyle
        self.isAggregateFeed = isAggregateFeed
        self.onSubredditTap = onSubredditTap
        self.onAuthorTap = onAuthorTap
        self.onCommentsTap = onCommentsTap
        self.onTranslateTap = onTranslateTap
        self.moreMenu = moreMenu
    }

    @ViewBuilder var moreOptionsButton: some View {
        if let moreMenu {
            Menu { moreMenu() } label: {
                StockIcon("inline-more-options")
                    // A finger-sized target around a 13pt glyph.
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .padding(.horizontal, -8)
                    .padding(.vertical, -6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More options")
        } else {
            StockIcon("inline-more-options")
        }
    }
    /// Loaded once per row render rather than per thumbnail-position
    /// check, matching the settings snapshot the rest of the feed
    /// already reads once per load.
    @Setting(GeneralSettings.self) var generalSettings

    /// "Show Voting Buttons" (`AppearanceSettings.showVotingButtons`,
    /// key `CompactModeHideVotingButtons` inverted): hides the
    /// per-row vote arrow column when off.
    var showsVotingButtons: Bool { appearanceSettings.showVotingButtons }
    var largePostsShowVotingButtons: Bool { appearanceSettings.largePostsShowVotingButtons }

    /// Reborn "Bold Post Titles" (Appearance > Posts). Same once-per-row-render
    /// pattern as the two above.
    @Setting(AppearanceSettings.self) var appearanceSettings
    /// Real "Voting Buttons Position"
    /// (`AppearanceSettings.votingButtonsPosition`), only meaningful
    /// while `showsVotingButtons` is on.
    var votingButtonsPosition: AppearanceEdgePosition { appearanceSettings.votingButtonsPosition }
    /// The post title as ONE string; a tag filter covers it with
    /// `TagFilterCover` rather than altering the text.
    var titleString: String {
        translatedTitle ?? post.title
    }
    /// A link post's bare host, shown INLINE at the end of the title,
    /// tinted tertiary in the same 15pt face.
    /// Reddit's own media hosts (v.redd.it, i.redd.it, galleries) show no
    /// domain: the thumbnail already says what the post is.
    var titleDomain: String? {
        // An NSFW post shows its tag instead.
        guard !post.isSelf, !post.over18, let urlString = post.url,
              let host = URL(string: urlString)?.host?.lowercased() else { return nil }
        let bare = host.replacingOccurrences(of: "www.", with: "")
        if bare.hasSuffix("redd.it") || bare == "reddit.com" || bare.hasSuffix(".reddit.com") { return nil }
        return bare
    }

    /// What `titleText` draws, for `TitleFlairLayout`'s measurement.
    var titleMeasureString: String {
        if let titleDomain { return titleString + " (\(titleDomain))" }
        return titleString
    }

    /// The measured 15pt title scaled by Dynamic Type, shared by the
    /// `Text` and `TitleFlairLayout`'s TextKit measurement so the flair
    /// capsule still lands after the last glyph at any text size.
    var titleFontSize: CGFloat {
        ScaledSystemFont.scaled(15, style: .body, for: dynamicTypeSize)
    }

    var titleText: Text {
        let weight: Font.Weight = appearanceSettings.boldPostTitles ? .semibold : .regular
        let font = Font.system(size: titleFontSize, weight: weight)
        // #D0D1D6 in dark+PureBlack, NOT white - see
        // `Color.apolloPrimaryText`, dimmed further once read.
        var text = Text(titleString)
            .font(font)
            .foregroundColor(Color.apolloPrimaryText(
                isRead: isRead,
                colorScheme: colorScheme,
                themeColors: themeColors
            ))
        if let titleDomain {
            text = text + Text(" (\(titleDomain))")
                .font(font)
                .foregroundColor(Color.apolloTertiaryText(colorScheme: colorScheme, themeColors: themeColors))
        }
        return text
    }

    /// Per-subreddit flair colors; `nil` falls back to flat-grey
    /// styling. Gated on "Color Flairs"
    /// (`GeneralSettings.enableFlairColors`, default true).
    var linkFlairBackgroundColor: Color? {
        guard generalSettings.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: post.linkFlairBackgroundColor).map(Color.init(hex:))
    }
    var linkFlairTextColor: Color? {
        guard generalSettings.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: post.linkFlairTextColorRaw).map(Color.init(hex:))
    }
    var authorFlairBackgroundColor: Color? {
        guard generalSettings.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: post.authorFlairBackgroundColor).map(Color.init(hex:))
    }
    var authorFlairTextColor: Color? {
        guard generalSettings.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: post.authorFlairTextColorRaw).map(Color.init(hex:))
    }

    /// Whether this post is currently saved. Read through the shared
    /// `VoteStateStore` rather than `post.saved`, since a save can be
    /// written there without the feed's post model being refetched.
    var isSaved: Bool { voteStore.isSaved(post.name, serverValue: post.saved) }

    /// How many comments arrived since this post's thread was last
    /// opened - the number Apollo's unread badge shows. 0 for a
    /// never-opened post, which is why a fresh feed shows no badges.
    /// See `NewCommentsTracker.newCommentCount`.
    var newCommentCount: Int {
        NewCommentsTracker.newCommentCount(postID: post.id, currentCount: post.numComments)
    }

    var body: some View {
        // Corner wedge marking a saved post (see `SavedIndicator`).
        // Apollo composes it into the cell itself, so it applies to
        // BOTH the compact and large layouts, hence it is attached
        // here rather than inside either one.
        Group {
            if displayStyle == .large {
                largeThumbnailBody
            } else {
                compactBody
                    // VoiceOver: one stop per post, not a dozen.
                    // Apollo's cell is a single accessible cell. Large
                    // rows are NOT merged, since their media (videos,
                    // galleries, link cards) is separately interactive.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isSaved {
                SavedIndicatorBadge(size: .regular)
            }
        }
        // Read posts are dimmed; the row owns this so it updates the
        // moment a post is marked read, not on the next feed reload.
        .opacity(isRead ? 0.5 : 1)
        .onAppear { isRead = ReadPostStore.isRead(post.name) }
        .onReceive(NotificationCenter.default.publisher(for: .apolloReadPostsChanged)) { note in
            if (note.object as? String) == post.name { isRead = true }
        }
        // Vote/save/comments/subreddit/author, the same actions the
        // row's arrows, swipes and context menu offer, reachable from
        // the VoiceOver rotor on both layouts.
        .accessibilityAction(named: voteState == true ? "Remove Upvote" : "Upvote") {
            Task { await PostVoting.toggle(post: post, direction: 1, repository: repository) }
        }
        .accessibilityAction(named: voteState == false ? "Remove Downvote" : "Downvote") {
            Task { await PostVoting.toggle(post: post, direction: -1, repository: repository) }
        }
        .accessibilityAction(named: isSaved ? "Unsave" : "Save") {
            Task { await PostVoting.toggleSave(post: post, repository: repository) }
        }
        .accessibilityAction(named: "View Comments") { onCommentsTap?() }
        .accessibilityAction(named: "Go to \(post.subreddit)") { onSubredditTap() }
        .accessibilityAction(named: "Go to \(post.author)") { onAuthorTap() }
    }

    /// Everything the compact row shows, in words (`AccessibilitySummary`).
    var accessibilitySummary: String {
        AccessibilitySummary.post(
            title: titleString, subreddit: post.subreddit, author: post.author,
            score: displayScore, comments: post.numComments, created: post.created,
            flair: generalSettings.showPostFlair ? post.linkFlairText : nil,
            domain: titleDomain, nsfw: post.over18, spoiler: post.spoiler,
            stickied: post.stickied, saved: isSaved, vote: voteState)
    }

    /// Apollo's per-row stacked up/down-arrow vote control, pinned to
    /// the row's far right edge. The subreddit icon only appears on
    /// aggregate feeds and honors `ShowSubredditIconsForPosts`.
    var showsSubredditIcon: Bool {
        isAggregateFeed && appearanceSettings.showSubredditIconsForPosts
    }

    /// Whether the subreddit row is drawn above the title: on an aggregate feed
    /// with Show Subreddit at Top. Off, compact rows lead the info row with it
    /// and large rows put it on the ••• / vote line. Inside a subreddit Apollo
    /// never names it; the author leads the info row instead
    /// (`showsAuthorInInfoRow`).
    var showsSubredditHeader: Bool {
        isAggregateFeed && appearanceSettings.showSubredditAtTop
    }

    /// Inside one subreddit the info row leads with the author, with
    /// their picture when "Show User Profile Pictures" is on, whatever
    /// "Always Show Usernames" says: that setting is about the feeds
    /// where the subreddit is shown instead.
    var showsAuthorInInfoRow: Bool {
        !isAggregateFeed
    }

    /// Mirrors chosenThumbnails / enableCompactThumbnails: a small
    /// configurable-size thumbnail alongside the text. Position
    /// matches `CompactModeLeftThumbnails` (default left), size
    /// matches `CompactPostsThumbnailSize` (default small). `.hidden`
    /// renders nothing.
    @ViewBuilder
    var thumbnailView: some View {
        if generalSettings.thumbnailSize != .hidden, resolvedThumbnailURL == nil,
           post.isSelf, appearanceSettings.compactShowSelfPostThumbnails {
            let size = generalSettings.thumbnailSize.pointSize
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.08))
                .frame(width: size, height: size)
                .overlay {
                    StockIcon("self-post-indicator", size: CGSize(width: size * 0.4, height: size * 0.4 * 26 / 28))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        } else if generalSettings.thumbnailSize != .hidden,
           let url = resolvedThumbnailURL {
            let size = generalSettings.thumbnailSize.pointSize
            CachedAsyncImage(url: url)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Native thumbnail if Apollo's own pipeline produced one, else
    /// - for a self-post only - a derived thumbnail from the first
    /// image in its selftext, gated on "Text Post Thumbnails"
    /// (`GeneralSettings.textPostThumbnailsEnabled`; native thumbnails
    /// still show regardless).
    /// Width the large card's media occupies: the widest common phone
    /// width rather than a measured value, since Reddit's ladder
    /// (216/320/640/960/1080) makes a nearby value pick the same rung.
    static let largeCardWidth: Double = 430

    var resolvedThumbnailURL: URL? {
        // A crosspost shows its chip/card, not the original's thumbnail.
        guard post.crosspostParent == nil else { return nil }
        // Prefer Reddit's pre-resized preview over its thumbnail:
        // `post.thumbnail` is a 140px square, while the large card
        // draws it at full width, a ~3x upscale. Only for the large
        // style; the compact row's 60pt square is what the thumbnail is for.
        if displayStyle == .large,
           let preview = post.previewImageURL(displayWidth: Self.largeCardWidth) {
            return preview
        }
        if let thumbnail = post.thumbnail, thumbnail.hasPrefix("http"),
           let url = URL(string: thumbnail.replacingOccurrences(of: "&amp;", with: "&")) {
            return url
        }
        // A link post whose `thumbnail` is "default"/"nsfw"/empty can
        // still carry Reddit's preview.
        if !post.over18, !post.spoiler, let preview = post.previewImageURL(displayWidth: 80) {
            return preview
        }
        guard generalSettings.textPostThumbnailsEnabled else { return nil }
        return post.derivedSelfPostThumbnailURL
    }

    /// Mirrors Apollo's voting behavior: tapping an already-active vote
    /// button un-votes (direction 0).
    func vote(direction: Int) async {
        Haptics.light()
        await PostVoting.vote(post: post, direction: direction, repository: repository)
    }
}
