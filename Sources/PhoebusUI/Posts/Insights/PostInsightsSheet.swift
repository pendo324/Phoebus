import SwiftUI
import Charts
import PhoebusCore

/// Phoebus-only "Insights" for your own post: Reddit's author-only
/// `/poststats/<id>/` page, shown natively. Needs the web session, like
/// Comment Insights; without one it offers the web sign-in.
struct PostInsightsSheet: View {
    let post: RedditPost
    let repository: RedditRepository

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accountManager) private var accountManager
    @State private var insights: PostInsights?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var needsWebSession = false
    @State private var showingSignIn = false
    @State private var selectedHour: Int?

    var body: some View {
        NavigationStack {
            List {
                if let insights {
                    content(insights)
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .accessibilityIdentifier("postInsights.loading")
                } else if needsWebSession {
                    Text("Post Insights needs a Reddit web session. Sign in on the web to see how your posts are doing.")
                        .foregroundStyle(.secondary)
                    Button("Sign In on the Web") { showingSignIn = true }
                        .accessibilityIdentifier("postInsights.signIn")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn't load Insights.")
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("postInsights.error")
                    Button("Try Again") { Task { await load() } }
                        .accessibilityIdentifier("postInsights.retry")
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Post Insights")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("postInsights.done")
                }
            }
            .refreshable { await load() }
        }
        .task { await load() }
        .sheet(isPresented: $showingSignIn) {
            NavigationStack {
                WebSessionLoginScreen(
                    requiredUsername: activeUsername,
                    onSuccess: { credential in
                        showingSignIn = false
                        accountManager?.addWebSessionAccount(credential)
                        Task { await load() }
                    },
                    onCancel: { showingSignIn = false }
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ insights: PostInsights) -> some View {
        if insights.isEmpty {
            Text("Reddit hasn't reported any Insights for this post yet.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("postInsights.empty")
        }
        Section {
            Text(insights.postTitle ?? post.title)
                .font(.headline)
            metricRow("Views", insights.views, id: "views")
            metricRow("Upvotes", insights.upvotes, id: "upvotes")
            if let ratio = insights.upvoteRatioPercent {
                LabeledContent("Upvote Ratio", value: "\(formatted(ratio))%")
                    .accessibilityIdentifier("postInsights.ratio")
            }
            metricRow("Comments", insights.comments, id: "comments")
            metricRow("Shares", insights.shares, id: "shares")
            metricRow("Reposts", insights.reposts, id: "reposts")
            metricRow("Awards", insights.awards, id: "awards")
        }
        if !insights.hourlyViews.isEmpty {
            Section("Views for the First 48 Hours") {
                viewsChart(insights)
            }
        }
        if !insights.countries.isEmpty {
            Section("Top Countries by Views") {
                ForEach(insights.countries) { country in
                    countryRow(country)
                }
            }
        }
        if !insights.topComments.isEmpty {
            Section("Top Comments") {
                ForEach(insights.topComments) { comment in
                    Button { open(comment) } label: { commentRow(comment) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("postInsights.comment.\(comment.commentID)")
                }
            }
        }
    }

    @ViewBuilder
    private func metricRow(_ title: String, _ value: Int?, id: String) -> some View {
        if let value {
            LabeledContent(title, value: value.formatted())
                .accessibilityIdentifier("postInsights.\(id)")
        }
    }

    private func viewsChart(_ insights: PostInsights) -> some View {
        let points = Array(insights.hourlyViews.enumerated())
        return VStack(alignment: .leading, spacing: 8) {
            Text(selectedHour.flatMap { insights.hourLabel($0) } ?? "Touch and drag the chart for a single hour")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Chart {
                ForEach(points, id: \.offset) { point in
                    BarMark(x: .value("Hour", point.offset + 1), y: .value("Views", point.element))
                        .foregroundStyle(selectedHour == nil || selectedHour == point.offset + 1
                                         ? Color.apolloAccent : Color.apolloAccent.opacity(0.35))
                }
            }
            .chartXSelection(value: $selectedHour)
            .chartXScale(domain: 0.5...Double(max(insights.hourlyViews.count, 1)) + 0.5)
            .chartXAxis {
                AxisMarks(values: [1, 12, 24, 36, 48]) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Views for the first 48 hours")
            .accessibilityValue(insights.chartAccessibilitySummary)
            .accessibilityChartDescriptor(PostInsightsChartDescriptor(insights: insights))
            .accessibilityIdentifier("postInsights.chart")
        }
    }

    private func countryRow(_ country: PostInsights.CountryShare) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let flag = country.flag { Text(flag) }
                Text(country.name)
                Spacer()
                Text("\(formatted(country.percent))%")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(country.percent, 0), 100), total: 100)
                .tint(Color.apolloAccent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(country.name), \(formatted(country.percent)) percent")
        .accessibilityIdentifier("postInsights.country.\(country.name)")
    }

    private func commentRow(_ comment: PostInsights.TopComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author).font(.subheadline.weight(.semibold))
                Text(comment.ageText).foregroundStyle(.secondary)
                Spacer()
                if let votes = comment.votes {
                    Text(votes.formatted()).foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            Text(comment.text)
                .lineLimit(4)
        }
        .contentShape(Rectangle())
    }

    /// Dismisses the sheet, then opens the comment through the app's Reddit
    /// link routing, which pushes it natively.
    private func open(_ comment: PostInsights.TopComment) {
        guard let url = comment.url else { return }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            openURL(url)
        }
    }

    private var activeUsername: String? {
        guard let accountManager, let index = accountManager.activeIndex,
              accountManager.accounts.indices.contains(index) else { return nil }
        return accountManager.accounts[index].username
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard await repository.hasWebFeatureSession() else {
            needsWebSession = true
            return
        }
        needsWebSession = false
        do {
            insights = try await repository.fetchPostInsights(postID: post.id)
            errorMessage = nil
        } catch {
            // A failed refresh keeps the numbers already on screen.
            if insights == nil { errorMessage = error.localizedDescription }
        }
    }

    private func formatted(_ percent: Double) -> String {
        percent == percent.rounded() ? String(Int(percent)) : String(format: "%.1f", percent)
    }
}

/// VoiceOver's audio-graph description of the 48-hour views chart.
private struct PostInsightsChartDescriptor: AXChartDescriptorRepresentable {
    let insights: PostInsights

    func makeChartDescriptor() -> AXChartDescriptor {
        let counts = insights.hourlyViews
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Hour", range: 1...Double(max(counts.count, 1)), gridlinePositions: []
        ) { "Hour \(Int($0))" }
        let peak = Double(counts.max() ?? 0)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Views", range: 0...max(peak, 1), gridlinePositions: []
        ) { "\(Int($0)) views" }
        let series = AXDataSeriesDescriptor(
            name: "Views", isContinuous: false,
            dataPoints: counts.enumerated().map { AXDataPoint(x: Double($0.offset + 1), y: Double($0.element)) }
        )
        return AXChartDescriptor(
            title: "Views for the first 48 hours", summary: insights.chartAccessibilitySummary,
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}
