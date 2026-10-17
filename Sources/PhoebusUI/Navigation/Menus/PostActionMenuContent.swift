import SwiftUI
import PhoebusCore

/// What a row of a feed post's menu can do. The feed performs them; the
/// Action Menus preview performs none.
enum PostMenuAction {
    case save, hide, copyLink, saveAllMedia, crosspost, remindMe, toggleMute, filterSubreddit
    case insights, setFlair, report
    case downloadVideo(URL)
    case saveGIF(URL, asVideo: Bool)
    /// "Save GIFs as…" names a format, so the row saves without asking.
    case saveGIFInFormat(URL)
    case subscribe, unsubscribe, follow, block, copyUsername, tagUser
    case moderator(PostModeratorAction)
}

/// A post's hold and ••• menu in a feed. Entries are listed in the app's
/// order and arranged by the user's Action Menus layout (Reborn #1131,
/// context `post`); moderator rows follow the `moderator-post` layout.
struct PostActionMenuContent: View {
    let post: RedditPost
    let repository: RedditRepository
    let signedInUsername: String?
    let isModerator: Bool
    var isPreview = false
    let perform: (PostMenuAction) -> Void

    @Setting(GeneralSettings.self) private var general

    var body: some View {
        let plan = ActionMenuPlan.feedPost(author: post.author, signedInUsername: signedInUsername,
                                           isModerator: isModerator, galleryImageCount: post.galleryImageURLs.count)
        ForEach(plan.main, id: \.self) { id in
            row(id)
        }
        if let moderator = plan.moderator {
            Divider()
            ForEach(moderator, id: \.self) { id in
                row(id)
            }
        }
        Divider()
        row("report")
    }

    private var moderatorState: PostModeratorMenuState {
        PostModeratorMenuState(distinguished: post.distinguished == "moderator", stickied: post.stickied,
                               locked: post.locked ?? false)
    }

    @ViewBuilder
    private func row(_ id: String) -> some View {
        switch id {
        case "save":
            Button { perform(.save) } label: { Label("Save", systemImage: "bookmark") }
        case "hide":
            Button { perform(.hide) } label: { Label("Hide", systemImage: "eye.slash") }
        case "share":
            MenuShareLink(item: .text(post.shareText()), isPreview: isPreview)
        case "copy-link":
            // Apollo's copy-URL activity (Reborn #967): ShareLink cannot register
            // custom activities, so it is its own row.
            Button { perform(.copyLink) } label: { Label("Copy Link", systemImage: "link") }
        case "save-all-media":
            // Reborn #1048: an album post's hold menu gains Save All Media.
            Button { perform(.saveAllMedia) } label: {
                Label(SaveAllMediaSummary.menuTitle, systemImage: SaveAllMediaSummary.menuSymbol)
            }
        case "crosspost":
            Button { perform(.crosspost) } label: { Label("Crosspost", systemImage: "arrowshape.turn.up.right") }
        case "remind-me":
            // Reborn "Action Menus" (#1368): Remind Me In… is a catalogued row.
            Button { perform(.remindMe) } label: { Label("Remind Me In…", systemImage: "alarm") }
        case "mute-notifications":
            Button { perform(.toggleMute) } label: {
                Label(MutedThreadsStore.isMuted(post.name) ? "Unmute Notifications" : "Mute Notifications",
                      systemImage: MutedThreadsStore.isMuted(post.name) ? "bell" : "bell.slash")
            }
        case "filter-subreddit":
            Button { perform(.filterSubreddit) } label: {
                Label("Filter Subreddit", systemImage: "line.3.horizontal.decrease.circle")
            }
        case "post-insights":
            Button { perform(.insights) } label: { Label("Insights", systemImage: "chart.bar") }
        case "nsfw", "spoiler":
            if let mark = PostMark(rawValue: id) {
                PostMarkMenuButton(mark: mark, post: post, repository: repository,
                                   identifierPrefix: "feed.postMenu", isInert: isPreview)
            }
        case "post-flair":
            // Apollo's flair action: change a post's flair after posting.
            Button { perform(.setFlair) } label: { Label("Set Flair", systemImage: "tag") }
        case "media-download":
            mediaDownloadRows
        case "subscribe-actions":
            Divider()
            Button { perform(.subscribe) } label: {
                Label("Subscribe to r/\(post.subreddit)", systemImage: "plus.circle")
            }
            Button { perform(.unsubscribe) } label: {
                Label("Unsubscribe from r/\(post.subreddit)", systemImage: "minus.circle")
            }
            Button { perform(.follow) } label: {
                Label("Follow u/\(post.author)", systemImage: "person.crop.circle.badge.plus")
            }
            Button { perform(.block) } label: {
                Label("Block u/\(post.author)", systemImage: "person.crop.circle.badge.xmark")
            }
            // Reborn addition: copy the author's username.
            Button { perform(.copyUsername) } label: {
                Label("Copy Username", systemImage: "doc.on.doc")
            }
            // Phoebus-only user tags (`UserTags`).
            if post.author != "[deleted]" {
                UserTagMenuItem(username: post.author) { perform(.tagUser) }
                    .accessibilityIdentifier("feed.postMenu.tagUser")
            }
        case "report":
            Button(role: .destructive) { perform(.report) } label: { Label("Report", systemImage: "flag") }
        case "mod-approve", "mod-remove", "mod-spam", "mod-distinguish", "mod-sticky", "mod-lock":
            PostModeratorMenuRow(id: id, post: post, repository: repository, state: moderatorState,
                                 markIdentifierPrefix: "feed.postMenu", isPreview: isPreview) {
                perform(.moderator($0))
            }
        default:
            EmptyView()
        }
    }

    /// Download Video… / Save GIF…, right after Filter Subreddit as in
    /// Apollo's post menu.
    @ViewBuilder
    private var mediaDownloadRows: some View {
        switch PostMediaKind.classify(post: post) {
        case .video(let videoURL):
            Button { perform(.downloadVideo(videoURL)) } label: {
                Label("Download Video…", systemImage: "arrow.down.circle")
            }
        case .gif(let gifURL):
            // "Save GIFs as…" setting (`GeneralSettings.gifSaveFormat`).
            // `.askEachTime` presents its own two-option chooser rather
            // than silently picking one.
            if general.gifSaveFormat == .askEachTime {
                Button { perform(.saveGIF(gifURL, asVideo: false)) } label: {
                    Label("Save as GIF", systemImage: "photo")
                }
                Button { perform(.saveGIF(gifURL, asVideo: true)) } label: {
                    Label("Save as Video", systemImage: "video")
                }
            } else {
                Button { perform(.saveGIFInFormat(gifURL)) } label: {
                    Label("Save GIF…", systemImage: "arrow.down.circle")
                }
            }
        default:
            EmptyView()
        }
    }
}
