import AppIntents
import Foundation
import PhoebusCore
import SwiftUI

// Reborn "Siri & Spotlight" (#1299): the actions Siri, Spotlight and
// Shortcuts offer once content indexing is on. Reborn marks the open and
// search intents with `@AppIntent(schema: .system.open)` and
// `.system.searchInApp`. The macro's compiler plugin only ships with Xcode,
// so each of those intents carries the extensions the macro expands to
// instead (what Xcode 27 prints for it, which Apple's metadata then
// registers as an assistant schema).

@available(iOS 27.0, *)
struct OpenPhoebusPostIntent {
    static let title: LocalizedStringResource = "Open Phoebus Post"
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Post", requestValueDialog: "Which post?")
    var target: PhoebusPostEntity

    init() {}

    init(target: PhoebusPostEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriLog.event("Open post action started")
        guard let record = try await PhoebusContentService.shared.resolve([target.id], kind: .post).first else {
            throw AppIntentError.Unrecoverable.entityNotFound
        }
        SiriNavigation.open(record.navigationTarget)
        SiriLog.event("Open post action completed")
        return .result()
    }
}

@available(iOS 27.0, *)
extension OpenPhoebusPostIntent: AssistantSchemaIntent {
    static let __appSchemaIntent = "system.open"
}

@available(iOS 27.0, *)
extension OpenPhoebusPostIntent: AppIntent {}

@available(iOS 27.0, *)
extension OpenPhoebusPostIntent: OpenIntent {}

@available(iOS 27.0, *)
struct OpenPhoebusSubscribedSubredditIntent {
    static let title: LocalizedStringResource = "Open Subscribed Phoebus Community"
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Subreddit", requestValueDialog: "Which subreddit?")
    var target: PhoebusSubredditEntity

    init() {}

    init(target: PhoebusSubredditEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriLog.event("Open subscribed subreddit action started")
        guard let record = try await PhoebusContentService.shared.resolve([target.id], kind: .subreddit).first else {
            throw AppIntentError.Unrecoverable.entityNotFound
        }
        SiriNavigation.open(record.navigationTarget)
        SiriLog.event("Open subscribed subreddit action completed")
        return .result()
    }
}

@available(iOS 27.0, *)
extension OpenPhoebusSubscribedSubredditIntent: AssistantSchemaIntent {
    static let __appSchemaIntent = "system.open"
}

@available(iOS 27.0, *)
extension OpenPhoebusSubscribedSubredditIntent: AppIntent {}

@available(iOS 27.0, *)
extension OpenPhoebusSubscribedSubredditIntent: OpenIntent {}

@available(iOS 27.0, *)
struct OpenPhoebusCommentIntent {
    static let title: LocalizedStringResource = "Open Phoebus Comment"
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Comment", requestValueDialog: "Which comment?")
    var target: PhoebusCommentEntity

    init() {}

    init(target: PhoebusCommentEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriLog.event("Open comment action started")
        guard let record = try await PhoebusContentService.shared.comments([target.id]).first else {
            throw AppIntentError.Unrecoverable.entityNotFound
        }
        SiriNavigation.open(record.navigationTarget)
        SiriLog.event("Open comment action completed")
        return .result()
    }
}

@available(iOS 27.0, *)
extension OpenPhoebusCommentIntent: AssistantSchemaIntent {
    static let __appSchemaIntent = "system.open"
}

@available(iOS 27.0, *)
extension OpenPhoebusCommentIntent: AppIntent {}

@available(iOS 27.0, *)
extension OpenPhoebusCommentIntent: OpenIntent {}

/// Siri's in-app search contract is navigation: Apple defines `searchInApp`
/// as "navigates to search results" and notes Siri may not show dialog or
/// snippet output. In-Siri post results come from the Spotlight semantic
/// index (`PhoebusPostEntity` and `OpenPhoebusPostIntent`), not from here.
@available(iOS 27.0, *)
struct SearchPhoebusIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Phoebus"
    static let description = IntentDescription(
        "Searches Reddit in Phoebus and shows the results in its search screen.",
        searchKeywords: ["search", "find", "look up", "reddit", "posts", "subreddit"])
    static let searchScopes: [StringSearchScope] = [.general]
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter()
    var criteria: StringSearchCriteria

    static var parameterSummary: some ParameterSummary {
        Summary("Search Phoebus for \(\.$criteria)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriLog.event("Search action started; foreground navigation")
        // Callers may supply empty criteria. Ask before touching navigation.
        let resolved = criteria.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? try await $criteria.requestValue("What would you like to search for in Phoebus?")
            : criteria
        try SiriNavigation.search(resolved.term)
        SiriLog.event("Search action completed; no snippet")
        return .result()
    }
}

