import Foundation

/// Apollo-Reborn's "Backup & Restore": exports every UserDefaults-backed
/// setting and local-data store as a single JSON document, plus the signed-in
/// accounts, and restores from one.
public struct BackupBundle: Codable, Sendable {
    public var generalSettings: GeneralSettings
    public var markReadSettings: MarkReadSettings
    public var swipeActionSettings: SwipeActionSettings
    /// Every screen's swipe-action settings are captured, not just the Posts
    /// slots.
    public var swipeActionSettingsByScreen: [String: SwipeActionSettings]?
    public var contentFilters: [ContentFilter]
    public var tagFilterSettings: TagFilterSettings
    public var customSubredditSourceSettings: CustomSubredditSourceSettings
    public var savedCategories: [SavedCategory]
    public var savedCategoryAssignments: [String: String]
    /// Every backed-up `UserDefaults` key, captured wholesale as Apollo-Reborn
    /// backs up whole preference domains, so new settings are included without
    /// being listed. The typed fields are kept alongside it so a version-1
    /// export still restores; see `restore()`.
    public var settingsDomain: [String: JSONValue]?

    /// The signed-in accounts, so a restore returns a working session. Apollo-Reborn
    /// does the same with `keychain.plist` and `accounts.txt`.
    ///
    /// Security: this makes the archive credential-bearing, so the export flow
    /// warns that it contains logged-in account credentials.
    public var accounts: AccountStorePersisted?

    /// Format version, so a future restore can detect and migrate an older export.
    public var version: Int

    /// Version 2 adds `settingsDomain` and `accounts`.
    public static let currentVersion = 2

    public init(
        generalSettings: GeneralSettings,
        markReadSettings: MarkReadSettings,
        swipeActionSettings: SwipeActionSettings,
        swipeActionSettingsByScreen: [String: SwipeActionSettings]? = nil,
        contentFilters: [ContentFilter],
        tagFilterSettings: TagFilterSettings,
        customSubredditSourceSettings: CustomSubredditSourceSettings,
        savedCategories: [SavedCategory],
        savedCategoryAssignments: [String: String],
        version: Int = BackupBundle.currentVersion
    ) {
        self.generalSettings = generalSettings
        self.markReadSettings = markReadSettings
        self.swipeActionSettings = swipeActionSettings
        self.swipeActionSettingsByScreen = swipeActionSettingsByScreen
        self.contentFilters = contentFilters
        self.tagFilterSettings = tagFilterSettings
        self.customSubredditSourceSettings = customSubredditSourceSettings
        self.savedCategories = savedCategories
        self.savedCategoryAssignments = savedCategoryAssignments
        self.version = version
    }

    /// Snapshots every store this rewrite persists to UserDefaults.
    public static func captureCurrent(includeAccounts: Bool = true) -> BackupBundle {
        var bundle = BackupBundle(
            generalSettings: GeneralSettingsStore.load(),
            markReadSettings: ReadPostStore.loadSettings(),
            swipeActionSettings: SwipeActionStore.load(),
            swipeActionSettingsByScreen: Dictionary(uniqueKeysWithValues: SwipeActionScreen.allCases.map { ($0.rawValue, SwipeActionStore.load(for: $0)) }),
            contentFilters: ContentFilterStore.load(),
            tagFilterSettings: TagFilterStore.load(),
            customSubredditSourceSettings: CustomSubredditSourceStore.load(),
            savedCategories: SavedCategoryStore.loadCategories(),
            savedCategoryAssignments: SavedCategoryStore.allAssignments()
        )
        bundle.settingsDomain = SettingsDomainSnapshot.capture()
        if includeAccounts {
            // Read through the same platform keychain store the app uses, not a live
            // AccountStore: the backup wants what is persisted.
            bundle.accounts = AccountKeychainStoreBox().load()
        }
        return bundle
    }

    /// Writes every field back into its store, overwriting what is persisted.
    /// Read-tracking (`ReadPostStore`) and per-thread new-comment tracking
    /// (`NewCommentsTracker`) are excluded: they are high-churn view-state caches,
    /// and restoring stale ones would mark posts read that were never seen here.
    public func restore() {
        // Domain snapshot first, typed fields second: a version-1 export has no
        // `settingsDomain`, and a version-2 one holds the same stores in both places,
        // so both formats converge on the same result.
        if let settingsDomain {
            SettingsDomainSnapshot.restore(settingsDomain)
        }
        // The API key and redirect land in defaults with the domain, but
        // the live OAuth config only reads them at launch; restored
        // accounts refresh their tokens through it.
        CustomAPISettingsStore.applyPersisted()
        if let accounts {
            AccountKeychainStoreBox().save(accounts)
        }
        GeneralSettingsStore.save(generalSettings)
        ReadPostStore.saveSettings(markReadSettings)
        SwipeActionStore.save(swipeActionSettings)
        if let byScreen = swipeActionSettingsByScreen {
            for (raw, settings) in byScreen {
                guard let screen = SwipeActionScreen(rawValue: raw) else { continue }
                SwipeActionStore.save(settings, for: screen)
            }
        }
        ContentFilterStore.save(contentFilters)
        TagFilterStore.save(tagFilterSettings)
        CustomSubredditSourceStore.save(customSubredditSourceSettings)
        SavedCategoryStore.saveCategories(savedCategories)
        SavedCategoryStore.replaceAllAssignments(savedCategoryAssignments)
        if accounts != nil {
            NotificationCenter.default.post(name: .apolloAccountsRestored, object: nil)
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> BackupBundle {
        try JSONDecoder().decode(BackupBundle.self, from: data)
    }
}
