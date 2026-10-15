import Foundation

/// The settings tree's thirteen task groups, in root order: who you are,
/// what you look at (appearance, posts, the feed, comments, media), where
/// links go, what you filter out, what interrupts you, how you drive the
/// app, what it plugs into, what it keeps, then About.
///
/// A category is a screen of settings, not a list of links to them: its
/// sections hold the switches and pickers themselves. A drill-down exists
/// only where a setting needs a screen of its own (a list editor, a
/// pinned live preview, a multi-step tool).
///
/// `SettingsSection` stays the screen inventory (Apollo's own row
/// order, titles and tiles); this is the tree the Settings tab shows,
/// and the one source the root, the drill-down rows, the shortcuts and
/// the search index read.
public enum SettingsCategory: String, CaseIterable, Sendable, Identifiable {
    case accountsSecurity
    case appearance
    case posts
    case feed
    case comments
    case media
    case linksSharing
    case filters
    case inboxNotifications
    case gesturesHaptics
    case integrations
    case dataStorage
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accountsSecurity: return "Accounts & Security"
        case .appearance: return "Appearance"
        case .posts: return "Posts"
        case .feed: return "Feed"
        case .comments: return "Comments"
        case .media: return "Media"
        case .linksSharing: return "Links & Sharing"
        case .filters: return "Filters"
        case .inboxNotifications: return "Inbox & Notifications"
        case .gesturesHaptics: return "Gestures & Haptics"
        case .integrations: return "Integrations"
        case .dataStorage: return "Data & Storage"
        case .about: return "About"
        }
    }

    public var systemImage: String {
        switch self {
        case .accountsSecurity: return "lock.shield.fill"
        case .appearance: return "paintbrush.fill"
        case .posts: return "newspaper.fill"
        case .feed: return "rectangle.grid.1x2.fill"
        case .comments: return "text.bubble.fill"
        case .media: return "play.rectangle.fill"
        case .linksSharing: return "link"
        case .filters: return "line.3.horizontal.decrease.circle.fill"
        case .inboxNotifications: return "bell.fill"
        case .gesturesHaptics: return "hand.tap.fill"
        case .integrations: return "puzzlepiece.extension.fill"
        case .dataStorage: return "externaldrive.fill"
        case .about: return "info.circle.fill"
        }
    }

    /// Root rows render as iOS-style Settings rows: a white glyph on a
    /// rounded per-row coloured tile, one colour per category.
    public var tintRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .accountsSecurity: return (0.25, 0.56, 0.97)
        case .appearance: return (0.70, 0.14, 0.47)
        case .posts: return (1.00, 0.58, 0.00)
        case .feed: return (0.19, 0.69, 0.78)
        case .comments: return (0.40, 0.81, 0.40)
        case .media: return (0.94, 0.42, 0.64)
        case .linksSharing: return (0.69, 0.28, 0.85)
        case .filters: return (0.31, 0.69, 0.72)
        case .inboxNotifications: return (0.92, 0.32, 0.30)
        case .gesturesHaptics: return (0.44, 0.48, 0.97)
        case .integrations: return (0.35, 0.34, 0.84)
        case .dataStorage: return (0.20, 0.48, 0.90)
        case .about: return (0.39, 0.39, 0.40)
        }
    }

    /// One line under the category's title on its root row, naming what
    /// the errand is.
    public var subtitle: String {
        switch self {
        case .accountsSecurity: return "Accounts, API keys, passcode"
        case .appearance: return "Theme, icon and text"
        case .posts: return "Post layout, flairs and polls"
        case .feed: return "Sorting, read posts and subreddit lists"
        case .comments: return "Sorting, collapsing and highlights"
        case .media: return "Playback, galleries and saving"
        case .linksSharing: return "Browsers, sharing and uploads"
        case .filters: return "What you don't see"
        case .inboxNotifications: return "Alerts, sound and delivery"
        case .gesturesHaptics: return "Swipes, haptics and rotation"
        case .integrations: return "Siri, widget, translation and AI"
        case .dataStorage: return "Backups, saved items and caches"
        case .about: return "Version, updates and support"
        }
    }

    /// A right-detail value on the root row, where one says something
    /// the title doesn't. `values` carries what only the app layer
    /// knows (signed-in account count, bundle version).
    public func trailingValue(_ values: SettingsCategoryValues) -> String? {
        switch self {
        case .accountsSecurity:
            if AppLockStore.load().isEnabled {
                return Self.appLockSummary(isEnabled: true, biometry: AppLockStore.biometry)
            }
            return values.accountCount > 1 ? "\(values.accountCount) accounts" : nil
        case .appearance:
            let theme = ThemeStore.load()
            return "\(theme.name) · \(theme.isDark ? "Dark" : "Light")"
        case .about:
            return values.version.isEmpty ? nil : values.version
        case .posts, .feed, .comments, .media, .linksSharing, .filters, .inboxNotifications,
             .gesturesHaptics, .integrations, .dataStorage:
            return nil
        }
    }

    /// What locks the app: the biometry that unlocks it, the passcode
    /// alone, or "Off".
    public static func appLockSummary(isEnabled: Bool, biometry: AppLockBiometry) -> String {
        guard isEnabled else { return "Off" }
        switch biometry {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Passcode"
        }
    }

    /// The category screen's sections, top to bottom. A section lists
    /// the drill-downs and actions it holds; its switches and pickers
    /// are the screen's own, found by the search index.
    public var sections: [SettingsCategorySection] {
        switch self {
        case .accountsSecurity:
            return [
                .init("Accounts"),
                .init("Sign-In", drillDowns: [.signInTroubleshooting, .apiKeySetupGuide]),
                .init("Settings per Account"),
                .init("API Keys"),
                .init("Kagi Search"),
                .init("YouTube"),
                .init("Passcode"),
                .init(nil, actions: [.signOut]),
            ]
        case .appearance:
            return [
                .init("Theme", drillDowns: [.themeManager, .appIcon]),
                .init("Text", drillDowns: [.textSizes]),
                .init("Tab Bar"),
                .init("Bars & Navigation"),
                .init("Keyboard"),
                .init("Profiles", drillDowns: [.profileLayout]),
            ]
        case .posts:
            return [
                .init("Layout"),
                .init("Large Posts"),
                .init("Compact Posts"),
                .init("Thumbnails"),
                .init("Flair & Awards"),
                .init("Post Info", drillDowns: [.infoRow]),
                .init("Polls", crossLinks: [.webSignIn]),
            ]
        case .feed:
            return [
                .init("Sorting"),
                .init("Loading"),
                .init("Read Posts"),
                .init("Auto Hide"),
                .init("Recently Read"),
                .init("Floating Tabs"),
                .init("Interactive Posts"),
                .init("Subreddit List", drillDowns: [.feedShortcuts, .subredditSections, .subredditLayout]),
                .init("Search", drillDowns: [.searchSources]),
            ]
        case .comments:
            return [
                .init("Sorting"),
                .init("Collapsing"),
                .init("Navigation"),
                .init("Highlights"),
                .init("Removed Comments"),
                .init("Live Comments"),
                .init("Display", drillDowns: [.commentsTheme, .inlineMedia]),
            ]
        case .media:
            return [
                .init("Browsing"),
                .init("Playback"),
                .init("NSFW Media"),
                .init("Saving"),
                .init("Miniplayer", drillDowns: [.pictureInPicture]),
                .init("Network"),
            ]
        case .linksSharing:
            return [
                .init("Open Links In"),
                .init("In-App Browser"),
                .init("Other Apps", drillDowns: [.openInApp]),
                .init("Sharing"),
                .init("Uploads"),
                .init("Link Previews", drillDowns: [.linkPreview]),
            ]
        case .filters:
            return [
                .init("Filtered Keywords"),
                .init("Filtered Subreddits"),
                .init("Rules", drillDowns: [.postRules, .commentFilters]),
                .init(nil, drillDowns: [.blockedUsers]),
                .init(nil, drillDowns: [.userTags]),
                .init("Filtered Authors & Domains"),
                .init("Subreddit-Specific Filters"),
                .init("Filter Subreddits by Name"),
                .init("Tag Filters"),
                .init("Per-Subreddit Overrides"),
            ]
        case .inboxNotifications:
            return [
                .init("Inbox"),
                .init("Notification Sound"),
                .init("Moderator"),
                .init("Delivery"),
                .init("Registration"),
                .init("Watchers", drillDowns: [.subredditWatchers]),
            ]
        case .gesturesHaptics:
            return SwipeActionScreen.allCases.map { SettingsCategorySection($0.displayName) } + [
                .init("Other"),
                .init("Haptics"),
                .init("Rotation"),
                .init("Menus", drillDowns: [.actionMenus]),
            ]
        case .integrations:
            return [
                .init("Siri & Spotlight", requires: .iOS27),
                .init("Index Status", requires: .iOS27),
                .init("Widget"),
                .init("Widget Setup Code"),
                .init("Translation & AI", drillDowns: [.translation, .apolloAI]),
                .init("Settings Tab", drillDowns: [.settingsShortcuts]),
            ]
        case .dataStorage:
            return [
                .init("Backups"),
                .init("Backup Schedule"),
                .init("Backup Activity"),
                .init(nil, drillDowns: [.localBackups]),
                .init("Export & Restore"),
                .init("Saved Items", drillDowns: [.savedCategories]),
                .init("Storage", drillDowns: [.cacheExplainer], actions: [.clearCache, .clearBanners]),
                .init("Uploads", drillDowns: [.deleteImgurUploads]),
            ]
        case .about:
            return [
                .init(nil),
                .init("Updates"),
                .init("Support", drillDowns: [.bugReports, .crashReports], actions: [.exportLogs]),
                .init("Credits"),
            ]
        }
    }

    /// Every drill-down the category's screen pushes, top to bottom.
    public var drillDowns: [SettingsDrillDown] {
        sections.flatMap(\.drillDowns)
    }

    /// The links to other categories' rows the category's screen draws.
    public var crossLinks: [SettingsCrossLink] {
        sections.flatMap(\.crossLinks)
    }

    /// The tap path to this category, or to `section` on its screen, for
    /// copy that sends the user there ("Settings → Accounts & Security →
    /// API Keys").
    public func path(section: String? = nil) -> String {
        "Settings \u{2192} \(title)" + (section.map { " \u{2192} \($0)" } ?? "")
    }

    /// The tap path to a drill-down from the Settings root.
    public static func path(to destination: SettingsDrillDownDestination) -> String {
        guard let category = category(containing: destination),
              let drillDown = category.drillDowns.first(where: { $0.destination == destination }) else {
            return "Settings"
        }
        return category.path(section: drillDown.title)
    }

    /// The category whose screen holds the row that opens `destination`.
    public static func category(containing destination: SettingsDrillDownDestination) -> SettingsCategory? {
        allCases.first { $0.drillDowns.contains { $0.destination == destination } }
    }

    /// The drill-down that opens `destination`, wherever in the tree it is.
    public static func drillDown(for destination: SettingsDrillDownDestination) -> SettingsDrillDown? {
        for category in allCases {
            if let found = category.drillDowns.first(where: { $0.destination == destination }) { return found }
        }
        return nil
    }
}

