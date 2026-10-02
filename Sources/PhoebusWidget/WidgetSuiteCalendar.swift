import WidgetKit
import SwiftUI
import AppIntents
import PhoebusCore

// MARK:, Calendar

/// One locked photo of the day from a subreddit with the date overlaid. It
/// picks one image per calendar day deterministically and persists it, so it
/// never changes during the day and avoids repeats (rolling ~150-day history).
/// Sort is always Top: This Week.
@available(iOS 17.0, *)
struct CalendarWidgetIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Calendar"
    static let description = IntentDescription("A photo of the day with the date overlaid.")

    @Parameter(title: "Subreddit or Multireddit", default: "EarthPorn")
    var query: String?
    @Parameter(title: "Date Style", default: .rounded)
    var dateStyle: CalendarDateStyle
    /// "Show Title (default off)"
    @Parameter(title: "Show Title", default: false)
    var showTitle: Bool

    func resolvedSource() -> WidgetFeedSource {
        WidgetFeedSource.parse(query ?? "") ?? .subreddits(["EarthPorn"])
    }
}

/// The five real date styles, each a distinct system font.
@available(iOS 17.0, *)
enum CalendarDateStyle: String, AppEnum {
    case rounded, serif, mono, condensed, stamp

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Date Style")
    static let caseDisplayRepresentations: [CalendarDateStyle: DisplayRepresentation] = [
        .rounded: "Rounded", .serif: "Serif", .mono: "Mono",
        .condensed: "Condensed", .stamp: "Stamp",
    ]

    /// "Rounded – SF Pro Rounded … Serif – New York … Mono –
    /// monospaced digital readout …"
    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        case .condensed, .stamp: return .default
        }
    }
}

struct CalendarEntry: TimelineEntry {
    let date: Date
    let post: RedditPost?
    let style: CalendarDateStyle
    let showTitle: Bool
    let message: String?
    /// The photo itself, fetched in the provider: a widget view cannot run
    /// async work, so an image it had to load would stay blank.
    var imageData: Data?
}

@available(iOS 17.0, *)
struct CalendarProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        CalendarEntry(date: Date(), post: nil, style: .rounded, showTitle: false,
                      message: nil, imageData: nil)
    }

    func snapshot(for configuration: CalendarWidgetIntent, in context: Context) async -> CalendarEntry {
        await entry(for: configuration, on: Date())
    }

    func timeline(for configuration: CalendarWidgetIntent, in context: Context) async -> Timeline<CalendarEntry> {
        // It pre-renders the next few days so the photo flips at
        // midnight even without a reload.
        var entries: [CalendarEntry] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for offset in 0..<3 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            entries.append(await entry(for: configuration, on: day))
        }
        let next = calendar.date(byAdding: .day, value: 3, to: today) ?? Date()
        return Timeline(entries: entries, policy: .after(next))
    }

    private func entry(for configuration: CalendarWidgetIntent, on day: Date) async -> CalendarEntry {
        // Sort is FIXED to Top: This Week, "(best image)".
        switch await WidgetFetcher.pool(source: configuration.resolvedSource(),
                                        sort: .topWeek, limit: 25) {
        case .success(let fetched):
            let pool = WidgetKitShared.imagePostsOnly(fetched)
            guard !pool.isEmpty else {
                return CalendarEntry(date: day, post: nil, style: configuration.dateStyle,
                                     showTitle: configuration.showTitle, message: "No photos",
                                     imageData: nil)
            }
            let index = CalendarPhotoPicker.index(for: day, poolSize: pool.count)
            let chosen = pool[index]
            return CalendarEntry(date: day, post: chosen, style: configuration.dateStyle,
                                 showTitle: configuration.showTitle, message: nil,
                                 imageData: await WidgetFetcher.imageData(for: chosen))
        case .failure(let error):
            return CalendarEntry(date: day, post: nil, style: configuration.dateStyle,
                                 showTitle: configuration.showTitle, message: error.message,
                                 imageData: nil)
        }
    }
}

