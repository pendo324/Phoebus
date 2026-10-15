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
        .navigationTitle("Settings Shortcuts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
            }
        }
    }

    private func row(_ id: String) -> some View {
        HStack(spacing: ApolloSettingsRowMetrics.categoryTileToTitleGap) {
            SettingsTile(systemImage: SettingsShortcutsStore.systemImage(id), tint: Self.tint(id))
            Text(SettingsShortcutsStore.title(id))
                .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("settingsShortcuts.\(id)")
    }


    /// A category's own tile colour; Reborn's shortcut image colours for the
    /// screens they push, and blue for the rest.
    static func tint(_ id: String) -> Color {
        switch SettingsShortcutsStore.target(id) {
        case .category(let category):
            let rgb = category.tintRGB
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        default:
            break
        }
        switch id {
        // Reborn's shortcut image colours.
        case "saved-categories": return .green
        case "picture-in-picture": return .purple
        case "translation": return .teal
        case "apollo-ai": return .indigo
        case "crash-reports": return .orange
        case "feature-requests": return .yellow
        case "bug-reports": return .red
        case "theme-manager": return .indigo
        case "settings-root": return .purple
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
        switch SettingsShortcutsStore.target(id) {
        case .category(let category):
            SettingsCategoryScreen(category: category, accountManager: accountManager)
        case .drillDown(let destination):
            SettingsDrillDownLeaf(destination: destination)
        case .root, nil:
            SettingsScreen(repository: accountManager.repository, accountManager: accountManager)
        }
    }
}
