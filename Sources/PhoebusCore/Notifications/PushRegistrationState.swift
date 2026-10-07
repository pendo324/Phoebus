import Foundation

/// Which backend and Bark URL this device last registered with, so the
/// Notifications screen can say whether push is live and re-register
/// when the configuration changes.
public enum PushRegistrationState {
    private static let key = "com.pendo324.Phoebus.pushRegistration"

    public static func markRegistered(_ settings: NotificationBackendSettings) {
        UserDefaults.standard.set(fingerprint(settings), forKey: key)
    }

    /// The configuration a registration was made under: the backend, the
    /// Bark URL and the APNs token, so a newly arrived token reads as not
    /// yet registered.
    static func fingerprint(_ settings: NotificationBackendSettings) -> String {
        [settings.backendURL ?? "", settings.barkPushURL ?? "", PushDeviceIdentity.apnsToken() ?? ""]
            .joined(separator: "|")
    }

    public static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// Registered at some point, whatever the configuration since.
    public static var hasRegistration: Bool { UserDefaults.standard.string(forKey: key) != nil }

    /// Registered, and with the configuration still in effect.
    public static func isRegistered(_ settings: NotificationBackendSettings) -> Bool {
        UserDefaults.standard.string(forKey: key) == fingerprint(settings)
    }
}
