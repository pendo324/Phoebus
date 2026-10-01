import SwiftUI
import PhoebusCore

/// Reborn "Action Menus" (#1131, Interface → Menus → Action Menus): pick
/// a menu, then show/hide and reorder its items. Layouts live in
/// `ActionMenuLayoutStore` and are applied by each menu's builder.
public struct ActionMenusSettingsScreen: View {
    @State private var revision = 0

    public init() {}

    public var body: some View {
        List {
            Section {
                SettingsLink { ActionMenuAllMenusScreen() } label: {
                    menuRowLabel("All Menus", symbol: "list.bullet",
                                 summary: allSummary)
                }
                .apolloSearchRow("All Menus")
            } footer: {
                Text("Show or hide actions across every menu at once.")
                    .apolloSectionFooter()
            }
            Section {
                ForEach(ActionMenuContext.menus) { context in
                    SettingsLink { ActionMenuEditorScreen(context: context) } label: {
                        menuRowLabel(context.title, symbol: "ellipsis", summary: ActionMenuLayoutStore.summary(context))
                    }
                    .apolloSettingsRowHeight()
                    .apolloSettingsRowInsets()
                }
            } header: {
                Text("••• Menus").apolloSectionHeader()
            } footer: {
                Text("The ••• button’s menu in each place. Touching and holding a post or comment opens the same menu. Open one to reorder its actions or hide some, and to preview it.")
                    .apolloSectionFooter()
            }
            Section {
                ForEach(ActionMenuContext.moderatorMenus) { context in
                    SettingsLink { ActionMenuEditorScreen(context: context) } label: {
                        menuRowLabel(context.title, symbol: "shield", summary: ActionMenuLayoutStore.summary(context))
                    }
                    .apolloSettingsRowHeight()
                    .apolloSettingsRowInsets()
                }
            } header: {
                Text("Moderator Menus").apolloSectionHeader()
            } footer: {
                Text("The moderator shield’s menus. They only appear in subreddits you moderate.")
                    .apolloSectionFooter()
            }
        }
        .id(revision)
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Action Menus")
        .onReceive(NotificationCenter.default.publisher(for: .apolloActionMenuLayoutsChanged)) { _ in
            revision += 1
        }
    }

    private var allSummary: String {
        let count = ActionMenuContext.allCases.filter(ActionMenuLayoutStore.isCustomized).count
        return count == 0 ? "Default" : "\(count) customized"
    }

    private func menuRowLabel(_ title: String, symbol: String, summary: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol).frame(width: 29)
            Text(title)
            Spacer()
            Text(summary).foregroundStyle(.secondary)
        }
    }
}

/// One menu: a live preview of the resolved rows, then every item with
/// a checkmark for visible and a drag handle to reorder.
struct ActionMenuEditorScreen: View {
    let context: ActionMenuContext
    @State private var order: [String] = []
    @State private var hidden: Set<String> = []