@available(iOS 17.0, *)
struct ApolloCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ApolloCalendarWidget",
                               intent: CalendarWidgetIntent.self,
                               provider: CalendarProvider()) { entry in
            CalendarPhotoView(entry: entry)
                // The photo belongs in the container background (iOS 17+): the system
                // sizes and clips it to the widget's shape, rounded corners included, and
                // it stays out of the content layout. Drawn inside the view (a
                // `.resizable().scaledToFill()` in a ZStack), the image would size the
                // stack, grow the content past the widget bounds and push the title off
                // the bottom edge.
                .containerBackground(for: .widget) {
                    if let data = entry.imageData, let image = UIImage(data: data) {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                            // Scrim, so white date text stays legible
                            // over a bright sky. Bottom-weighted
                            // because the date sits bottom-leading.
                            LinearGradient(
                                colors: [.black.opacity(0.65), .clear],
                                startPoint: .bottom, endPoint: .center)
                        }
                    } else {
                        Color.black
                    }
                }
        }
        .configurationDisplayName("Calendar")
        .description("A photo of the day with the date overlaid.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CalendarPhotoView: View {
    let entry: CalendarEntry

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: entry.date)
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        // Only the date furniture lives here; the photo is the container
        // background.
        VStack(alignment: .leading, spacing: 2) {
            Text(dayNumber)
                .font(.system(size: 44, weight: .heavy, design: entry.style.design))
                .foregroundStyle(.white)
            Text(monthName.uppercased())
                .font(.system(size: 11, weight: .semibold, design: entry.style.design))
                .foregroundStyle(.white.opacity(0.85))
            if entry.style == .mono {
                // "monospaced digital readout with an ISO date line"
                Text(entry.date.formatted(.iso8601.year().month().day()))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if entry.showTitle, let post = entry.post {
                Text(post.title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
        // Fill the widget and pin the date to the bottom-leading
        // corner. Without the explicit frame the stack shrinks to its
        // text and centres itself.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .rotationEffect(.degrees(entry.style == .stamp ? -8 : 0))
    }
}

// MARK:, Headline

/// The top headline from a subreddit, on your Lock Screen. Sizes:
/// Lock Screen only (Rectangular, Inline). Fetches the current top
/// ~10 (Hot) and rotates through their titles.
/// Default r/worldnews.
@available(iOS 17.0, *)
struct HeadlineWidgetIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Headline"
    static let description = IntentDescription("The top headline from a subreddit.")

    @Parameter(title: "Subreddit or Multireddit", default: "worldnews")
    var query: String?

    func resolvedSource() -> WidgetFeedSource {
        WidgetFeedSource.parse(query ?? "") ?? .subreddits(["worldnews"])
    }
}

@available(iOS 17.0, *)
struct HeadlineProvider: AppIntentTimelineProvider {
    static let poolSize = 10

    func placeholder(in context: Context) -> FixedFeedEntry {
        FixedFeedEntry(date: Date(), post: nil, message: nil)
    }

    func snapshot(for configuration: HeadlineWidgetIntent, in context: Context) async -> FixedFeedEntry {
        await entry(for: configuration, at: Date())
    }

    func timeline(for configuration: HeadlineWidgetIntent, in context: Context) async -> Timeline<FixedFeedEntry> {
        let now = Date()
        return Timeline(entries: [await entry(for: configuration, at: now)],
                        policy: .after(WidgetKitShared.Rotation.nextChange(after: now)))
    }

    private func entry(for configuration: HeadlineWidgetIntent, at date: Date) async -> FixedFeedEntry {
        switch await WidgetFetcher.pool(source: configuration.resolvedSource(),
                                        sort: .hot, limit: Self.poolSize) {
        case .success(let pool):
            let index = WidgetKitShared.Rotation.index(at: date, poolSize: pool.count)
            return FixedFeedEntry(date: date, post: pool[index], message: nil)
        case .failure(let error):
            return FixedFeedEntry(date: date, post: nil, message: error.message)
        }
    }
}

@available(iOS 17.0, *)
struct ApolloHeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ApolloHeadlineWidget",
                               intent: HeadlineWidgetIntent.self,
                               provider: HeadlineProvider()) { entry in
            // "Text-only, like all Lock-Screen widgets."
            Text(entry.post?.title ?? entry.message ?? "Loading…")
                .font(.caption)
                .lineLimit(3)
                .widgetURL(entry.post.map(WidgetKitShared.DeepLink.post))
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Headline")
        .description("The top headline from a subreddit, on your Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
