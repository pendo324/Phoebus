import Foundation

/// Reborn "Siri & Spotlight" (#1299): what the index may hold.
public enum SiriContentLimits {
    public static let posts = 1000
    public static let communities = 500
    public static let retention: TimeInterval = 30 * 24 * 60 * 60
    /// Listing pages carry at most this many rows into the catalogue.
    public static let rowsPerPayload = 500
    public static let payloadBytes = 2 * 1024 * 1024
    public static let catalogBytes = 8 * 1024 * 1024
    /// Tombstones kept against stale in-flight listings.
    public static let tombstones = 2000
}

/// Persistent, account-scoped catalogue of the eligible records. Access it
/// from one actor (or a single-threaded test). Atomic snapshots are
/// deliberately simple at this bounded size.
public final class SiriContentCatalog {
    public struct State: Codable {
        public var version = 1
        public var enabled = false
        /// One-way account fingerprint; never credentials.
        public var account: String?
        public var records: [String: SiriContentRecord] = [:]
        /// Tombstones stop older in-flight listings from resurrecting a hide.
        public var suppressed: [String: Date]? = nil
        public var suppressedAliases: [String: String]? = nil
    }
    public enum Failure: Error { case unsupportedVersion, oversizedFile, invalidPayload }
    public private(set) var state: State
    private let file: URL
    public let postLimit: Int
    public let subredditLimit: Int
    public let retention: TimeInterval

    public init(file: URL, postLimit: Int = SiriContentLimits.posts, subredditLimit: Int = SiriContentLimits.communities,
                retention: TimeInterval = SiriContentLimits.retention) throws {
        self.file = file
        self.postLimit = max(0, postLimit)
        self.subredditLimit = max(0, subredditLimit)
        self.retention = retention
        if FileManager.default.fileExists(atPath: file.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= SiriContentLimits.catalogBytes else {
                throw Failure.oversizedFile
            }
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
            guard state.version == 1 else { throw Failure.unsupportedVersion }
        } else {
            state = State()
        }
    }

    /// Clears the previous account before any new records can be resolved.
    @discardableResult
    public func configure(enabled: Bool, account: String?) throws -> Bool {
        let changedScope = state.account != account || state.enabled != enabled
        guard changedScope else { return false }
        var next = state
        next.enabled = enabled
        next.account = account
        next.records.removeAll()
        next.suppressed = nil
        next.suppressedAliases = nil
        try commit(next)
        return true
    }

    public func ingest(_ data: Data, account: String, now: Date = Date()) throws {
        guard state.enabled, state.account == account else { return }
        guard data.count <= SiriContentLimits.payloadBytes,
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.count <= SiriContentLimits.rowsPerPayload else { throw Failure.invalidPayload }
        var next = state
        for row in rows {
            guard let id = SiriContentRecord.identifier(row) else { continue }
            guard next.suppressed?[id] == nil else { continue }
            // Also delete a previously eligible record that becomes hidden,
            // NSFW, private, removed, or an unsubscribed community.
            next.records[id] = SiriContentRecord.parse(row, now: now)
        }
        prune(&next, now: now)
        try commit(next)
    }

    public func expire(now: Date = Date()) throws {
        var next = state
        prune(&next, now: now)
        if next.records != state.records || next.suppressed != state.suppressed { try commit(next) }
    }

    public func suppress(_ identifiers: [String], account: String, now: Date = Date()) throws {
        guard state.enabled, state.account == account else { return }
        var next = state
        var suppressed = next.suppressed ?? [:]
        for id in identifiers.prefix(SiriContentLimits.tombstones) {
            guard id.hasPrefix("reddit:post:t3_") || id.hasPrefix("reddit:subreddit:") else { continue }
            guard id.utf8.count <= 100 else { continue }
            suppressed[id] = now
            if let record = next.records[id], record.kind == .subreddit, let fullName = record.fullName {
                if next.suppressedAliases == nil { next.suppressedAliases = [:] }
                next.suppressedAliases?[fullName.lowercased()] = id
            }
            next.records.removeValue(forKey: id)
        }
        next.suppressed = suppressed
        prune(&next, now: now)
        try commit(next)
    }

    public func allow(_ identifiers: [String], account: String) throws {
        guard state.enabled, state.account == account else { return }
        var next = state
        for id in identifiers.prefix(SiriContentLimits.tombstones) { next.suppressed?.removeValue(forKey: id) }
        next.suppressedAliases = next.suppressedAliases?.filter { next.suppressed?[$0.value] != nil }
        // Never resurrect cached text here. A fresh eligible listing is required.
        try commit(next)
    }

