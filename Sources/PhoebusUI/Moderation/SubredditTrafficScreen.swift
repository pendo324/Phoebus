import SwiftUI
import Charts
import PhoebusCore

/// Mod-only subreddit traffic: a "Uniques" / "Views" segmented control in the nav
/// bar's title view, each showing Hourly/Daily/Monthly bar charts (Swift Charts
/// `BarMark`). Uniques also shows a Subscriptions (Daily) chart; Reddit has no
/// hourly/monthly subscriptions breakdown. A secondary toolbar button pushes a
/// tables view (`trafficTablesHTML`) with Hour-of-Day / Day-of-Week / Month tables
/// of averaged uniques/views/subscriptions.
public struct SubredditTrafficScreen: View {
    let subreddit: String
    let repository: RedditRepository

    @State private var traffic: SubredditTraffic?
    @State private var errorMessage: String?
    @State private var trafficType: TrafficType = .uniques
    @State private var showingTables = false

    enum TrafficType: String, CaseIterable {
        case uniques = "Uniques"
        case views = "Views"
    }

    public init(subreddit: String, repository: RedditRepository) {
        self.subreddit = subreddit
        self.repository = repository
    }

    public var body: some View {
        Group {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            } else if traffic != nil {
                List {
                    // Apollo's titles: "Unique Visitors (Hourly)" etc, "Page Views (Hourly)" etc.
                    let metricLabel = trafficType == .uniques ? "Unique Visitors" : "Page Views"
                    barChartSection(title: "\(metricLabel) (Hourly)", points: hourlyPoints, value: metricValue)
                    barChartSection(title: "\(metricLabel) (Daily)", points: dailyPoints, value: metricValue)
                    barChartSection(title: "\(metricLabel) (Monthly)", points: monthlyPoints, value: metricValue)

                    if trafficType == .uniques {
                        // Subscriptions has only a daily breakdown in Reddit's traffic data.
                        barChartSection(title: "Subscriptions (Daily)", points: subscriptionsDailyPoints, value: { $0.subscriptions ?? 0 }, color: .green)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Traffic: r/\(subreddit)")
        .toolbar {
            // The Uniques/Views segmented control lives in the nav bar's `titleView`, not as
            // the first row of the scrolling list, so it does not scroll away.
            ToolbarItem(placement: .principal) {
                ApolloSettingsPicker("Type", selection: $trafficType,
                                 options: TrafficType.allCases.map { $0 },
                                 display: { $0.rawValue })
                .pickerStyle(.segmented)
                .accessibilityIdentifier("traffic.typePicker")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingTables = true
                } label: {
                    Image(systemName: "tablecells")
                    .accessibilityLabel("Tables")
                }
                .disabled(traffic == nil)
            }
        }
        .sheet(isPresented: $showingTables) {
            NavigationStack {
                if let traffic {
                    SubredditTrafficTablesScreen(traffic: traffic)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func barChartSection(title: String, points: [SubredditTraffic.TrafficPoint], value: @escaping (SubredditTraffic.TrafficPoint) -> Int, color: Color = .blue) -> some View {
        Section(title) {
            if points.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value(title, value(point))
                    )
                    .foregroundStyle(color)
                }
                .frame(height: 180)
            }
        }
    }

    private var metricValue: (SubredditTraffic.TrafficPoint) -> Int {
        trafficType == .uniques ? { $0.uniques } : { $0.pageviews }
    }

    private var hourlyPoints: [SubredditTraffic.TrafficPoint] { traffic?.hour ?? [] }
    private var dailyPoints: [SubredditTraffic.TrafficPoint] { traffic?.day ?? [] }
    private var monthlyPoints: [SubredditTraffic.TrafficPoint] { traffic?.month ?? [] }
    private var subscriptionsDailyPoints: [SubredditTraffic.TrafficPoint] { traffic?.day ?? [] }

    private func load() async {
        do {
            traffic = try await repository.fetchSubredditTraffic(subreddit: subreddit)
        } catch {
            errorMessage = "Couldn't load traffic stats. This is only available to subreddit moderators."
        }
    }
}

/// The tables view: the same traffic data as three plain tables (Hour of Day / Day
/// of Week / Month) for precise numeric reading, as a SwiftUI `List` rather than a
/// `WKWebView` since the content is only tabular data.
struct SubredditTrafficTablesScreen: View {
    let traffic: SubredditTraffic

    var body: some View {
        List {
            Section("Hour of Day") {
                ForEach(0..<24, id: \.self) { hour in
                    let (uniques, views) = hourlyAverages(hour)
                    HStack {
                        Text("\(hour):00")
                        Spacer()
                        Text("\(uniques) uniques").font(.caption).foregroundStyle(.secondary)
                        Text("\(views) views").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Day of Week") {
                ForEach(1...7, id: \.self) { weekday in
                    let (uniques, views, subs) = dailyAverages(weekday)
                    HStack {
                        Text(Self.dayNames[weekday - 1])
                        Spacer()
                        Text("\(uniques) uniques").font(.caption).foregroundStyle(.secondary)
                        Text("\(views) views").font(.caption).foregroundStyle(.secondary)
                        Text("\(subs) subs").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Month") {
                ForEach(traffic.month) { point in
                    HStack {
                        Text(point.date, format: .dateTime.month(.abbreviated).year())
                        Spacer()
                        Text("\(point.uniques) uniques").font(.caption).foregroundStyle(.secondary)
                        Text("\(point.pageviews) views").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Traffic Tables")
    }

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private func hourlyAverages(_ hour: Int) -> (uniques: Int, views: Int) {
        let matches = traffic.hour.filter { Calendar.current.component(.hour, from: $0.date) == hour }
        guard !matches.isEmpty else { return (0, 0) }
        return (matches.map(\.uniques).reduce(0, +) / matches.count, matches.map(\.pageviews).reduce(0, +) / matches.count)
    }

    private func dailyAverages(_ weekday: Int) -> (uniques: Int, views: Int, subs: Int) {
        let matches = traffic.day.filter { Calendar.current.component(.weekday, from: $0.date) == weekday }
        guard !matches.isEmpty else { return (0, 0, 0) }
        let subsSum = matches.compactMap(\.subscriptions).reduce(0, +)
        return (
            matches.map(\.uniques).reduce(0, +) / matches.count,
            matches.map(\.pageviews).reduce(0, +) / matches.count,
            subsSum / matches.count
        )
    }
}
