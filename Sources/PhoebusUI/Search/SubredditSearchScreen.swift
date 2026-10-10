import SwiftUI
import PhoebusCore

/// Subreddit search and subscription management.
public struct SubredditSearchScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    @State private var query = ""
    @State private var results: [RedditSubreddit] = []
    @State private var errorMessage: String?
    let repository: RedditRepository
    let onSelect: (RedditSubreddit) -> Void
    /// Opens a Reddit page on this tab's stack (a Google or Kagi result).
    let onOpenTarget: (RedditURLTarget) -> Void
    /// Opens a recently visited multireddit by path and name.
    let onOpenMultireddit: (String, String) -> Void
    /// "Search With" (Reborn #1260, #1305): Reddit is Apollo's own search;
    /// Google and Kagi list Reddit threads they found, searched on Return;
    /// Reddit Answers (Phoebus-only) answers the question asked on Return.
    @State private var engine = SearchEngine.current
    /// The query the external engine was asked, set on Return or a suggestion.
    @State private var externalQuery = ""
    /// Reddit Answers' answer, kept here so it outlives the answer screen.
    @StateObject private var answersSession = RedditAnswersSession()

    /// The asked query is still the one in the field (a change of case or
    /// spacing alone, as the search field can make, doesn't count).
    private var showsAskedQuery: Bool {
        !externalQuery.isEmpty && RedditAnswersSession.sameQuestion(externalQuery, query)
    }
    @State private var suggestions: [String] = []
    /// Kagi picked with no Session Link saved: asks for one first.
    @State private var showsKagiLinkSheet = false
    /// Reddit Answers picked with no reddit.com web session: asks for a sign-in first.
    @State private var showsAnswersSignIn = false

    public init(repository: RedditRepository, onSelect: @escaping (RedditSubreddit) -> Void,
                onOpenTarget: @escaping (RedditURLTarget) -> Void = { _ in },
                onOpenMultireddit: @escaping (String, String) -> Void = { _, _ in }) {
        self.repository = repository
        self.onSelect = onSelect
        self.onOpenTarget = onOpenTarget
        self.onOpenMultireddit = onOpenMultireddit
    }

    private var showsExternal: Bool { engine.isExternal && !query.isEmpty }
    private var showsAnswers: Bool { engine == .answers && !query.isEmpty }

    public var body: some View {
        Group {
            #if canImport(WebKit) && canImport(UIKit)
            if showsAnswers, showsAskedQuery {
                RedditAnswerScreen(query: externalQuery, repository: repository, onOpen: onOpenTarget,
                                   session: answersSession) { question in
                    query = question
                    externalQuery = question
                }
            } else if showsAnswers {
                answersPrompt
            } else if showsExternal, showsAskedQuery {
                GoogleSearchResultsView(engine: engine, query: externalQuery, repository: repository, onOpen: onOpenTarget)
            } else if showsExternal {
                suggestionList
            } else {
                redditList
            }
            #else
            redditList
            #endif
        }
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: engine.placeholder ?? "Search Posts, Subreddits, Users")
        .onSubmit(of: .search) {
            if engine.isExternal || engine == .answers { externalQuery = query }
        }
        .onChange(of: query) { _, newValue in
            if engine.isExternal {
                Task { await loadSuggestions(newValue) }
            } else if engine == .answers {
                // Asked on Return; there is nothing to look up while typing.
            } else {
                Task { await search(newValue) }
            }
        }
        #if canImport(UIKit)
        .background(SearchEngineMagnifier(engine: engine) { pick($0) }.frame(width: 0, height: 0))
        .sheet(isPresented: $showsKagiLinkSheet) {
            KagiSessionLinkSheet { pick(.kagi) }
        }
        .sheet(isPresented: $showsAnswersSignIn) {
            RedditAnswersSignInSheet { pick(.answers) }
        }
        // Removing the Session Link in Settings puts Kagi mode back on Reddit.
        .onReceive(NotificationCenter.default.publisher(for: .kagiSessionLinkChanged)) { _ in syncEngine() }
        .onAppear { syncEngine() }
        #endif
        .apolloFlatListAppearance()
        // No navigation title: the Search tab shows none, so the search field sits
        // directly under the status bar with "TRENDING SUBREDDITS" first below it.
        .navigationTitle("")
        .navigationBarTitleDisplayModeIfAvailable()
    }

    /// The Search With choice. Kagi without a Session Link asks for one first
    /// and is picked again once it's saved. A query already entered runs on
    /// the new external engine; otherwise the field goes back to suggestions.
    private func pick(_ picked: SearchEngine) {
        if picked == .kagi, !KagiSession.hasToken {
            showsKagiLinkSheet = true
            return
        }
        if picked == .answers, !RedditAnswers.hasWebSession {
            showsAnswersSignIn = true
            return
        }
        if !(picked.isExternal && !externalQuery.isEmpty) { externalQuery = "" }
        engine = picked
        SearchEngine.current = picked
        if picked == .reddit {
            Task { await search(query) }
        } else if picked.isExternal {
            Task { await loadSuggestions(query) }
        }
    }

    /// Follows a change made elsewhere (the Session Link removed or added in
    /// Settings) without rewriting the remembered choice.
    private func syncEngine() {
        let current = SearchEngine.current
        guard engine != current else { return }
        engine = current
        externalQuery = ""
        if current == .reddit { Task { await search(query) } }
    }

    /// While typing in an external mode: the engine's own suggestions, under a
    /// row that searches exactly what was typed.
    private var suggestionList: some View {
        List {
            Button {
                externalQuery = query
            } label: {
                Label("Search \(engine.title) for \u{201C}\(query)\u{201D}", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("googleSearch.submit")
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    query = suggestion
                    externalQuery = suggestion
                } label: {
                    Label(suggestion, systemImage: "magnifyingglass").foregroundStyle(.primary)
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Searches Reddit through \(engine.title). Add r/name to search one subreddit, put a phrase in \"quotes\" to match it exactly, or add -word to leave a word out.")
                    .apolloSectionFooter()
            }
        }
        .apolloFlatListAppearance()
    }

    /// Reddit Answers while typing: one row asks exactly what was typed.
    private var answersPrompt: some View {
        List {
            Button {
                externalQuery = query
            } label: {
                Label("Ask Reddit Answers \u{201C}\(query)\u{201D}", systemImage: "sparkles")
            }
            .accessibilityIdentifier("answers.ask")
            Section {
                EmptyView()
            } footer: {
                Text("Reddit Answers writes a reply from Reddit posts and comments, with the posts it used. Reddit limits how many questions you can ask.")
                    .apolloSectionFooter()
            }
        }
        .apolloFlatListAppearance()
    }

    private func loadSuggestions(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { suggestions = []; return }
        #if canImport(WebKit) && canImport(UIKit)
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard text == query else { return }
        let found = await GoogleSearchSession.suggestions(for: trimmed, engine: engine)
        guard text == query else { return }
        suggestions = Array(found.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }.prefix(8))
        #endif
    }

    private var redditList: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if query.isEmpty {
                // Order matches Apollo's Search tab: TRENDING SUBREDDITS first under its own
                // uppercase header, bare names behind a trend-line glyph; the two Random rows
                // follow in a separate, header-less section. Recently Visited (Phoebus-only)
                // goes above them all.
                RecentlyVisitedSection(entries: recentlyVisitedEntries, area: "search",
                                       onOpen: openRecentlyVisited) {
                    Text("Recently Visited").textCase(.uppercase)
                } row: { entry in
                    SearchLandingRow(title: entry.title, systemImage: entry.systemImage)
                }
                if !trendingNames.isEmpty {
                    Section {
                        ForEach(trendingNames, id: \.self) { name in
                            Button {
                                Task { await openTrendingSubreddit(name) }
                            } label: {
                                // `chart.line.uptrend.xyaxis`, the glyph Reborn uses for its trend row.
                                SearchLandingRow(title: name, systemImage: "chart.line.uptrend.xyaxis")
                            }
                        }
                    } header: {
                        // Uppercase, unlike settings screens' title-case headers, matching "TRENDING
                        // SUBREDDITS".
                        Text("Trending Subreddits").textCase(.uppercase)
                    }
                }
                Section {
                    Button {
                        Task { await openRandomSubreddit() }
                    } label: {
                        SearchLandingRow(title: "Random Subreddit", systemImage: "shuffle")
                    }
                    .disabled(isLoadingRandom)
                    // Reborn's separate "Random NSFW Subreddit" row, shown only with "Show RandNSFW in
                    // Search" on. Its glyph is the same shuffle as the row above it.
                    if showsRandomNSFW {
                        Button {
                            Task { await openRandomNSFWSubreddit() }
                        } label: {
                            SearchLandingRow(title: "Random NSFW Subreddit", systemImage: "shuffle")
                        }
                        .disabled(isLoadingRandom)
                    }
                }
                .task { await loadTrending() }
                // Apollo has no dedicated Multis tab, so multireddits are reachable from Discover.
                Section {
                    SettingsLink {
                        MultiredditListScreen(repository: repository)
                    } label: {
                        SearchLandingRow(title: "Multireddits", systemImage: "square.stack")
                    }
                }
            }
            ForEach(results) { subreddit in
                Button {
                    onSelect(subreddit)
                } label: {
                    SubredditRow(subreddit: subreddit, repository: repository)
                }
                .buttonStyle(.plain)
            }
        }
        // Not the bottom glass bar: this is the Search tab's root, a discovery landing
        // page (Random Subreddit, Trending), so the field is pinned at the top
        // (`.searchable` on `body`). The Reddit prompt is verbatim.
    }

    @Setting(CustomSubredditSourceStore.storage) private var sources
    @Setting(SubredditSectionsSettingsStore.storage) private var sectionsSettings
    @Setting(RecentlyVisitedStore.storage) private var recentlyVisited

    /// Hidden with the Subreddits list's section by "Show Recently Visited".
    private var recentlyVisitedEntries: [RecentlyVisitedEntry] {
        guard sectionsSettings.showRecentlyVisited else { return [] }
        return recentlyVisited[RecentlyVisitedStore.bucket(for: FavoriteSubredditsAccountContext.currentUsernameProvider())] ?? []
    }

    private func openRecentlyVisited(_ entry: RecentlyVisitedEntry) {
        switch entry.kind {
        case .subreddit:
            if let subreddit = RedditSubreddit.named(entry.name) { onSelect(subreddit) }
        case .user:
            onOpenTarget(.user(entry.name))
        case .multireddit:
            onOpenMultireddit(entry.path ?? entry.name, entry.name)
        }
    }
    private var showsRandomNSFW: Bool { sources.showRandNSFWInSearch }
    @State private var isLoadingRandom = false
    @State private var trendingNames: [String] = []

    private func openRandomSubreddit() async {
        isLoadingRandom = true
        defer { isLoadingRandom = false }
        do {
            let sources = CustomSubredditSourceStore.load()
            let name: String
            do {
                name = try await CustomSubredditSourceClient.fetchRandomSubredditName(from: sources.effectiveRandomSourceURL)
            } catch {
                name = try await repository.fetchRandomSubredditName()
            }
            let subreddit = try await repository.fetchSubredditInfo(name: name)
            onSelect(subreddit)
        } catch {
            errorMessage = "Couldn't load a random subreddit."
        }
    }

    /// Reborn's separate "Random NSFW Subreddit" row, with its own
    /// `RandNsfwSubredditsSource` custom-source setting distinct from the regular
    /// Random Subreddit's.
    private func openRandomNSFWSubreddit() async {
        guard let sourceURL = CustomSubredditSourceStore.load().effectiveRandomNSFWSourceURL else {
            ApolloToast.showError("Random NSFW Source Required",
                                  detail: "Configure a Random NSFW source in Apollo Reborn settings.")
            return
        }
        isLoadingRandom = true
        defer { isLoadingRandom = false }
        do {
            let name = try await CustomSubredditSourceClient.fetchRandomSubredditName(from: sourceURL)
            let subreddit = try await repository.fetchSubredditInfo(name: name)
            onSelect(subreddit)
        } catch {
            errorMessage = "Couldn't load a random NSFW subreddit."
        }
    }

    private func openTrendingSubreddit(_ name: String) async {
        do {
            let subreddit = try await repository.fetchSubredditInfo(name: name)
            onSelect(subreddit)
        } catch {
            errorMessage = "Couldn't load r/\(name)."
        }
    }

    private func loadTrending() async {
        guard trendingNames.isEmpty else { return }
        do {
            let sources = CustomSubredditSourceStore.load()
            let names: [String]
            do {
                names = try await CustomSubredditSourceClient.fetchNames(from: sources.effectiveTrendingSourceURL)
            } catch {
                names = try await repository.fetchTrendingSubredditNames()
            }
            trendingNames = CustomSubredditSourceClient.sample(names, limit: generalSettings.trendingSubredditsLimit)
        } catch {
            // Trending is a best-effort nicety: fail silently rather than showing an error.
        }
    }

    private func search(_ text: String) async {
        guard !text.isEmpty else {
            results = []
            return
        }
        // Debounced, and only the answer for what is still typed lands, so a slow answer
        // for "ap" cannot replace the results for "apple".
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard text == query else { return }
        do {
            let data = try await repository.searchSubreddits(query: text)
            let listing = try await RedditListing.decodedInBackground(from: data)
            let subreddits = await listing.childrenInBackground(RedditSubreddit.self)
            guard text == query else { return }
            errorMessage = nil
            // "Filter Subreddits by Name" covers search too, as in Reborn.
            let rules = PostFilterStore.load()
            results = subreddits.filter { !rules.hidesSubredditName($0.displayName) }
        } catch {
            guard text == query else { return }
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

struct SubredditRow: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let subreddit: RedditSubreddit
    let repository: RedditRepository
    @State private var isSubscribed: Bool

    init(subreddit: RedditSubreddit, repository: RedditRepository) {
        self.subreddit = subreddit
        self.repository = repository
        _isSubscribed = State(initialValue: subreddit.userIsSubscriber ?? false)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("r/\(subreddit.displayName)").font(.headline)
                if let subs = subreddit.subscribers {
                    Text(subs == 1 ? "1 subscriber" : "\(subs) subscribers").font(.caption).foregroundStyle(.secondary)
                }
                if let description = subreddit.publicDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(isSubscribed ? "Joined" : "Join") {
                Task { await toggleSubscribe() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func toggleSubscribe() async {
        let target = !isSubscribed
        isSubscribed = target
        do {
            try await repository.subscribe(subredditFullname: subreddit.name, subscribe: target)
        } catch {
            isSubscribed = !target
        }
    }
}

/// A Search landing row as Apollo draws it: the glyph in the accent colour, the
/// title in the label colour, and a chevron.
private struct SearchLandingRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Color.apolloAccent)
                .frame(width: 30)
            Text(title)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            ApolloSettingsChevron()
        }
        .contentShape(Rectangle())
    }
}
