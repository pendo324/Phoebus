import SwiftUI
import PhoebusCore

/// Reborn "Customize Action Menus" (#1131, #1368; Interface → Menus): pick
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
                                 summary: ActionMenuLayoutStore.allMenusSummary())
                }
                .apolloSearchRow("All Menus")
            } footer: {
                Text("Show or hide actions across every menu at once.")
                    .apolloSectionFooter()
            }
            Section {
                ForEach(ActionMenuContext.menus) { context in
                    SettingsLink { ActionMenuEditorScreen(context: context) } label: {
                        menuRowLabel(context.hubTitle, symbol: "ellipsis", summary: ActionMenuLayoutStore.summary(context))
                    }
                    .apolloSettingsRowHeight()
                    .apolloSettingsRowInsets()
                }
            } header: {
                Text("Menus").apolloSectionHeader()
            } footer: {
                Text("Touching and holding a post or comment opens the same menu.")
                    .apolloSectionFooter()
            }
            Section {
                ForEach(ActionMenuContext.moderatorMenus) { context in
                    SettingsLink { ActionMenuEditorScreen(context: context) } label: {
                        menuRowLabel(context.hubTitle, symbol: "shield", summary: ActionMenuLayoutStore.summary(context))
                    }
                    .apolloSettingsRowHeight()
                    .apolloSettingsRowInsets()
                }
            } header: {
                Text("Moderator Menus").apolloSectionHeader()
            } footer: {
                Text("Shown in subreddits you moderate.")
                    .apolloSectionFooter()
            }
        }
        .id(revision)
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Customize Action Menus")
        .onReceive(NotificationCenter.default.publisher(for: .apolloActionMenuLayoutsChanged)) { _ in
            revision += 1
        }
    }

    /// The summary only shows on a menu that differs from the default.
    private func menuRowLabel(_ title: String, symbol: String, summary: String?) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol).frame(width: 29)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let summary {
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

/// One menu: a live preview of the resolved rows, then every item with
/// a checkmark for visible and a drag handle to reorder.
struct ActionMenuEditorScreen: View {
    let context: ActionMenuContext
    @State private var order: [String] = []
    @State private var hidden: Set<String> = []
    @State private var confirmingReset = false

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
                Text(context.detail + " Dimmed rows are shown only when relevant.")
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .foregroundStyle(hidden.contains(item.id) ? .secondary : .primary)
                                if let note = relevanceNote(item) {
                                    Text(note).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
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
                Text("Tap an action to show or hide it. Drag to reorder. Some actions are only available in certain contexts." + lockedNote)
                    .apolloSectionFooter()
            }
            Section {
                Button("Reset Menu…", role: .destructive) { confirmingReset = true }
                    .disabled(!ActionMenuLayoutStore.isCustomized(context))
                    .accessibilityIdentifier("actionMenus.resetMenu")
                    .apolloPlainSettingsRowInsets(rule: false)
            }
        }
        .confirmationDialog("Reset Menu", isPresented: $confirmingReset, titleVisibility: .visible) {
            ForEach(ActionMenuLayoutStore.resetChoices(context), id: \.title) { choice in
                Button(choice.title, role: .destructive) {
                    if choice.orderOnly { ActionMenuLayoutStore.resetOrder(context) } else { ActionMenuLayoutStore.reset(context) }
                    reload()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .environment(\.editMode, .constant(.active))
        .apolloSettingsListAppearance()
        .navigationTitle(context.title)
        .onAppear(perform: reload)
    }

    private var catalog: [ActionMenuItem] { ActionMenuCatalog.items(for: context) }

    private var lockedNote: String {
        lockedItems.map { " \($0.title) stays at the top and can’t be hidden." }.joined()
    }

    /// Why a row may be missing from the menu right now.
    private func relevanceNote(_ item: ActionMenuItem) -> String? {
        if item.usuallyShown { return nil }
        return item.id == "moderator" ? "Shown in subreddits you moderate" : "Shown when relevant"
    }
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
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {} footer: {
                Text("Show or hide actions across all menus, including moderator menus. Actions enabled here appear in every menu that supports them.")
                    .apolloSectionFooter()
            }
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
                                if let hiddenIn = ActionMenuLayoutStore.hiddenInSummary(itemID: item.id) {
                                    Text(hiddenIn).font(.footnote).foregroundStyle(.secondary)
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
            } footer: {
                Text("Tap an action to show or hide it across the menus that support it.")
                    .apolloSectionFooter()
            }
            Section {
                Button("Reset All Menus…", role: .destructive) { confirmingReset = true }
                    .disabled(!ActionMenuContext.allCases.contains(where: ActionMenuLayoutStore.isCustomized))
                    .accessibilityIdentifier("actionMenus.resetAllMenus")
                    .apolloPlainSettingsRowInsets(rule: false)
            }
        }
        .confirmationDialog("Reset All Menus", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset All Menus", role: .destructive) { ActionMenuLayoutStore.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the default order and visibility in every menu.")
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
