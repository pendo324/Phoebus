import SwiftUI
import PhoebusCore
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Notifications settings. Apollo's inbox push and trending-subreddit watchers
/// relied on its own backend relay; without it, delivery goes through the
/// self-hosted backend (see `NotificationSettings.swift`).
public struct NotificationsSettingsScreen: View {
    @Setting(NotificationBackendSettings.self) private var notificationBackendSettings
    @Setting(NotificationSettingsStore.storage) private var settings
    @State private var authorizationStatus: String = "Checking…"

    public init() {}

    @Environment(\.accountManager) private var accountManager
    @State private var syncingFromServer = false

    /// A registered backend with Bark delivery.
    private var backendLive: Bool {
        let backend = notificationBackendSettings
        return PushNotificationClient.deliveryActive(backend) && PushRegistrationState.isRegistered(backend)
    }

    /// With a live backend the toggle shows the server's flag, which defaults to on
    /// at registration.
    private func loadInboxFlag() async {
        guard backendLive, let repository = accountManager?.repository,
              let me = try? await repository.fetchIdentity(),
              let flags = try? await PushNotificationClient.accountNotifications(
                settings: notificationBackendSettings, redditID: me.id) else { return }
        syncingFromServer = true
        $settings.update { $0.inboxNotificationsEnabled = flags.inbox }
        syncingFromServer = false
    }

    private func pushInboxFlag(_ on: Bool) async {
        guard !syncingFromServer else { return }
        guard backendLive, let repository = accountManager?.repository,
              let me = try? await repository.fetchIdentity() else { return }
        // Only the inbox flag changes: the watcher and mute state stay as
        // the server has them.
        let current = try? await PushNotificationClient.accountNotifications(
            settings: notificationBackendSettings, redditID: me.id)
        try? await PushNotificationClient.setAccountNotifications(
            settings: notificationBackendSettings, redditID: me.id,
            inbox: on, watchers: current?.watchers ?? true, globalMute: current?.globalMute ?? false)
    }

    public var body: some View {
        List {
            // Contextual status banner. Only "Notifications disabled. Tap to change." is
            // achievable here; the Ultra-billing variants are out of scope.
            if authorizationStatus == "Denied" {
                Section {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label("Notifications disabled. Tap to change.", systemImage: "bell.slash.fill")
                            .foregroundStyle(.orange)
                    }
                    .apolloPlainSettingsRowInsets(rule: false)
                }
            }

            // With a registered backend this is the account's `inbox_notifications` flag on
            // the server (`PATCH .../notifications`); without one it only governs local
            // permission.
            Section {
                Toggle("Inbox Notifications", isOn: $settings.inboxNotificationsEnabled)
                    .apolloSearchRow("Inbox Notifications", lastBeforeFooter: true)
                    .onChange(of: settings.inboxNotificationsEnabled) { _, newValue in
                        if newValue && !backendLive {
                            Task {
                                let granted = await RemindMeScheduler.requestAuthorizationIfNeeded()
                                if !granted { $settings.update { $0.inboxNotificationsEnabled = false } }
                                await refreshStatus()
                            }
                        }
                        Task { await pushInboxFlag(newValue) }
                    }
            } footer: {
                Text(backendLive
                     ? (PushDeviceIdentity.usesAPNS(settings: notificationBackendSettings) ? "Delivered by your notification backend as push notifications: replies, mentions and messages for this account." : "Delivered by your notification backend through Bark: replies, mentions and messages for this account.")
                     : "Apollo delivered these through a push server that no longer exists. Set up a backend under Settings › Apollo Reborn › Notification Backend and register this device to get them.")
                    .apolloSectionFooter()
            }

            Section {
                ApolloSettingsPicker("Sound", selection: $settings.notificationSound,
                                 options: NotificationSound.allCases.map { $0 },
                                 display: { $0.displayName })
                    .apolloSearchRow("Sound")
                    // A registered backend gets the new sound straight away.
                    .onChange(of: settings.notificationSound) { _, sound in
                        guard PushRegistrationState.isRegistered(notificationBackendSettings) else { return }
                        Task {
                            try? await PushNotificationClient.syncDevice(settings: notificationBackendSettings,
                                                                         soundID: sound.barkSoundID)
                        }
                    }
            } header: {
                Text("Notification Sound")
                    .apolloSectionHeader()
            }

            // Subreddit watchers and trending subreddits, backed by the self-hosted
            // backend's watchers (`/v1/device/{token}/account/{id}/watcher(s)`).
            WatchersSection(backendLive: backendLive)

        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Notifications")
        .task {
            await refreshStatus()
            await loadInboxFlag()
        }
    }

    private func refreshStatus() async {
        #if canImport(UserNotifications)
        switch await RemindMeScheduler.currentAuthorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            authorizationStatus = "Enabled"
        case .denied:
            authorizationStatus = "Denied"
        case .notDetermined:
            authorizationStatus = "Not Determined"
        @unknown default:
            authorizationStatus = "Unknown"
        }
        #else
        authorizationStatus = "Unsupported"
        #endif
    }

    private func openSystemSettings() {
        #if canImport(UIKit) && !os(watchOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
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
        Text("Subreddit watchers and trending alerts need a notification backend. Set one up under Settings › Apollo Reborn › Notification Backend and register this device.")
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
