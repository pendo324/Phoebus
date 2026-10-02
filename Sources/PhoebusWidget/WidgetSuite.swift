import WidgetKit
import SwiftUI
import AppIntents
import PhoebusCore

/// The nine Reborn widgets, all in one extension so they cost one App ID.
///
/// Shared sort/caption/rotation/filtering live in `WidgetKitShared`; the single
/// network path is `WidgetFetcher`.

// MARK: - Shared intent parameters

@available(iOS 17.0, *)
enum WidgetSortOption: String, AppEnum {
    case hot, new, topToday, topWeek

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sort")
    static let caseDisplayRepresentations: [WidgetSortOption: DisplayRepresentation] = [
        .hot: "Hot", .new: "New", .topToday: "Top: Today", .topWeek: "Top: This Week",
    ]

    var shared: WidgetKitShared.Sort {
        switch self {
        case .hot: return .hot
        case .new: return .new
        case .topToday: return .topToday
        case .topWeek: return .topWeek
        }
    }
}

@available(iOS 17.0, *)
enum WidgetCaptionOption: String, AppEnum {
    case none, title, titleAndStats, detailed

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Caption")
    static let caseDisplayRepresentations: [WidgetCaptionOption: DisplayRepresentation] = [
        .none: "None", .title: "Title", .titleAndStats: "Title + Stats", .detailed: "Detailed",
    ]

    var shared: WidgetKitShared.Caption {
        switch self {
        case .none: return .none
        case .title: return .title
        case .titleAndStats: return .titleAndStats
        case .detailed: return .detailed
        }
    }
}

@available(iOS 17.0, *)
enum WidgetSourceOption: String, AppEnum {
    case home, popular, all, custom

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Source")
    static let caseDisplayRepresentations: [WidgetSourceOption: DisplayRepresentation] = [
        .home: "Home", .popular: "Popular", .all: "All",
        .custom: "Subreddit or Multireddit",
    ]
}

// MARK: - Entry

struct PostPoolEntry: TimelineEntry {
    let date: Date
    let post: RedditPost?
    let pool: [RedditPost]
    let source: WidgetFeedSource
    let caption: WidgetKitShared.Caption
    let message: String?
    /// Image bytes fetched by the provider, for widgets that show a photo. A
    /// widget view cannot load anything asynchronously. Nil for text-only widgets.
    var imageData: Data?
}

// MARK: - Post widget

/// "The top post from a subreddit, multireddit, or feed you choose." Sizes
/// S/M/L; config Source · Sub/Multi · Sort · Caption; default Popular · Hot.
@available(iOS 17.0, *)
struct PostWidgetIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Post"
    static let description = IntentDescription("The top post from a feed you choose.")

    @Parameter(title: "Source", default: .popular)
    var source: WidgetSourceOption
    @Parameter(title: "Subreddit or Multireddit", default: "popular")
    var query: String?
    @Parameter(title: "Sort", default: .hot)
    var sort: WidgetSortOption
    @Parameter(title: "Caption", default: .titleAndStats)
    var caption: WidgetCaptionOption

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
struct PostWidgetProvider: AppIntentTimelineProvider {
    /// Fetches the top ~50 and rotates through them.
    static let poolSize = 50

    func placeholder(in context: Context) -> PostPoolEntry {
        PostPoolEntry(date: Date(), post: nil, pool: [], source: .popular,
                      caption: .titleAndStats, message: nil)
    }

    func snapshot(for configuration: PostWidgetIntent, in context: Context) async -> PostPoolEntry {
        await entry(for: configuration, at: Date())
    }

    func timeline(for configuration: PostWidgetIntent, in context: Context) async -> Timeline<PostPoolEntry> {
        let now = Date()
        let entry = await entry(for: configuration, at: now)
        return Timeline(entries: [entry],
                        policy: .after(WidgetKitShared.Rotation.nextChange(after: now)))
    }

    private func entry(for configuration: PostWidgetIntent, at date: Date) async -> PostPoolEntry {
        let source = configuration.resolvedSource()
        let caption = configuration.caption.shared
        switch await WidgetFetcher.pool(source: source, sort: configuration.sort.shared,
                                        limit: Self.poolSize) {
        case .success(let pool):
            let index = WidgetKitShared.Rotation.index(at: date, poolSize: pool.count)
            return PostPoolEntry(date: date, post: pool[index], pool: pool,
                                 source: source, caption: caption, message: nil)
        case .failure(let error):
            return PostPoolEntry(date: date, post: nil, pool: [], source: source,
                                 caption: caption, message: error.message)
        }
    }
}

// MARK: - Zero-config rotating widgets

/// Showerthoughts and Jokes take no configuration: the zero-config lock-screen widgets.
struct FixedFeedEntry: TimelineEntry {
    let date: Date
    let post: RedditPost?
    let message: String?
}

/// `Sendable` because WidgetKit calls these completion handlers across
/// concurrency domains; the stored properties are all value types.
struct FixedFeedProvider: TimelineProvider, Sendable {
    let subreddit: String
    let sort: WidgetKitShared.Sort
    let selfPostsOnly: Bool

    func placeholder(in context: Context) -> FixedFeedEntry {
        FixedFeedEntry(date: Date(), post: nil, message: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FixedFeedEntry) -> Void) {
        let subreddit = self.subreddit
        let sort = self.sort
        let selfOnly = self.selfPostsOnly
        Task {
            completion(await Self.entry(at: Date(), subreddit: subreddit,
                                        sort: sort, selfPostsOnly: selfOnly))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FixedFeedEntry>) -> Void) {
        let subreddit = self.subreddit
        let sort = self.sort
        let selfOnly = self.selfPostsOnly
        Task {
            let now = Date()
            let entry = await Self.entry(at: now, subreddit: subreddit,
                                         sort: sort, selfPostsOnly: selfOnly)
            completion(Timeline(entries: [entry],
                                policy: .after(WidgetKitShared.Rotation.nextChange(after: now))))
        }
    }

    private static func entry(at date: Date, subreddit: String,
                              sort: WidgetKitShared.Sort,
                              selfPostsOnly: Bool) async -> FixedFeedEntry {
        switch await WidgetFetcher.pool(source: .subreddits([subreddit]), sort: sort, limit: 25) {
        case .success(let fetched):
            let pool = selfPostsOnly ? WidgetKitShared.selfPostsOnly(fetched) : fetched
            guard !pool.isEmpty else {
                return FixedFeedEntry(date: date, post: nil, message: "No posts")
            }
            let index = WidgetKitShared.Rotation.index(at: date, poolSize: pool.count)
            return FixedFeedEntry(date: date, post: pool[index], message: nil)
        case .failure(let error):
            return FixedFeedEntry(date: date, post: nil, message: error.message)
        }
    }
}
