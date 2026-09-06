import Foundation

/// Apollo's Notifications settings screen, distinct from `RemindMeScreen`'s
/// per-post reminder.
///
/// Apollo's inbox push came from its own backend relay, which a plain
/// Reddit client cannot replicate; this models local notification
/// permission and a local periodic inbox check within iOS's
/// background-refresh limits.
public struct NotificationSettings: Codable, Sendable, Equatable {
    /// The Inbox Notifications toggle, enabling the local periodic inbox check.
    public var inboxNotificationsEnabled: Bool
    /// The selected local notification sound.
    public var notificationSound: NotificationSound

    public static let `default` = NotificationSettings(inboxNotificationsEnabled: false, notificationSound: .defaultSound)

    public init(inboxNotificationsEnabled: Bool, notificationSound: NotificationSound) {
        self.inboxNotificationsEnabled = inboxNotificationsEnabled
        self.notificationSound = notificationSound
    }
}

/// Apollo's bundled notification sounds; the names are the `.wav` filenames
/// in its notification service extension.
///
/// The audio is not shipped. Selecting one names it for
/// `UNNotificationSound(named:)`, so a build without those assets falls
/// back to the system default.
public enum NotificationSound: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The system default, for a user who wants no custom sound.
    case defaultSound = "default"
    /// Silence.
    case none = "none"
    case bubblesAndBotany = "bubbles-and-botany"
    case cat = "cat"
    case chicken = "chicken"
    case clickityClickerson = "clickity-clickerson"
    case cow = "cow"
    case curiousCuttlefish = "curious-cuttlefish"
    case developerSayingBeep = "developer-saying-beep"
    case diabolicalDoorbell = "diabolical-doorbell"
    case digDigDig = "dig-dig-dig"
    case dog = "dog"
    case dropOfDeliberation = "drop-of-deliberation"
    case duDuuuu = "du-duuuu"
    case echoingExpansion = "echoing-expansion"
    case headsUpHenry = "heads-up-henry"
    case honervasHarp = "honervas-harp"
    case horse = "horse"
    case inspiredIcicle = "inspired-icicle"
    case moon = "moon"
    case neptuneNods = "neptune-nods"
    case penguin = "penguin"
    case sheep = "sheep"
    case sonicSnap = "sonic-snap"
    case traloop = "traloop"
    case turkey = "turkey"
    case wow = "wow"

    public var id: String { rawValue }

    /// The id Bark plays (`<id>.caf`, imported into the Bark app from Reborn's
    /// `assets/bark-sounds/`): Apollo's camelCase name, the value Reborn pins
    /// as `?sound=`. nil for Default/None.
    public var barkSoundID: String? {
        switch self {
        case .defaultSound: return nil
        // Bark's built-in silent sound, so None is quiet rather than the
        // default tone.
        case .none: return "silence"
        default:
            let parts = rawValue.split(separator: "-")
            return parts.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined()
        }
    }

    /// The bundled filename, matching the asset exactly.
    public var filename: String? {
        switch self {
        case .defaultSound, .none: return nil
        default: return rawValue + ".wav"
        }
    }

    /// Display names. Some are spelled out verbatim since Apollo
    /// lowercases short joining words, which plain
    /// title-casing the filename does not produce:
    ///
    ///   bubbles-and-botany  -> "Bubbles and Botany"   (lowercase "and")
    ///   drop-of-deliberation -> "Drop of Deliberation" (lowercase "of")
    ///   honervas-harp       -> "Honerva\u{2019}s Harp"    (curly apostrophe)
    public var displayName: String {
        switch self {
        case .defaultSound: return "Default"
        case .none: return "None"
        case .bubblesAndBotany: return "Bubbles and Botany"
        case .cat: return "Cat"
        case .chicken: return "Chicken"
        case .clickityClickerson: return "Clickity Clickerson"
        case .cow: return "Cow"
        case .curiousCuttlefish: return "Curious Cuttlefish"
        case .developerSayingBeep: return "Developer Saying Beep"
        case .diabolicalDoorbell: return "Diabolical Doorbell"
        case .digDigDig: return "Dig Dig Dig"
        case .dog: return "Dog"
        case .dropOfDeliberation: return "Drop of Deliberation"
        case .duDuuuu: return "Du Duuuu"
        case .echoingExpansion: return "Echoing Expansion"
        case .headsUpHenry: return "Heads Up Henry"
        case .honervasHarp: return "Honerva\u{2019}s Harp"
        case .horse: return "Horse"
        case .inspiredIcicle: return "Inspired Icicle"
        case .moon: return "Moon"
        case .neptuneNods: return "Neptune Nods"
        case .penguin: return "Penguin"
        case .sheep: return "Sheep"
        case .sonicSnap: return "Sonic Snap"
        case .traloop: return "Traloop"
        case .turkey: return "Turkey"
        case .wow: return "Wow"
        }
    }
}

public enum NotificationSettingsStore {
    private static let key = "com.pendo324.Phoebus.notificationSettings"

    public static let storage = SettingsStore<NotificationSettings>(key: key) { NotificationSettings.default }

    public static func load() -> NotificationSettings { storage.load() }

    public static func save(_ settings: NotificationSettings) { storage.save(settings) }
}

#if canImport(UserNotifications)
import UserNotifications

public extension NotificationSound {
    /// The `UNNotificationSound` this choice maps to. Sounds with no bundled
    /// audio asset map to the default alert tone.
    var unNotificationSound: UNNotificationSound? {
        switch self {
        case .none: return nil
        case .defaultSound: return .default
        default:
            // Named against the app bundle; without the audio assets iOS falls back
            // to the default sound.
            guard let filename else { return .default }
            return UNNotificationSound(named: UNNotificationSoundName(filename))
        }
    }
}
#endif

extension NotificationSettings: StoredSettingsModel {
    public static var store: SettingsStore<NotificationSettings> { NotificationSettingsStore.storage }
}
