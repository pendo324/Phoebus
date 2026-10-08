#if canImport(UIKit)
import UIKit
import UserNotifications
import BackgroundTasks
import os
import PhoebusCore

/// The home-screen side of notifications, three ways, so the app icon's
/// badge follows the inbox as Apollo's does:
///
///  1. While the app runs, `InboxBadge` sets the icon badge with the tab
///     badge (`setAppIconBadge`).
///  2. In the background, iOS wakes the app now and then
///     (`BGAppRefreshTask`) to fetch the unread count and update it.
///  3. With push in the signing (`aps-environment`), the self-hosted
///     backend pushes straight to this app over APNs, and each push sets
///     the badge itself. Without it the backend delivers through Bark,
///     which can only badge the Bark app, so 1 and 2 carry the badge.
///
/// It is also the notification center's delegate: taps on backend
/// notifications open their thread or the inbox, and Remind Me taps open
/// their post.
@MainActor
public final class PushNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = PushNotificationCoordinator()

    /// Listed in Info.plist's `BGTaskSchedulerPermittedIdentifiers`.
    public static let refreshTaskIdentifier = "com.pendo324.Phoebus.inbox-badge-refresh"

    /// The accounts to (re-)register when an APNs token first arrives,
    /// supplied by the app's `AccountManager`.
    public var registrationAccounts: (() async -> [PushNotificationClient.Account])?

    /// Last Reddit Chat unread count seen in the foreground. Chat needs a
    /// browser-minted token the background fetch can't get, so it reuses
    /// this rather than dropping chat from the badge.
    private static let chatUnreadKey = "com.pendo324.Phoebus.lastChatUnread"

    // MARK: Launch

    /// From `application(_:didFinishLaunchingWithOptions:)`: background
    /// tasks must be registered before launch finishes.
    public func applicationDidFinishLaunching(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        // On the main queue: the handler is main-actor isolated, and on
        // BackgroundTasks' own queue Swift's isolation check aborts.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            MainActor.assumeIsolated { Self.shared.handle(task) }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.shared.scheduleRefresh() }
        }
        Task { await registerForRemoteNotificationsIfAuthorized() }
    }

    /// Asks for notification permission once, after sign-in, and registers
    /// for APNs when granted. Registering never prompts; a signing without
    /// push fails it quietly (`didFailToRegister`).
    public func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            // The count was set before badges were allowed.
            setAppIconBadge(InboxBadge.shared.unreadCount)
        }
        await registerForRemoteNotificationsIfAuthorized()
    }

    private func registerForRemoteNotificationsIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: App icon badge

    /// Sets the home-screen badge to the unread count, when the user
    /// allows badges.
    public func setAppIconBadge(_ count: Int, chatUnread: Int? = nil) {
        if let chatUnread { UserDefaults.standard.set(chatUnread, forKey: Self.chatUnreadKey) }
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().badgeSetting == .enabled else { return }
            try? await center.setBadgeCount(max(0, count))
        }
    }

    // MARK: Background refresh

    /// Asks iOS for the next background wake. iOS decides when, from how
    /// the app is used; 15 minutes is only the earliest it may come.
    public func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.log.error("could not schedule the background inbox refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "com.pendo324.Phoebus", category: "badge")

    private func handle(_ task: BGAppRefreshTask) {
        scheduleRefresh()
        Self.log.info("background inbox refresh started")
        let work = Task { @MainActor in
            guard let repository = AccountManager.makeActiveRepository() else {
                Self.log.info("background inbox refresh: no account")
                task.setTaskCompleted(success: false)
                return
            }
            let inbox: Int
            do {
                inbox = try await repository.fetchUnreadInboxCount()
            } catch {
                Self.log.error("background inbox refresh failed: \(error.localizedDescription, privacy: .public)")
                task.setTaskCompleted(success: false)
                return
            }
            let chat = UserDefaults.standard.integer(forKey: Self.chatUnreadKey)
            let count = InboxUnreadCount.combined(inbox: inbox, chat: chat,
                                                  inboxListsChat: !(await repository.inboxLacksChatMirrors))
            Self.log.info("background inbox refresh: \(count, privacy: .public) unread")
            setAppIconBadge(count)
            task.setTaskCompleted(success: true)
        }
        // Called on a background queue, so it must not inherit this
        // method's main-actor isolation.
        task.expirationHandler = { @Sendable in work.cancel() }
    }

    // MARK: APNs registration

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        let changed = PushDeviceIdentity.storeAPNSToken(deviceToken, sandbox: Self.signingUsesSandboxAPNS())
        guard changed else { return }
        Task { await moveRegistrationToAPNS() }
    }

    public func didFailToRegisterForRemoteNotifications(error: Error) {
        // NSCocoaErrorDomain 3000: no `aps-environment` in this signing,
        // which won't change until the app is re-signed. Bark stays.
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == 3000 {
            PushDeviceIdentity.clearAPNSToken()
        }
    }

    /// When the device was registered with the backend before (through
    /// Bark, or an older APNs token), registers it again under the new
    /// token, so notifications switch to native push without a visit to
    /// Settings.
    private func moveRegistrationToAPNS() async {
        let settings = NotificationBackendSettingsStore.load()
        guard PushRegistrationState.hasRegistration, PushNotificationClient.backendURL(settings) != nil,
              let accounts = await registrationAccounts?(), !accounts.isEmpty else { return }
        let api = CustomAPISettingsStore.load()
        do {
            try await PushNotificationClient.moveToAPNS(
                settings: settings, accounts: accounts,
                soundID: NotificationSettingsStore.load().notificationSound.barkSoundID,
                clientID: RedditOAuthConfig.clientID, clientSecret: RedditOAuthConfig.clientSecret,
                redirectURI: RedditOAuthConfig.redirectURI,
                userAgent: api.userAgent.flatMap { $0.isEmpty ? nil : $0 } ?? RedditAPIClient.oauthUserAgent)
            PushRegistrationState.markRegistered(settings)
        } catch {}
    }

    /// Apple's sandbox gateway serves development-signed builds. Read from
    /// the embedded provisioning profile; without one, production.
    private static func signingUsesSandboxAPNS() -> Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return false }
        return PushDeviceIdentity.apsEnvironment(provisioningProfile: data) == "development"
    }

    // MARK: UNUserNotificationCenterDelegate

    // The completion-handler forms, not the async ones: Swift calls an
    // async delegate method's completion off the main thread, and UIKit
    // asserts on that once the app takes the tap (a crash on every tap).

    /// In the foreground, a backend push shows as a banner and refreshes
    /// the inbox badge.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async {
            Task { await InboxBadge.shared.refresh() }
            completionHandler([.banner, .list, .sound])
        }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let url: URL?
        if let permalink = userInfo["permalink"] as? String, !permalink.isEmpty {
            // Remind Me.
            let path = permalink.hasPrefix("/") ? permalink : "/" + permalink
            url = URL(string: "\(PushNotificationClient.scheme)://reddit.com\(path)")
        } else {
            url = PushNotificationClient.appURL(fromPushPayload: userInfo)
        }
        DispatchQueue.main.async {
            if let url { UIApplication.shared.open(url) }
            completionHandler()
        }
    }
}
#endif