/// A condition a row exists under; without it the row is left out of its
/// category screen and of search.
public enum SettingsRowRequirement: String, CaseIterable, Sendable {
    /// iOS 27 or later (Siri & Spotlight's index needs it).
    case iOS27
    /// A build with a release channel, so it has an update source to check.
    case releaseChannel
    /// A Reddit session the screen can end (not on the global-defaults
    /// sheet, which edits the layer every account shares).
    case session
}

/// One section of a category screen: its header (`nil` for an untitled
/// one) and the drill-downs and actions it holds. The switches and
/// pickers inside are the screen's own.
public struct SettingsCategorySection: Sendable, Equatable {
    public let title: String?
    public let requires: SettingsRowRequirement?
    public let drillDowns: [SettingsDrillDown]
    public let actions: [SettingsAction]
    public let crossLinks: [SettingsCrossLink]

    public init(_ title: String?, requires: SettingsRowRequirement? = nil,
                drillDowns: [SettingsDrillDownDestination] = [], actions: [SettingsAction] = [],
                crossLinks: [SettingsCrossLink] = []) {
        self.title = title
        self.requires = requires
        self.drillDowns = drillDowns.map(SettingsDrillDown.init)
        self.actions = actions
        self.crossLinks = crossLinks
    }
}

/// A row that sends the user to a row on another category's screen, for a
/// setting that depends on one that lives elsewhere. It is not a second
/// entrance to a screen: it opens the category screen the row is on, scrolled
/// to that row, so the one-entrance rule for drill-downs is unaffected.
public enum SettingsCrossLink: String, CaseIterable, Sendable {
    /// Polls need the active account signed in with a reddit.com web session.
    case webSignIn

