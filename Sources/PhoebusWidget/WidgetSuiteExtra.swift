import WidgetKit
import SwiftUI
import AppIntents
import PhoebusCore

// MARK: - Photo

/// "A full-bleed top image from a subreddit, minimal chrome … image
/// posts only, top ~25, rotates."
/// Default r/EarthPorn · Top: Today.
@available(iOS 17.0, *)
struct PhotoWidgetIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Photo"
    static let description = IntentDescription("A full-bleed top image from a subreddit.")

    @Parameter(title: "Subreddit or Multireddit", default: "EarthPorn")
    var query: String?
    @Parameter(title: "Sort", default: .topToday)
    var sort: WidgetSortOption
    /// "Caption (default Title; choose None for a clean image)"
    @Parameter(title: "Caption", default: .title)
    var caption: WidgetCaptionOption

    func resolvedSource() -> WidgetFeedSource {
        WidgetFeedSource.parse(query ?? "") ?? .subreddits(["EarthPorn"])
    }
}

@available(iOS 17.0, *)
struct PhotoWidgetProvider: AppIntentTimelineProvider {
    static let poolSize = 25

    func placeholder(in context: Context) -> PostPoolEntry {
        PostPoolEntry(date: Date(), post: nil, pool: [], source: .subreddits(["EarthPorn"]),
                      caption: .title, message: nil)
    }

    func snapshot(for configuration: PhotoWidgetIntent, in context: Context) async -> PostPoolEntry {
        await entry(for: configuration, at: Date())
    }

    func timeline(for configuration: PhotoWidgetIntent, in context: Context) async -> Timeline<PostPoolEntry> {
        let now = Date()
        return Timeline(entries: [await entry(for: configuration, at: now)],
                        policy: .after(WidgetKitShared.Rotation.nextChange(after: now)))
    }

    private func entry(for configuration: PhotoWidgetIntent, at date: Date) async -> PostPoolEntry {
        let source = configuration.resolvedSource()
        switch await WidgetFetcher.pool(source: source, sort: configuration.sort.shared,
                                        limit: Self.poolSize) {
        case .success(let fetched):
            // "image posts only"
            let pool = WidgetKitShared.imagePostsOnly(fetched)
            guard !pool.isEmpty else {
                return PostPoolEntry(date: date, post: nil, pool: [], source: source,
                                     caption: configuration.caption.shared, message: "No photos")
            }
            let index = WidgetKitShared.Rotation.index(at: date, poolSize: pool.count)
            let chosen = pool[index]
            return PostPoolEntry(date: date, post: chosen, pool: pool, source: source,
                                 caption: configuration.caption.shared, message: nil,
                                 imageData: await WidgetFetcher.imageData(for: chosen))
        case .failure(let error):
            return PostPoolEntry(date: date, post: nil, pool: [], source: source,
                                 caption: configuration.caption.shared, message: error.message)
        }
    }
}

