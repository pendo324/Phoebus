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
    /// Opens a Reddit page on this tab's stack (a Google result).
    let onOpenTarget: (RedditURLTarget) -> Void
    /// "Search With" (Reborn #1260): Reddit is Apollo's own search;
    /// Google lists Reddit threads Google found, searched on Return.
    @State private var engine = SearchEngine.current
    /// The query Google was asked, set on Return or a suggestion.
    @State private var googleQuery = ""
    @State private var googleSuggestions: [String] = []

    public init(repository: RedditRepository, onSelect: @escaping (RedditSubreddit) -> Void,
                onOpenTarget: @escaping (RedditURLTarget) -> Void = { _ in }) {
        self.repository = repository
        self.onSelect = onSelect
        self.onOpenTarget = onOpenTarget
    }

    private var showsGoogle: Bool { engine == .google && !query.isEmpty }

    public var body: some View {
        Group {
            #if canImport(WebKit) && canImport(UIKit)
            if showsGoogle, !googleQuery.isEmpty, googleQuery == query {
                GoogleSearchResultsView(query: googleQuery, repository: repository, onOpen: onOpenTarget)
            } else if showsGoogle {
                googleSuggestionList
            } else {
                redditList
            }
            #else
            redditList
            #endif
        }
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: engine == .google ? "Search Reddit with Google" : "Search Posts, Subreddits, Users")
        .onSubmit(of: .search) {
            if engine == .google { googleQuery = query }
        }
        .onChange(of: query) { _, newValue in
            if engine == .google {
                Task { await loadSuggestions(newValue) }
            } else {
                Task { await search(newValue) }
            }
        }
        #if canImport(UIKit)
        .background(SearchEngineMagnifier(engine: engine) { picked in
            engine = picked
            SearchEngine.current = picked
            googleQuery = ""
            if picked == .reddit { Task { await search(query) } }
        }.frame(width: 0, height: 0))
        #endif
        .apolloFlatListAppearance()
        // No navigation title: the Search tab shows none, so the search field sits
        // directly under the status bar with "TRENDING SUBREDDITS" first below it.
        .navigationTitle("")
        .navigationBarTitleDisplayModeIfAvailable()
    }

    /// While typing in Google mode: Google's own suggestions, under a row
    /// that searches exactly what was typed.
    private var googleSuggestionList: some View {
        List {
            Button {
                googleQuery = query
            } label: {
                Label("Search Google for \u{201C}\(query)\u{201D}", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("googleSearch.submit")
            ForEach(googleSuggestions, id: \.self) { suggestion in
                Button {
                    query = suggestion
                    googleQuery = suggestion
                } label: {
                    Label(suggestion, systemImage: "magnifyingglass").foregroundStyle(.primary)
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Searches Reddit through Google. Add r/name to search one subreddit, put a phrase in \"quotes\" to match it exactly, or add -word to leave a word out.")
                    .apolloSectionFooter()
            }
        }
        .apolloFlatListAppearance()
    }

    private func loadSuggestions(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { googleSuggestions = []; return }
        #if canImport(WebKit) && canImport(UIKit)
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard text == query else { return }
        let found = await GoogleSearchSession.suggestions(for: trimmed)
        guard text == query else { return }
        googleSuggestions = Array(found.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }.prefix(8))
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
                // follow in a separate, header-less section.
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