    public var title: String {
        switch self {
        case .webSignIn: return "Web Sign-In"
        }
    }

    /// The category screen it opens.
    public var category: SettingsCategory {
        switch self {
        case .webSignIn: return .accountsSecurity
        }
    }

    /// The search row on that screen it scrolls to and flashes.
    public var row: String {
        switch self {
        case .webSignIn: return "reddit.com Web Sign-In"
        }
    }
}

/// A row that pushes a screen of its own from a category screen.
public struct SettingsDrillDown: Sendable, Equatable, Identifiable {
    public let destination: SettingsDrillDownDestination

    public init(_ destination: SettingsDrillDownDestination) {
        self.destination = destination
    }

    public var id: String { destination.rawValue }
    public var title: String { destination.title }
}

/// Every screen a category screen pushes. `SettingsDrillDownLeaf` in
/// PhoebusUI switches over it exhaustively, so a drill-down added here
/// does not compile until it is routed.
public enum SettingsDrillDownDestination: String, CaseIterable, Sendable {
    case signInTroubleshooting
    case apiKeySetupGuide

    case themeManager
    case appIcon
    case textSizes
    case profileLayout

    case infoRow

    case feedShortcuts
    case subredditSections
    case subredditLayout
    case searchSources

    case commentsTheme
    case inlineMedia