@available(iOS 27.0, *)
extension SearchPhoebusIntent: AssistantSchemaIntent {
    static let __appSchemaIntent = "system.searchInApp"
}

@available(iOS 27.0, *)
extension SearchPhoebusIntent: AppIntent {}

/// Controls are explicit Shortcuts actions; they don't create a donation per
/// post or subreddit or clutter the App Shortcuts provider.
@available(iOS 27.0, *)
struct SetPhoebusContentIndexingIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Phoebus Content Indexing"
    static let description = IntentDescription("Make eligible public posts loaded in Phoebus and subscribed communities searchable in Spotlight. Turning off removes this content index. Private, NSFW and hidden content is excluded.")
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Enabled")
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set Phoebus content indexing to \(\.$enabled)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await PhoebusContentService.shared.setEnabled(enabled)
        return .result(dialog: enabled
            ? "Indexing enabled. Browse Phoebus to collect eligible public posts and subscribed communities."
            : "Indexing disabled and Phoebus's content index cleared.")
    }
}

@available(iOS 27.0, *)
struct PhoebusContentIndexStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Phoebus Content Index Status"
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let status = try await PhoebusContentService.shared.status()
        return .result(value: status, dialog: "\(status)")
    }
}

@available(iOS 27.0, *)
struct FindIndexedPhoebusPostsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Indexed Phoebus Posts"
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Search")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find indexed Phoebus posts matching \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[PhoebusPostEntity]> & ProvidesDialog & ShowsSnippetIntent {
        SiriLog.event("Indexed post search action started")
        let snapshot = try await PhoebusContentService.shared.searchSnapshot(query: query)
        SiriLog.event("Indexed post search returning snippet", count: snapshot.records.count)
        return .result(value: snapshot.records.map(PhoebusPostEntity.init),
                       // Full text for voice-only contexts; supporting text sits beside the snippet.
                       dialog: IntentDialog(full: snapshot.records.first.map { "Found \(snapshot.records.count) posts. The top one is \($0.title), in r/\($0.subreddit)." }
                                                ?? "I didn't find any matching posts you've seen in Phoebus.",
                                            supporting: "Found \(snapshot.records.count) indexed posts in Phoebus."),
                       snippetIntent: PhoebusPostResultsSnippetIntent(records: snapshot.records, account: snapshot.account))
    }
}

@available(iOS 27.0, *)
struct RefreshPhoebusSubscriptionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Phoebus Subscriptions Index"
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let complete = try await PhoebusContentService.shared.refreshSubscriptions()
        return .result(dialog: complete
            ? "Phoebus's eligible subscribed communities are indexed."
            : "Indexed the first 500 subscriptions. This account has more; existing entries were not removed.")
    }
}

@available(iOS 27.0, *)
struct PhoebusPostResultsSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Phoebus Post Results"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Post identifiers")
    var identifiers: [String]

    @Parameter(title: "Account scope")
    var account: String

    init() {}

    init(records: [SiriContentRecord], account: String) {
        self.identifiers = records.map(\.id)
        self.account = account
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        SiriLog.event("Post results snippet requested")
        let records = try await PhoebusContentService.shared.snippetRecords(identifiers: identifiers, account: account)
        SiriLog.event("Post results snippet view returned", count: records.count)
        return .result(view: PhoebusPostResultsView(posts: records.prefix(3).map(PhoebusPostEntity.init),
                                                    totalCount: records.count))
    }
}

@available(iOS 27.0, *)
struct PhoebusPostResultsView: View {
    let posts: [PhoebusPostEntity]
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posts from Phoebus").font(.headline)
            if posts.isEmpty {
                Text("No available posts. Enable content indexing and browse Phoebus, or try another search.")
                    .font(.body).foregroundStyle(.secondary)
            } else {
                ForEach(posts) { post in
                    PhoebusPostResultRow(post: post)
                }
                if totalCount > posts.count {
                    Text("Showing \(posts.count) of \(totalCount) matches. All matches are included in the action’s output.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

@available(iOS 27.0, *)
struct PhoebusPostResultRow: View {
    let post: PhoebusPostEntity

    var body: some View {
        Button(intent: OpenPhoebusPostIntent(target: post)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title).font(.body).fontWeight(.semibold).lineLimit(3)
                Text("r/\(post.subreddit) · u/\(post.author)")
                    .font(.caption).foregroundStyle(.secondary)
                if !post.text.isEmpty {
                    Text(post.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens this post in Phoebus"))
    }
}
