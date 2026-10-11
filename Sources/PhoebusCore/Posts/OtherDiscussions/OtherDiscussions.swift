import Foundation

/// Other Discussions: the other posts of the same link, from Reddit's
/// `/duplicates/<id>`. A Phoebus addition; neither Apollo nor Reborn has it.
public enum OtherDiscussions {
    /// Reddit matches duplicates by URL, so a text post has none of its
    /// own; a crosspost of one still lists the original's other crossposts.
    public static func isAvailable(for post: RedditPost) -> Bool {
        !post.isSelf || post.isCrosspost
    }

    /// The row under the post header: only when the setting is on and
    /// Reddit reports at least one other discussion.
    public static func showsCountRow(count: Int?, post: RedditPost, settings: OtherDiscussionsSettings) -> Bool {
        settings.showCountRow && isAvailable(for: post) && (count ?? 0) > 0
    }

    public static func countLabel(_ count: Int) -> String {
        count.apolloCounted("Other Discussion", "Other Discussions")
    }

    /// The other posts in a `/duplicates/<id>` response
    /// (`[postListing, duplicatesListing]`): the second listing, minus the
    /// post itself and any repeat. Nil when the shape is wrong.
    public static func page(from data: Data, excluding postID: String) throws -> OtherDiscussionsPage? {
        let listings = try JSONDecoder.reddit.decode([RedditListing].self, from: data)
        guard listings.count > 1 else { return nil }
        let duplicates = listings[1]
        var seen: Set<String> = [postID]
        let posts = duplicates.posts().filter { seen.insert($0.id).inserted }
        return OtherDiscussionsPage(posts: posts, after: duplicates.data.after)
    }

    /// Appends a next page, skipping posts already shown (Reddit can repeat
    /// one across a page boundary).
    public static func appending(_ page: [RedditPost], to existing: [RedditPost]) -> [RedditPost] {
        var seen = Set(existing.map(\.id))
        return existing + page.filter { seen.insert($0.id).inserted }
    }
}

public struct OtherDiscussionsPage: Sendable {
    public let posts: [RedditPost]
    public let after: String?
}

/// "Other Discussions" row under a link post's header. Apollo has no such
/// setting, so the key is Phoebus's own.
public struct OtherDiscussionsSettings: Codable, Sendable, Equatable {
    public var showCountRow: Bool

    public static let `default` = OtherDiscussionsSettings(showCountRow: true)

    public init(showCountRow: Bool) {
        self.showCountRow = showCountRow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showCountRow = (try? container.decodeIfPresent(Bool.self, forKey: .showCountRow)) ?? true
    }
}

public enum OtherDiscussionsSettingsStore {
    public static let key = "com.pendo324.Phoebus.otherDiscussionsSettings"

    public static let storage = SettingsStore<OtherDiscussionsSettings>(key: key) { OtherDiscussionsSettings.default }

    public static func load() -> OtherDiscussionsSettings { storage.load() }

    public static func save(_ settings: OtherDiscussionsSettings) { storage.save(settings) }
}

extension OtherDiscussionsSettings: StoredSettingsModel {
    public static var store: SettingsStore<OtherDiscussionsSettings> { OtherDiscussionsSettingsStore.storage }
}
