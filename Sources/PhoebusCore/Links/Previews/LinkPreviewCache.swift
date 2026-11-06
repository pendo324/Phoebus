import Foundation

/// Reborn's link preview cache: an in-memory (per-session) cache of fetched
/// previews keyed by URL, so scrolling back past an already-rendered card
/// doesn't fetch the page again. A link with nothing to show is remembered
/// too, and two cards for the same link share one fetch. Also backs the
/// "Clear Link Preview Cache" settings row.
public actor LinkPreviewCache {
    public static let shared = LinkPreviewCache()

    fileprivate enum Entry {
        case found(LinkPreview)
        case empty
    }

    /// The entries, behind a lock so a card can read one in the same pass
    /// that builds it (`cachedNow`) instead of waiting on the actor.
    private let memory = Memory()
    private var inFlight: [String: Task<LinkPreview?, Never>] = [:]

    private init() {}

    /// The cached preview, or `nil` when the link was never fetched or
    /// had nothing to show; `isKnown` tells the two apart.
    public func cached(for url: URL) -> (preview: LinkPreview?, isKnown: Bool) {
        cachedNow(for: url)
    }

    /// `cached(for:)` without the actor hop. A card built again (a comment
    /// row that was collapsed and expanded) starts from this, so it draws
    /// the card it showed instead of a placeholder of another height.
    public nonisolated func cachedNow(for url: URL) -> (preview: LinkPreview?, isKnown: Bool) {
        switch memory[url.absoluteString] {
        case .found(let preview): return (preview, true)
        case .empty: return (nil, true)
        case nil: return (nil, false)
        }
    }

    /// `rememberMiss` is asked once a fetch found nothing: false leaves the link
    /// unknown, so a later card asks again (a lookup that stood down for Reddit's
    /// rate limit hold says nothing about the link).
    public func preview(for url: URL, rememberMiss: @escaping @Sendable () -> Bool = { true },
                        fetch: @escaping @Sendable () async -> LinkPreview?) async -> LinkPreview? {
        let key = url.absoluteString
        switch memory[key] {
        case .found(let preview): return preview
        case .empty: return nil
        case nil: break
        }
        if let task = inFlight[key] { return await task.value }
        let task = Task { await fetch() }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        memory[key] = result.map(Entry.found) ?? (rememberMiss() ? .empty : nil)
        return result
    }

    public func clear() {
        memory.removeAll()
    }

    public var count: Int {
        memory.count
    }

    private final class Memory: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        subscript(key: String) -> Entry? {
            get { lock.lock(); defer { lock.unlock() }; return entries[key] }
            set { lock.lock(); defer { lock.unlock() }; entries[key] = newValue }
        }

        func removeAll() { lock.lock(); defer { lock.unlock() }; entries.removeAll() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    }
}
