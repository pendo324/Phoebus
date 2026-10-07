import SwiftUI
import PhoebusCore

/// Per-subreddit post notifications, from the last row ("Subreddit
/// Notifications") of the subreddit "•••" menu.
///
/// Apollo presents this as an action sheet of choices titled "Notifications for
/// posts in " + the subreddit name, not a single switch.
///
/// Push for this ran through Apollo's own server, which no longer exists, so
/// Reddit alone cannot drive it. The sheet registers against the self-hosted
/// `apollo-backend` (`NotificationBackendSettings`, configured by Reborn's
/// Notification Backend row) and says plainly when none is configured.
public struct SubredditNotificationsSheet: View {
    let subredditName: String
    let onDone: () -> Void

    @Setting(NotificationBackendSettingsStore.storage) private var settings
    @State private var watchedSubreddits = SubredditWatchStore.load()

    public init(subredditName: String, onDone: @escaping () -> Void) {
        self.subredditName = subredditName
        self.onDone = onDone
    }

    @Environment(\.accountManager) private var accountManager
    @State private var errorMessage: String?

    /// A registered backend with Bark delivery (see `PushNotificationClient`).
    private var isConfigured: Bool {
        PushNotificationClient.deliveryActive(settings) && PushRegistrationState.isRegistered(settings)
    }

    private var isWatching: Bool {
        watchedSubreddits.contains(subredditName.lowercased())
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("New Posts", isOn: Binding(
                        get: { isWatching },
                        set: { setWatching($0) }
                    ))
                    .disabled(!isConfigured)
                    .accessibilityIdentifier("subredditNotifications.newPosts")
                } header: {
                    // Apollo's title: "Notifications for posts in "
                    // plus the subreddit.
                    Text("Notifications for posts in r/\(subredditName)")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if isConfigured {
                        Text("Apollo's own notification server is gone, so this registers with the backend configured in Settings › Apollo Reborn › Notification Backend.")
                    .apolloSectionFooter()
                    } else {
                        Text("Set up a notification backend in Settings › Apollo Reborn › Notification Backend and register this device first. Apollo's original server (apolloapp.io) no longer exists, so subreddit notifications need a self-hosted one.")
                    }
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Subreddit Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
    }

    private func setWatching(_ watching: Bool) {
        var updated = watchedSubreddits
        if watching {
            updated.insert(subredditName.lowercased())
        } else {
            updated.remove(subredditName.lowercased())
        }
        watchedSubreddits = updated
        SubredditWatchStore.save(updated)
        Task { await syncWatcher(watching) }
    }

    /// Creates or deletes the backend's subreddit watcher for this
    /// subreddit. The local set is kept as the toggle's state; the
    /// backend is the thing that actually notifies.
    private func syncWatcher(_ watching: Bool) async {
        guard isConfigured, let repository = accountManager?.repository,
              let me = try? await repository.fetchIdentity() else { return }
        do {
            if watching {
                let body = PushNotificationClient.watcherBody(type: "subreddit", subreddit: subredditName, user: nil, label: subredditName)
                try await PushNotificationClient.createWatcher(settings: settings, redditID: me.id, body: body)
            } else {
                let existing = try await PushNotificationClient.listWatchers(settings: settings, redditID: me.id)
                for w in existing where w.type == "subreddit" && w.sourceLabel.caseInsensitiveCompare(subredditName) == .orderedSame {
                    try await PushNotificationClient.deleteWatcher(settings: settings, redditID: me.id, id: w.id)
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
