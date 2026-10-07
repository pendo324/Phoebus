import Foundation

/// Which device identity this install registers with a notification
/// backend, as Reborn chooses it:
///
///  - **Bark**, when a Bark push URL is set: a synthetic token
///    (`PushNotificationClient.syntheticTokenHex`) and the Bark push URL.
///  - **APNs**, otherwise, when the build is signed with an
///    `aps-environment` entitlement and iOS handed out a device token. The backend pushes straight to this app, with the
///    unread count as the app icon's badge.
public enum PushDeviceIdentity {
    public enum Transport: String, Sendable, Equatable {
        case apns
        case bark
    }

    private static let tokenKey = "com.pendo324.Phoebus.apnsDeviceToken"
    private static let sandboxKey = "com.pendo324.Phoebus.apnsSandbox"

    /// The APNs device token iOS last handed out, hex-encoded, or nil when
    /// this signing has no push entitlement.
    public static func apnsToken(defaults: UserDefaults = .standard) -> String? {
        guard let token = defaults.string(forKey: tokenKey), !token.isEmpty else { return nil }
        return token
    }

    /// Whether the APNs token belongs to Apple's sandbox gateway (a
    /// development-signed build).
    public static func apnsSandbox(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: sandboxKey)
    }

    /// Records a token from `didRegisterForRemoteNotificationsWithDeviceToken`.
    /// Returns whether it differs from the one stored before.
    @discardableResult
    public static func storeAPNSToken(_ token: Data, sandbox: Bool, defaults: UserDefaults = .standard) -> Bool {
        let hex = hexString(token)
        let changed = defaults.string(forKey: tokenKey) != hex || defaults.bool(forKey: sandboxKey) != sandbox
        defaults.set(hex, forKey: tokenKey)
        defaults.set(sandbox, forKey: sandboxKey)
        return changed
    }

    /// Forgets the APNs token, when registration fails because the signing
    /// has no push entitlement.
    public static func clearAPNSToken(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: sandboxKey)
    }

    public static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// The token and transport to register: Bark's synthetic token when
    /// Bark is set up, else APNs when there is a real token, else nil.
    /// Bark wins because setting it up is an explicit choice: a signing
    /// can grant push while the backend has no APNs key for it, and a
    /// Bark-only backend rejects APNs devices.
    public static func current(settings: NotificationBackendSettings,
                               defaults: UserDefaults = .standard) -> (token: String, transport: Transport)? {
        if PushNotificationClient.barkURL(settings) != nil {
            return (PushNotificationClient.syntheticTokenHex(defaults: defaults), .bark)
        }
        if let token = apnsToken(defaults: defaults) { return (token, .apns) }
        return nil
    }

    public static func usesAPNS(settings: NotificationBackendSettings,
                                defaults: UserDefaults = .standard) -> Bool {
        current(settings: settings, defaults: defaults)?.transport == .apns
    }

    /// The token the backend knows this device by, for the per-device
    /// endpoints (accounts, watchers, test, unregister).
    public static func registeredToken(settings: NotificationBackendSettings,
                                       defaults: UserDefaults = .standard) -> String {
        current(settings: settings, defaults: defaults)?.token
            ?? PushNotificationClient.syntheticTokenHex(defaults: defaults)
    }

    /// `aps-environment` from a provisioning profile (`embedded.mobileprovision`,
    /// a signed CMS envelope around an XML plist): "development",
    /// "production", or nil when the profile grants no push.
    public static func apsEnvironment(provisioningProfile data: Data) -> String? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return nil }
        return entitlements["aps-environment"] as? String
    }
}
