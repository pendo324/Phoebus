import SwiftUI
import PhoebusCore

/// Settings search UI: the `.searchable` results list on the Settings root, and
/// the destination for a chosen result.
///
/// Reborn's settings search. The matcher is a direct port (`SettingsSearch` in
/// PhoebusCore). Upstream is a tweak and navigates by synthesising taps with
/// delays and retries; here a result carries its destination directly and SwiftUI
/// pushes it. The visible behaviour is kept: the result shows its breadcrumb, and
/// the destination scrolls to the specific row and flashes it.
struct SettingsSearchResultsList: View {
    let entries: [SettingsSearchEntry]
    let accountManager: AccountManager
    let repository: RedditRepository

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableViewIfAvailable(
                title: "No Results",
                message: "No settings match your search.",
                systemImage: "magnifyingglass"
            )
        } else {
            List(entries) { entry in
                SettingsLink {
                    SettingsSearchDestination(
                        entry: entry,
                        accountManager: accountManager,
                        repository: repository
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                        // Result rows carry the breadcrumb, the only way to tell two identically named
                        // rows apart ("Provider" exists under both Translation and Apollo AI).
                        Text(entry.breadcrumb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.search.result.\(entry.title)")
            }
            .accessibilityIdentifier("settings.search.results")
        }
    }
}

/// The screen a chosen search result opens, with the target row
/// highlighted.
struct SettingsSearchDestination: View {
    let entry: SettingsSearchEntry
    let accountManager: AccountManager
    let repository: RedditRepository

    var body: some View {
        screen
            // After landing, the target row is scrolled to and briefly flashed. Upstream does
            // this by index path against a UITableView; here the row publishes its own title
            // and matching rows highlight themselves.
            .environment(\.settingsSearchHighlightedRow, entry.rowTitle)
    }

    @ViewBuilder
    private var screen: some View {
        switch entry.screen {
        case .settingsRoot, .accounts:
            AccountManagerScreen(accountManager: accountManager)
        case .general: GeneralSettingsScreen()
        case .gestures: GestureSettingsScreen()
        case .filters: FiltersSettingsScreen()
        case .markRead: MarkReadSettingsScreen()
        case .appIcon: AppIconSettingsScreen()
        case .appearance: AppearanceSettingsScreen()
        case .theme: ThemeSettingsScreen()
        case .about: AboutScreen()
        case .notifications: NotificationsSettingsScreen()
        case .security: SecuritySettingsScreen()
        case .portraitLock: PortraitLockSettingsScreen()
        case .apolloReborn: ApolloRebornHubScreen(accountManager: accountManager)
        case .savedCategories: SavedCategoriesSettingsScreen()
        case .translation: TranslationSettingsScreen()
        case .tagFilters: TagFiltersSettingsScreen()
        case .backupRestore: BackupRestoreSettingsScreen()
        case .comments: CommentsSettingsScreen()
        case .commentsTheme: CommentsThemeSettingsScreen()
        case .customAPI: AccountsAPIKeysScreen(accountManager: accountManager)
        case .deletedComments: DeletedCommentsSettingsScreen()
        case .externalBrowser: ExternalBrowserSettingsScreen()
        case .openInApp: OpenInAppSettingsScreen()
        case .infoRow: InfoRowSettingsScreen()
        case .inlineMedia: InlineMediaSettingsScreen()
        case .interfaceSettings: InterfaceSettingsScreen()
        case .actionMenus: ActionMenusSettingsScreen()
        case .linkPreview: LinkPreviewSettingsScreen()
        case .media: MediaSettingsScreen()
        case .notificationBackend: NotificationBackendSettingsScreen()
        case .pictureInPicture: PictureInPictureSettingsScreen()
        case .polls: PollsSettingsScreen(accountManager: accountManager)
        case .postsFeeds: PostsFeedsSettingsScreen()
        case .profileLayout: ProfileLayoutSettingsScreen()
        case .subredditLayout: SubredditLayoutSettingsScreen()
        case .subredditSections: SubredditSectionsSettingsScreen()
        case .subreddits: SubredditsSettingsScreen()
        case .apolloAI: ApolloAISettingsScreen()
        case .wallpapers: WallpapersSettingsScreen()
        case .automaticBackup: AutomaticBackupSettingsScreen()
        case .accountsAPIKeys: AccountsAPIKeysScreen(accountManager: accountManager)
        case .clearTweakCaches: ClearTweakCachesScreen()
        case .themeGallery:
            // The gallery needs a selection handler a search result cannot supply, so this
            // lands on the Theme screen that owns it.
            ThemeSettingsScreen()
        }
    }
}

// MARK: - Row highlighting

private struct SettingsSearchHighlightedRowKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Title of the row a search result asked to be highlighted, if any.
    var settingsSearchHighlightedRow: String? {
        get { self[SettingsSearchHighlightedRowKey.self] }
        set { self[SettingsSearchHighlightedRowKey.self] = newValue }
    }
}