    public func isSuppressed(_ id: String) -> Bool { state.suppressed?[id] != nil }

    /// Catalogue ids for Reddit names: `t3_` posts, `r/<name>` communities,
    /// and `t5_` community fullnames (resolved through what is held or
    /// recently suppressed).
    public func canonicalIdentifiers(_ nativeIdentifiers: [String]) -> [String] {
        nativeIdentifiers.prefix(SiriContentLimits.tombstones).compactMap { raw in
            let name = raw.lowercased()
            if name.hasPrefix("t3_") {
                return SiriContentRecord.identifier(["kind": "t3", "name": name])
            }
            if name.hasPrefix("r/") {
                return SiriContentRecord.identifier(["kind": "t5", "display_name": String(name.dropFirst(2))])
            }
            if name.hasPrefix("t5_") {
                return state.records.values.first { $0.kind == .subreddit && $0.fullName?.lowercased() == name }?.id
                    ?? state.suppressedAliases?[name]
            }
            return nil
        }
    }

    public func records(kind: SiriContentRecord.Kind? = nil, query: String = "", limit: Int = 100,
                        now: Date = Date()) -> [SiriContentRecord] {
        guard state.enabled, state.account != nil, limit > 0 else { return [] }
        let terms = Self.folded(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let eligible = state.records.values.filter {
            now.timeIntervalSince($0.observedAt) < retention && (kind == nil || $0.kind == kind)
        }
        var matches: [SiriContentRecord] = []
        if kind == .subreddit, !terms.isEmpty {
            // Siri may transcribe a joined community name as separate words or
            // insert a hyphen ("boutique blu-ray"). Match the whole name before
            // searching descriptions; don't let a description match displace an
            // exact destination. Keep underscores meaningful and return every
            // match rather than arbitrarily selecting an ambiguous destination.
            let name = Self.spokenSubredditName(query)
            if !name.isEmpty {
                matches = eligible.filter {
                    Self.spokenSubredditName($0.subreddit) == name
                        || $0.displayTitle.map(Self.spokenSubredditName) == name
                }
            }
        }
        if matches.isEmpty {
            matches = eligible.filter { record in
                let haystack = Self.folded("\(record.title) \(record.displayTitle ?? "") \(record.subreddit) \(record.author) \(record.text)")
                return terms.allSatisfy { haystack.contains($0) }
            }
        }
        return matches.sorted {
            $0.observedAt == $1.observedAt ? $0.id < $1.id : $0.observedAt > $1.observedAt
        }.prefix(limit).map { $0 }
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func spokenSubredditName(_ value: String) -> String {
        var name = folded(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("/r/") { name.removeFirst(3) }
        else if name.hasPrefix("r/") { name.removeFirst(2) }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-‐‑‒–—"))
        return String(name.unicodeScalars.filter { !separators.contains($0) })
    }

    public func resolve(_ identifiers: [String], now: Date = Date()) -> [SiriContentRecord] {
        guard state.enabled, state.account != nil else { return [] }
        return identifiers.compactMap { state.records[$0] }.filter { now.timeIntervalSince($0.observedAt) < retention }
    }

    private func prune(_ next: inout State, now: Date) {
        let recent = (next.suppressed ?? [:]).filter { now.timeIntervalSince($0.value) < retention }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        next.suppressed = Dictionary(uniqueKeysWithValues: recent.prefix(SiriContentLimits.tombstones).map { ($0.key, $0.value) })
        next.suppressedAliases = next.suppressedAliases?.filter { next.suppressed?[$0.value] != nil }
        next.records = next.records.filter { now.timeIntervalSince($0.value.observedAt) < retention }
        for (kind, limit) in [(SiriContentRecord.Kind.post, postLimit), (.subreddit, subredditLimit)] {
            let sorted = next.records.values.filter { $0.kind == kind }.sorted {
                $0.observedAt == $1.observedAt ? $0.id < $1.id : $0.observedAt > $1.observedAt
            }
            for record in sorted.dropFirst(limit) { next.records.removeValue(forKey: record.id) }
        }
    }

    private func commit(_ next: State) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        let data = try JSONEncoder().encode(next)
        guard data.count <= SiriContentLimits.catalogBytes else { throw Failure.oversizedFile }
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        state = next // Don't acknowledge a write which didn't reach disk.
    }
}
