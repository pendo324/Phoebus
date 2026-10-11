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

/// How many link cards stack under one post body or comment before the rest
/// fold behind "Show N more previews". Phoebus's own setting; Apollo and Reborn
/// draw every card. Stored by raw value, 0 meaning Unlimited.
public enum LinkCardLimit: Int, Codable, Sendable, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case five = 5
    case ten = 10
    case unlimited = 0

    public var id: Int { rawValue }

    public var title: String {
        self == .unlimited ? "Unlimited" : String(rawValue)
    }

    /// `nil` when every card shows.
    public var count: Int? { self == .unlimited ? nil : rawValue }

    /// Which attachments of a body draw. `isLink` flags each attachment in
    /// order (true for a link card, false for inline media). Only link cards
    /// count against the limit; media always draw.
    public func visibility(isLink: [Bool], expanded: Bool) -> LinkCardVisibility {
        guard let count, !expanded else { return LinkCardVisibility(visible: isLink.map { _ in true }, hiddenCount: 0) }
        var seen = 0
        var hidden = 0
        let visible = isLink.map { link -> Bool in
            guard link else { return true }
            seen += 1
            if seen <= count { return true }
            hidden += 1
            return false
        }
        return LinkCardVisibility(visible: visible, hiddenCount: hidden)
    }
}

/// Per-attachment visibility from `LinkCardLimit.visibility`, and how many
/// link cards it folded away.
public struct LinkCardVisibility: Equatable, Sendable {
    public let visible: [Bool]
    public let hiddenCount: Int

    public init(visible: [Bool], hiddenCount: Int) {
        self.visible = visible
        self.hiddenCount = hiddenCount
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
    /// Link cards stacked under one body or comment.
    public var maxCards: LinkCardLimit = .five

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
        maxCards = (try? container.decodeIfPresent(LinkCardLimit.self, forKey: .maxCards)) ?? .five
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
