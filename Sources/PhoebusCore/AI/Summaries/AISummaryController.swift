import Foundation
#if canImport(Combine)
import Combine
#endif

/// Drives the two inline AI summary cards for one open thread
/// (Apollo AI Summary tweak). Display-time gating on the sub-toggles
/// hides an already-generated card rather than only future ones;
/// `AISummaryMode` decides whether generation starts on open and
/// whether the card opens expanded; expansion is remembered per post.
@MainActor
public final class AISummaryController {
    /// Hand-rolled instead of `ObservableObject`/`@Published`: Combine
    /// is unavailable on Linux. The view observes via `objectWillChange`.
    #if canImport(Combine)
    public let objectWillChange = ObservableObjectPublisher()
    #endif

    private func changed() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }

    public private(set) var postState: AISummaryCard.State = .none {
        didSet { if postState != oldValue { changed() } }
    }
    public private(set) var commentState: AISummaryCard.State = .none {
        didSet { if commentState != oldValue { changed() } }
    }
    public var postExpanded = false {
        didSet { if postExpanded != oldValue { changed() } }
    }
    public var commentExpanded = false {
        didSet { if commentExpanded != oldValue { changed() } }
    }
    /// How many comments the discussion summary actually read, for the
    /// "Based on N representative comments" caption.
    public private(set) var commentSourceCount = 0
    public private(set) var postKind: AISummaryCard.Kind = .post
    /// The provider named in the ready card's caption. Read from the
    /// live settings rather than captured once, so a provider change
    /// mid-thread can't mislabel where the text was sent.
    public var provider: AIProvider { settings.provider }

    private let post: RedditPost
    private var settings: ApolloAISettings
    private var didStart = false
    /// Whether the post has anything to summarize at the current word
    /// threshold. Resolved when settings change, not per render: the
    /// detector runs regexes over the whole selftext.
    private var hasPostCardKind: Bool

    public init(post: RedditPost, settings: ApolloAISettings) {
        self.post = post
        self.settings = settings
        // The card's identity is fixed by the post, not by a setting.
        let kind = AIArticleDetector.postCardKind(for: post, wordThreshold: settings.postWordThreshold)
        postKind = kind ?? .post
        hasPostCardKind = kind != nil
        postExpanded = Self.rememberedExpansion(fullname: post.name, isPost: true)
            ?? settings.summaryMode.autoExpand
        commentExpanded = Self.rememberedExpansion(fullname: post.name, isPost: false)
            ?? settings.summaryMode.autoExpand
    }

    /// Whether a post card should exist: master toggle, post
    /// sub-toggle, and something summarizable, all required.
    public var showsPostCard: Bool {
        settings.summariesEnabled && settings.postSummariesEnabled
            && hasPostCardKind
    }

    /// Whether a discussion card should exist: at least `minComments`
    /// eligible comments and `minCommentChars` of gathered text.
    public func showsCommentCard(commentCount: Int) -> Bool {
        settings.summariesEnabled && settings.commentSummariesEnabled
            && commentCount >= AICommentSelector.minComments
    }

    /// Called when the thread opens. Honours the three-way mode:
    /// `.tapToSummarize` parks the post card in its idle state and
    /// generates nothing until tapped.
    public func onAppear() {
        // Resume a discussion summary that `pause()` interrupted.
        if commentState == .none, !settings.summaryMode.tapToSummarize, let pendingComments,
           settings.summariesEnabled, settings.commentSummariesEnabled {
            generateCommentSummary(pendingComments)
        }
        guard !didStart, settings.summariesEnabled else { return }
        didStart = true
        guard showsPostCard else { return }
        if settings.summaryMode.tapToSummarize {
            postState = .tapToSummarize
        } else {
            generatePostSummary()
        }
    }

    /// Comments finished loading; start (or park) the discussion card.
    ///
    /// `candidates` is the whole loaded tree - the selector, not the
    /// caller, decides which comments are representative.
    public func commentsDidLoad(candidates: [AICommentSelector.Candidate]) {
        guard settings.summariesEnabled, settings.commentSummariesEnabled else {
            commentState = .none
            return
        }
        let gathered = AICommentSelector.gather(candidates)
        guard AICommentSelector.hasEnoughDiscussion(text: gathered.text, count: gathered.count) else {
            commentState = .none
            return
        }
        pendingComments = gathered
        if settings.summaryMode.tapToSummarize {
            if commentState == .none { commentState = .tapToSummarize }
            return
        }
        guard commentState == .none || commentState == .tapToSummarize else { return }
        generateCommentSummary(gathered)
    }

    /// The most recent gathered comment set, so a later tap (Tap to
    /// Summarize) summarizes the same text the card was offered for.
    private var pendingComments: (text: String, count: Int)?

    /// The idle card was tapped under Tap to Summarize. Stays
    /// collapsed while generating and opens once ready via a pending
    /// open-on-ready flag, avoiding the text visibly streaming into an
    /// already-expanded card.
    public func tapToGeneratePost() {
        guard case .tapToSummarize = postState else { return }
        postExpandOnReady = true
        generatePostSummary()
    }

    public func tapToGenerateComments() {
        guard case .tapToSummarize = commentState, let pendingComments else { return }
        commentExpandOnReady = true
        generateCommentSummary(pendingComments)
    }

    /// Set by a Tap-to-Summarize tap; consumed when the summary lands.
    private var postExpandOnReady = false
    private var commentExpandOnReady = false

    /// Applies a pending open-on-ready once a summary has arrived.
    /// Only a READY summary opens the card; an error stays collapsed
    /// behind its one-line subtitle, as Reborn's ready handler does.
    private func applyExpandOnReady(isPost: Bool) {
        if isPost {
            guard postExpandOnReady, case .ready = postState else { return }
            postExpandOnReady = false
            if !postExpanded { toggleExpansion(isPost: true) }
        } else {
            guard commentExpandOnReady, case .ready = commentState else { return }
            commentExpandOnReady = false
            if !commentExpanded { toggleExpansion(isPost: false) }
        }
    }

    /// Re-applies changed settings to an OPEN thread.
    ///
    /// Display-time gating: flipping a sub-toggle off must hide a card
    /// that already generated, not just suppress future ones.
    public func settingsChanged(to newSettings: ApolloAISettings) {
        if newSettings.postWordThreshold != settings.postWordThreshold {
            hasPostCardKind = AIArticleDetector.postCardKind(
                for: post, wordThreshold: newSettings.postWordThreshold) != nil
        }
        settings = newSettings
        if !newSettings.summariesEnabled {
            postState = .none
            commentState = .none
            return
        }
        if !newSettings.postSummariesEnabled { postState = .none }
        if !newSettings.commentSummariesEnabled { commentState = .none }
    }

    public func toggleExpansion(isPost: Bool) {
        // A manual expand/collapse supersedes any pending open-on-ready
        // intent.
        if isPost { postExpandOnReady = false } else { commentExpandOnReady = false }
        if isPost {
            postExpanded.toggle()
            Self.rememberExpansion(fullname: post.name, isPost: true, expanded: postExpanded)
        } else {
            commentExpanded.toggle()
            Self.rememberExpansion(fullname: post.name, isPost: false, expanded: commentExpanded)
        }
    }

    private var postTask: Task<Void, Never>?
    private var commentTask: Task<Void, Never>?

    /// The thread left the screen: stop paying for requests nobody will
    /// read. Finished summaries stay; interrupted ones restart (or come
    /// from the cache) on the next `onAppear`.
    public func pause() {
        postTask?.cancel()
        commentTask?.cancel()
        if postState == .loading {
            postState = .none
            didStart = false
        }
        if commentState == .loading { commentState = .none }
    }

    private func generatePostSummary() {
        let detail = settings.postDetail
        let cacheKey = "\(post.name).post.\(detail.rawValue)"
        if let cached = AISummaryCache.summary(for: cacheKey) {
            postState = .ready(cached)
            applyExpandOnReady(isPost: true)
            return
        }
        postState = .loading
        let maxChars = AISummaryPrompts.maxPostChars(detail)
        // Only the post's own text is sent, capped at Reborn's per-detail
        // character limit. The comment card gets its own request; they are never
        // one combined prompt.
        var text = "Title: \(post.title)"
        let bodyless = DevvitPostDetector.aiShouldTreatAsBodyless(
            post: post, devvitInteractivePosts: true)
        let selftext = bodyless ? "" : (post.selftext ?? "")
        if !selftext.isEmpty {
            text += "\n\n" + String(selftext.prefix(maxChars))
        }
        let postText = text
        let kind = postKind
        let articleURL = (kind == .link || kind == .postAndLink) ? AIArticleDetector.articleURL(for: post) : nil
        let articleKey = post.name
        let settingsCopy = settings
        postTask?.cancel()
        postTask = Task { [weak self] in
            do {
                // Link and Post & link cards read the article itself; an
                // unreadable page falls back to the post, or to "Nothing to summarize".
                var target: ApolloAIClient.Target = .post
                var input = postText
                if let articleURL {
                    let article = await AIArticleExtractor.articleText(urlString: articleURL, cacheKey: articleKey)
                    guard !Task.isCancelled else { return }
                    if let article {
                        if kind == .postAndLink, !selftext.isEmpty {
                            target = .postAndLink
                            input = "Post:\n\(postText)\n\nLinked article:\n\(article.prefix(2000))"
                        } else {
                            target = .article
                            input = article
                        }
                    } else if kind == .link || selftext.isEmpty {
                        self?.postState = .empty
                        return
                    }
                }
                let summary = try await ApolloAIClient.summarize(
                    text: input, settings: settingsCopy, target: target)
                AISummaryCache.store(summary, for: cacheKey)
                guard !Task.isCancelled else { return }
                self?.postState = .ready(summary)
                self?.applyExpandOnReady(isPost: true)
            } catch {
                guard !Task.isCancelled else { return }
                self?.postState = Self.failureState(error)
            }
        }
    }

    private func generateCommentSummary(_ gathered: (text: String, count: Int)) {
        commentSourceCount = gathered.count
        // Keyed by how many comments were read, so a thread that has
        // grown gets a fresh summary.
        let cacheKey = "\(post.name).comments.\(settings.commentDetail.rawValue).\(gathered.count)"
        if let cached = AISummaryCache.summary(for: cacheKey) {
            commentState = .ready(cached)
            applyExpandOnReady(isPost: false)
            return
        }
        commentState = .loading
        let text = gathered.text
        let settingsCopy = settings
        commentTask?.cancel()
        commentTask = Task { [weak self] in
            do {
                let summary = try await ApolloAIClient.summarize(
                    text: text, settings: settingsCopy, target: .comments)
                AISummaryCache.store(summary, for: cacheKey)
                guard !Task.isCancelled else { return }
                self?.commentState = .ready(summary)
                self?.applyExpandOnReady(isPost: false)
            } catch {
                guard !Task.isCancelled else { return }
                self?.commentState = Self.failureState(error)
            }
        }
    }

    /// An empty result is `.empty` ("Nothing to summarize"), not an
    /// error: that terminal state is reserved for a tapped link with
    /// no usable prose, which is a normal outcome rather than a
    /// failure to report.
    private static func failureState(_ error: Error) -> AISummaryCard.State {
        if let aiError = error as? ApolloAIClient.AIError, aiError == .invalidResponse {
            return .empty
        }
        let message = (error as? LocalizedError)?.errorDescription
            ?? "Couldn't generate this summary."
        return .error(message)
    }

    // MARK: - Remembered expansion

    /// Kept for the session only, as Reborn keeps it on the thread's
    /// header; persisting it would add defaults keys per post indefinitely.
    private static var expansions: [String: Bool] = [:]

    private static func expansionKey(fullname: String, isPost: Bool) -> String {
        "\(isPost ? "post" : "comment").\(fullname)"
    }

    static func rememberedExpansion(fullname: String, isPost: Bool) -> Bool? {
        expansions[expansionKey(fullname: fullname, isPost: isPost)]
    }

    static func rememberExpansion(fullname: String, isPost: Bool, expanded: Bool) {
        expansions[expansionKey(fullname: fullname, isPost: isPost)] = expanded
    }
}
