import SwiftUI
import PhoebusCore

/// The Moderator (Subreddit) menu: the rows this app can open, in Apollo's
/// order, arranged by the Action Menus layout (Reborn #1131, context
/// `moderator-subreddit`). The queue's own views switch its list in place
/// (`onFilter`); the rest push a screen, which the Action Menus preview
/// (`isPreview`) draws as buttons that do nothing.
struct ModeratorSubredditMenuContent: View {
    let subreddit: String
    let repository: RedditRepository
    var isPreview = false
    let onFilter: (RedditRepository.ModQueueFilter) -> Void

    var body: some View {
        ForEach(ActionMenuPlan.moderatorSubreddit(), id: \.self) { id in
            row(id)
        }
    }

    @ViewBuilder
    private func row(_ id: String) -> some View {
        switch id {
        case "mod-mail":
            link("Mod Mail", symbol: "envelope.badge.shield.half.filled") { ModmailListScreen(repository: repository) }
        case "mod-queue": filterRow(.all, title: "Mod Queue", symbol: "tray.full")
        case "mod-reports": filterRow(.reports, title: "Reports", symbol: "flag")
        case "mod-spam-queue": filterRow(.spam, title: "Spam", symbol: "exclamationmark.shield")
        case "mod-unmoderated": filterRow(.unmoderated, title: "Unmoderated", symbol: "eye.slash")
        case "mod-log":
            link("Mod Log", symbol: "list.bullet.clipboard") { ModeratorLogScreen(subreddit: subreddit, repository: repository) }
        case "mod-all-comments":
            link("All Comments", symbol: "text.bubble") { AllSubredditCommentsScreen(subreddit: subreddit, repository: repository) }
        case "mod-traffic":
            link("Traffic Stats", symbol: "chart.xyaxis.line") { SubredditTrafficScreen(subreddit: subreddit, repository: repository) }
        case "mod-ban-users": userListRow(.banned)
        case "mod-mute-users": userListRow(.muted)
        case "mod-approved-submitters": userListRow(.approved)
        case "mod-rules":
            link("Rules", symbol: "list.number") { SubredditRulesScreen(subredditName: subreddit, repository: repository) }
        case "mod-automoderator":
            link("AutoModerator", symbol: "shield.lefthalf.filled") { AutoModeratorScreen(subreddit: subreddit, repository: repository) }
        case "mod-moderators":
            link("Moderators", symbol: "shield") { SubredditModeratorsScreen(subredditName: subreddit, repository: repository) }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func link<Destination: View>(_ title: String, symbol: String,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        if isPreview {
            Button {} label: { Label(title, systemImage: symbol) }
        } else {
            SettingsLink(destination: destination) { Label(title, systemImage: symbol) }
        }
    }

    /// The queue's own views switch the list in place.
    private func filterRow(_ option: RedditRepository.ModQueueFilter, title: String, symbol: String) -> some View {
        Button {
            onFilter(option)
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    private func userListRow(_ kind: ModeratorUsersScreen.UserListKind) -> some View {
        link(kind.title, symbol: ApolloMenuIcon.symbol(kind.apolloIconName, fallback: "person.2.slash")) {
            ModeratorUsersScreen(subreddit: subreddit, repository: repository, kind: kind)
        }
    }
}
