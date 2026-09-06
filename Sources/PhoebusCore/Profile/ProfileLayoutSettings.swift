import Foundation

/// Reimplements Apollo-Reborn's "Profile Layout" screen: customizes
/// the header band of `UserProfileScreen`.
///
/// Fields:
///
///  - `sProfileHeaderImmersive` (`UDKeyProfileHeaderImmersive`,
///    default `YES`): "New (Immersive)" adds a melt backdrop and more
///    space; "Classic (Compact)" is flat.
///  - `sProfileAvatarStyle` (`UDKeyProfileAvatarStyle`, default `0`):
///    0 = Full (snoovatar), 1 = Circle, 2 = Square.
///  - `sProfileShowBanner` / `sProfileShowStatCards` /
///    `sProfileShowSocialLinks` / `sProfileShowActions` (all default
///    `YES`): independent show/hide bands.
///  - `sBadgeBookEnabled` (`UDKeyBadgeBookEnabled`, default `YES`):
///    unlike the pure-visibility switches above, the row also gates
///    the Badge Book feature's own scraping/prewarm: off means no
///    strip, no fetches, no entry point at all.
public struct ProfileLayoutSettings: Codable, Sendable, Equatable {
    public enum AvatarStyle: Int, Codable, Sendable, CaseIterable, Identifiable {
        case full = 0
        case circle = 1
        case square = 2

        public var id: Int { rawValue }
        public var displayName: String {
            switch self {
            case .full: return "Full"
            case .circle: return "Circle"
            case .square: return "Square"
            }
        }
    }

    public var headerImmersive: Bool
    /// `sShowDetailedProfiles` (`UDKeyShowDetailedProfiles`, default `YES`).
    /// OFF is Reborn's third Profile Style, "Native": Apollo's stock header
    /// (title pill + three bare stats) instead of the banner/avatar header, and
    /// every other row on the screen disappears. The labels are Immersive /
    /// Compact / Native.
    public var showDetailedProfiles: Bool = true

    /// The Profile Style picker's value:
    /// `!detailed ? Native : (immersive ? Immersive : Compact)`.
    public enum Style: Int, CaseIterable, Identifiable, Sendable {
        case immersive = 0, compact = 1, native = 2
        public var id: Int { rawValue }
        public var displayName: String {
            switch self {
            case .immersive: return "Immersive"
            case .compact: return "Compact"
            case .native: return "Native"
            }
        }
    }

    public var style: Style {
        get { !showDetailedProfiles ? .native : (headerImmersive ? .immersive : .compact) }
        set {
            // detailed = mode != 2, immersive = mode == 0.
            showDetailedProfiles = newValue != .native
            headerImmersive = newValue == .immersive
        }
    }
    public var avatarStyle: AvatarStyle
    public var showBanner: Bool
    public var showStatCards: Bool
    public var showSocialLinks: Bool
    public var badgeBookEnabled: Bool
    public var showActions: Bool

    /// Reborn defaults: every band defaults visible, header defaults
    /// Immersive, avatar defaults Full.
    public static let `default` = ProfileLayoutSettings(
        headerImmersive: true,
        // Circle: Reborn #1136 made Circle the registered default once the
        // shape went app-wide.
        avatarStyle: .circle,
        showBanner: true,
        showStatCards: true,
        showSocialLinks: true,
        badgeBookEnabled: true,
        showActions: true
    )

    public init(
        headerImmersive: Bool,
        avatarStyle: AvatarStyle,
        showBanner: Bool,
        showStatCards: Bool,
        showSocialLinks: Bool,
        badgeBookEnabled: Bool,
        showActions: Bool
    ) {
        self.headerImmersive = headerImmersive
        self.avatarStyle = avatarStyle
        self.showBanner = showBanner
        self.showStatCards = showStatCards
        self.showSocialLinks = showSocialLinks
        self.badgeBookEnabled = badgeBookEnabled
        self.showActions = showActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headerImmersive = (try? container.decodeIfPresent(Bool.self, forKey: .headerImmersive)) ?? ProfileLayoutSettings.default.headerImmersive
        avatarStyle = (try? container.decodeIfPresent(AvatarStyle.self, forKey: .avatarStyle)) ?? ProfileLayoutSettings.default.avatarStyle
        showBanner = (try? container.decodeIfPresent(Bool.self, forKey: .showBanner)) ?? ProfileLayoutSettings.default.showBanner
        showStatCards = (try? container.decodeIfPresent(Bool.self, forKey: .showStatCards)) ?? ProfileLayoutSettings.default.showStatCards
        showSocialLinks = (try? container.decodeIfPresent(Bool.self, forKey: .showSocialLinks)) ?? ProfileLayoutSettings.default.showSocialLinks
        badgeBookEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .badgeBookEnabled)) ?? ProfileLayoutSettings.default.badgeBookEnabled
        showActions = (try? container.decodeIfPresent(Bool.self, forKey: .showActions)) ?? ProfileLayoutSettings.default.showActions
        showDetailedProfiles = (try? container.decodeIfPresent(Bool.self, forKey: .showDetailedProfiles)) ?? true
    }

    /// The hub row's subtitle: header mode, then avatar style, then an "N hidden"
    /// count of the five hideable bands (banner, stat cards, social links,
    /// badge book, actions), joined with " · ".
    public var summaryText: String {
        if !showDetailedProfiles { return "Native (Apollo)" }
        var parts: [String] = []
        parts.append(headerImmersive ? "Immersive" : "Compact")
        parts.append(avatarStyle.displayName)
        let hiddenCount = [showBanner, showStatCards, showSocialLinks, badgeBookEnabled, showActions]
            .filter { !$0 }
            .count
        if hiddenCount > 0 {
            parts.append("\(hiddenCount) hidden")
        }
        return parts.joined(separator: " · ")
    }
}

public enum ProfileLayoutSettingsStore {
    private static let key = "com.pendo324.Phoebus.profileLayoutSettings"

    /// Reborn #1136's one-shot migration key: starts the shared
    /// avatar-shape feature on Circle for every installation, including
    /// users with an older Profile Layout choice. Run once so later
    /// explicit shape selections remain intact.
    static let sharedShapeMigrationKey = "SharedAvatarShapeCircleDefaultApplied"

    /// Reborn #1136: an older saved layout starts on Circle once; a
    /// choice saved since is explicit and stays.
    public static let storage = SettingsStore<ProfileLayoutSettings>(
        key: key, didChange: .apolloProfilePictureShapeChanged,
        migrate: { settings, defaults in
            guard !defaults.bool(forKey: sharedShapeMigrationKey) else { return false }
            defaults.set(true, forKey: sharedShapeMigrationKey)
            settings.avatarStyle = .circle
            return true
        },
        mirror: { _, defaults in defaults.set(true, forKey: sharedShapeMigrationKey) }
    ) { ProfileLayoutSettings.default }

    public static func load() -> ProfileLayoutSettings { storage.load() }

    public static func save(_ settings: ProfileLayoutSettings) { storage.save(settings) }
}


extension ProfileLayoutSettings: StoredSettingsModel {
    public static var store: SettingsStore<ProfileLayoutSettings> { ProfileLayoutSettingsStore.storage }
}
