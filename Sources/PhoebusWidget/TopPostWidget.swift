import WidgetKit
import SwiftUI
import AppIntents
import PhoebusCore

/// Phoebus widget extension, reimplementing Reborn's widgets.
///
/// Shows the personalized home feed via `SharedFeedCache`, an App Group
/// container the app writes after each home-feed load, falling back to
/// Reddit's public `/r/popular/hot.json` when the cache is empty.

/// Reborn "Widgets for Any Feed": point the Feed and Post widgets at Home,
/// Popular, All, several subreddits, or a multireddit.
///
/// Narrower than Reborn's Post widget: no Large size, no Sort/Caption
/// parameters, no rotation, and no Setup Code (only the App Group cache,
/// covering Home). The default is Home rather than Reborn's `popular`, since
/// the cache is the only personalised source.
///
/// Picker shape: a Source picker for the built-in feeds plus a free-text
/// "Subreddit or Multireddit" field, parsed by `WidgetFeedSource.parse`.
@available(iOS 17.0, *)
struct FeedSourceIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Feed"
    static let description = IntentDescription("Choose which feed this widget shows.")

    /// The built-in options, in Reborn's order.
    enum Source: String, AppEnum {
        case home, popular, all, custom

        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Source")
        static let caseDisplayRepresentations: [Source: DisplayRepresentation] = [
            .home: "Home",
            .popular: "Popular",
            .all: "All",
            .custom: "Subreddit or Multireddit",
        ]
    }

    @Parameter(title: "Source", default: .home)
    var source: Source

    /// The free-text field. Only meaningful for `.custom`.
    @Parameter(title: "Subreddit or Multireddit")
    var query: String?

    /// Resolves the two controls into one feed.
    func resolvedSource() -> WidgetFeedSource {
        switch source {
        case .home: return .home
        case .popular: return .popular
        case .all: return .all
        case .custom:
            return WidgetFeedSource.parse(query ?? "") ?? .popular
        }
    }
}

/// All nine widgets ship in one extension: each extension consumes one
/// App ID, so splitting them would break sideloading on a free Apple ID.
@main
struct PhoebusWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Zero-config, so they work on any iOS 17 build.
        ApolloShowerthoughtsWidget()
        ApolloJokesWidget()
        ApolloActionsWidget()
        if #available(iOS 17.0, *) {
            ApolloPostWidget()
            ApolloFeedWidget()
            ApolloPhotoWidget()
            ApolloShortcutsWidget()
            ApolloCalendarWidget()
            ApolloHeadlineWidget()
        }
        // The Follow Thread Live Activity's own presentation. A Live
        // Activity is rendered by a widget extension, so it has to be
        // declared in this bundle alongside the widgets.
        if #available(iOS 16.2, *) {
            FollowThreadLiveActivity()
        }
    }
}

struct TopPostWidget: Widget {
    let kind = "TopPostWidget"

    var body: some WidgetConfiguration {
        // Intent-configurable, so the feed can actually be chosen.
        AppIntentConfiguration(kind: kind,
                               intent: FeedSourceIntent.self,
                               provider: TopPostIntentProvider()) { entry in
            TopPostWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Top Post")
        .description("Shows the top post from a feed you choose.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Timeline provider for the configurable widget.
@available(iOS 17.0, *)
struct TopPostIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TopPostEntry {
        TopPostEntry(date: Date(), post: nil, errorMessage: nil, isPersonalized: false, source: .home)
    }

    func snapshot(for configuration: FeedSourceIntent, in context: Context) async -> TopPostEntry {
        await entry(for: configuration.resolvedSource())
    }

    func timeline(for configuration: FeedSourceIntent, in context: Context) async -> Timeline<TopPostEntry> {
        let entry = await entry(for: configuration.resolvedSource())
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
    }

    private func entry(for source: WidgetFeedSource) async -> TopPostEntry {
        // Home and your own multireddits need the with-account setup code;
        // the widget shows a sign-in message instead of failing quietly. Home
        // is served from the App Group cache the app writes.
        if source.requiresAccount, let cached = SharedFeedCache.loadTopPost() {
            return TopPostEntry(date: cached.cachedAt, post: cached.post,
                                errorMessage: nil, isPersonalized: true, source: source)
        }
        // Otherwise fetched here, with the account's credentials when
        // the widget can read them (see `WidgetFetcher.pool`).
        return await TopPostFetcher.fetch(source: source)
    }
}

struct TopPostEntry: TimelineEntry {
    let date: Date
    let post: RedditPost?
    let errorMessage: String?
    let isPersonalized: Bool
    /// The chosen feed, so the header can name it ("Home", "r/soccer+nba", "m/bar").
    var source: WidgetFeedSource = .home
}

/// Top hot post for a public listing, through the same fetcher (auth,
/// content filters, error mapping) the other widgets use.
enum TopPostFetcher {
    static func fetch(source: WidgetFeedSource) async -> TopPostEntry {
        switch await WidgetFetcher.pool(source: source, sort: .hot, limit: 1) {
        case .success(let posts) where !posts.isEmpty:
            return TopPostEntry(date: Date(), post: posts[0], errorMessage: nil,
                                isPersonalized: false, source: source)
        case .success:
            return TopPostEntry(date: Date(), post: nil, errorMessage: WidgetFetchError.empty.message,
                                isPersonalized: false, source: source)
        case .failure(let error):
            return TopPostEntry(date: Date(), post: nil, errorMessage: error.message,
                                isPersonalized: false, source: source)
        }
    }
}

struct TopPostWidgetView: View {
    let entry: TopPostEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The Feed header shows the source ("Home", "r/soccer+nba", "m/bar").
            Label(entry.source.displayName,
                  systemImage: entry.source == .home ? "house" : "flame")
                .font(.caption.bold())
                .foregroundStyle(entry.isPersonalized ? .blue : .orange)

            if let post = entry.post {
                Text(post.title)
                    .font(.subheadline.bold())
                    .lineLimit(3)
                Spacer(minLength: 0)
                HStack {
                    Label("\(post.score)", systemImage: "arrow.up")
                    Label("\(post.numComments)", systemImage: "bubble.right")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                // The fetcher's own message, never a raw error string.
                Text(entry.errorMessage ?? "Loading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }
}
