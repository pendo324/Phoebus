import AppIntents
import CoreSpotlight
import CoreTransferable
import Foundation
import PhoebusCore

// Reborn "Siri & Spotlight" (#1299): the entities Spotlight indexes and Siri
// reads. Everything here needs iOS 27 (indexed entity queries); the app's
// minimum is 17, so each type is gated.

@available(iOS 27.0, *)
struct PhoebusPostEntity: IndexedEntity {
    // Synonyms are what Siri matches when someone names the kind of thing
    // ("the post", "that thread") rather than the entity itself; numericFormat
    // lets it phrase counts ("3 posts") naturally.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Reddit Post", numericFormat: "\(placeholder: .int) Reddit posts",
        synonyms: ["Post", "Reddit Thread", "Thread"])
    static let defaultQuery = PhoebusPostQuery()
    let id: String
    let expiresAt: Date
    @Property(title: "Title") var title: String
    @Property(title: "Subreddit") var subreddit: String
    @Property(title: "Author") var author: String
    // Properties with an indexing key feed the Spotlight semantic index
    // directly, so a vague description ("the post about keyboards") finds it.
    @Property(title: "Text", indexingKey: \.textContent) var text: String
    @Property(title: "Posted", indexingKey: \.contentCreationDate) var createdAt: Date
    /// Public HTTPS permalink; local navigation keeps using the record's route.
    @Property(title: "Link", indexingKey: \.url) var webURL: URL
    @Property(title: "Score") var score: Int?
    @Property(title: "Comment Count") var commentCount: Int?
    @Property(title: "Linked Site") var linkDomain: String?

    /// Comments Phoebus has already loaded because the person opened this
    /// post. Deferred (large values load lazily and stay out of archives) and
    /// served from memory only: resolving it never issues a Reddit request, so
    /// Siri answering "what are the comments saying" costs nothing. Empty for
    /// posts never opened.
    var loadedComments: [PhoebusCommentEntity] {
        get async throws {
            try await PhoebusContentService.shared.comments(forPost: id, limit: 40).map(PhoebusCommentEntity.init)
        }
    }

    // Reborn declares `loadedComments` with `@DeferredProperty(title: "Loaded
    // Comments")` (#1299). The macro's plugin only ships with Xcode, so this
    // is what it expands to, minus the `$loadedComments` projection nothing
    // here reads.
    var _loadedComments = EntityProperty<[PhoebusCommentEntity]>(
        identifier: "loadedComments", title: "Loaded Comments",
        asyncGetter: { (entity: Self) in try await entity.loadedComments })

    init(_ record: SiriContentRecord) {
        id = record.id
        expiresAt = record.observedAt.addingTimeInterval(SiriContentLimits.retention)
        title = record.title; subreddit = record.subreddit
        author = record.author; text = record.text; createdAt = record.createdAt
        webURL = record.webURL
        score = record.score; commentCount = record.commentCount; linkDomain = record.linkDomain
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "r/\(subreddit) · u/\(author)",
                              image: .init(systemName: "text.bubble"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = "r/\(subreddit) · u/\(author)\n\(text)"
        attributes.authorNames = [author]
        attributes.keywords = [subreddit, "r/\(subreddit)", "Phoebus", "Reddit"] + (linkDomain.map { [$0] } ?? [])
        return attributes
    }

    /// Readable export: what "send this to …" / "summarize this" should carry.
    /// A method, not a property: the metadata processor reads a type's
    /// properties, and cannot read a computed one built from calls.
    func exportedText() -> String {
        [title, "r/\(subreddit) · u/\(author)", text, webURL.absoluteString]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

// Cross-app transfer ("send this post to Sam", "add this to my notes"). The
// HTTPS permalink comes first so link-aware receivers get a rich link; plain
// text carries the content itself.
@available(iOS 27.0, *)
extension PhoebusPostEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.webURL)
        DataRepresentation(exportedContentType: .plainText) { Data($0.exportedText().utf8) }
    }
}

/// A comment on a post the person opened. A plain AppEntity, not indexed:
/// comments are reached through onscreen annotations ("what does this comment
/// mean", "send this reply to Sam"). Resolution is served from the
/// memory-only session context and disappears with it.
@available(iOS 27.0, *)
struct PhoebusCommentEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Reddit Comment", numericFormat: "\(placeholder: .int) Reddit comments",
        synonyms: ["Comment", "Reply"])
    static let defaultQuery = PhoebusCommentQuery()
    let id: String
    @Property(title: "Text") var body: String
    @Property(title: "Author") var author: String
    @Property(title: "Score") var score: Int?
    @Property(title: "Written by Original Poster") var isOriginalPoster: Bool
    @Property(title: "Reply Depth") var depth: Int
    @Property(title: "Posted") var createdAt: Date
    @Property(title: "Subreddit") var subreddit: String
    @Property(title: "Link") var webURL: URL
    /// Built once: a bounded title like Apple's message entity, which titles
    /// with its body.
    let shownAs: DisplayRepresentation

    init(_ record: SiriCommentRecord) {
        // The stored values first: assigning a property-wrapped one uses `self`.
        id = record.id
        shownAs = DisplayRepresentation(
            title: "\(String(record.body.prefix(140)))",
            subtitle: "u/\(record.author)\(record.isOP ? " (OP)" : "") · r/\(record.subreddit)",
            image: .init(systemName: "text.bubble"))
        body = record.body; author = record.author; score = record.score
        isOriginalPoster = record.isOP; depth = record.depth; createdAt = record.createdAt
        subreddit = record.subreddit
        webURL = record.webURL
    }

    var displayRepresentation: DisplayRepresentation { shownAs }

    func exportedText() -> String { "u/\(author): \(body)\n\n\(webURL.absoluteString)" }
}

