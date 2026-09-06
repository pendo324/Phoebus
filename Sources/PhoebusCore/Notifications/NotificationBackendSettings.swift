import Foundation

/// Reborn's "Notification Backend" sub-screen model: a self-hosted push
/// backend (`UDKeyNotificationBackendURL`) and/or the Bark app
/// (`UDKeyBarkNotificationsEnabled`, `UDKeyBarkPushURL`) as an alternative
/// to Apple's native push. This app has no push backend of its own, so the
/// model only stores the values.
public struct NotificationBackendSettings: Codable, Sendable, Equatable {
    /// `UDKeyNotificationBackendURL`. `nil`/empty means disabled.
    public var backendURL: String?
    /// `UDKeyNotificationBackendRegistrationToken`. Only required if the
    /// self-hosted backend sets `REGISTRATION_SECRET`.
    public var registrationToken: String?
    /// `UDKeyBarkNotificationsEnabled`: deliver through the Bark app instead
    /// of native push.
    public var barkEnabled: Bool
    /// `UDKeyBarkPushURL`, e.g. `https://api.day.app/yourdevicekey`.
    public var barkPushURL: String?

    public static let `default` = NotificationBackendSettings(
        backendURL: nil,
        registrationToken: nil,
        barkEnabled: false,
        barkPushURL: nil
    )

    public init(backendURL: String?, registrationToken: String?, barkEnabled: Bool, barkPushURL: String?) {
        self.backendURL = backendURL
        self.registrationToken = registrationToken
        self.barkEnabled = barkEnabled
        self.barkPushURL = barkPushURL
    }
}

/// Same UserDefaults+JSON load/save pattern as `CustomAPISettingsStore`;
/// persistence only, since there is no push client to apply the values to.
public enum NotificationBackendSettingsStore {
    private static let key = "com.pendo324.Phoebus.notificationBackendSettings"

    public static let storage = SettingsStore<NotificationBackendSettings>(key: key) { NotificationBackendSettings.default }

    public static func load() -> NotificationBackendSettings { storage.load() }

    public static func save(_ settings: NotificationBackendSettings) { storage.save(settings) }
}

extension NotificationBackendSettings: StoredSettingsModel {
    public static var store: SettingsStore<NotificationBackendSettings> { NotificationBackendSettingsStore.storage }
}
