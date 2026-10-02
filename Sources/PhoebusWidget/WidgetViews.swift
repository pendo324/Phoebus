import WidgetKit
import SwiftUI
import AppIntents
import PhoebusCore

// MARK: - Shared post rendering

/// Renders a post per the Caption setting.
struct WidgetPostView: View {
    let post: RedditPost?
    let caption: WidgetKitShared.Caption
    let message: String?
    var headerText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let headerText {
                Text(headerText)
                    .font(.caption2.bold())
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
            if let post {
                if caption.showsTitle {
                    Text(post.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(4)
                }
                if caption.showsDetails, post.isSelf, let body = post.selftext, !body.isEmpty {
                    // "(and the body preview, for text posts)"
                    Text(body)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                if caption.showsStats {
                    HStack(spacing: 8) {
                        Label("\(post.score)", systemImage: "arrow.up")
                        Label("\(post.numComments)", systemImage: "bubble.right")
                        if caption.showsDetails {
                            // "+ age, author"
                            Text(post.created, style: .relative)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if caption.showsDetails {
                        Text("u/\(post.author)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(message ?? "Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Post

@available(iOS 17.0, *)
struct ApolloPostWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ApolloPostWidget",
                               intent: PostWidgetIntent.self,
                               provider: PostWidgetProvider()) { entry in
            WidgetPostView(post: entry.post, caption: entry.caption,
                           message: entry.message,
                           headerText: entry.source.displayName)
                .widgetURL(entry.post.map(WidgetKitShared.DeepLink.post))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Post")
        .description("The top post from a subreddit, multireddit, or feed you choose.")
        // Sizes: Small, Medium, Large.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Showerthoughts / Jokes

/// "Sizes: Small, Medium, Large, Lock Screen (Rectangular, Inline).
/// Config: Setup Code only."
struct ApolloShowerthoughtsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ApolloShowerthoughtsWidget",
                            // "pulls Top: This Week"
                            provider: FixedFeedProvider(subreddit: "showerthoughts",
                                                        sort: .topWeek,
                                                        selfPostsOnly: false)) { entry in
            WidgetPostView(post: entry.post, caption: .title, message: entry.message,
                           headerText: "Showerthoughts")
                .containerBackground(
                    LinearGradient(colors: [.blue, .cyan],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    for: .widget)
        }
        .configurationDisplayName("Showerthoughts")
        .description("A rotating top post from r/showerthoughts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline])
    }
}

/// "the title is the setup, the body is the punchline … Top: Today,
/// filtered to self-text jokes (so there's always a punchline)".
struct ApolloJokesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ApolloJokesWidget",
                            provider: FixedFeedProvider(subreddit: "Jokes",
                                                        sort: .topToday,
                                                        selfPostsOnly: true)) { entry in
            JokeView(entry: entry)
                .containerBackground(
                    LinearGradient(colors: [.purple, .indigo],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    for: .widget)
        }
        .configurationDisplayName("Jokes")
        .description("A joke from r/Jokes — title is the setup, body is the punchline.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct JokeView: View {
    let entry: FixedFeedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let post = entry.post {
                Text(post.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(4)
                // "On the Lock Screen it shows the setup - tap to open
                // Apollo for the punchline."
                if family != .accessoryRectangular && family != .accessoryInline,
                   let body = post.selftext, !body.isEmpty {
                    Text(body)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }
            } else {
                Text(entry.message ?? "Loading…")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Feed

/// "A scrolling-style list of a feed's top posts … Sizes: Medium,
/// Large."
@available(iOS 17.0, *)
struct FeedWidgetIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Feed"
    static let description = IntentDescription("A list of a feed's top posts.")

    @Parameter(title: "Source", default: .popular)
    var source: WidgetSourceOption
    @Parameter(title: "Subreddit or Multireddit", default: "popular")
    var query: String?
    @Parameter(title: "Sort", default: .hot)
    var sort: WidgetSortOption
    /// "Compact (default off — hides thumbnails and fits more rows)"
    @Parameter(title: "Compact", default: false)
    var compact: Bool

    func resolvedSource() -> WidgetFeedSource {
        switch source {
        case .home: return .home
        case .popular: return .popular
        case .all: return .all
        case .custom: return WidgetFeedSource.parse(query ?? "") ?? .popular
        }
    }
}

@available(iOS 17.0, *)
struct FeedWidgetProvider: AppIntentTimelineProvider {
    /// Fetches the top ~12.
    static let poolSize = 12

    func placeholder(in context: Context) -> PostPoolEntry {
        PostPoolEntry(date: Date(), post: nil, pool: [], source: .popular,
                      caption: .title, message: nil)
    }

    func snapshot(for configuration: FeedWidgetIntent, in context: Context) async -> PostPoolEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: FeedWidgetIntent, in context: Context) async -> Timeline<PostPoolEntry> {
        let entry = await entry(for: configuration)
        // Refreshes about every 30 minutes.
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: FeedWidgetIntent) async -> PostPoolEntry {
        let source = configuration.resolvedSource()
        switch await WidgetFetcher.pool(source: source, sort: configuration.sort.shared,
                                        limit: Self.poolSize) {
        case .success(let pool):
            return PostPoolEntry(date: Date(), post: pool.first, pool: pool, source: source,
                                 caption: configuration.compact ? .title : .titleAndStats,
                                 message: nil)
        case .failure(let error):
            return PostPoolEntry(date: Date(), post: nil, pool: [], source: source,
                                 caption: .title, message: error.message)
        }
    }
}

@available(iOS 17.0, *)
struct ApolloFeedWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ApolloFeedWidget",
                               intent: FeedWidgetIntent.self,
                               provider: FeedWidgetProvider()) { entry in
            FeedRowsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Feed")
        .description("A list of a feed's top posts.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct FeedRowsView: View {
    let entry: PostPoolEntry
    @Environment(\.widgetFamily) private var family

    /// "the row count fits the widget height (a Medium shows ~2-3, a
    /// Large fills by device size)".
    private var rowCount: Int { family == .systemLarge ? 7 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // "The header names the source and opens it in Apollo."
            Text(entry.source.displayName)
                .font(.caption2.bold())
                .foregroundStyle(.tint)
            if entry.pool.isEmpty {
                Text(entry.message ?? "Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.pool.prefix(rowCount), id: \.id) { post in
                    Link(destination: WidgetKitShared.DeepLink.post(post)) {
                        Text(post.title)
                            .font(.caption)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
