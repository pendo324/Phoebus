import Foundation

/// Apollo appearance settings, persisted under Apollo's own UserDefaults keys.
/// Rows that duplicate a `GeneralSettings` concept (thumbnail visibility,
/// position and size, self-post derived thumbnails) live on that field instead.
public enum AppearanceEdgePosition: String, Codable, CaseIterable, Sendable {
    case left
    case right

    public var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// Where the thin GIF/video progress strip is drawn. Cases match
/// Apollo's own three options.
public enum GIFProgressLocation: String, Codable, Sendable, CaseIterable, Identifiable {
    case everywhere
    case thumbnail
    case mediaViewer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .everywhere: return "Everywhere"
        case .thumbnail: return "Thumbnails"
        case .mediaViewer: return "Media Viewer"
        }
    }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    /// `ShowSubredditIconsInSubredditList`.
    public var showSubredditIconsInSubredditList: Bool
    /// `ShowSubredditIconsForPosts`: the per-post subreddit avatar on aggregate feeds.
    public var showSubredditIconsForPosts: Bool
    /// `AlwaysShowUsernames` — shows the author on rows that name the
    /// subreddit (Home, Popular, All, Recently Read). Inside one
    /// subreddit the author is always shown in its place.
    public var alwaysShowUsernames: Bool
    /// `ShowSubredditAtTop`: moves the subreddit name above the title (author
    /// inline alongside it) instead of below, in Recently Read.
    public var showSubredditAtTop: Bool
    /// "Show Page Endings": a separator row at each Reddit listing page boundary.
    public var showPageEndings: Bool
    /// Reborn "Bold Post Titles" (`BoldPostTitles`, #226), default OFF. Re-weights
    /// feed titles and a crosspost's inner title to semibold; the comments-header
    /// title is left alone.
    public var boldPostTitles: Bool
    /// `CompactModeHideVotingButtons` (inverted for a positive toggle): hides the
    /// per-row vote arrow column in compact and large-thumbnail rows when off.
    public var showVotingButtons: Bool
    /// `CompactModeRightVotingButtons`: which edge the compact row's vote arrow
    /// column sits on; relevant only while `showVotingButtons` is on.
    public var votingButtonsPosition: AppearanceEdgePosition
    /// `RememberRedditPostSize`: per-subreddit memory of the last-picked post
    /// display style (Compact/Large Thumbnails), via `PostSizeMemoryStore`.
    public var rememberPostSizePerSubreddit: Bool
    /// `SystemTextSwitchTag` / "Use System Text Size". When off, `textSizeScale`
    /// is applied as a `dynamicTypeSize` environment override at the app root;
    /// when on, the OS's Dynamic Type setting governs.
    public var useSystemTextSize: Bool
    /// Apollo's text-size slider value; see `useSystemTextSize`.
    public var textSizeScale: Double
    /// `LargeThumbnailsShowVotingButtons`, default YES, the "Large
    /// Posts" section's one row.
    public var largePostsShowVotingButtons: Bool
    /// `ShowGIFProgressLocation`: `everywhere` (default), `thumbnail`
    /// or `mediaViewer`.
    public var gifProgressLocation: GIFProgressLocation
    /// `CompactModeShowSelfPostThumbnails`, default YES: a compact
    /// self post with no image shows Apollo's text-lines placeholder.
    public var compactShowSelfPostThumbnails: Bool

    public static let `default` = AppearanceSettings()

    /// Defaults match Apollo's bundled values: `ShowPageEndings = false`,
    /// `CompactModeRightVotingButtons = true`, `CompactModeHideVotingButtons = false`,
    /// `UseSystemTextSize = false`.
    public init(
        showSubredditIconsInSubredditList: Bool = true,
        showSubredditIconsForPosts: Bool = true,
        alwaysShowUsernames: Bool = false,
        showSubredditAtTop: Bool = false,
        showPageEndings: Bool = false,
        boldPostTitles: Bool = false,
        showVotingButtons: Bool = true,
        votingButtonsPosition: AppearanceEdgePosition = .right,
        rememberPostSizePerSubreddit: Bool = false,
        useSystemTextSize: Bool = false,
        textSizeScale: Double = 1.0,
        largePostsShowVotingButtons: Bool = true,
        gifProgressLocation: GIFProgressLocation = .everywhere,
        compactShowSelfPostThumbnails: Bool = true
    ) {
        self.showSubredditIconsInSubredditList = showSubredditIconsInSubredditList
        self.showSubredditIconsForPosts = showSubredditIconsForPosts
        self.alwaysShowUsernames = alwaysShowUsernames
        self.showSubredditAtTop = showSubredditAtTop
        self.showPageEndings = showPageEndings
        self.boldPostTitles = boldPostTitles
        self.showVotingButtons = showVotingButtons
        self.votingButtonsPosition = votingButtonsPosition
        self.rememberPostSizePerSubreddit = rememberPostSizePerSubreddit
        self.useSystemTextSize = useSystemTextSize
        self.textSizeScale = textSizeScale
        self.largePostsShowVotingButtons = largePostsShowVotingButtons
        self.gifProgressLocation = gifProgressLocation
        self.compactShowSelfPostThumbnails = compactShowSelfPostThumbnails
    }

    /// Decodes leniently via `decodeIfPresent` so a blob missing a field still
    /// decodes instead of losing the whole Appearance blob.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showSubredditIconsInSubredditList = (try? container.decodeIfPresent(Bool.self, forKey: .showSubredditIconsInSubredditList)) ?? AppearanceSettings.default.showSubredditIconsInSubredditList
        showSubredditIconsForPosts = (try? container.decodeIfPresent(Bool.self, forKey: .showSubredditIconsForPosts)) ?? AppearanceSettings.default.showSubredditIconsForPosts
        alwaysShowUsernames = (try? container.decodeIfPresent(Bool.self, forKey: .alwaysShowUsernames)) ?? AppearanceSettings.default.alwaysShowUsernames
        showSubredditAtTop = (try? container.decodeIfPresent(Bool.self, forKey: .showSubredditAtTop)) ?? AppearanceSettings.default.showSubredditAtTop
        showPageEndings = (try? container.decodeIfPresent(Bool.self, forKey: .showPageEndings)) ?? AppearanceSettings.default.showPageEndings
        boldPostTitles = (try? container.decodeIfPresent(Bool.self, forKey: .boldPostTitles)) ?? AppearanceSettings.default.boldPostTitles
        showVotingButtons = (try? container.decodeIfPresent(Bool.self, forKey: .showVotingButtons)) ?? AppearanceSettings.default.showVotingButtons
        votingButtonsPosition = (try? container.decodeIfPresent(AppearanceEdgePosition.self, forKey: .votingButtonsPosition)) ?? AppearanceSettings.default.votingButtonsPosition
        rememberPostSizePerSubreddit = (try? container.decodeIfPresent(Bool.self, forKey: .rememberPostSizePerSubreddit)) ?? AppearanceSettings.default.rememberPostSizePerSubreddit
        useSystemTextSize = (try? container.decodeIfPresent(Bool.self, forKey: .useSystemTextSize)) ?? AppearanceSettings.default.useSystemTextSize
        textSizeScale = (try? container.decodeIfPresent(Double.self, forKey: .textSizeScale)) ?? AppearanceSettings.default.textSizeScale
        largePostsShowVotingButtons = (try? container.decodeIfPresent(Bool.self, forKey: .largePostsShowVotingButtons)) ?? true
        gifProgressLocation = (try? container.decodeIfPresent(GIFProgressLocation.self, forKey: .gifProgressLocation)) ?? .everywhere
        compactShowSelfPostThumbnails = (try? container.decodeIfPresent(Bool.self, forKey: .compactShowSelfPostThumbnails)) ?? true
    }
}

public enum AppearanceSettingsStore {
    private static let key = "Phoebus.appearanceSettings"

    public static let storage = SettingsStore<AppearanceSettings>(
        key: key, didChange: didChangeNotification) { AppearanceSettings.default }

    public static func load() -> AppearanceSettings { storage.load() }

    /// Posted after any appearance change. Screens load these settings once into
    /// `@State`, and the Text Size override reads its value once when the root
    /// view is built, so a change needs a broadcast to take effect before relaunch.
    public static let didChangeNotification =
        Notification.Name("com.pendo324.Phoebus.appearanceSettingsDidChange")

    public static func save(_ settings: AppearanceSettings) { storage.save(settings) }
}

extension AppearanceSettings: StoredSettingsModel {
    public static var store: SettingsStore<AppearanceSettings> { AppearanceSettingsStore.storage }
}
