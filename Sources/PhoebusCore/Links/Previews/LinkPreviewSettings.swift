import Foundation

/// Reborn's Rich Link Previews sub-screen. The summary row reads
/// "Body {mode} · Comments {mode} · {color}" and pushes this screen, which
/// controls `LinkPreviewCard`/`LinkPreviewCache`'s display mode and color.
///
/// The mode (Off / Compact / Full) applies independently to a post's own
/// body preview and to link previews inline in comments.
public enum LinkPreviewDisplayMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case compact
    case full

    public var id: String { rawValue }

    /// Titles as Reborn words them.
    public var title: String {
        switch self {
        case .off: return "Off"
        case .compact: return "Compact"
        case .full: return "Full"
        }
    }
}

/// Backs `sLinkPreviewBodyMode`, `sLinkPreviewCommentsMode`,
/// `sLinkPreviewCardColorHex`, shown as `#RRGGBB`/"Default color".
public struct LinkPreviewSettings: Codable, Sendable, Equatable {
    public var bodyDisplayMode: LinkPreviewDisplayMode
    public var commentsDisplayMode: LinkPreviewDisplayMode
    /// `nil`/empty means "Default color", stored without a leading `#` (added
    /// only for display).
    public var cardColorHex: String?
    /// Asked for a tweet X itself won't give out.
    public var twitterFallback: TwitterFallbackProvider = .none

    /// Full / Full, Reborn's registered defaults.
    public static let `default` = LinkPreviewSettings(bodyDisplayMode: .full, commentsDisplayMode: .full, cardColorHex: nil)

    public init(bodyDisplayMode: LinkPreviewDisplayMode, commentsDisplayMode: LinkPreviewDisplayMode, cardColorHex: String?) {
        self.bodyDisplayMode = bodyDisplayMode
        self.commentsDisplayMode = commentsDisplayMode
        self.cardColorHex = cardColorHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bodyDisplayMode = (try? container.decodeIfPresent(LinkPreviewDisplayMode.self, forKey: .bodyDisplayMode)) ?? .full
        commentsDisplayMode = (try? container.decodeIfPresent(LinkPreviewDisplayMode.self, forKey: .commentsDisplayMode))
            ?? LinkPreviewSettings.default.commentsDisplayMode
        cardColorHex = (try? container.decodeIfPresent(String.self, forKey: .cardColorHex))
        twitterFallback = (try? container.decodeIfPresent(TwitterFallbackProvider.self, forKey: .twitterFallback)) ?? .none
    }

    /// `"#RRGGBB"` for display, or "Default color" when unset.
    public var displayColorText: String {
        guard let cardColorHex, !cardColorHex.isEmpty else { return "Default color" }
        return "#\(cardColorHex.uppercased())"
    }
}

public enum LinkPreviewSettingsStore {
    private static let key = "com.pendo324.Phoebus.linkPreviewSettings"

    public static let storage = SettingsStore<LinkPreviewSettings>(key: key) { LinkPreviewSettings.default }

    public static func load() -> LinkPreviewSettings { storage.load() }

    public static func save(_ settings: LinkPreviewSettings) { storage.save(settings) }
}

extension LinkPreviewSettings: StoredSettingsModel {
    public static var store: SettingsStore<LinkPreviewSettings> { LinkPreviewSettingsStore.storage }
}