    var body: some View {
        List {
            Section {
                ForEach(previewItems) { item in
                    HStack(spacing: 15) {
                        Image(systemName: item.symbol).frame(width: 29)
                        Text(item.title)
                    }
                    .foregroundStyle(item.usuallyShown ? .primary : .secondary)
                    .apolloSettingsRowHeight()
                    .apolloSettingsRowInsets()
                }
            } header: {
                Text("Preview").apolloSectionHeader()
            } footer: {
                Text(context.detail + " Dimmed rows appear only for your own content or when a feature is enabled.")
                    .apolloSectionFooter()
            }
            Section {
                ForEach(lockedItems) { item in
                    HStack(spacing: 15) {
                        Image(systemName: item.symbol).frame(width: 29)
                        Text(item.title)
                        Spacer()
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    }
                    .apolloSettingsRowHeight()
                    .apolloSettingsRowInsets()
                }
                ForEach(movableItems) { item in
                    Button {
                        toggle(item)
                    } label: {
                        HStack(spacing: 15) {
                            Image(systemName: item.symbol).frame(width: 29)
                            Text(item.title)
                                .foregroundStyle(hidden.contains(item.id) ? .secondary : .primary)
                            Spacer()
                            if !hidden.contains(item.id) {
                                Image(systemName: "checkmark").foregroundStyle(Color.apolloAccent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .apolloSettingsRowHeight()
                    .apolloSettingsRowInsets()
                    .accessibilityHint(hidden.contains(item.id) ? "Double tap to show it in this menu." : "Double tap to hide it from this menu.")
                }
                .onMove(perform: move)
            } header: {
                Text("Items").apolloSectionHeader()
            } footer: {
                Text("Only actions supported by this menu are listed. Some appear only for your own content or when a feature is enabled; the preview at the top dims those. Tap an action to show or hide it; touch and hold to reorder. Hiding keeps Phoebus’s order.")
                    .apolloSectionFooter()
            }
            Section {
                Button("Reset This Menu", role: .destructive) {
                    ActionMenuLayoutStore.reset(context)
                    reload()
                }
                .disabled(!ActionMenuLayoutStore.isCustomized(context))
                .apolloPlainSettingsRowInsets(rule: false)
            }
        }
        .environment(\.editMode, .constant(.active))
        .apolloSettingsListAppearance()
        .navigationTitle(context.title)
        .onAppear(perform: reload)
    }

    private var catalog: [ActionMenuItem] { ActionMenuCatalog.items(for: context) }
    private var lockedItems: [ActionMenuItem] { catalog.filter(\.locked) }
    private var movableItems: [ActionMenuItem] {
        order.compactMap { id in catalog.first { $0.id == id && !$0.locked } }
    }
    private var previewItems: [ActionMenuItem] {
        order.compactMap { id in catalog.first { $0.id == id } }.filter { !hidden.contains($0.id) }
    }

    private func reload() {
        order = ActionMenuLayoutStore.resolvedOrder(context)
        hidden = ActionMenuLayoutStore.hiddenIDs(context)
    }

    private func toggle(_ item: ActionMenuItem) {
        let nowHidden = !hidden.contains(item.id)
        ActionMenuLayoutStore.setHidden(nowHidden, itemID: item.id, for: context)
        reload()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var movable = movableItems.map(\.id)
        movable.move(fromOffsets: source, toOffset: destination)
        ActionMenuLayoutStore.setOrder(lockedItems.map(\.id) + movable, for: context)
        reload()
    }
}

/// Visibility across every menu at once.
struct ActionMenuAllMenusScreen: View {
    @State private var revision = 0

    var body: some View {
        List {
            Section {
                ForEach(allItems, id: \.id) { item in
                    let state = visibility(item.id)
                    Button {
                        setHidden(state != .hidden, itemID: item.id)
                    } label: {
                        HStack(spacing: 15) {
                            Image(systemName: item.symbol).frame(width: 29)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(state == .hidden ? .secondary : .primary)
                                if state == .mixed {
                                    Text("Shown in Some Menus").font(.footnote).foregroundStyle(.secondary)
                                } else if state == .hidden {
                                    Text("Hidden in All Supported Menus").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if state == .shown {
                                Image(systemName: "checkmark").foregroundStyle(Color.apolloAccent)
                            } else if state == .mixed {
                                Image(systemName: "minus").foregroundStyle(Color.apolloAccent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .apolloSettingsRowHeight()
                    .apolloSettingsRowInsets()
                }
            } header: {
                Text("Items").apolloSectionHeader()
            } footer: {
                Text("Tap an action to show or hide it across the menus that support it. Shown in Some Menus means your per-menu choices differ. Select a menu to adjust its choices and order.")
                    .apolloSectionFooter()
            }
            Section {
                Button("Reset All Menus", role: .destructive) { ActionMenuLayoutStore.resetAll() }
                    .disabled(!ActionMenuContext.allCases.contains(where: ActionMenuLayoutStore.isCustomized))
                    .apolloPlainSettingsRowInsets(rule: false)
            } footer: {
                Text("Visibility across every menu, the moderator menus included. Open a menu from the previous screen to reorder its actions or preview it.")
                    .apolloSectionFooter()
            }
        }
        .id(revision)
        .apolloSettingsListAppearance()
        .navigationTitle("All Menus")
        .onReceive(NotificationCenter.default.publisher(for: .apolloActionMenuLayoutsChanged)) { _ in
            revision += 1
        }
    }

    private enum Visibility { case shown, hidden, mixed }

    /// Every unlocked item any menu offers, first appearance order.
    private var allItems: [ActionMenuItem] {
        var seen = Set<String>()
        var result: [ActionMenuItem] = []
        for context in ActionMenuContext.allCases {
            for item in ActionMenuCatalog.items(for: context) where !item.locked && seen.insert(item.id).inserted {
                result.append(item)
            }
        }
        return result
    }

    private func contexts(for id: String) -> [ActionMenuContext] {
        ActionMenuContext.allCases.filter { ActionMenuCatalog.item(id, in: $0) != nil }
    }

    private func visibility(_ id: String) -> Visibility {
        let states = contexts(for: id).map { ActionMenuLayoutStore.hiddenIDs($0).contains(id) }
        if states.allSatisfy({ $0 }) { return .hidden }
        if states.contains(true) { return .mixed }
        return .shown
    }

    private func setHidden(_ hidden: Bool, itemID: String) {
        for context in contexts(for: itemID) {
            ActionMenuLayoutStore.setHidden(hidden, itemID: itemID, for: context)
        }
    }
}
