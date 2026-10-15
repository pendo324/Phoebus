import SwiftUI
import PhoebusCore

/// A row that pushes one of the screens a category's `sections` list. The
/// title comes from Core, so the row, the pushed screen's navigation
/// title, the search index and the shortcut menu cannot name it
/// differently.
struct SettingsDrillDownRow: View {
    let destination: SettingsDrillDownDestination
    /// A grey summary before the disclosure chevron.
    var value: String? = nil
    /// Artwork after the value, for App Icon's current icon.
    var artwork: Image? = nil
    /// The last row of a section that has a footer draws no rule.
    var lastBeforeFooter = false

    var body: some View {
        SettingsLink {
            SettingsDrillDownLeaf(destination: destination)
        } label: {
            HStack(spacing: 8) {
                ValueRow(title: destination.title, value: value ?? "")
                if let artwork {
                    artwork
                        .resizable()
                        .scaledToFill()
                        .frame(width: 29, height: 29)
                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                }
            }
        }
        .apolloPlainSettingsRowInsets(rule: !lastBeforeFooter)
        .accessibilityIdentifier("settings.\(destination.rawValue)")
    }
}

/// A title with a grey value on the trailing edge, before the disclosure
/// chevron the enclosing link draws.
struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .layoutPriority(1)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// The screen a drill-down row pushes. Exhaustive over Core's
/// destinations, so a row added there cannot be left unrouted.
struct SettingsDrillDownLeaf: View {
    let destination: SettingsDrillDownDestination

    var body: some View {
        switch destination {
        case .signInTroubleshooting: SignInTroubleshootingScreen()
        case .apiKeySetupGuide: APIKeySetupGuideScreen()
        case .themeManager: ThemeSettingsScreen()
        case .appIcon: AppIconSettingsScreen()
        case .textSizes: TextSizesAndFontsScreen()
        case .profileLayout: ProfileLayoutSettingsScreen()
        case .infoRow: InfoRowSettingsScreen()
        case .feedShortcuts: FeedShortcutsSettingsScreen()
        case .subredditSections: SubredditSectionsSettingsScreen()
        case .subredditLayout: SubredditLayoutSettingsScreen()
        case .searchSources: SearchSourcesSettingsScreen()
        case .commentsTheme: CommentsThemeSettingsScreen()
        case .inlineMedia: InlineMediaSettingsScreen()
        case .pictureInPicture: PictureInPictureSettingsScreen()
        case .openInApp: OpenInAppSettingsScreen()
        case .linkPreview: LinkPreviewSettingsScreen()
        case .postRules: PostRulesScreen()
        case .commentFilters: CommentFiltersScreen()
        case .blockedUsers: BlockedUsersScreen()
        case .userTags: UserTagsSettingsScreen()
        case .subredditWatchers: SubredditWatchersScreen()
        case .actionMenus: ActionMenusSettingsScreen()
        case .translation: TranslationSettingsScreen()
        case .apolloAI: ApolloAISettingsScreen()
        case .settingsShortcuts: SettingsShortcutsScreen()
        case .localBackups: LocalBackupsScreen()
        case .savedCategories: SavedCategoriesSettingsScreen()
        case .cacheExplainer: CacheExplainerScreen()
        case .deleteImgurUploads: DeleteImgurUploadsScreen()
        case .bugReports: BugReportScreen()
        case .crashReports: CrashReportsScreen()
        }
    }
}
