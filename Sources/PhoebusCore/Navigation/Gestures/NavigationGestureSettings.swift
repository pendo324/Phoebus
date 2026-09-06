import Foundation

/// Apollo's Gestures screen "Navigation Gestures" section: "Ability to swipe
/// forward/back pages" (`PushPopSwipeGesturesEnabled`), "Disable Right
/// Swipes" (`DisableRightSwipeGestureActions`) and "Disable Left Swipes"
/// (`DisableLeftSwipeGestureActions`).
/// `LongSwipeGestureTriggerPoint` values; the default is "normal".
/// Apollo's two values, as stored (`normal`, `later`).
public enum LongSwipeTriggerPoint: String, Codable, CaseIterable, Sendable {
    case normal
    case later

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .later: return "Later"
        }
    }

    /// Fraction of the row width the drag must cross before the long
    /// action engages.
    public var fraction: Double {
        switch self {
        case .normal: return 0.5
        case .later: return 0.7
        }
    }

    /// Reads the stock values and the legacy `early`/`late`.
    public init(storedValue: String) {
        self = storedValue == "later" || storedValue == "late" ? .later : .normal
    }

    public init(from decoder: Decoder) throws {
        self.init(storedValue: try decoder.singleValueContainer().decode(String.self))
    }
}

public struct NavigationGestureSettings: Codable, Sendable, Equatable {
    public var pushPopSwipeGesturesEnabled: Bool
    public var disableRightSwipeGestureActions: Bool
    public var disableLeftSwipeGestureActions: Bool
    /// Row "Long Swipe Trigger Point" (`LongSwipeGestureTriggerPoint`), a
    /// discrete named choice (default "normal"), not a continuous slider.
    public var longSwipeTriggerPoint: LongSwipeTriggerPoint

    public static let `default` = NavigationGestureSettings(
        pushPopSwipeGesturesEnabled: true,
        disableRightSwipeGestureActions: false,
        disableLeftSwipeGestureActions: false,
        longSwipeTriggerPoint: .normal
    )

    public init(pushPopSwipeGesturesEnabled: Bool = true, disableRightSwipeGestureActions: Bool = false, disableLeftSwipeGestureActions: Bool = false, longSwipeTriggerPoint: LongSwipeTriggerPoint = .normal) {
        self.pushPopSwipeGesturesEnabled = pushPopSwipeGesturesEnabled
        self.disableRightSwipeGestureActions = disableRightSwipeGestureActions
        self.disableLeftSwipeGestureActions = disableLeftSwipeGestureActions
        self.longSwipeTriggerPoint = longSwipeTriggerPoint
    }
}

public enum NavigationGestureSettingsStore {
    private static let key = "com.pendo324.Phoebus.navigationGestureSettings"

    /// Cached because `load()` is called from gesture paths that run dozens
    /// of times per second; `save()` refreshes it.
    private nonisolated(unsafe) static var cached: NavigationGestureSettings?
    private static let cacheLock = NSLock()

    public static func load() -> NavigationGestureSettings {
        cacheLock.lock()
        let hit = cached
        cacheLock.unlock()
        if let hit { return hit }
        // Decoded outside the lock: the store's mirror takes the same
        // lock to fill the cache, and NSLock isn't recursive.
        let settings = decode()
        cacheLock.lock()
        cached = settings
        cacheLock.unlock()
        return settings
    }

    /// Any save, including the Gestures screen's `@Setting` writes,
    /// refreshes the cache the gesture code reads.
    public static let storage = SettingsStore<NavigationGestureSettings>(key: key, mirror: { settings, _ in
        cacheLock.lock()
        cached = settings
        cacheLock.unlock()
    }) { NavigationGestureSettings.default }

    private static func decode() -> NavigationGestureSettings { storage.load() }

    public static func save(_ settings: NavigationGestureSettings) {
        storage.save(settings)
        cacheLock.lock()
        cached = settings
        cacheLock.unlock()
    }

    /// Drops the cache, for tests and for any path that writes the
    /// defaults key directly rather than through `save`.
    public static func invalidateCache() {
        cacheLock.lock()
        cached = nil
        cacheLock.unlock()
    }
}

extension NavigationGestureSettings: StoredSettingsModel {
    public static var store: SettingsStore<NavigationGestureSettings> { NavigationGestureSettingsStore.storage }
}