@available(iOS 27.0, *)
extension PhoebusCommentEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.webURL)
        DataRepresentation(exportedContentType: .plainText) { Data($0.exportedText().utf8) }
    }
}

@available(iOS 27.0, *)
struct PhoebusSubredditEntity: IndexedEntity {
    // Generic "Subreddit", not "Subscribed Subreddit": Siri matches this and
    // its synonyms against how people actually speak.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Subreddit", numericFormat: "\(placeholder: .int) subreddits",
        synonyms: ["Community", "Sub", "Reddit Community"])
    static let defaultQuery = PhoebusSubredditQuery()
    let id: String
    let expiresAt: Date
    let webURL: URL
    @Property(title: "Name") var name: String
    @Property(title: "Description", indexingKey: \.contentDescription) var summary: String
    /// Spoken aliases: the bare name and the community's own display title.
    /// Siri hears "open boutique blu-ray", never "open r/boutiquebluray".
    let aliases: [String]
    let shownAs: DisplayRepresentation

    init(_ record: SiriContentRecord) {
        var spoken = [record.subreddit]
        if let title = record.displayTitle, !title.isEmpty, title.caseInsensitiveCompare(record.subreddit) != .orderedSame {
            spoken.append(title)
        }
        // The stored values first: assigning a property-wrapped one uses `self`.
        id = record.id
        expiresAt = record.observedAt.addingTimeInterval(SiriContentLimits.retention)
        webURL = record.webURL
        aliases = spoken
        shownAs = DisplayRepresentation(
            title: "\(record.title)", subtitle: "\(record.text)",
            image: .init(systemName: "bubble.left.and.bubble.right"),
            synonyms: spoken.map { "\($0)" })
        name = record.title; summary = record.text
    }

    var displayRepresentation: DisplayRepresentation { shownAs }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = name
        attributes.alternateNames = aliases
        attributes.textContent = summary
        attributes.url = webURL
        attributes.keywords = ["Phoebus", "Reddit", "subreddit", "community"] + aliases
        return attributes
    }
}

@available(iOS 27.0, *)
extension PhoebusSubredditEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.webURL)
    }
}

@available(iOS 27.0, *)
struct PhoebusCommentQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PhoebusCommentEntity] {
        try await SiriLog.query("Comment IDs") {
            try await PhoebusContentService.shared.comments(identifiers).map(PhoebusCommentEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [PhoebusCommentEntity] {
        try await SiriLog.query("Comment text match") {
            try await PhoebusContentService.shared.searchComments(string, limit: 20).map(PhoebusCommentEntity.init)
        }
    }

    func suggestedEntities() async throws -> [PhoebusCommentEntity] { [] }
}

@available(iOS 27.0, *)
struct PhoebusPostQuery: EntityStringQuery, IndexedEntityQuery {
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await PhoebusContentService.shared.reindex(identifiers, protectionClass: indexDescription.protectionClass)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await PhoebusContentService.shared.reindex(protectionClass: indexDescription.protectionClass)
    }

    func entities(for identifiers: [String]) async throws -> [PhoebusPostEntity] {
        try await SiriLog.query("Post IDs") {
            try await PhoebusContentService.shared.resolve(identifiers, kind: .post).map(PhoebusPostEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [PhoebusPostEntity] {
        try await SiriLog.query("Post text match") {
            try await PhoebusContentService.shared.records(kind: .post, query: string).map(PhoebusPostEntity.init)
        }
    }

    func suggestedEntities() async throws -> [PhoebusPostEntity] {
        try await SiriLog.query("Post suggestions") {
            try await PhoebusContentService.shared.records(kind: .post, limit: 10).map(PhoebusPostEntity.init)
        }
    }
}

@available(iOS 27.0, *)
struct PhoebusSubredditQuery: EntityStringQuery, IndexedEntityQuery {
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await PhoebusContentService.shared.reindex(identifiers, protectionClass: indexDescription.protectionClass)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await PhoebusContentService.shared.reindex(protectionClass: indexDescription.protectionClass)
    }

    func entities(for identifiers: [String]) async throws -> [PhoebusSubredditEntity] {
        try await SiriLog.query("Subscribed subreddit IDs") {
            try await PhoebusContentService.shared.resolve(identifiers, kind: .subreddit).map(PhoebusSubredditEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [PhoebusSubredditEntity] {
        try await SiriLog.query("Subscribed subreddit text match") {
            try await PhoebusContentService.shared.records(kind: .subreddit, query: string).map(PhoebusSubredditEntity.init)
        }
    }

    func suggestedEntities() async throws -> [PhoebusSubredditEntity] {
        try await SiriLog.query("Subscribed subreddit suggestions") {
            try await PhoebusContentService.shared.records(kind: .subreddit, limit: 10).map(PhoebusSubredditEntity.init)
        }
    }
}
