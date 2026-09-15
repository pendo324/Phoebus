import Foundation

/// Reimplements Apollo's saved categories — lets users organize their
/// saved posts/comments into custom local categories/folders ("Add
/// Saved Category", "Categorize your saved items", "Saved
/// Categories"). This is a purely client-side feature — Reddit's API
/// has no concept of saved-item categories, so like Apollo's original,
/// this is stored locally and keyed by the saved item's fullname.
public struct SavedCategory: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

/// Persists the mapping from saved-item fullname to category name,
/// plus the set of category names that currently exist (so empty
/// categories can still be shown/renamed).
public enum SavedCategoryStore {
    private static let categoriesKey = "com.pendo324.Phoebus.savedCategories"
    private static let assignmentsKey = "com.pendo324.Phoebus.savedCategoryAssignments"

    public static let categoriesStorage = SettingsStore<[SavedCategory]>(key: categoriesKey) { [] }
    public static let assignmentsStorage = SettingsStore<[String: String]>(key: assignmentsKey) { [:] }

    public static func loadCategories() -> [SavedCategory] { categoriesStorage.load() }

    public static func saveCategories(_ categories: [SavedCategory]) { categoriesStorage.save(categories) }

    /// Adds a new category if a category with that name doesn't
    /// already exist (mirrors Apollo's "A saved category already
    /// exists with that name, please choose a unique name" guard).
    @discardableResult
    public static func addCategory(named name: String) -> Bool {
        var categories = loadCategories()
        guard !categories.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return false
        }
        categories.append(SavedCategory(name: name))
        saveCategories(categories)
        return true
    }

    /// Renames a category and re-points every item assigned to it,
    /// reimplementing Apollo's "Rename" action on the Saved
    /// Categories screen. Returns false (no-op) if the new name is empty,
    /// unchanged, or already used by a different category.
    @discardableResult
    public static func renameCategory(_ oldName: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return false }
        var categories = loadCategories()
        guard categories.contains(where: { $0.name == oldName }) else { return false }
        guard !categories.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return false
        }
        categories = categories.map { $0.name == oldName ? SavedCategory(name: trimmed) : $0 }
        saveCategories(categories)

        var assignments = loadAssignments()
        for (fullname, category) in assignments where category == oldName {
            assignments[fullname] = trimmed
        }
        saveAssignments(assignments)
        return true
    }

    /// Deletes a category, clearing the assignment on any items that
    /// used it (they fall back to uncategorized, matching Apollo's
    /// real behavior of simply removing the category key from the
    /// database rather than deleting the saved items themselves).
    public static func deleteCategory(_ name: String) {
        let categories = loadCategories().filter { $0.name != name }
        saveCategories(categories)

        var assignments = loadAssignments()
        for (fullname, category) in assignments where category == name {
            assignments.removeValue(forKey: fullname)
        }
        saveAssignments(assignments)
    }

    private static func loadAssignments() -> [String: String] { assignmentsStorage.load() }

    private static func saveAssignments(_ assignments: [String: String]) { assignmentsStorage.save(assignments) }

    public static func category(for fullname: String) -> String? {
        loadAssignments()[fullname]
    }

    public static func assign(fullname: String, category: String?) {
        var assignments = loadAssignments()
        assignments[fullname] = category
        saveAssignments(assignments)
    }

    public static func clearCategory(for fullname: String) {
        assign(fullname: fullname, category: nil)
    }

    /// Exposed for `BackupBundle` — the full fullname->category
    /// assignment map, otherwise kept private since ordinary callers
    /// should go through `category(for:)`/`assign(fullname:category:)`.
    public static func allAssignments() -> [String: String] {
        loadAssignments()
    }

    /// Exposed for `BackupBundle` restore.
    public static func replaceAllAssignments(_ assignments: [String: String]) {
        saveAssignments(assignments)
    }
}
