import Foundation

/// Apollo-Reborn's "Subreddit Layout" screen: the customize screen for
/// subreddit-page appearance, distinct from the subreddit-list screen
/// (`SubredditSectionsSettings.swift`). Controls whether a subreddit page
/// uses Reborn's own header (default off, native Apollo page otherwise),
/// its Immersive/Compact density, per-band visibility, and Community
/// Highlights mode (Off/Partial/Full pinned-posts carousel). Partial shows the
/// pinned posts the REST API returns; Full adds a scrape of the web page for
/// up to six cards.
public struct SubredditLayoutSettings: Codable, Sendable, Equatable {
    public enum CommunityHighlightsMode: String, Codable, Sendable, CaseIterable, Identifiable {
        case off
        case partial
        case full

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .off: return "Off"
            case .partial: return "Partial"
            case .full: return "Full"
            }
        }
    }

    /// Lines of the description shown before it is expanded (3).
    public static let aboutCollapsedLines = 3

    // MARK: - Header action cluster
    //
    // Flair, Join and Sidebar lay out as one centered cluster; Flair and
    // Sidebar are icon-only squares of a fixed side, not labelled pills,
    // so they must match each other's size.

    /// Width and height of the Flair/Sidebar buttons.
    public static let secondaryActionSide: Double = 44

    /// The glyph inside that square.
    public static let secondaryActionIconSide: Double = 22

    /// Spacing between controls in the cluster.
    public static let actionGap: Double = 10

    /// Gap below the Join pill, above the body.
    public static let actionBottomGap: Double = 16

    /// Used when Dynamic Type forces Join onto its own row and the
    /// secondary controls wrap below it.
    public static let stackedActionGap: Double = 8

    /// Join's minimum width: max(148, intrinsic + 52).
    public static let joinMinimumWidth: Double = 148

    public var showSubredditHeaders: Bool
    public var subredditHeaderImmersive: Bool
    public var subredditShowBanner: Bool
    public var subredditShowJoinButton: Bool
    public var subredditShowDisplayName: Bool
    /// Reborn header bands. `SubredditShowSubtitle` (default on): the
    /// community's own title plus member count, e.g. "Linux, GNU/Linux · 1.2M
    /// members". Distinct from the r/name row.
    public var subredditShowSubtitle: Bool
    /// `SubredditShowDescription` (default on): the sidebar blurb, collapsed
    /// to 3 lines and expandable.
    public var subredditShowDescription: Bool
    /// `SubredditShowSidebarButton` (default off).
    public var subredditShowSidebarButton: Bool
    /// `SubredditShowUserFlairButton` (default off). Reborn only shows it once
    /// the user is known to be able to set flair here.
    public var subredditShowUserFlairButton: Bool
    public var communityHighlights: CommunityHighlightsMode

    /// The hub row's subtitle: "Native (Apollo)" when custom headers are off
    /// entirely, else the header mode followed by a "X, Y off" list of hidden
    /// header elements, joined with " · ".
    public var summaryText: String {
        // "Native", or "Immersive"/"Compact" then "X, Y off".
        guard showSubredditHeaders else { return "Native" }
        var parts: [String] = [subredditHeaderImmersive ? "Immersive" : "Compact"]
        var hidden: [String] = []
        if !subredditShowBanner { hidden.append("Banner") }
        if !subredditShowJoinButton { hidden.append("Join Button") }
        // Reborn lists these too, though they default off.
        if !subredditShowUserFlairButton { hidden.append("User Flair Button") }
        if !subredditShowSidebarButton { hidden.append("Sidebar Button") }
        if !subredditShowDisplayName { hidden.append("Subreddit Name") }
        if !subredditShowSubtitle { hidden.append("Subtitle") }
        if !subredditShowDescription { hidden.append("Description") }
        if !hidden.isEmpty {
            parts.append("\(hidden.joined(separator: ", ")) off")
        }
        return parts.joined(separator: " · ")
    }

    /// Reborn defaults: its own header is off (the native Apollo page shows
    /// until the user opts in), density is Immersive once on, every band is
    /// visible, and Community Highlights is Off.
    public static let `default` = SubredditLayoutSettings(
        showSubredditHeaders: false,
        subredditHeaderImmersive: true,
        subredditShowBanner: true,
        subredditShowJoinButton: true,
        subredditShowDisplayName: true,
        subredditShowSubtitle: true,
        subredditShowDescription: true,
        subredditShowSidebarButton: false,
        subredditShowUserFlairButton: false,
        communityHighlights: .off
    )

    public init(
        showSubredditHeaders: Bool,
        subredditHeaderImmersive: Bool,
        subredditShowBanner: Bool,
        subredditShowJoinButton: Bool,
        subredditShowDisplayName: Bool,
        subredditShowSubtitle: Bool = true,
        subredditShowDescription: Bool = true,
        subredditShowSidebarButton: Bool = false,
        subredditShowUserFlairButton: Bool = false,
        communityHighlights: CommunityHighlightsMode
    ) {
        self.showSubredditHeaders = showSubredditHeaders
        self.subredditHeaderImmersive = subredditHeaderImmersive
        self.subredditShowBanner = subredditShowBanner
        self.subredditShowJoinButton = subredditShowJoinButton
        self.subredditShowDisplayName = subredditShowDisplayName
        self.subredditShowSubtitle = subredditShowSubtitle
        self.subredditShowDescription = subredditShowDescription
        self.subredditShowSidebarButton = subredditShowSidebarButton
        self.subredditShowUserFlairButton = subredditShowUserFlairButton
        self.communityHighlights = communityHighlights
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showSubredditHeaders = (try? container.decodeIfPresent(Bool.self, forKey: .showSubredditHeaders)) ?? SubredditLayoutSettings.default.showSubredditHeaders
        subredditHeaderImmersive = (try? container.decodeIfPresent(Bool.self, forKey: .subredditHeaderImmersive)) ?? SubredditLayoutSettings.default.subredditHeaderImmersive
        subredditShowBanner = (try? container.decodeIfPresent(Bool.self, forKey: .subredditShowBanner)) ?? SubredditLayoutSettings.default.subredditShowBanner
        subredditShowJoinButton = (try? container.decodeIfPresent(Bool.self, forKey: .subredditShowJoinButton)) ?? SubredditLayoutSettings.default.subredditShowJoinButton
        subredditShowDisplayName = (try? container.decodeIfPresent(Bool.self, forKey: .subredditShowDisplayName)) ?? SubredditLayoutSettings.default.subredditShowDisplayName
        subredditShowSubtitle = (try? container.decodeIfPresent(Bool.self, forKey: .subredditShowSubtitle)) ?? SubredditLayoutSettings.default.subredditShowSubtitle
        subredditShowDescription = (try? container.decodeIfPresent(Bool.self, forKey: .subredditShowDescription)) ?? SubredditLayoutSettings.default.subredditShowDescription
        subredditShowSidebarButton = (try? container.decodeIfPresent(Bool.self, forKey: .subredditShowSidebarButton)) ?? SubredditLayoutSettings.default.subredditShowSidebarButton
        subredditShowUserFlairButton = (try? container.decodeIfPresent(Bool.self, forKey: .subredditShowUserFlairButton)) ?? SubredditLayoutSettings.default.subredditShowUserFlairButton
        communityHighlights = (try? container.decodeIfPresent(CommunityHighlightsMode.self, forKey: .communityHighlights)) ?? SubredditLayoutSettings.default.communityHighlights
    }
}

public enum SubredditLayoutSettingsStore {
    private static let key = "com.pendo324.Phoebus.subredditLayoutSettings"

    public static let storage = SettingsStore<SubredditLayoutSettings>(key: key) { SubredditLayoutSettings.default }

    public static func load() -> SubredditLayoutSettings { storage.load() }

    public static func save(_ settings: SubredditLayoutSettings) { storage.save(settings) }
}

extension SubredditLayoutSettings: StoredSettingsModel {
    public static var store: SettingsStore<SubredditLayoutSettings> { SubredditLayoutSettingsStore.storage }
}
