// Compiled only on the xcode-27 runner (appintents-macro-probe.yml), to see
// what the assistant-schema macros expand to and what metadata Apple writes
// for them. Mirrors the shapes in Sources/Phoebus/SiriIntents.swift.
import AppIntents
import CoreSpotlight
import Foundation

struct ProbePostEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Post"
    static let defaultQuery = ProbePostQuery()
    var id: String
    @Property(title: "Title", indexingKey: \.title) var title: String
    @DeferredProperty(title: "Loaded Comments")
    var loadedComments: [String] {
        get async throws { [] }
    }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ProbePostQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ProbePostEntity] { [] }
    func entities(matching string: String) async throws -> [ProbePostEntity] { [] }
    func suggestedEntities() async throws -> [ProbePostEntity] { [] }
}

@AppIntent(schema: .system.open)
struct ProbeOpenPostIntent {
    static let title: LocalizedStringResource = "Open Post"
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    @Parameter(title: "Post", requestValueDialog: "Which post?") var target: ProbePostEntity
    init() {}
    func perform() async throws -> some IntentResult { .result() }
}

@AppIntent(schema: .system.searchInApp)
struct ProbeSearchIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Probe"
    static let description = IntentDescription("Searches.", searchKeywords: ["search"])
    static let searchScopes: [StringSearchScope] = [.general]
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    var criteria: StringSearchCriteria
    static var parameterSummary: some ParameterSummary { Summary("Search Probe for \(\.$criteria)") }
    init() {}
    func perform() async throws -> some IntentResult { .result() }
}
