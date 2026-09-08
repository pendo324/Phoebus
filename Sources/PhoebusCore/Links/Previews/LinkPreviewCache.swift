import Foundation

/// Reborn's link preview cache: an in-memory (per-session) cache of fetched
/// previews keyed by URL, so scrolling back past an already-rendered card
/// doesn't fetch the page again. A link with nothing to show is remembered
/// too, and two cards for the same link share one fetch. Also backs the
/// "Clear Link Preview Cache" settings row.
public actor LinkPreviewCache {
    public static let shared = LinkPreviewCache()

    private enum Entry {
        case found(LinkPreview)
        case empty
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<LinkPreview?, Never>] = [:]

    private init() {}

    /// The cached preview, or `nil` when the link was never fetched or
    /// had nothing to show; `isKnown` tells the two apart.
    public func cached(for url: URL) -> (preview: LinkPreview?, isKnown: Bool) {
        switch entries[url.absoluteString] {
        case .found(let preview): return (preview, true)
        case .empty: return (nil, true)
        case nil: return (nil, false)
        }
    }

    public func preview(for url: URL, fetch: @escaping @Sendable () async -> LinkPreview?) async -> LinkPreview? {
        let key = url.absoluteString
        switch entries[key] {
        case .found(let preview): return preview
        case .empty: return nil
        case nil: break
        }
        if let task = inFlight[key] { return await task.value }
        let task = Task { await fetch() }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        entries[key] = result.map(Entry.found) ?? .empty
        return result
    }

    public func clear() {
        entries.removeAll()
    }

    public var count: Int {
        entries.count
    }
}