@available(iOS 17.0, *)
struct ApolloPhotoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ApolloPhotoWidget",
                               intent: PhotoWidgetIntent.self,
                               provider: PhotoWidgetProvider()) { entry in
            PhotoView(entry: entry)
                // Full-bleed photo as the container background (iOS 17+), so the system
                // sizes and clips it to the widget's shape; see CalendarPhotoView.
                .containerBackground(for: .widget) {
                    if let data = entry.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black
                    }
                }
        }
        .configurationDisplayName("Photo")
        .description("A full-bleed top image from a subreddit.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PhotoView: View {
    let entry: PostPoolEntry

    var body: some View {
        // The photo is the container background; only the caption furniture
        // lives here. The photo comes from bytes the provider fetched, since the
        // view cannot fetch remote images.
        ZStack(alignment: .bottomLeading) {
            if entry.imageData == nil, let post = entry.post, let raw = post.url,
               let url = URL(string: raw) {
                // Image unavailable (download failed or unsupported host); name it
                // rather than showing an unexplained black card.
                Text(url.host ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            if entry.caption.showsTitle, let post = entry.post {
                // "subtle vignette" behind the caption.
                Text(post.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(8)
                    .background(
                        LinearGradient(colors: [.black.opacity(0.7), .clear],
                                       startPoint: .bottom, endPoint: .top))
            }
            if entry.post == nil {
                Text(entry.message ?? "Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

// MARK: - Shortcuts

/// "A grid of colored tiles, one per subreddit, that open the sub in
/// Apollo … no network needed — tiles use letter avatars and a stable
/// color palette."
@available(iOS 17.0, *)
struct ShortcutsWidgetIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Shortcuts"
    static let description = IntentDescription("Tiles that open subreddits in Phoebus.")

    /// "Source (Popular / New / Home / Custom)"
    @Parameter(title: "Subreddits", default: "popular, all, worldnews, apolloapp")
    var subreddits: String?

    func names() -> [String] {
        (subreddits ?? "")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
            .map { $0.lowercased().hasPrefix("r/") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
    }
}

struct ShortcutsEntry: TimelineEntry {
    let date: Date
    let names: [String]
}

@available(iOS 17.0, *)
struct ShortcutsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShortcutsEntry {
        ShortcutsEntry(date: Date(), names: ["popular", "all"])
    }

    func snapshot(for configuration: ShortcutsWidgetIntent, in context: Context) async -> ShortcutsEntry {
        ShortcutsEntry(date: Date(), names: configuration.names())
    }

    func timeline(for configuration: ShortcutsWidgetIntent, in context: Context) async -> Timeline<ShortcutsEntry> {
        // "Shortcuts refreshes icons ~daily"
        Timeline(entries: [ShortcutsEntry(date: Date(), names: configuration.names())],
                 policy: .after(Date().addingTimeInterval(24 * 60 * 60)))
    }
}

@available(iOS 17.0, *)
struct ApolloShortcutsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ApolloShortcutsWidget",
                               intent: ShortcutsWidgetIntent.self,
                               provider: ShortcutsProvider()) { entry in
            ShortcutsGrid(names: entry.names)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Shortcuts")
        .description("Tiles that open subreddits in Phoebus.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ShortcutsGrid: View {
    let names: [String]
    @Environment(\.widgetFamily) private var family

    /// "Small (2x2), Medium (2x3), Large (2x4)"
    private var capacity: Int {
        switch family {
        case .systemSmall: return 4
        case .systemMedium: return 6
        default: return 8
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6),
              count: family == .systemSmall ? 2 : 3)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(names.prefix(capacity), id: \.self) { name in
                Link(destination: WidgetKitShared.DeepLink.subreddit(name)) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Self.color(for: name))
                        Text(String(name.prefix(1)).uppercased())
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    /// "a stable color palette" — derived from the name so a given
    /// subreddit always gets the same tile colour.
    static func color(for name: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red]
        let hash = name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return palette[hash % palette.count]
    }
}

// MARK: - Apollo Actions

/// "A Threads-style quick-action panel: a 'Search Apollo' pill … plus
/// four tiles — Home, Popular, All, Inbox. Sizes: Medium only. Config:
/// none (static)."
struct ActionsEntry: TimelineEntry { let date: Date }

struct ActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActionsEntry { ActionsEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (ActionsEntry) -> Void) {
        completion(ActionsEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActionsEntry>) -> Void) {
        // Static: nothing to refresh.
        completion(Timeline(entries: [ActionsEntry(date: Date())], policy: .never))
    }
}

struct ApolloActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ApolloActionsWidget", provider: ActionsProvider()) { _ in
            ActionsPanel()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Phoebus Actions")
        .description("Quick actions: search, Home, Popular, All, Inbox.")
        .supportedFamilies([.systemMedium])
    }
}

struct ActionsPanel: View {
    /// Real tiles and their order.
    private static let tiles: [(String, String, URL)] = [
        ("Home", "house.fill", WidgetKitShared.DeepLink.quickAction(.home)),
        ("Popular", "flame.fill", WidgetKitShared.DeepLink.subreddit("popular")),
        ("All", "square.stack.fill", WidgetKitShared.DeepLink.subreddit("all")),
        ("Inbox", "envelope.fill", WidgetKitShared.DeepLink.quickAction(.inbox)),
    ]

    var body: some View {
        VStack(spacing: 8) {
            Link(destination: WidgetKitShared.DeepLink.quickAction(.search)) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search Phoebus")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(.quaternary))
            }
            HStack(spacing: 8) {
                ForEach(Self.tiles, id: \.0) { tile in
                    Link(destination: tile.2) {
                        VStack(spacing: 3) {
                            Image(systemName: tile.1)
                                .font(.callout)
                            Text(tile.0)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
                    }
                }
            }
        }
    }
}
