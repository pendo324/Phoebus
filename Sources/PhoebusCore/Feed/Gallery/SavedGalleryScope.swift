import Foundation

/// Reborn "Gallery View for Saved" (`Apollo-Reborn#1440`): which saved
/// posts a Saved gallery shows and when its paging is finished.
///
/// A category is a local fullname list (see `SavedCategoryStore`), not a
/// Reddit filter, so a category gallery walks the ordinary Saved listing and
/// keeps the posts assigned to it. Saved comments never make tiles.
public struct SavedGalleryScope: Sendable, Equatable {
    public let category: String?
    /// The category's post fullnames; empty for All Saved.
    private let members: Set<String>
    /// Members already met in a loaded page, media or not.
    private var inspected: Set<String> = []

    /// `assignments` is the fullname-to-category map.
    public init(category: String?, assignments: [String: String]) {
        self.category = category
        if let category {
            members = Set(assignments.filter { $0.value == category && $0.key.hasPrefix("t3_") }.keys)
        } else {
            members = []
        }
    }

    /// A category nobody is assigned to (or holding only comments) is empty
    /// without asking Reddit for anything.
    public var isEmptyByConstruction: Bool { category != nil && members.isEmpty }

    /// Every member has been met, so the rest of Saved cannot add a tile.
    /// A member that is no longer saved never shows up, so a category holding
    /// one still walks to the end of Saved, which only costs extra pages.
    public var isComplete: Bool { category != nil && !members.isEmpty && members.isSubset(of: inspected) }

    /// The posts of a loaded page this gallery may show, in order.
    public mutating func admit(_ posts: [RedditPost]) -> [RedditPost] {
        guard category != nil else { return posts }
        var kept: [RedditPost] = []
        for post in posts where members.contains(post.name) {
            inspected.insert(post.name)
            kept.append(post)
        }
        return kept
    }

    /// What to do after a page was admitted: `gained` is the number of
    /// tiles-worth of media posts it added, `after` the cursor it returned and
    /// `previousAfter` the one it was asked with.
    public func outcome(gained: Int, after: String?, previousAfter: String?) -> PageOutcome {
        let cursor = (after?.isEmpty == false) ? after : nil
        let advanced = cursor != nil && cursor != previousAfter
        let exhausted = !advanced || isComplete
        // An empty grid has no tile whose appearance would load the next
        // page, so Saved keeps walking until it finds media or the end.
        return PageOutcome(exhausted: exhausted, walkOn: gained == 0 && !exhausted)
    }

    public struct PageOutcome: Sendable, Equatable {
        public let exhausted: Bool
        public let walkOn: Bool

        public init(exhausted: Bool, walkOn: Bool) {
            self.exhausted = exhausted
            self.walkOn = walkOn
        }
    }

    /// Reddit lists Saved 100 at a time here, its largest page.
    public static let pageSize = 100

    /// Gallery's own wording: "Saved" or "Saved — <category>".
    public var sourceDescription: String {
        category.map { "Saved — \($0)" } ?? "Saved"
    }
}
