#if canImport(WebKit) && canImport(UIKit)
import SwiftUI
import WebKit
import PhoebusCore

/// The Search tab's Google mode (Reborn #1260): Reddit threads found through
/// Google, with the time and Exact Words chips above, cards showing the
/// subreddit, title, Google's snippet (query terms bold) and its forum
/// line; Read More opens the card with the post's own text and Reddit's
/// numbers; tapping a card opens the thread natively.
struct GoogleSearchResultsView: View {
    let query: String
    let repository: RedditRepository
    let onOpen: (RedditURLTarget) -> Void

    @StateObject private var session = GoogleSearchSession()
    @State private var options = GoogleSearchOptions.load()
    @State private var results: [GoogleSearchResult] = []
    @State private var phase: Phase = .loading
    @State private var mayHaveMore = false
    @State private var nextPage = 1
    @State private var loadingMore = false
    @State private var moreFailed = false
    @State private var expanded: Set<String> = []
    @State private var readMoreLoading: Set<String> = []
    @State private var readMoreTried: Set<String> = []
    @State private var opening: String?
    @State private var shareURL: URL?
    @Environment(\.openURL) private var openURL

    enum Phase: Equatable {
        case loading, results
        case failed(title: String, detail: String)
    }

    var body: some View {
        List {
            Section {
                filterChips
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            switch phase {
            case .loading:
                status(spinning: true, title: nil,
                       detail: session.isSlow ? "Google is taking longer than usual." : "Searching Google\u{2026}")
            case .failed(let title, let detail):
                status(spinning: false, title: title, detail: detail, action: ("Try Again", { Task { await load(page: 0) } }))
            case .results:
                if results.isEmpty {
                    status(spinning: false, title: "No Reddit Results on Google", detail: emptyHint)
                }
                ForEach(results) { result in
                    card(result)
                        .onAppear { loadMoreIfNeeded(after: result) }
                }
                if mayHaveMore || loadingMore || moreFailed {
                    if moreFailed {
                        status(spinning: false, title: nil, detail: "Couldn't load more results.",
                               action: ("Try Again", { Task { await load(page: nextPage) } }))
                    } else {
                        status(spinning: true, title: nil, detail: nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .task(id: query) { await load(page: 0) }
        .onDisappear { session.cancel() }
        .sheet(isPresented: Binding(get: { session.verificationWebView != nil },
                                    set: { if !$0 { session.verificationCancelledByUser() } })) {
            if let web = session.verificationWebView {
                GoogleVerificationSheet(web: web) { session.verificationCancelledByUser() }
            }
        }
        .sheet(item: Binding(get: { shareURL.map(IdentifiedURL.init) }, set: { shareURL = $0?.url })) { item in
            ActivityShareSheet(items: [item.url])
        }
    }

    // MARK: Filters

    private var filterChips: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(GoogleSearchOptions.TimeRange.allCases, id: \.self) { range in
                    Button {
                        setOptions { $0.timeRange = range }
                    } label: {
                        if range == options.timeRange { Label(range.title, systemImage: "checkmark") } else { Text(range.title) }
                    }
                }
            } label: {
                chip(options.timeRange.title, systemImage: "clock", on: options.timeRange != .any, chevron: true)
            }
            Button {
                setOptions { $0.exactWords.toggle() }
            } label: {
                chip("Exact Words", systemImage: "text.quote", on: options.exactWords, chevron: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Google's Verbatim mode: no synonyms or spelling fixes.")
            Spacer()
        }
    }

    private func chip(_ title: String, systemImage: String, on: Bool, chevron: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
            if chevron { Image(systemName: "chevron.down").font(.caption2.weight(.semibold)) }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(on ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
    }

    private func setOptions(_ change: (inout GoogleSearchOptions) -> Void) {
        change(&options)
        options.save()
        Task { await load(page: 0) }
    }

    private var emptyHint: String {
        var tips = ["Try fewer or different words"]
        if options.exactWords { tips.append("turn off Exact Words") }
        if options.timeRange != .any { tips.append("pick a longer time range") }
        return tips.count == 1 ? tips[0] + "." : tips.dropLast().joined(separator: ", ") + " or " + tips.last! + "."
    }

    // MARK: Loading

    private func load(page: Int) async {
        if page == 0 {
            phase = .loading
            results = []
            expanded = []
            readMoreTried = []
            moreFailed = false
        } else {
            loadingMore = true
            moreFailed = false
        }
        do {
            let found = try await session.search(query, options: options, page: page)
            if page == 0 {
                results = found.results
            } else {
                let known = Set(results.map(\.dedupeKey))
                results += found.results.filter { !known.contains($0.dedupeKey) }
            }
            mayHaveMore = found.mayHaveMore && !found.results.isEmpty
            nextPage = page + 1
            phase = .results
        } catch is CancellationError {
            // A newer search took over; the bottom spinner must stop and paging
            // must resume.
            loadingMore = false
            return
        } catch {
            if page == 0 {
                let cancelled = (error as? GoogleSearchSession.SearchError).map {
                    if case .verificationCancelled = $0 { return true } else { return false }
                } ?? false
                phase = .failed(title: cancelled ? "Google Check Not Finished" : "Couldn't Search Google",
                                detail: error.localizedDescription)
            } else {
                moreFailed = true
            }
        }
        loadingMore = false
    }

    /// Asks for the next page while the last few are still coming in.
    private func loadMoreIfNeeded(after result: GoogleSearchResult) {
        guard phase == .results, mayHaveMore, !loadingMore, !moreFailed,
              let index = results.firstIndex(where: { $0.id == result.id }), index + 3 >= results.count else { return }
        Task { await load(page: nextPage) }
    }

    // MARK: Cards

    private func card(_ result: GoogleSearchResult) -> some View {
        let info = result.redditInfo
        let isExpanded = expanded.contains(result.id)
        let canReadMore = info == nil && !readMoreTried.contains(result.id)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                if let subreddit = result.subreddit ?? info?.subreddit {
                    Text("r/\(subreddit)")
                }
                if result.kind == .comment {
                    Text("·")
                    Text(info?.author.map { "Comment by u/\($0)" } ?? "Comment")
                }
                if info?.over18 == true { Text("NSFW").foregroundStyle(.red) }
                if info?.spoiler == true { Text("Spoiler") }
                Spacer()
                if opening == result.id { ProgressView().controlSize(.mini) }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            Text(info?.title ?? result.title)
                .font(.headline)
                .foregroundStyle(.primary)
            if isExpanded, let body = info?.body {
                Text(GoogleSearch.plainText(fromMarkdown: body))
                    .font(.subheadline)
            } else if !result.snippet.isEmpty {
                Text(Self.snippet(result))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 4)
            }
            HStack(spacing: 12) {
                stats(result)
                Spacer()
                if canReadMore || isExpanded || info?.body != nil {
                    Button(readMoreLoading.contains(result.id) ? "Loading\u{2026}" : isExpanded ? "Show Less" : "Read More") {
                        Task { await toggleReadMore(result) }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .disabled(readMoreLoading.contains(result.id))
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { Task { await open(result) } }
        .contextMenu {
            Button { Task { await open(result) } } label: { Label("Open", systemImage: "arrow.up.forward.app") }
            Button { Task { if let url = await resolvedURL(result) { openURL(url) } } } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            Button { Task { if let url = await resolvedURL(result) { UIPasteboard.general.url = url } } } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
            Button { Task { shareURL = await resolvedURL(result) } } label: {
                Label("Share\u{2026}", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityIdentifier("googleSearch.result")
    }

    @ViewBuilder
    private func stats(_ result: GoogleSearchResult) -> some View {
        if let info = result.redditInfo {
            HStack(spacing: 10) {
                Label(GoogleSearchRedditInfo.compactCount(info.score), systemImage: "arrow.up")
                if result.kind != .comment || info.commentCount > 0 {
                    Label(GoogleSearchRedditInfo.compactCount(info.commentCount), systemImage: "bubble.left")
                }
                if let created = info.created {
                    Label(GoogleSearchRedditInfo.compactAge(created), systemImage: "clock")
                }
                if result.kind != .comment {
                    switch info.media {
                    case .image: Label("Image", systemImage: "photo")
                    case .gallery: Label("Gallery", systemImage: "photo.on.rectangle")
                    case .video: Label("Video", systemImage: "play.rectangle")
                    case .link: if let domain = info.linkDomain { Label(domain, systemImage: "link") }
                    case .none: EmptyView()
                    }
                }
            }
            .labelStyle(CompactStatLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let meta = result.googleMeta {
            Text(meta).font(.caption).foregroundStyle(.secondary)
        }
    }

    private struct CompactStatLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) { configuration.icon.imageScale(.small); configuration.title }
        }
    }

    /// Google's snippet with the query terms it bolded.
    static func snippet(_ result: GoogleSearchResult) -> AttributedString {
        let attributed = NSMutableAttributedString(string: result.snippet)
        for range in result.snippetBoldRanges where NSMaxRange(range) <= attributed.length {
            attributed.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .subheadline).withTraits(.traitBold), range: range)
            attributed.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        }
        return (try? AttributedString(attributed, including: \.uiKit)) ?? AttributedString(result.snippet)
    }

    private func status(spinning: Bool, title: String?, detail: String?,
                        action: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            if spinning { ProgressView() }
            if let title { Text(title).font(.headline) }
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let action {
                Button(action.0, action: action.1).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowSeparator(.hidden)
    }

    // MARK: Actions

    private func update(_ id: String, _ change: (inout GoogleSearchResult) -> Void) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        change(&results[index])
    }

    /// Follows the result's Google link (its one "click"), keeping what it
    /// learns, so later actions don't click again.
    private func resolvedURL(_ result: GoogleSearchResult) async -> URL? {
        guard let resolved = await GoogleSearchSession.resolve(result) else { return nil }
        update(result.id) { $0 = GoogleSearchResult.merging(resolved, into: $0) }
        return resolved.url
    }

    private func open(_ result: GoogleSearchResult) async {
        opening = result.id
        defer { opening = nil }
        guard let url = await resolvedURL(result) else { return }
        onOpen(RedditURLTarget.parse(url))
    }

    /// First Read More: follow the link and read the post from Reddit,
    /// then open the card with its text and Reddit's own numbers. A
    /// failed Reddit read may be retried; a link that couldn't be
    /// followed stays as it is.
    private func toggleReadMore(_ result: GoogleSearchResult) async {
        let id = result.id
        if expanded.contains(id) { expanded.remove(id); return }
        if result.redditInfo == nil, !readMoreTried.contains(id) {
            readMoreLoading.insert(id)
            defer { readMoreLoading.remove(id) }
            guard let resolved = await GoogleSearchSession.resolve(result) else { readMoreTried.insert(id); return }
            let info = await repository.fetchGoogleResultInfo(postID: resolved.postID, commentID: resolved.commentID)
            update(id) {
                $0 = GoogleSearchResult.merging(resolved, into: $0)
                $0.redditInfo = info
            }
            if info != nil || resolved.postID == nil { readMoreTried.insert(id) }
        }
        expanded.insert(id)
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}

extension GoogleSearchResult {
    /// A followed result's Reddit identity, onto the card as shown (its id
    /// stays the card's, so the list doesn't reshuffle).
    static func merging(_ resolved: GoogleSearchResult, into card: GoogleSearchResult) -> GoogleSearchResult {
        var merged = card
        merged.url = resolved.url
        merged.kind = resolved.kind
        merged.subreddit = resolved.subreddit ?? card.subreddit
        merged.username = resolved.username
        merged.postID = resolved.postID
        merged.commentID = resolved.commentID
        return merged
    }
}

/// Google's check or consent page, handed to the user; the search goes on
/// by itself once Google returns to the results.
private struct GoogleVerificationSheet: View {
    let web: WKWebView
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Google wants to check this search before showing results. Finish the check below and your results will load.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
                HostedWebView(web: web)
            }
            .navigationTitle("Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
    }

    private struct HostedWebView: UIViewRepresentable {
        let web: WKWebView
        func makeUIView(context: Context) -> WKWebView { web }
        func updateUIView(_ view: WKWebView, context: Context) {}
    }
}
#endif
