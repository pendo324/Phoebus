import Foundation

/// Reborn "Settings Shortcuts" (#1150):
/// press and hold the Settings tab for a menu of up to 15 settings
/// screens, chosen and ordered under Interface > Tab Bar > Settings
/// Shortcuts. Key `SettingsTabShortcuts` (array of route IDs).
public enum SettingsShortcutsStore {
    public static let key = "SettingsTabShortcuts"
    /// Maximum number of shortcuts.
    public static let limit = 15

    /// Fixed discovery order.
    public static let catalog: [String] = [
        "reborn", "accounts-api-keys", "posts-feeds", "comments", "media",
        "subreddits", "profile-layout", "interface", "rich-link-previews", "apollo-ai",
        "theme-manager", "open-in-app", "picture-in-picture", "translation", "saved-categories", "tag-filters",
        "automatic-backups", "crash-reports", "feature-requests", "bug-reports",
        "buy-coffee", "general", "appearance", "app-icon", "filters", "gestures",
    ]

    /// Reborn's default when nothing is saved.
    public static let defaults = ["theme-manager", "automatic-backups", "feature-requests", "bug-reports", "buy-coffee"]

    /// Saved order, unknown IDs dropped,
    /// "inline-media" migrated to "media", de-duplicated, capped.
    public static let storage = CustomSettingsSource<[String]>(
        key: key, load: { read($0) }, save: { ids, defaults in defaults.set(Array(ids.prefix(limit)), forKey: key) })

    public static func load() -> [String] { storage.load() }

    private static func read(_ store: UserDefaults) -> [String] {
        guard let saved = store.array(forKey: key) as? [String] else { return defaults }
        var valid: [String] = []
        for entry in saved {
            let id = entry == "inline-media" ? "media" : entry
            if catalog.contains(id), !valid.contains(id), valid.count < limit { valid.append(id) }
        }
        return valid
    }

    public static func save(_ ids: [String]) { storage.save(ids) }

    /// Display title for a shortcut or route ID.
    public static func title(_ id: String) -> String {
        switch id {
        case "reborn": return "Apollo Reborn"
        case "accounts-api-keys": return "Accounts & API Keys"
        case "posts-feeds": return "Posts & Feeds"
        case "comments": return "Comments"
        case "media": return "Media"
        case "subreddits": return "Subreddits"
        case "profile-layout": return "Profile Layout"
        case "interface": return "Interface"
        case "rich-link-previews": return "Rich Link Previews"
        case "apollo-ai": return "Phoebus AI"
        case "theme-manager": return "Theme Manager"
        case "open-in-app": return "Open in App"
        case "picture-in-picture": return "Picture-in-Picture"
        case "translation": return "Translation"
        case "saved-categories": return "Saved Categories"
        case "tag-filters": return "Tag Filters"
        case "automatic-backups": return "Backup Settings"
        case "crash-reports": return "Crash Reports"
        case "feature-requests": return "Feature Requests"
        case "bug-reports": return "Bug Reports"
        case "buy-coffee": return "Buy Us a Coffee"
        case "general": return "General"
        case "appearance": return "Appearance"
        case "app-icon": return "App Icon"
        case "filters": return "Filters & Blocks"
        case "gestures": return "Gestures"
        default: return id
        }
    }

    /// SF Symbols for the shortcut rows, with the
    /// hub/root tile symbols for the native rows.
    public static func systemImage(_ id: String) -> String {
        switch id {
        case "theme-manager": return "paintbrush.fill"
        case "saved-categories": return "bookmark.fill"
        case "automatic-backups": return "square.and.arrow.up.fill"
        case "tag-filters": return "tag.fill"
        case "translation": return "character.bubble.fill"
        case "picture-in-picture": return "pip.fill"
        case "apollo-ai": return "sparkles"
        case "open-in-app": return "arrow.up.forward.app.fill"
        case "media": return "play.rectangle.fill"
        case "posts-feeds": return "newspaper.fill"
        case "comments": return "text.bubble.fill"
        case "subreddits": return "person.3.fill"
        case "profile-layout": return "person.crop.circle.fill"
        case "interface": return "slider.horizontal.3"
        case "accounts-api-keys": return "key.fill"
        case "rich-link-previews": return "link"
        case "crash-reports": return "bandage"
        case "feature-requests": return "lightbulb.fill"
        case "bug-reports": return "ladybug.fill"
        case "reborn": return "gearshape.2.fill"
        case "buy-coffee": return "cup.and.saucer.fill"
        case "general": return "gearshape.fill"
        case "appearance": return "paintbrush.pointed.fill"
        case "app-icon": return "app.fill"
        case "filters": return "nosign"
        case "gestures": return "hand.tap.fill"
        default: return "gearshape"
        }
    }
}
