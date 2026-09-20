import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Schedules a local notification reminding the user about a post at a
/// chosen delay or date (Apollo's Remind Me). Local scheduling needs no push
/// infrastructure and works offline. UserNotifications is Apple-only, so it
/// is gated with `#if canImport` to keep PhoebusCore building on Linux.
public enum RemindMeScheduler {
    #if canImport(UserNotifications)
    public static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Queries current permission status without triggering the system prompt,
    /// for the Notifications settings banner ("Notifications disabled. Tap to
    /// change.").
    public static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Schedules a reminder. `fireDate` should be in the future.
    public static func scheduleReminder(postTitle: String, postPermalink: String, fireDate: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = postTitle
        // The "Notification Sound" setting; `nil` (the "None" option) is silent.
        content.sound = NotificationSettingsStore.load().notificationSound.unNotificationSound
        content.userInfo = ["permalink": postPermalink]

        let interval = max(fireDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }
    #else
    public static func requestAuthorizationIfNeeded() async -> Bool { false }
    public static func currentAuthorizationStatus() async -> Int { 0 }
    public static func scheduleReminder(postTitle: String, postPermalink: String, fireDate: Date) async throws {
        throw RemindMeError.unsupportedPlatform
    }
    #endif

    /// Matches Apollo's "Or Choose Hours…" quick-pick options.
    public static let quickPickHours: [Int] = [1, 3, 6, 12, 24, 72, 168]
}

public enum RemindMeError: Error {
    case unsupportedPlatform
}
