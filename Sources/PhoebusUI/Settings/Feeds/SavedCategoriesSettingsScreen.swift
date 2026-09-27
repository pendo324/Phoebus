import SwiftUI
import PhoebusCore

/// Reborn's Saved Categories screen: add, rename and delete categories.
/// `SavedCategoryMenuModifier` in `UserProfileScreen` remains the quick "New
/// Category…" entry point during item assignment.
public struct SavedCategoriesSettingsScreen: View {
    @State private var categories: [SavedCategory] = SavedCategoryStore.loadCategories()
    @State private var showingAdd = false
    @State private var newCategoryName = ""
    @State private var addErrorMessage: String?
    @State private var renamingCategory: SavedCategory?
    @State private var renameText = ""
    @State private var renameErrorMessage: String?
    @State private var actionsFor: SavedCategory?
    @State private var deleting: SavedCategory?

    public init() {}

    @ViewBuilder
    private func row(for category: SavedCategory) -> some View {
        // Reborn: a tap offers Rename / Delete.
        Button { actionsFor = category } label: {
            Text(category.name).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
            .apolloPlainSettingsRowInsets()
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleting = category
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    beginRename(category)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button("Rename") { beginRename(category) }
                Button("Delete", role: .destructive) { deleting = category }
            }
    }

    private func delete(_ category: SavedCategory) {
        SavedCategoryStore.deleteCategory(category.name)
        categories = SavedCategoryStore.loadCategories()
    }

    private func beginRename(_ category: SavedCategory) {
        renamingCategory = category
        renameText = category.name
    }

    public var body: some View {
        List {
            Section {
                if categories.isEmpty {
                    Text("No saved categories")
                        .foregroundStyle(.secondary)
                } else {
                    // Extracted into its own builder: with both a `swipeActions` and a `contextMenu`
                    // block inline, the Swift 6.4 compiler fails with "unable to type-check this
                    // expression in reasonable time".
                    ForEach(categories) { category in
                        // `row(for:)` carries
                        // `.apolloPlainSettingsRowInsets()`.
                        row(for: category)
                    }
                }
            }
        }
        .apolloSettingsListAppearance()
        // Categories also change from the Saved tab.
        .onAppear { categories = SavedCategoryStore.loadCategories() }
        .apolloActionSheet(isPresented: $actionsFor.isPresent(), title: actionsFor?.name, rows: actionsFor.map { category in [
            ApolloActionSheetRow("Rename") { beginRename(category) },
            ApolloActionSheetRow("Delete", isDestructive: true) { deleting = category },
        ] } ?? [])
        .alert("Delete Category", isPresented: $deleting.isPresent(), presenting: deleting) { category in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete(category) }
        } message: { category in
            Text("Are you sure you want to delete \"\(category.name)\"? Items saved to this category will not be deleted.")
        }
        .navigationTitle("Saved Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newCategoryName = ""
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                    .accessibilityLabel("Add Category")
                }
            }
        }
        .alert("New Saved Category", isPresented: $showingAdd) {
            TextField("Category Name", text: $newCategoryName)
            Button("Add") { addCategory() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Name Already Used", isPresented: .constant(addErrorMessage != nil), presenting: addErrorMessage) { _ in
            Button("OK") { addErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("Rename Category", isPresented: .constant(renamingCategory != nil), presenting: renamingCategory) { category in
            TextField("Category Name", text: $renameText)
            Button("Rename") { renameCategory(category) }
            Button("Cancel", role: .cancel) { renamingCategory = nil }
        }
        .alert("Name Already Used", isPresented: .constant(renameErrorMessage != nil), presenting: renameErrorMessage) { _ in
            Button("OK") { renameErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    /// Reborn's case-insensitive duplicate guard; no length rule.
    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if SavedCategoryStore.addCategory(named: trimmed) {
            categories = SavedCategoryStore.loadCategories()
        } else {
            addErrorMessage = "A saved category already exists with that name, please choose a unique name."
        }
    }

    private func renameCategory(_ category: SavedCategory) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        defer { renamingCategory = nil }
        guard trimmed != category.name else { return }
        if SavedCategoryStore.renameCategory(category.name, to: trimmed) {
            categories = SavedCategoryStore.loadCategories()
        } else if !trimmed.isEmpty {
            renameErrorMessage = "A saved category already exists with that name, please choose a unique name."
        }
    }
}
