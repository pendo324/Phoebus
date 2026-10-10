import Foundation

/// "Remember Thread Position": reopening a thread lands on the comment the
/// reader had reached. Phoebus-only; neither Apollo nor Reborn has it.
public struct ThreadPositionSettings: Codable, Sendable, Equatable {
    public var rememberThreadPosition: Bool
    /// How many threads keep a position before the least recent is dropped.
    public var capacity: Int

    public static let `default` = ThreadPositionSettings(rememberThreadPosition: false, capacity: 20)
    public static let capacityOptions = [5, 10, 20, 50, 100]

    public init(rememberThreadPosition: Bool, capacity: Int) {
        self.rememberThreadPosition = rememberThreadPosition
        self.capacity = capacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        rememberThreadPosition = try container.decode(.rememberThreadPosition, default: d, \.rememberThreadPosition)
        capacity = max(1, try container.decode(.capacity, default: d, \.capacity))
    }
}

public enum ThreadPositionSettingsStore {
    public static let storage = SettingsStore<ThreadPositionSettings>(
        key: "com.pendo324.Phoebus.threadPositionSettings") { .default }

    public static func load() -> ThreadPositionSettings { storage.load() }
}

extension ThreadPositionSettings: StoredSettingsModel {
    public static var store: SettingsStore<ThreadPositionSettings> { ThreadPositionSettingsStore.storage }
}

/// The topmost comment on screen when the reader left a thread, with the
/// comments above it (top-level first) to fall back on when it isn't
/// loaded next time.
public struct ThreadPosition: RememberedPosition {
    public var postID: String
    public var commentID: String
    public var ancestorIDs: [String]

    public var key: String { postID }

    public init(postID: String, commentID: String, ancestorIDs: [String]) {
        self.postID = postID
        self.commentID = commentID
        self.ancestorIDs = ancestorIDs
    }
}

/// Saved thread positions, persisted as one JSON blob.
public enum ThreadPositionStore {
    static let key = "com.pendo324.Phoebus.threadPositions"

    public static func load(from defaults: UserDefaults = .standard) -> RememberedPositions<ThreadPosition> {
        guard let data = defaults.data(forKey: key),
              let positions = try? JSONDecoder().decode(RememberedPositions<ThreadPosition>.self, from: data) else {
            return RememberedPositions()
        }
        return positions
    }

    /// The saved position for a thread, when the setting is on.
    public static func position(postID: String, defaults: UserDefaults = .standard) -> ThreadPosition? {
        guard ThreadPositionSettingsStore.storage.load(from: defaults).rememberThreadPosition else { return nil }
        return load(from: defaults).entry(for: postID)
    }

    /// Saves `position` for `postID`, or forgets the thread's position when
    /// it is nil (the reader went back to the top). No-op while the setting
    /// is off.
    public static func record(_ position: ThreadPosition?, postID: String, defaults: UserDefaults = .standard) {
        let settings = ThreadPositionSettingsStore.storage.load(from: defaults)
        guard settings.rememberThreadPosition else { return }
        let current = load(from: defaults)
        let updated = position.map { current.recording($0, capacity: settings.capacity) }
            ?? current.removing(key: postID)
        guard updated != current, let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: key)
    }
}

public enum ThreadPositionPolicy {
    /// Live sort follows the newest comments and a linked comment is the
    /// point of opening it, so neither restores a saved position.
    public static func shouldRestore(enabled: Bool, focusedCommentID: String?, sort: String) -> Bool {
        enabled && focusedCommentID == nil && sort != "live"
    }

    /// What to save on leaving: the topmost comment on screen, or nil to
    /// forget the thread when the reader is back at its top.
    public static func position(postID: String, roots: [CommentTreeNode],
                                onScreen: Set<String>, atTop: Bool) -> ThreadPosition? {
        guard !atTop else { return nil }
        let order = roots.flatMap { $0.visibleFlattened() }.map(\.id)
        guard let top = TopVisibleRowPolicy.topmost(order: order, onScreen: onScreen),
              let path = ancestorPath(to: top, in: roots) else { return nil }
        return ThreadPosition(postID: postID, commentID: top, ancestorIDs: path)
    }

    /// The ids above `id`, top-level first; nil when `id` isn't loaded.
    public static func ancestorPath(to id: String, in roots: [CommentTreeNode]) -> [String]? {
        for root in roots {
            if root.id == id { return [] }
            if let below = ancestorPath(to: id, in: root.children) { return [root.id] + below }
        }
        return nil
    }

    /// The comment to scroll to on reopening: the saved one if it is on
    /// screen, else its nearest ancestor that is (one hidden under "more
    /// replies" or a collapsed parent lands on that parent). Collapsed
    /// threads stay collapsed.
    public static func restoreTarget(for position: ThreadPosition, roots: [CommentTreeNode]) -> String? {
        let visible = Set(roots.flatMap { $0.visibleFlattened() }.map(\.id))
        return ([position.commentID] + position.ancestorIDs.reversed()).first(where: visible.contains)
    }
}