    case pictureInPicture

    case openInApp
    case linkPreview

    case postRules
    case commentFilters
    case blockedUsers
    case userTags

    case subredditWatchers

    case actionMenus

    case translation
    case apolloAI
    case settingsShortcuts

    case localBackups
    case savedCategories
    case cacheExplainer
    case deleteImgurUploads

    case bugReports
    case crashReports

    /// The row's title, which is also the pushed screen's navigation title.
    public var title: String {
        switch self {
        case .signInTroubleshooting: return "Can't sign in?"
        case .apiKeySetupGuide: return "Giphy & Image Chest API Key Setup"
        case .themeManager: return "Theme Manager"
        case .appIcon: return "App Icon"
        case .textSizes: return "Text Sizes & Fonts"
        case .profileLayout: return "Profile Layout"
        case .infoRow: return "Info Row"
        case .feedShortcuts: return "Subreddit Shortcuts"
        case .subredditSections: return "Subreddit List Sections"
        case .subredditLayout: return "Subreddit Layout"
        case .searchSources: return "Search Sources"
        case .commentsTheme: return "Thread Colours"
        case .inlineMedia: return "Inline Images"
        case .pictureInPicture: return "Picture-in-Picture"
        case .openInApp: return "Open in App"
        case .linkPreview: return "Preview Cards"
        case .postRules: return "Post Rules"
        case .commentFilters: return "Comment Rules"
        case .blockedUsers: return "Blocked Users"
        case .userTags: return "User Tags"
        case .subredditWatchers: return "Subreddit Watchers"
        case .actionMenus: return "Action Menus"
        case .translation: return "Translation"
        case .apolloAI: return "Phoebus AI"
        case .settingsShortcuts: return "Settings Shortcuts"
        case .localBackups: return "Manage Backups"
        case .savedCategories: return "Saved Categories"
        case .cacheExplainer: return CacheExplainer.title
        case .deleteImgurUploads: return "Manage Imgur Uploads"
        case .bugReports: return "Bug Reports"
        case .crashReports: return "Crash Reports"
        }
    }
}

/// A row on a category screen that acts in place rather than pushing.
public enum SettingsAction: String, CaseIterable, Sendable {
    case signOut
    case clearCache
    case clearBanners
    case exportLogs

    public var title: String {
        switch self {
        case .signOut: return "Sign Out"
        case .clearCache: return "Clear Cache"
        case .clearBanners: return "Clear Banners & Icons"
        case .exportLogs: return "Export Debug Logs"
        }
    }

    /// Actions that destroy something ask first. Exporting a log only
    /// opens the share sheet, so it runs on the tap.
    public var confirmsFirst: Bool {
        switch self {
        case .signOut, .clearCache, .clearBanners: return true
        case .exportLogs: return false
        }
    }

    /// The condition the row exists under, if any.
    public var requires: SettingsRowRequirement? {
        self == .signOut ? .session : nil
    }
}

/// Values only the app layer can supply to a category's trailing value.
public struct SettingsCategoryValues: Sendable, Equatable {
    /// Signed-in Reddit accounts.
    public var accountCount: Int
    /// The bundle's short version, already prefixed ("v3.7.1").
    public var version: String

    public init(accountCount: Int, version: String) {
        self.accountCount = accountCount
        self.version = version
    }
}
