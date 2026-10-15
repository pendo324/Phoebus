import Foundation

/// Reborn "Settings Shortcuts" (#1150):
/// press and hold the Settings tab for a menu of up to 15 settings
/// screens, chosen and ordered under Integrations › Settings Shortcuts. Key
/// `SettingsTabShortcuts` (array of route IDs).
public enum SettingsShortcutsStore {
    public static let key = "SettingsTabShortcuts"
    /// Maximum number of shortcuts.
    public static let limit = 15

    /// Fixed discovery order: the root, the category screens, then the
    /// screens they push.
    public static let catalog: [String] = [
        "settings-root", "accounts-security", "appearance", "posts", "feed", "comments",
        "media", "links-sharing", "filters", "inbox-notifications", "gestures-haptics",
        "integrations", "data-storage", "about",
        "theme-manager", "app-icon", "rich-link-previews", "open-in-app", "picture-in-picture",
        "translation", "apollo-ai", "saved-categories", "crash-reports", "feature-requests",
        "bug-reports",
    ]

    /// Reborn's default when nothing is saved.
    public static let defaults = ["theme-manager", "data-storage", "feature-requests", "bug-reports"]

    /// Saved order, ids migrated, unknown IDs dropped, de-duplicated, capped.
    public static let storage = CustomSettingsSource<[String]>(
        key: key, load: { read($0) }, save: { ids, defaults in defaults.set(Array(ids.prefix(limit)), forKey: key) })

    public static func load() -> [String] { storage.load() }

    private static func read(_ store: UserDefaults) -> [String] {
        guard let saved = store.array(forKey: key) as? [String] else { return defaults }
        var valid: [String] = []
        for entry in saved {
            let id = migratedID(entry)
            if catalog.contains(id), !valid.contains(id), valid.count < limit { valid.append(id) }
        }
        return valid
    }

    /// IDs retired since a shortcut list was saved, each pointing at the
    /// category that now holds those settings.
    public static func migratedID(_ id: String) -> String {
        switch id {
        // Reborn merged Inline Media into Media.
        case "inline-media": return "media"
        // Reborn #1352 moved Profile Layout under User Profiles; that screen's
        // settings are now Appearance's Profiles section.
        case "profile-layout", "user-profiles", "interface": return "appearance"
        // The settings hub the row opened is gone; the settings root is
        // its replacement, so the shortcut keeps working.
        case "reborn": return "settings-root"
        case "accounts-api-keys": return "accounts-security"
        // Feeds, Subreddits and General's feed, read-post and default-load
        // rows are the Feed category.
        case "posts-feeds", "subreddits", "general": return "feed"
        // Tag Filters is a section of Filters.
        case "tag-filters": return "filters"
        // Backups are a section of Data & Storage.
        case "automatic-backups": return "data-storage"
        case "gestures": return "gestures-haptics"
        default: return id
        }
    }

    public static func save(_ ids: [String]) { storage.save(ids) }

    /// The screen a shortcut opens: the settings root, a category screen
    /// or one of the screens a category pushes.
    public enum Target: Equatable, Sendable {
        case root
        case category(SettingsCategory)
        case drillDown(SettingsDrillDownDestination)
    }

    /// Where a catalogue id goes. Every catalogue id has one.
    public static func target(_ id: String) -> Target? {
        switch id {
        case "settings-root": return .root
        case "accounts-security": return .category(.accountsSecurity)
        case "appearance": return .category(.appearance)
        case "posts": return .category(.posts)
        case "feed": return .category(.feed)
        case "comments": return .category(.comments)
        case "media": return .category(.media)
        case "links-sharing": return .category(.linksSharing)
        case "filters": return .category(.filters)
        case "inbox-notifications": return .category(.inboxNotifications)
        case "gestures-haptics": return .category(.gesturesHaptics)
        case "integrations": return .category(.integrations)
        case "data-storage": return .category(.dataStorage)
        case "about", "feature-requests": return .category(.about)
        case "theme-manager": return .drillDown(.themeManager)
        case "app-icon": return .drillDown(.appIcon)
        case "rich-link-previews": return .drillDown(.linkPreview)
        case "open-in-app": return .drillDown(.openInApp)
        case "picture-in-picture": return .drillDown(.pictureInPicture)
        case "translation": return .drillDown(.translation)
        case "apollo-ai": return .drillDown(.apolloAI)
        case "saved-categories": return .drillDown(.savedCategories)
        case "crash-reports": return .drillDown(.crashReports)
        case "bug-reports": return .drillDown(.bugReports)
        default: return nil
        }
    }

    /// Display title for a shortcut or route ID: the title of the row or
    /// screen it opens.
    public static func title(_ id: String) -> String {
        switch id {
        case "feature-requests": return "Feature Requests"
        default: break
        }
        switch target(id) {
        case .root: return "Settings"
        case .category(let category): return category.title
        case .drillDown(let destination): return destination.title
        case nil: return id
        }
    }

    /// SF Symbols for the shortcut rows: a category's own tile glyph, and
    /// the settings tile symbols for the screens they push.
    public static func systemImage(_ id: String) -> String {
        switch id {
        case "settings-root": return "gearshape.2.fill"
        case "theme-manager": return "paintbrush.fill"
        case "app-icon": return "app.fill"
        case "rich-link-previews": return "link"
        case "open-in-app": return "arrow.up.forward.app.fill"
        case "picture-in-picture": return "pip.fill"
        case "translation": return "character.bubble.fill"
        case "apollo-ai": return "sparkles"
        case "saved-categories": return "bookmark.fill"
        case "crash-reports": return "bandage"
        case "feature-requests": return "lightbulb.fill"
        case "bug-reports": return "ladybug.fill"
        default:
            if case .category(let category) = target(id) { return category.systemImage }
            return "gearshape"
        }
    }
}
