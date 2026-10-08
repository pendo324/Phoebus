import AppIntents
import CoreSpotlight
import Foundation
import PhoebusCore
import PhoebusUI
import UIKit

// Reborn "Siri & Spotlight" (#1299): owns the catalogue, the session context
// and the Spotlight publication. Everything is off until the person turns
// "Index Phoebus Content" on.

/// Starts the capture, and answers Settings.
@available(iOS 27.0, *)
@MainActor
enum PhoebusContentBridge {
    private static var started = false
    private static var observed = false
    private static var lastEnabled = SiriContentSettings.isEnabled

    static func start() {
        guard !started else { return }
        started = true
        // Events reach the service in the order they happened.
        let (events, continuation) = AsyncStream.makeStream(of: SiriContentEvent.self)
        SiriContentCapture.sink = { continuation.yield($0) }
        SiriContent.controller = PhoebusContentController()
        SiriAnnotationFactory.post = { EntityIdentifier(for: PhoebusPostEntity.self, identifier: $0) }
        SiriAnnotationFactory.comment = { EntityIdentifier(for: PhoebusCommentEntity.self, identifier: $0) }
        SiriAnnotationFactory.donateOpenPost = { donateOpen($0) }
        Task {
            for await event in events { await PhoebusContentService.shared.handle(event) }
        }
        // Account changes and opt-out are noticed even when no listing
        // arrives (including sign-out).
        let center = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification, .apolloActiveAccountChanged, .apolloAccountsRestored] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in refresh() }
            }
        }
        // Defaults change constantly; only the opt-in flipping matters (a
        // Shortcuts action or a restored backup can flip it outside the UI).
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                guard SiriContentSettings.isEnabled != lastEnabled else { return }
                lastEnabled = SiriContentSettings.isEnabled
                refresh()
            }
        }
        refresh()
    }

    /// Opening a post from the app's UI donates the open action, unless an
    /// intent started the navigation (the system already donates those).
    private static func donateOpen(_ fullName: String) {
        guard !SiriNavigation.intentNavigationIsRecent, let id = SiriOnscreen.postID(fullName) else {
            SiriLog.event("Donation skipped; navigation came from an intent")
            return
        }
        Task {
            guard let record = try? await PhoebusContentService.shared.resolve([id], kind: .post).first else { return }
            do {
                _ = try await IntentDonationManager.shared.donate(intent: OpenPhoebusPostIntent(target: PhoebusPostEntity(record)))
                SiriLog.event("Open-post interaction donated")
            } catch {
                SiriLog.event("Open-post donation failed")
            }
        }
    }

    private static func refresh() {
        Task {
            do { try await PhoebusContentService.shared.refresh() }
            catch { SiriLog.event("Content catalogue refresh failed") }
        }
    }
}

@available(iOS 27.0, *)
struct PhoebusContentController: SiriContentControlling {
    func setIndexing(_ enabled: Bool) async -> String {
        do {
            try await PhoebusContentService.shared.setEnabled(enabled)
            return try await PhoebusContentService.shared.status()
        } catch { return Self.message(for: error) }
    }

    func indexStatus() async -> String {
        do { return try await PhoebusContentService.shared.status() }
        catch { return Self.message(for: error) }
    }

    func refreshSubscriptions() async -> String {
        do {
            let complete = try await PhoebusContentService.shared.refreshSubscriptions()
            let status = try await PhoebusContentService.shared.status()
            return complete ? status : SiriContentStatus.incompleteRefresh(status)
        } catch { return Self.message(for: error) }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? any CustomLocalizedStringResourceConvertible {
            return String(localized: localized.localizedStringResource)
        }
        return "Phoebus could not update its content index. Try again."
    }
}

