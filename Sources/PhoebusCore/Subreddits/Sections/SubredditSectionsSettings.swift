import Foundation

/// Apollo-Reborn's "Subreddit Sections" screen: arranges the rest of the
/// Subreddits-root list (below the four feed-shortcut rows): section
/// order, a dedicated Following section, and multireddit-description
/// visibility.
///
/// Four reorderable tokens (`favorites`, `multireddits`, `moderator`,
/// `following`) default to that order. `separateFollowedUsers` pulls
/// `u_<name>` subscriptions into their own Following section when on;
/// when off the `following` token is skipped entirely. Enhancements and
/// Modern Dividers both default on; Modern Dividers is only visible
/// while Enhancements is on.
public struct SubredditSectionsSettings: Codable, Sendable, Equatable {
    /// Reborn's string constants, verbatim.
    public enum SectionToken: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
        case favorites
        case multireddits
        case moderator
        case following

        public var id: String { rawValue }

        /// Display names, verbatim from Reborn.
        public var displayName: String {
            switch self {
            case .favorites: return "Favorites"
            case .multireddits: return "Multireddits"
            case .moderator: return "Moderator"
            case .following: return "Following"
            }
        }
    }

    /// User-chosen order of the four tokens. May be incomplete or stale after
    /// an update adds a token; read through `resolvedOrder`, which sanitizes it.
    public var order: [SectionToken]
    public var separateFollowedUsers: Bool
    public var hideMultiredditDescriptions: Bool
    /// Reborn's list Enhancements switch, default on.
    public var subredditListEnhancements: Bool
    /// Reborn's Modern Dividers switch, default on.
    public var modernSubredditDividers: Bool

    /// Modern bands collapse to the classic grey band whenever Enhancements
    /// is off, regardless of the dividers switch.
    public var usesModernDividers: Bool { subredditListEnhancements && modernSubredditDividers }

    /// Canonical default order: Favorites, Multireddits, Moderator, Following.
    /// Feed shortcuts always sit above all of this; settings only let the user
    /// override the baseline.
    public static let defaultOrder: [SectionToken] = [.favorites, .multireddits, .moderator, .following]

    public static let `default` = SubredditSectionsSettings(
        order: defaultOrder,
        separateFollowedUsers: false,
        hideMultiredditDescriptions: false
    )

    public init(
        order: [SectionToken],
        separateFollowedUsers: Bool,
        hideMultiredditDescriptions: Bool,
        subredditListEnhancements: Bool = true,
        modernSubredditDividers: Bool = true
    ) {
        self.order = order
        self.separateFollowedUsers = separateFollowedUsers
        self.hideMultiredditDescriptions = hideMultiredditDescriptions
        self.subredditListEnhancements = subredditListEnhancements
        self.modernSubredditDividers = modernSubredditDividers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? container.decodeIfPresent([SectionToken].self, forKey: .order)) ?? SubredditSectionsSettings.defaultOrder
        separateFollowedUsers = (try? container.decodeIfPresent(Bool.self, forKey: .separateFollowedUsers)) ?? false
        hideMultiredditDescriptions = (try? container.decodeIfPresent(Bool.self, forKey: .hideMultiredditDescriptions)) ?? false
        // Both default to on, so a payload written before these existed decodes
        // to on, not `false`.
        subredditListEnhancements = (try? container.decodeIfPresent(Bool.self, forKey: .subredditListEnhancements)) ?? true
        modernSubredditDividers = (try? container.decodeIfPresent(Bool.self, forKey: .modernSubredditDividers)) ?? true
    }

    /// Sanitizes `order` into a complete, duplicate-free token list: valid
    /// stored tokens in stored order, then any missing defaults. Consumers
    /// read this, never `order`, so a corrupted or incomplete array cannot
    /// drop a section.
    public var resolvedOrder: [SectionToken] {
        var resolved: [SectionToken] = []
        for token in order where !resolved.contains(token) {
            resolved.append(token)
        }
        for token in SubredditSectionsSettings.defaultOrder where !resolved.contains(token) {
            resolved.append(token)
        }
        return resolved
    }

    /// The order shown on screen: `resolvedOrder` without `following` when
    /// Separate Followed Users is off.
    public var visibleOrder: [SectionToken] {
        resolvedOrder.filter { separateFollowedUsers || $0 != .following }
    }

    /// The hub row's subtitle: the resolved display names, skipping
    /// Following when per-account separation is off, joined with " · ".
    public var summaryText: String {
        visibleOrder.map(\.displayName).joined(separator: " · ")
    }
}

public enum SubredditSectionsSettingsStore {
    private static let key = "com.pendo324.Phoebus.subredditSectionsSettings"

    public static let storage = SettingsStore<SubredditSectionsSettings>(key: key) { SubredditSectionsSettings.default }

    public static func load() -> SubredditSectionsSettings { storage.load() }

    public static func save(_ settings: SubredditSectionsSettings) { storage.save(settings) }
}

extension SubredditSectionsSettings: StoredSettingsModel {
    public static var store: SettingsStore<SubredditSectionsSettings> { SubredditSectionsSettingsStore.storage }
}
