import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Persists Apollo's app-lock setting and exposes the device's biometry
/// capability, which decides which row titles/footers to show.
public struct AppLockSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// "Require Passcode" grace period in seconds, 0 = Immediately.
    public var requireAfterSeconds: Int

    public init(isEnabled: Bool = false, requireAfterSeconds: Int = 0) {
        self.isEnabled = isEnabled
        self.requireAfterSeconds = requireAfterSeconds
    }

    enum CodingKeys: String, CodingKey { case isEnabled, requireAfterSeconds }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        requireAfterSeconds = (try? c.decodeIfPresent(Int.self, forKey: .requireAfterSeconds)) ?? 0
    }

    /// Whether returning to the app after `elapsed` seconds away needs
    /// authentication again, per "Require Passcode: After N Minutes".
    public func requiresUnlock(afterBeingAwayFor elapsed: TimeInterval) -> Bool {
        guard isEnabled else { return false }
        return elapsed >= TimeInterval(requireAfterSeconds)
    }

    /// Apollo's four choices.
    public static let requireAfterChoices: [(seconds: Int, title: String)] = [
        (0, "Immediately"), (60, "After 1 Minute"), (300, "After 5 Minutes"), (3600, "After 1 Hour"),
    ]
}

public enum AppLockBiometry: Sendable {
    case none
    case touchID
    case faceID
}

public enum AppLockStore {
    private static let key = "Phoebus.appLock"

    public static let storage = SettingsStore<AppLockSettings>(key: key) { AppLockSettings() }

    public static func load() -> AppLockSettings { storage.load() }

    public static func save(_ settings: AppLockSettings) { storage.save(settings) }

    /// The biometry actually usable right now (enrolled and available).
    public static var biometry: AppLockBiometry {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
        #else
        return .none
        #endif
    }

    /// The biometry the hardware supports regardless of enrollment, used to
    /// decide whether to show the "you haven't enrolled" note.
    public static var hardwareBiometry: AppLockBiometry {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
        #else
        return .none
        #endif
    }

    public static var biometryNotEnrolled: Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        let canUse = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if canUse { return false }
        return (error as? LAError)?.code == .biometryNotEnrolled
        #else
        return false
        #endif
    }

    /// Performs the biometric/passcode challenge. Without it, "Require Face ID"
    /// would be a switch that silently protects nothing.
    ///
    /// Uses `.deviceOwnerAuthentication` (not `...WithBiometrics`) so the system
    /// passcode is the fallback when biometry fails or isn't enrolled.
    public static func authenticate(reason: String = "Unlock Phoebus") async -> Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        // No passcode set: nothing to authenticate against, and failing closed
        // would lock the user out of their own app, so allow entry.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
        #else
        return true
        #endif
    }

    public static var deviceHasPasscode: Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        #else
        return false
        #endif
    }
}

/// Persists Apollo's Portrait Lock setting, which forces the app to stay in
/// portrait regardless of the device's rotation lock.
public struct PortraitLockSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Apollo's "Portrait Lock Buddy". When iOS's own rotation lock is engaged,
    /// the media viewer still detects a physical turn and offers to rotate the
    /// media anyway, e.g. one landscape photo full-width.
    public var portraitLockBuddy: Bool

    public init(isEnabled: Bool = false, portraitLockBuddy: Bool = false) {
        self.isEnabled = isEnabled
        self.portraitLockBuddy = portraitLockBuddy
    }

    /// Absent-tolerant so older blobs without `portraitLockBuddy` still decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        portraitLockBuddy = (try? container.decodeIfPresent(Bool.self, forKey: .portraitLockBuddy)) ?? false
    }
}

public enum PortraitLockStore {
    public static let storage = SettingsStore<PortraitLockSettings>(key: "Phoebus.portraitLock") { PortraitLockSettings() }

    public static func load() -> PortraitLockSettings { storage.load() }

    public static func save(_ settings: PortraitLockSettings) { storage.save(settings) }
}

extension AppLockSettings: StoredSettingsModel {
    public static var store: SettingsStore<AppLockSettings> { AppLockStore.storage }
}
