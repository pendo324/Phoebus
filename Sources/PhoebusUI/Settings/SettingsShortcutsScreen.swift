import SwiftUI
import PhoebusCore

/// Reborn "Settings Shortcuts" editor: "Enabled Shortcuts" (reorderable,
/// deletable, up to 15) and "Available Shortcuts" (tap + to add), with Reborn's
/// footers verbatim.
public struct SettingsShortcutsScreen: View {
    @Setting(SettingsShortcutsStore.storage) private var included
    @State private var editMode: EditMode = .inactive

    public init() {}

    private var available: [String] {
        SettingsShortcutsStore.catalog.filter { !included.contains($0) }
    }

    public var body: some View {
        List {
            Section {
                ForEach(included, id: \.self) { id in
                    row(id)
                        .apolloSettingsRowInsets()
                }
                .onMove { from, to in $included.update { $0.move(fromOffsets: from, toOffset: to) } }
                .onDelete { offsets in $included.update { $0.remove(atOffsets: offsets) } }
            } header: {
                Text("Enabled Shortcuts").apolloSectionHeader()
            } footer: {
                Text("\(included.count) of \(SettingsShortcutsStore.limit) shortcuts enabled. Press and hold the Settings tab to open them. Changes are saved automatically.")
                    .apolloSectionFooter()
            }
            Section {
                ForEach(available, id: \.self) { id in
                    HStack {
                        row(id)
                        Spacer()
                        Button {
                            guard included.count < SettingsShortcutsStore.limit else { return }
                            $included.update { $0.append(id) }
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(included.count >= SettingsShortcutsStore.limit)
                        .accessibilityLabel("Add \(SettingsShortcutsStore.title(id))")
                    }
                    .apolloSettingsRowInsets()
                }
            } header: {
                Text("Available Shortcuts").apolloSectionHeader()
            } footer: {
                Text("Tap Edit to add, remove, or reorder shortcuts.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .environment(\.editMode, $editMode)
        .navigationTitle("Shortcuts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
            }
        }
    }

    private func row(_ id: String) -> some View {
        HStack(spacing: ApolloSettingsRowMetrics.hubTileToTitleGap) {
            SettingsTile(systemImage: SettingsShortcutsStore.systemImage(id), tint: Self.tint(id))
            Text(SettingsShortcutsStore.title(id))
                .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("settingsShortcuts.\(id)")
    }


    /// Blue, except Saved Categories green, Picture-in-Picture purple, and the emoji
    /// tiles' yellow/red; native rows keep their own Settings/hub tile colours.
    static func tint(_ id: String) -> Color {
        switch id {
        // Reborn's shortcut image colours.
        case "saved-categories": return .green
        case "picture-in-picture": return .purple
        case "translation": return .teal
        case "apollo-ai": return .indigo
        case "media": return .pink
        case "posts-feeds": return .orange
        case "comments": return .green
        case "subreddits": return .red
        case "profile-layout": return .teal
        case "interface": return .purple
        case "accounts-api-keys": return .gray
        case "tag-filters", "crash-reports": return .orange
        case "feature-requests": return .yellow
        case "bug-reports": return .red
        case "theme-manager": return .indigo
        case "reborn": return .purple
        case "buy-coffee": return .yellow
        case "general": return .gray
        case "filters": return .green
        case "gestures": return Color(red: 0.4, green: 0.45, blue: 0.95)
        default: return .blue
        }
    }
}

/// The screen a shortcut opens.
public struct SettingsShortcutDestination: View {
    let id: String
    let accountManager: AccountManager

    public init(id: String, accountManager: AccountManager) {
        self.id = id
        self.accountManager = accountManager
    }

    public var body: some View {
        switch id {
        case "reborn": ApolloRebornHubScreen(accountManager: accountManager)
        case "accounts-api-keys": AccountsAPIKeysScreen(accountManager: accountManager)
        case "posts-feeds": PostsFeedsSettingsScreen()
        case "comments": CommentsSettingsScreen()
        case "media": MediaSettingsScreen()
        case "subreddits": SubredditsSettingsScreen()
        case "profile-layout": ProfileLayoutSettingsScreen()
        case "interface": InterfaceSettingsScreen()
        case "rich-link-previews": LinkPreviewSettingsScreen()
        case "apollo-ai": ApolloAISettingsScreen()
        case "theme-manager": ThemeSettingsScreen()
        case "open-in-app": OpenInAppSettingsScreen()
        case "picture-in-picture": PictureInPictureSettingsScreen()
        case "translation": TranslationSettingsScreen()
        case "saved-categories": SavedCategoriesSettingsScreen()
        case "tag-filters": TagFiltersSettingsScreen()
        case "automatic-backups": AutomaticBackupSettingsScreen()
        case "crash-reports": CrashReportsScreen()
        case "bug-reports": BugReportScreen()
        case "buy-coffee": BuyUsACoffeeScreen()
        case "general": GeneralSettingsScreen()
        case "appearance": AppearanceSettingsScreen()
        case "app-icon": AppIconSettingsScreen()
        case "filters": FiltersSettingsScreen()
        case "gestures": GestureSettingsScreen()
        default: ApolloRebornHubScreen(accountManager: accountManager)
        }
    }
}
