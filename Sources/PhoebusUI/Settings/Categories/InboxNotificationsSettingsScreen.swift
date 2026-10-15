import SwiftUI
import PhoebusCore
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Inbox & Notifications: the inbox, its alerts and sound, how they reach
/// the device, and the subreddit watchers. Apollo's inbox push and
/// trending-subreddit watchers relied on its own backend relay; without it,
/// delivery goes through the self-hosted backend (see
/// `NotificationSettings.swift`). Apollo's Notifications screen, Reborn's
/// Notification Backend screen and General's Unify Modmail in Inbox are its
/// sections.
public struct InboxNotificationsSettingsScreen: View {
    @Setting(NotificationBackendSettings.self) private var notificationBackendSettings
    @Setting(NotificationSettingsStore.storage) private var settings
    @Setting(GeneralSettingsStore.storage) private var general
    @State private var authorizationStatus: String = "Checking…"
    @State private var deliveryAlert: String?
    /// The signed-in account moderates something (`is_mod`); remembered for
    /// the session so the section doesn't pop in on every visit.
    @State private var isModerator = InboxNotificationsSettingsScreen.knownModerator ?? false
    nonisolated(unsafe) private static var knownModerator: Bool?

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
            } header: {
                Text("Inbox")
                    .apolloSectionHeader()
            } footer: {
                Text(backendLive
                     ? (PushDeviceIdentity.usesAPNS(settings: notificationBackendSettings) ? "Delivered by your notification backend as push notifications: replies, mentions and messages for this account." : "Delivered by your notification backend through Bark: replies, mentions and messages for this account.")
                     : "Apollo delivered these through a push server that no longer exists. Set up a backend under \(SettingsCategory.inboxNotifications.path(section: "Delivery")) and register this device to get them.")
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

            // Stock shows this section to moderators only.
            if isModerator {
                Section {
                    Toggle("Unify Modmail in Inbox", isOn: $general.unifyModmailInInbox)
                        .apolloSearchRow("Unify Modmail in Inbox")
                } header: {
                    Text("Moderator")
                        .apolloSectionHeader()
                }
            }

            NotificationDeliverySections(alertMessage: $deliveryAlert)

            Section {
                SettingsDrillDownRow(destination: .subredditWatchers, lastBeforeFooter: true)
            } header: {
                Text("Watchers")
                    .apolloSectionHeader()
            } footer: {
                Text("Subreddit watchers and trending-subreddit alerts, delivered through your notification backend.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.inboxNotifications.title)
        .navigationBarTitleDisplayModeIfAvailable()
        .alert("Notification Backend", isPresented: $deliveryAlert.isPresent()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deliveryAlert ?? "")
        }
        .task {
            await refreshStatus()
            await loadInboxFlag()
        }
        .task {
            guard let repository = ActiveRedditRepository.provider(),
                  let me = try? await repository.fetchIdentity() else { return }
            Self.knownModerator = me.isMod
            isModerator = me.isMod
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