@available(iOS 27.0, *)
actor PhoebusContentService {
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case accountUnavailable, indexingDisabled, busy, indexUnavailable, rateLimit, network, invalidResponse

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .accountUnavailable: "Phoebus is still loading its account. Open Phoebus and try again."
            case .indexingDisabled: "Enable Siri & Spotlight content indexing in Phoebus first."
            case .busy: "Phoebus is already loading content. Try again shortly."
            case .indexUnavailable: "Spotlight could not finish updating. Phoebus will retry after a short pause. If it stays unavailable, reopen Phoebus. Index removal is not confirmed until an update succeeds."
            case .rateLimit: "Reddit is rate limiting requests. Try again later."
            case .network: "Phoebus could not load Reddit. Check its API setup and connection."
            case .invalidResponse: "Reddit returned an unexpected response."
            }
        }
    }

    static let shared = PhoebusContentService()
    static let indexName = "Phoebus.Content.v1"
    private var catalog: SiriContentCatalog?
    /// Viewed posts and loaded comments; never persisted or indexed.
    private let session = SiriSessionContext()
    private var dirty = false
    private var resetIndex = false // Forces a full delete/rebuild (recovery, reindex-all, scope change).
    private var checkpoint: SiriPublishCheckpoint?
    private var checkpointLoaded = false
    private var syncTask: Task<Void, Error>?
    private var syncFailure: (any Error)?
    private var retryAfter: ContinuousClock.Instant?
    private static let publicationGate = SiriPublicationGate()
    private var protectionClass: FileProtectionType? = .completeUntilFirstUserAuthentication
    private var refreshInProgress = false

    private static func supportDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Phoebus/Siri")
    }

    private func store() throws -> SiriContentCatalog {
        if let catalog { return catalog }
        let loaded = try SiriContentCatalog(file: Self.supportDirectory().appendingPathComponent("catalog-v1.json"))
        catalog = loaded
        return loaded
    }

    // MARK: - Scope

    /// Brings the catalogue in line with the opt-in and the signed-in account.
    func refresh() async throws {
        let enabled = SiriContentSettings.isEnabled
        let fingerprint: String?
        switch SiriAccountStatus.current() {
        case .unresolved:
            // Before first unlock the accounts can't be read: keep what is held.
            guard !enabled else { throw Failure.accountUnavailable }
            fingerprint = nil
        case .signedOut:
            fingerprint = nil
        case .signedIn(let username):
            fingerprint = SiriAccountStatus.fingerprint(username)
        }
        let catalog = try store()
        // A disabled index belongs to nobody: switching accounts while it is off changes nothing.
        let changed = try catalog.configure(enabled: enabled, account: enabled ? fingerprint : nil)
        session.configure(account: catalog.state.enabled ? catalog.state.account : nil)
        if changed {
            retryAfter = nil // Account changes and opt-out must attempt cleanup immediately.
            resetIndex = true
            // Remove donations that no longer apply: a different account or an
            // opt-out makes every prior open-content donation stale.
            Self.deleteAllDonations()
        }
        let count = catalog.state.records.count
        try catalog.expire()
        if changed || resetIndex || (enabled && loadCheckpoint() == nil) || count != catalog.state.records.count {
            scheduleSync()
        }
        publishOnscreen()
    }

    func setEnabled(_ enabled: Bool) async throws {
        await MainActor.run { SiriContentSettings.enabled.save(enabled) }
        try await refresh()
        // Turning off completes only after our entities have been removed from
        // Spotlight. An in-flight older upsert cannot race a completed disable.
        try await waitForSync()
    }

    func status() async throws -> String {
        try await refresh()
        try await waitForSync()
        let catalog = try store()
        return SiriContentStatus.text(
            enabled: catalog.state.enabled, signedIn: catalog.state.account != nil,
            posts: catalog.records(kind: .post, limit: SiriContentLimits.posts).count,
            communities: catalog.records(kind: .subreddit, limit: SiriContentLimits.communities).count)
    }

    private func enabledAccount() throws -> String {
        let catalog = try store()
        guard catalog.state.enabled else { throw Failure.indexingDisabled }
        guard let account = catalog.state.account else { throw Failure.accountUnavailable }
        return account
    }

    // MARK: - Capture

    func handle(_ event: SiriContentEvent) async {
        do {
            switch event {
            case .listing(let data, let account):
                try await ingest(data, account: SiriAccountStatus.fingerprint(account))
            case .openedPost(let data, let account):
                try await observePost(data, account: SiriAccountStatus.fingerprint(account))
            case .comments(let data, let account):
                try await observeComments(data, account: SiriAccountStatus.fingerprint(account))
            case .suppress(let names, let account):
                try await suppress(names, account: SiriAccountStatus.fingerprint(account))
            case .allow(let names, let account):
                try await allow(names, account: SiriAccountStatus.fingerprint(account))
            }
        } catch {
            SiriLog.event("Content update failed; no payload logged")
        }
    }

    func ingest(_ payload: Data, account: String) async throws {
        try await refresh()
        try store().ingest(payload, account: account)
        scheduleSync()
        publishOnscreen()
    }

    private func suppress(_ names: [String], account: String) async throws {
        try await refresh()
        let catalog = try store()
        let canonical = catalog.canonicalIdentifiers(names)
        try catalog.suppress(canonical, account: account)
        session.suppress(canonical)
        Self.deleteDonations(forPosts: canonical.filter { $0.hasPrefix("reddit:post:") })
        scheduleSync()
        publishOnscreen()
    }

    private func allow(_ names: [String], account: String) async throws {
        try await refresh()
        let catalog = try store()
        try catalog.allow(catalog.canonicalIdentifiers(names), account: account)
    }

    /// Opened posts and loaded comments: memory-only context, so onscreen
    /// annotations resolve for posts reached from a link too.
    private func observePost(_ payload: Data, account: String) async throws {
        try await refresh()
        let catalog = try store()
        guard catalog.state.enabled, catalog.state.account == account, payload.count <= 64 * 1024,
              let rows = try JSONSerialization.jsonObject(with: payload) as? [[String: Any]],
              let record = rows.first.flatMap({ SiriContentRecord.parse($0, now: Date()) }),
              !catalog.isSuppressed(record.id) else { return }
        session.observe(post: record, account: account)
        publishOnscreen()
    }

    private func observeComments(_ payload: Data, account: String) async throws {
        try await refresh()
        let catalog = try store()
        guard catalog.state.enabled, catalog.state.account == account, payload.count <= SiriContentLimits.payloadBytes,
              let rows = try JSONSerialization.jsonObject(with: payload) as? [[String: Any]] else { return }
        let comments = rows.prefix(SiriContentLimits.rowsPerPayload).compactMap { row -> SiriCommentRecord? in
            SiriCommentRecord.parse(row, order: (row["order"] as? NSNumber)?.intValue ?? Int.max)
        }.filter { !catalog.isSuppressed($0.postID) }
        session.observe(comments: comments, account: account)
        SiriLog.event("Loaded comments added to session context", count: comments.count)
        publishOnscreen()
    }

    /// Replaces what the app may annotate: the catalogue's posts, the posts
    /// opened this session, and their loaded comments.
    private func publishOnscreen() {
        guard let catalog = try? store(), catalog.state.enabled, catalog.state.account != nil else {
            SiriOnscreen.replace(with: [])
            return
        }
        var ids = Set(catalog.records(kind: .post, limit: SiriContentLimits.posts).map(\.id))
        ids.formUnion(session.postIDs.filter { !catalog.isSuppressed($0) })
        ids.formUnion(session.commentIDs)
        SiriOnscreen.replace(with: ids)
    }

    // MARK: - Queries

    func searchSnapshot(query: String) async throws -> (records: [SiriContentRecord], account: String) {
        try await refresh()
        let catalog = try store()
        return (catalog.records(kind: .post, query: query, limit: 10), catalog.state.account ?? "")
    }

    /// Snippet redraws are reads, not new searches, writes or indexing
    /// requests. Never render a prior account's captured values after
    /// account switching.
    func snippetRecords(identifiers: [String], account: String) async throws -> [SiriContentRecord] {
        guard SiriContentSettings.isEnabled,
              case .signedIn(let username) = SiriAccountStatus.current(),
              SiriAccountStatus.fingerprint(username) == account else { return [] }
        let catalog = try store()
        guard catalog.state.account == account else { return [] }
        return catalog.resolve(Array(identifiers.prefix(10))).filter { $0.kind == .post }
    }

    func records(kind: SiriContentRecord.Kind, query: String = "", limit: Int = 50) async throws -> [SiriContentRecord] {
        try await refresh()
        return try store().records(kind: kind, query: query, limit: limit)
    }

    func resolve(_ identifiers: [String], kind: SiriContentRecord.Kind) async throws -> [SiriContentRecord] {
        try await refresh()
        let catalogued = try store().resolve(identifiers).filter { $0.kind == kind }
        guard kind == .post else { return catalogued }
        // Viewed-but-uncatalogued posts resolve too, so an annotated detail
        // screen and its open action work for posts opened from a link.
        let found = Set(catalogued.map(\.id))
        return catalogued + identifiers.filter { !found.contains($0) }.compactMap(session.post)
    }

    func comments(_ identifiers: [String]) async throws -> [SiriCommentRecord] {
        try await refresh()
        return session.comments(identifiers)
    }

    func comments(forPost postID: String, limit: Int) async throws -> [SiriCommentRecord] {
        try await refresh()
        return session.comments(forPost: postID, limit: limit)
    }

    func searchComments(_ query: String, limit: Int) async throws -> [SiriCommentRecord] {
        try await refresh()
        return session.search(query, limit: limit)
    }

    // MARK: - Subscriptions

    /// Walks the subscription list (at most five pages) and drops communities
    /// no longer on it. False when the list was longer than that: an unseen
    /// page never implies an unsubscribe.
    func refreshSubscriptions() async throws -> Bool {
        guard !refreshInProgress else { throw Failure.busy }
        refreshInProgress = true
        defer { refreshInProgress = false }
        try await refresh()
        let account = try enabledAccount()
        guard let repository = await Self.repository() else { throw Failure.accountUnavailable }
        var after: String?
        var observed = Set<String>()
        var cursors = Set<String>()
        for _ in 0..<5 {
            try Task.checkCancellation()
            let page = try await Self.subscriptionPage(repository, after: after)
            try Task.checkCancellation()
            guard let payload = SiriContentSanitizer.listingPayload(page.data.children) else { throw Failure.invalidResponse }
            try await ingest(payload, account: account)
            guard try enabledAccount() == account else { throw Failure.accountUnavailable }
            observed.formUnion(SiriContentSanitizer.communityIDs(page.data.children))
            guard let next = page.data.after, !next.isEmpty else {
                let catalog = try store()
                let stale = catalog.records(kind: .subreddit, limit: SiriContentLimits.communities).map(\.id)
                    .filter { !observed.contains($0) }
                try catalog.suppress(stale, account: account)
                scheduleSync()
                publishOnscreen()
                try await waitForSync()
                return true
            }
            guard cursors.insert(next).inserted else { throw Failure.invalidResponse }
            after = next
        }
        try await waitForSync()
        return false
    }

    @MainActor
    private static func repository() -> RedditRepository? {
        ActiveRedditRepository.provider() ?? AccountManager.makeActiveRepository()
    }

    private static func subscriptionPage(_ repository: RedditRepository, after: String?) async throws -> RedditListing {
        do {
            return try await repository.fetchSubscribedSubredditsPage(after: after)
        } catch let error as RedditAPIError {
            switch error {
            case .notAuthenticated, .sessionExpired: throw Failure.accountUnavailable
            case .httpError(let status, _) where status == 429: throw Failure.rateLimit
            default: throw Failure.network
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.network
        }
    }

    // MARK: - Donation hygiene

    private nonisolated static func deleteAllDonations() {
        Task {
            for type in [OpenPhoebusPostIntent.self, OpenPhoebusCommentIntent.self,
                         OpenPhoebusSubscribedSubredditIntent.self] as [any AppIntent.Type] {
                _ = try? await IntentDonationManager.shared.deleteDonations(matching: .intentType(type))
            }
            SiriLog.event("Cleared intent donations after scope change")
        }
    }

    private nonisolated static func deleteDonations(forPosts ids: [String]) {
        guard !ids.isEmpty else { return }
        let entities = ids.map { EntityIdentifier(for: PhoebusPostEntity.self, identifier: $0) }
        Task { try? await IntentDonationManager.shared.deleteDonations(matching: .entityIdentifiers(entities)) }
    }

    // MARK: - System-requested recovery

    /// IndexedEntityQuery.reindexAllEntities: a full rebuild.
    func reindex(protectionClass: FileProtectionType?) async throws {
        try await refresh()
        // The system supplies the protection class of the index being rebuilt.
        // Retain our index namespace but honour that supplied description.
        self.protectionClass = protectionClass
        resetIndex = true
        scheduleSync()
        try await waitForSync()
    }

    /// IndexedEntityQuery.reindexEntities: re-upsert only the named entities,
    /// deleting any we no longer hold.
    func reindex(_ identifiers: [String], protectionClass: FileProtectionType?) async throws {
        try await refresh()
        self.protectionClass = protectionClass
        let catalog = try store()
        let records = catalog.state.enabled ? catalog.resolve(identifiers) : []
        let present = Set(records.map(\.id))
        let missing = identifiers.filter { !present.contains($0) }
        try await Self.publish(reset: false, posts: records.filter { $0.kind == .post },
                               subreddits: records.filter { $0.kind == .subreddit },
                               removePosts: missing, removeSubreddits: missing,
                               protectionClass: protectionClass)
        SiriLog.event("Targeted reindex completed", count: records.count)
    }

    // MARK: - Incremental Spotlight publication

    private func checkpointURL() throws -> URL {
        try Self.supportDirectory().appendingPathComponent("spotlight-checkpoint-v1.json")
    }

    private func loadCheckpoint() -> SiriPublishCheckpoint? {
        if !checkpointLoaded {
            checkpointLoaded = true
            checkpoint = (try? Data(contentsOf: checkpointURL())).flatMap { try? JSONDecoder().decode(SiriPublishCheckpoint.self, from: $0) }
        }
        return checkpoint
    }

    private func saveCheckpoint(_ next: SiriPublishCheckpoint) throws {
        checkpoint = next
        var url = try checkpointURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func waitForSync() async throws {
        try await syncTask?.value
        // During backoff there is no task to await. Never claim a successful
        // update (especially "index is cleared") after a failed publication.
        if let syncFailure { throw syncFailure }
    }

    private func scheduleSync() {
        dirty = true
        guard syncTask == nil else { return }
        if let retryAfter, ContinuousClock.now < retryAfter { return }
        syncTask = Task {
            defer { syncTask = nil }
            do {
                // Coalesce normal listing bursts; the actor remains available for
                // capture and opt-out while Spotlight operations are suspended.
                try await Task.sleep(for: .milliseconds(500))
                while dirty {
                    dirty = false
                    let catalog = try store()
                    let account = catalog.state.enabled ? catalog.state.account : nil
                    let plan = SiriPublicationPlan.make(
                        checkpoint: loadCheckpoint(), account: account, forceReset: resetIndex,
                        posts: account == nil ? [] : catalog.records(kind: .post, limit: SiriContentLimits.posts),
                        subreddits: account == nil ? [] : catalog.records(kind: .subreddit, limit: SiriContentLimits.communities))
                    resetIndex = false
                    guard !plan.isEmpty else { continue }
                    do {
                        try await Self.publish(reset: plan.reset, posts: plan.changedPosts, subreddits: plan.changedSubreddits,
                                               removePosts: plan.removedPostIDs, removeSubreddits: plan.removedSubredditIDs,
                                               protectionClass: protectionClass,
                                               expectedState: plan.reset ? nil : plan.previous.clientState,
                                               newState: plan.next.clientState)
                    } catch let error as CSIndexError where error.code == .mismatchedClientState {
                        // Spotlight doesn't hold what our checkpoint says (index
                        // wiped or restored). Rebuild once instead of trusting it.
                        SiriLog.event("Spotlight client state mismatch; full rebuild")
                        resetIndex = true
                        dirty = true
                        continue
                    }
                    try saveCheckpoint(plan.next)
                    syncFailure = nil
                    retryAfter = nil
                    SiriLog.event("Content index synchronized; upserts", count: plan.changedPosts.count + plan.changedSubreddits.count)
                }
            } catch {
                resetIndex = true
                dirty = true
                syncFailure = error
                retryAfter = ContinuousClock.now.advanced(by: .seconds(60))
                SiriLog.event("Content index sync failed; refresh retries after cooldown")
                throw error
            }
        }
    }

    /// A task-group timeout would still await a non-cooperative SDK child.
    /// The gate releases callers after 20 seconds but keeps that operation's
    /// slot occupied until it drains, avoiding overlapping or unbounded calls.
    private nonisolated static func publish(reset: Bool, posts: [SiriContentRecord], subreddits: [SiriContentRecord],
                                            removePosts: [String], removeSubreddits: [String],
                                            protectionClass: FileProtectionType?,
                                            expectedState: Data? = nil, newState: Data? = nil) async throws {
        do {
            try await publicationGate.run {
                try await publishNow(reset: reset, posts: posts, subreddits: subreddits,
                                     removePosts: removePosts, removeSubreddits: removeSubreddits,
                                     protectionClass: protectionClass,
                                     expectedState: expectedState, newState: newState)
            }
        } catch is SiriPublicationGate.Failure {
            throw Failure.indexUnavailable
        }
    }

    // The SDK's CSSearchableIndex reference isn't Sendable. Keep it local to
    // this nonisolated async operation; never pass an actor-owned reference to
    // a nonisolated SDK method.
    private nonisolated static func publishNow(reset: Bool, posts: [SiriContentRecord], subreddits: [SiriContentRecord],
                                               removePosts: [String], removeSubreddits: [String],
                                               protectionClass: FileProtectionType?,
                                               expectedState: Data?, newState: Data?) async throws {
        try Task.checkCancellation()
        let index = CSSearchableIndex(name: indexName, protectionClass: protectionClass)
        // Canonical-index work is one batch whose client state commits only if
        // every call lands. A targeted reindex passes no state and stays
        // outside the batch contract.
        if newState != nil { index.beginBatch() }
        if reset {
            try await index.deleteAppEntities(ofType: PhoebusPostEntity.self)
            try Task.checkCancellation()
            try await index.deleteAppEntities(ofType: PhoebusSubredditEntity.self)
        } else {
            if !removePosts.isEmpty { try await index.deleteAppEntities(identifiedBy: removePosts, ofType: PhoebusPostEntity.self) }
            try Task.checkCancellation()
            if !removeSubreddits.isEmpty { try await index.deleteAppEntities(identifiedBy: removeSubreddits, ofType: PhoebusSubredditEntity.self) }
        }
        // A callback can arrive after the caller timed out or changed account.
        // Do not let the cancelled publication continue with stale writes.
        try Task.checkCancellation()
        // Entity-backed searchable items keep their App Intents association
        // and expire even when the app isn't launched again for weeks.
        // Upserting an existing identifier updates it in place.
        let items = posts.map { record in
            let entity = PhoebusPostEntity(record)
            let item = CSSearchableItem(appEntity: entity)
            item.expirationDate = entity.expiresAt
            return item
        } + subreddits.map { record in
            let entity = PhoebusSubredditEntity(record)
            let item = CSSearchableItem(appEntity: entity)
            item.expirationDate = entity.expiresAt
            return item
        }
        // Bounded batches keep a first full build from being one huge request.
        for start in stride(from: 0, to: items.count, by: 200) {
            try await index.indexSearchableItems(Array(items[start..<min(start + 200, items.count)]))
            try Task.checkCancellation()
        }
        if let newState {
            try await index.endIndexBatch(expectedClientState: expectedState, newClientState: newState)
        }
    }
}
