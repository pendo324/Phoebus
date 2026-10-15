import SwiftUI
import PhoebusCore

/// Reborn-style Subreddit Watchers: the watchers and trending-subreddit
/// alerts the self-hosted backend runs for this device.
public struct SubredditWatchersScreen: View {
    @Setting(NotificationBackendSettings.self) private var notificationBackendSettings

    public init() {}

    /// A registered backend with Bark delivery.
    private var backendLive: Bool {
        PushNotificationClient.deliveryActive(notificationBackendSettings)
            && PushRegistrationState.isRegistered(notificationBackendSettings)
    }

    public var body: some View {
        List {
            WatchersSection(backendLive: backendLive)
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Subreddit Watchers")
        .navigationBarTitleDisplayModeIfAvailable()
    }
}

/// Apollo's "Subreddit Watchers" and "Trending Subreddits" sections, backed by the
/// self-hosted backend's watchers (`/v1/device/{token}/account/{id}/watcher(s)`).
struct WatchersSection: View {
    @Setting(NotificationBackendSettings.self) private var notificationBackendSettings
    let backendLive: Bool
    @Environment(\.accountManager) private var accountManager
    @State private var watchers: [PushNotificationClient.Watcher] = []
    @State private var redditID: String?
    @State private var composing: ComposeKind?
    @State private var error: String?

    enum ComposeKind: Int, Identifiable { case subreddit, trending; var id: Int { rawValue } }

    private var subredditWatchers: [PushNotificationClient.Watcher] { watchers.filter { $0.type != "trending" } }
    private var trendingWatchers: [PushNotificationClient.Watcher] { watchers.filter { $0.type == "trending" } }

    var body: some View {
        Section {
            if !backendLive {
                unavailable
            } else {
                ForEach(subredditWatchers) { w in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.type == "user" ? "u/\(w.sourceLabel)" : (w.label.isEmpty ? "r/\(w.sourceLabel)" : w.label))
                        Text(Self.summary(w)).font(.caption).foregroundStyle(.secondary)
                    }
                    .apolloPlainSettingsRowInsets()
                    .accessibilityIdentifier("notifications.watcher.\(w.id)")
                }
                .onDelete { offsets in
                    let targets = offsets.map { subredditWatchers[$0] }
                    Task { await delete(targets) }
                }
                adder("Add Subreddit Watcher", kind: .subreddit)
            }
        } header: {
            Text("Subreddit Watchers").apolloSectionHeader()
        }
        // On the Section, not an EmptyView: an EmptyView inside a List is never
        // instantiated, so its `.task` would never run.
        .task(id: backendLive) { await load() }
        if backendLive {
            Section {
                ForEach(trendingWatchers) { w in
                    Text("r/\(w.sourceLabel)")
                        .apolloPlainSettingsRowInsets()
                        .accessibilityIdentifier("notifications.trending.\(w.id)")
                }
                .onDelete { offsets in
                    let targets = offsets.map { trendingWatchers[$0] }
                    Task { await delete(targets) }
                }
                adder("Watch a Subreddit for Trending Posts", kind: .trending)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).apolloPlainSettingsRowInsets(rule: false)
                }
            } header: {
                Text("Trending Subreddits").apolloSectionHeader()
            }
        }
    }

    private var unavailable: some View {
        Text("Subreddit watchers and trending alerts need a notification backend. Set one up under \(SettingsCategory.inboxNotifications.path(section: "Delivery")) and register this device.")
            .apolloFont(size: ApolloSettingsRowMetrics.footerPointSize)
            .foregroundStyle(Color.apolloSettingsSecondary)
            .apolloPlainSettingsRowInsets(rule: false)
            // Footer text, so no card behind it in light mode.
            .listRowBackground(Color.clear)
    }

    private func adder(_ title: String, kind: ComposeKind) -> some View {
        Button {
            composing = kind
        } label: {
            Label(title, systemImage: "plus.circle.fill")
        }
        .disabled(redditID == nil)
        // The sheet hangs off its own button: a `.sheet` on a List Section never presents.
        .sheet(isPresented: Binding(get: { composing == kind }, set: { if !$0 { composing = nil } })) {
            if let redditID {
                WatcherComposerScreen(redditID: redditID, trending: kind == .trending) {
                    Task { await load() }
                }
            }
        }
        .apolloPlainSettingsRowInsets()
        .accessibilityIdentifier(kind == .trending ? "notifications.addTrending" : "notifications.addWatcher")
    }

    /// "r/linux · “kde” · ≥ 100 · 3 hits".
    static func summary(_ w: PushNotificationClient.Watcher) -> String {
        var parts = [w.type == "user" ? "New posts by u/\(w.sourceLabel)" : "r/\(w.sourceLabel)"]
        if let k = w.keyword, !k.isEmpty { parts.append("“\(k)”") }
        if let f = w.flair, !f.isEmpty { parts.append("flair: \(f)") }
        if let d = w.domain, !d.isEmpty { parts.append("link: \(d)") }
        if let a = w.author, !a.isEmpty { parts.append("u/\(a)") }
        if let u = w.upvotes, u > 0 { parts.append("≥ \(u) upvotes") }
        if w.hits > 0 { parts.append("\(w.hits) hit\(w.hits == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard backendLive, let repository = accountManager?.repository else { return }
        if redditID == nil { redditID = try? await repository.fetchIdentity().id }
        guard let redditID else { return }
        do {
            watchers = try await PushNotificationClient.listWatchers(settings: notificationBackendSettings, redditID: redditID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ targets: [PushNotificationClient.Watcher]) async {
        guard let redditID else { return }
        for w in targets {
            try? await PushNotificationClient.deleteWatcher(settings: notificationBackendSettings, redditID: redditID, id: w.id)
        }
        await load()
    }
}
