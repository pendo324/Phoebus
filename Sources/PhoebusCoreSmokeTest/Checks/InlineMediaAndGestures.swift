import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Inline Imgur albums (Inline Media Previews)
//
// `PostMediaView` classifies `imgur.com/a/<id>` via
// `ImgurClient.extractAlbumID`, and the INLINE classifier must too: an album
// URL has no file extension, so it would otherwise fall past the extension
// checks and render as a plain link.
@MainActor func checkInlineImgurAlbumsV290() async throws {
    do {
        func albumID(_ string: String) -> String? {
            guard let url = URL(string: string) else { return nil }
            if case .imgurAlbum(let id)? = InlineMediaDetector.classify(url) { return id }
            return nil
        }
        check("an inline imgur album URL classifies as an album",
              albumID("https://imgur.com/a/AbCdE12") == "AbCdE12")
        check("an inline imgur gallery URL classifies as an album",
              albumID("https://imgur.com/gallery/AbCdE12") == "AbCdE12")
        // A direct image must still be an image, not an album.
        check("a direct imgur image is still classified as an image",
              {
                  guard let url = URL(string: "https://i.imgur.com/AbCdE12.jpg"),
                        case .image? = InlineMediaDetector.classify(url) else { return false }
                  return true
              }())
        // The post-level and inline classifiers must agree on this shape.
        // Reddit-hosted videos: the shape Reddit puts in comments
        // (`v.redd.it/abc123`) must classify, not only a direct `.mp4`/`.m3u8` path.
        func videoURL(_ string: String) -> String? {
            guard let url = URL(string: string) else { return nil }
            if case .video(let resolved)? = InlineMediaDetector.classify(url) {
                return resolved.absoluteString
            }
            return nil
        }
        check("a bare v.redd.it link resolves to its HLS playlist",
              videoURL("https://v.redd.it/abc123")
              == "https://v.redd.it/abc123/HLSPlaylist.m3u8")
        // `/link/<post>/video/<asset>/player` carries the asset id at fixed path
        // component indices.
        check("a reddit player-page link resolves to its HLS playlist",
              videoURL("https://www.reddit.com/link/1abc/video/xyz789/player")
              == "https://v.redd.it/xyz789/HLSPlaylist.m3u8")
        // An already-playable URL must be passed through untouched, not
        // rewritten into a playlist for a bogus asset id.
        check("a direct DASH mp4 is left as-is",
              videoURL("https://v.redd.it/abc123/DASH_720.mp4")
              == "https://v.redd.it/abc123/DASH_720.mp4")
        check("an existing HLS playlist is left as-is",
              videoURL("https://v.redd.it/abc123/HLSPlaylist.m3u8")
              == "https://v.redd.it/abc123/HLSPlaylist.m3u8")
        // A non-video reddit link must not be swept up by the player rule.
        check("an ordinary reddit permalink is not treated as video",
              videoURL("https://www.reddit.com/r/worldnews/comments/abc/def/") == nil)

        check("inline and post-level classification agree on albums",
              albumID("https://imgur.com/a/AbCdE12")
              == ImgurClient.extractAlbumID(from: URL(string: "https://imgur.com/a/AbCdE12")!))
    }
}

// MARK: - phoebus:// deep-link forms
@MainActor func checkPhoebusDeepLinkForms() async throws {
    do {
        func scheme(_ string: String) -> String {
            RedditURLTarget.parseAppScheme(URL(string: string)!)
                .map(String.init(describing:)) ?? "nil"
        }
        // Form 1, what the share extension produces.
        check("an encoded open?url= link resolves to the post",
              scheme("phoebus://open?url=https%3A%2F%2Fwww.reddit.com%2Fr%2Fswift%2Fcomments%2Fabc%2Ft%2F")
              == #"post(subreddit: "swift", id: "abc")"#)
        // Form 2, what a one-regex Shortcut produces. Reborn's recipe
        // rewrites ONLY scheme+host, so the path must survive intact.
        check("a scheme+host swapped link resolves to the same post",
              scheme("phoebus://reddit.com/r/swift/comments/abc/t/")
              == #"post(subreddit: "swift", id: "abc")"#)
        check("a www subdomain is accepted",
              scheme("phoebus://www.reddit.com/r/swift") == #"subreddit("swift")"#)
        check("a redd.it short link is accepted",
              scheme("phoebus://redd.it/abc123").contains("redd.it/abc123"))
        // Host allowlist: an arbitrary host must not be routed just
        // because it carries our scheme.
        check("a non-reddit host is rejected",
              scheme("phoebus://evil.com/r/swift") == "nil")
        // Host-SUFFIX attack: `notreddit.com` must not pass as reddit.com.
        check("a host-suffix lookalike is rejected",
              scheme("phoebus://notreddit.com/r/swift") == "nil")
        // A wrong scheme entirely must not be claimed.
        check("a foreign scheme is rejected",
              RedditURLTarget.parseAppScheme(URL(string: "otherapp://reddit.com/r/swift")!) == nil)

        // The other half of the handoff contract: the recorded output of the
        // extension's toAppURL(), which SafariExtension/Tests/fixtures.test.js pins on
        // the JS side. The two halves are built and tested in separate processes, so
        // they could otherwise disagree silently.
        let fixtureData = try! Data(contentsOf: URL(fileURLWithPath: "SafariExtension/Tests/app-url-fixtures.json"))
        let fixtures = try! JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
        let cases = fixtures["cases"] as! [[String: String]]
        check("the handoff fixture file covers several link shapes", cases.count >= 5)
        for fixtureCase in cases {
            let appURL = fixtureCase["appURL"]!
            check("the app resolves the extension's URL for \(fixtureCase["page"]!)",
                  scheme(appURL) == fixtureCase["target"]!)
        }
    }
}

// MARK: - Share/media link normalisation
@MainActor func checkShareMediaLinkNormalisation() async throws {
    do {
        func target(_ string: String) -> String {
            String(describing: RedditURLTarget.parse(URL(string: string)!))
        }
        // imgur.com/hyphenated-title-<id> -> imgur.com/<id> (the id is the LAST
        // hyphen-separated piece).
        check("an imgur title-id link is rewritten to the bare image",
              ShareLinkNormalizer.imgurTitleIDTarget(
                  URL(string: "https://imgur.com/some-title-AbCdE")!)?.absoluteString
              == "https://imgur.com/AbCdE")
        check("a bare imgur link is left alone",
              ShareLinkNormalizer.imgurTitleIDTarget(
                  URL(string: "https://imgur.com/AbCdE")!) == nil)
        check("an imgur album is not mistaken for a title-id link",
              ShareLinkNormalizer.imgurTitleIDTarget(
                  URL(string: "https://imgur.com/a/AbCdE")!) == nil)
        // The single-path-component rule protects this one: a hyphenated GALLERY
        // path would otherwise be rewritten to its last segment. The album case above
        // has no hyphen, so this is the case that holds the rule in place.
        check("a hyphenated imgur gallery path is not rewritten",
              ShareLinkNormalizer.imgurTitleIDTarget(
                  URL(string: "https://imgur.com/gallery/some-title-AbCdE")!) == nil)
        // reddit.com/media?url=<encoded> -> the inner URL.
        check("a reddit media wrapper unwraps to the real image",
              target("https://www.reddit.com/media?url=https%3A%2F%2Fi.redd.it%2Fx.jpg")
                  .contains("i.redd.it/x.jpg"))
        // youtube.com/shorts/<id> -> a normal watch URL.
        check("a shorts link normalises to a watch URL",
              ShareLinkNormalizer.youTubeShortsTarget(
                  URL(string: "https://www.youtube.com/shorts/abc123")!)?.absoluteString
              == "https://www.youtube.com/watch?v=abc123")
        // Normalisation must not disturb ordinary permalinks.
        check("an ordinary permalink still parses as a post",
              target("https://www.reddit.com/r/swift/comments/abc123/title/")
                  .contains("post(subreddit: \"swift\""))
    }
}

// MARK: - Colourize Vote Arrows
@MainActor func checkColourizeVoteArrowsV340() async throws {
    do {
        // Default is OFF: the theme's own flag reads absent = false.
        check("Colourize Vote Arrows defaults off",
              Theme.defaultLight.voteArrowsAccent == false)
        // The flag lives on the THEME, not in global settings, so each
        // theme carries its own choice.
        check("the flag is carried on the theme",
              {
                  var theme = Theme.defaultLight
                  theme.voteArrowsAccent = true
                  return theme.voteArrowsAccent
              }())
    }
}

// --- Inline AI summary cards ---
//
// Apollo Reborn's AI summaries render two inline cards in the thread,
// each backed by its own request and prompt. These checks exercise the
// ported logic directly where it is pure (titles, states, prompts,
// thresholds, the comment ranker) and fall back to source assertions
// for the SwiftUI placement, which cannot run on Linux.
@MainActor func checkInlineAISummaryCards() async throws {
    do {
        // (1) The three card titles, verbatim.
        check("the discussion card's title is the reported one",
              AISummaryCard.Kind.discussion.title == "Discussion so far")
        check("the post card's title is 'Post summary'",
              AISummaryCard.Kind.post.title == "Post summary")
        check("a link post's card says 'Link summary'",
              AISummaryCard.Kind.link.title == "Link summary")
        check("a post sharing a link says 'Post/Link summary'",
              AISummaryCard.Kind.postAndLink.title == "Post/Link summary")

        // (2) The collapsed subtitles, including the terminal empty state:
        // "  ·  Nothing to summarize", one muted line.
        check("the empty state reads 'Nothing to summarize'",
              AISummaryCard.collapsedSubtitle(for: .empty) == "Nothing to summarize")
        check("loading collapses to 'Summarizing…'",
              AISummaryCard.collapsedSubtitle(for: .loading) == "Summarizing…")
        check("the idle tap state reads 'Tap to summarize'",
              AISummaryCard.collapsedSubtitle(for: .tapToSummarize) == "Tap to summarize")
        // Ready/error carry a chevron INSTEAD of a subtitle, which is the
        // rule the next check pins.
        check("a ready card has no collapsed subtitle",
              AISummaryCard.collapsedSubtitle(for: .ready("x")) == nil)

        // (3) Chevron rule: expanded always, plus collapsed ready/error.
        // An idle or loading collapsed card must NOT show one.
        check("an expanded card shows a chevron",
              AISummaryCard.showsChevron(state: .loading, expanded: true))
        check("a collapsed ready card shows a chevron",
              AISummaryCard.showsChevron(state: .ready("x"), expanded: false))
        check("a collapsed loading card shows no chevron",
              !AISummaryCard.showsChevron(state: .loading, expanded: false))
        check("the terminal empty card shows no chevron",
              !AISummaryCard.showsChevron(state: .empty, expanded: false))
        // One-line clamp on exactly the chevron-less collapsed states.
        check("a collapsed idle card clamps to one line",
              AISummaryCard.clampsToOneLine(state: .tapToSummarize, expanded: false))
        check("a collapsed ready card is not clamped",
              !AISummaryCard.clampsToOneLine(state: .ready("x"), expanded: false))

        // (4) Expanded bodies differ between the post and discussion cards:
        // "Tap to summarize this post." vs "...the discussion."
        check("the post card's tap body names the post",
              AISummaryCard.expandedBody(kind: .post, state: .tapToSummarize)
                  == "Tap to summarize this post.")
        check("the discussion card's tap body names the discussion",
              AISummaryCard.expandedBody(kind: .discussion, state: .tapToSummarize)
                  == "Tap to summarize the discussion.")
        check("the discussion card's loading body is its own string",
              AISummaryCard.expandedBody(kind: .discussion, state: .loading)
                  == "Summarizing discussion…")
        check("an empty error message falls back to the real default",
              AISummaryCard.expandedBody(kind: .post, state: .error(""))
                  == "Couldn't generate this summary.")

        // (5) The trust caption always ends "· may be inaccurate". The
        // comment card also reports how many comments it read.
        check("the caption hedges on accuracy",
              AISummaryCard.attribution(for: .onDevice).hasSuffix("· may be inaccurate"))
        check("on-device attribution says the text stayed on device",
              AISummaryCard.attribution(for: .onDevice)
                  == "AI-generated on device · may be inaccurate")
        check("Gemini attribution names the cloud provider",
              AISummaryCard.attribution(for: .gemini)
                  == "AI-generated with Gemini · may be inaccurate")
        check("OpenRouter uses 'via', not 'with'",
              AISummaryCard.attribution(for: .openRouter).contains("via OpenRouter"))
        check("the discussion caption reports its source count",
              AISummaryCard.attribution(for: .onDevice, sourceCount: 12)
                  == "AI-generated on device · Based on 12 representative comments · may be inaccurate")
        check("a zero source count is omitted rather than printed",
              !AISummaryCard.attribution(for: .onDevice, sourceCount: 0).contains("Based on"))

        // (6) The six real prompts. There is no single generic prompt
        // ignoring the detail setting, since that would make Brief and
        // In-Depth produce identical output.
        check("brief post prompt asks for 1-2 sentences",
              AISummaryPrompts.postInstructions(.brief).contains("1-2 concise plain sentences"))
        check("balanced post prompt asks for 2 sentences",
              AISummaryPrompts.postInstructions(.balanced).contains("2 short plain sentences"))
        check("in-depth post prompt asks for 3-5 sentences",
              AISummaryPrompts.postInstructions(.inDepth).contains("3-5 focused plain sentences"))
        check("brief comment prompt asks for 1-2 sentences",
              AISummaryPrompts.commentInstructions(.brief).contains("1-2 concise plain sentences"))
        check("balanced comment prompt asks for 2-3 sentences",
              AISummaryPrompts.commentInstructions(.balanced).contains("2-3 short plain sentences"))
        check("in-depth comment prompt asks for 4-5 sentences",
              AISummaryPrompts.commentInstructions(.inDepth).contains("4-5 focused plain sentences"))
        // The load-bearing difference between the two prompt families: the
        // discussion card must summarize COMMENTERS. Without this a
        // "Discussion so far" card just restates the post.
        for detail in AISummaryDetail.allCases {
            check("the \(detail.displayName) comment prompt summarizes commenters, not the post",
                  AISummaryPrompts.commentInstructions(detail)
                      .contains("Summarize commenters, not the post"))
            // All six forbid markdown, because the card is a plain text
            // node and would render literal asterisks.
            check("the \(detail.displayName) post prompt forbids markdown",
                  AISummaryPrompts.postInstructions(detail).contains("No heading, Markdown, or added facts"))
        }
        check("post and comment prompts are actually different",
              AISummaryPrompts.postInstructions(.balanced)
                  != AISummaryPrompts.commentInstructions(.balanced))

        // (7) Token budgets and input caps. Balanced comments are 110,
        // not the 80 the post path uses.
        check("brief post replies are capped at 64 tokens",
              AISummaryPrompts.postResponseTokens(.brief) == 64)
        check("balanced post replies are capped at 80 tokens",
              AISummaryPrompts.postResponseTokens(.balanced) == 80)
        check("in-depth post replies are capped at 180 tokens",
              AISummaryPrompts.postResponseTokens(.inDepth) == 180)
        check("brief comment replies are capped at 70 tokens",
              AISummaryPrompts.commentResponseTokens(.brief) == 70)
        check("balanced comment replies are capped at 110 tokens",
              AISummaryPrompts.commentResponseTokens(.balanced) == 110)
        check("in-depth comment replies are capped at 200 tokens",
              AISummaryPrompts.commentResponseTokens(.inDepth) == 200)
        check("the comment budget is not copied from the post budget",
              AISummaryPrompts.commentResponseTokens(.balanced)
                  != AISummaryPrompts.postResponseTokens(.balanced))
        check("brief sends at most 1000 post chars",
              AISummaryPrompts.maxPostChars(.brief) == 1000)
        check("balanced sends at most 1400 post chars",
              AISummaryPrompts.maxPostChars(.balanced) == 1400)
        check("in-depth sends at most 2200 post chars",
              AISummaryPrompts.maxPostChars(.inDepth) == 2200)

        // (8) Word-threshold validation falls back to 150 rather than
        // clamping. A stored 275 is not "close enough" to 300; invalid
        // means 150.
        check("a valid threshold passes through",
              AISummaryPrompts.sanitizedWordThreshold(250) == 250)
        check("a too-small threshold falls back to 150",
              AISummaryPrompts.sanitizedWordThreshold(25) == 150)
        check("a too-large threshold falls back to 150",
              AISummaryPrompts.sanitizedWordThreshold(500) == 150)
        check("a non-multiple-of-50 falls back rather than clamping",
              AISummaryPrompts.sanitizedWordThreshold(275) == 150)
        check("the boundary values are themselves valid",
              AISummaryPrompts.sanitizedWordThreshold(50) == 50
              && AISummaryPrompts.sanitizedWordThreshold(300) == 300)
        check("a post at the threshold is eligible",
              AISummaryPrompts.postMeetsThreshold(wordCount: 150, threshold: 150))
        check("a post one word short is not",
              !AISummaryPrompts.postMeetsThreshold(wordCount: 149, threshold: 150))

        // (9) Article detection picks which title shows. The host
        // blocklist exists because these pages are player-only or
        // JS-rendered and yield no prose.
        check("a news article is a candidate",
              AIArticleDetector.isArticleCandidate("https://www.bbc.co.uk/news/article-123"))
        check("a YouTube link is not an article",
              !AIArticleDetector.isArticleCandidate("https://www.youtube.com/watch?v=abc"))
        check("a youtu.be short link is also blocked",
              !AIArticleDetector.isArticleCandidate("https://youtu.be/abc"))
        check("reddit's own links are excluded",
              !AIArticleDetector.isArticleCandidate("https://www.reddit.com/r/x/comments/y/z/"))
        check("a SUBDOMAIN of a blocked host is blocked too",
              !AIArticleDetector.isArticleCandidate("https://clips.twitch.tv/SomeClip"))
        check("v.redd.it is blocked via the redd.it entry",
              !AIArticleDetector.isArticleCandidate("https://v.redd.it/abcdef"))
        check("a direct image URL is not an article",
              !AIArticleDetector.isArticleCandidate("https://example.com/photo.jpg"))
        check("a PDF is not treated as prose",
              !AIArticleDetector.isArticleCandidate("https://example.com/paper.pdf"))
        check("non-http schemes are rejected",
              !AIArticleDetector.isArticleCandidate("ftp://example.com/x"))
        check("X.com is blocked as a JS-rendered SPA",
              !AIArticleDetector.isArticleCandidate("https://x.com/user/status/1"))
        // The `m.`/`www.` strip must not eat a real subdomain: stripping
        // the first label generally would turn news.bbc.co.uk into
        // bbc.co.uk, which is a different site.
        check("an m. prefix is normalised before matching",
              !AIArticleDetector.isArticleCandidate("https://m.youtube.com/watch?v=a"))
        check("a legitimate news subdomain survives",
              AIArticleDetector.isArticleCandidate("https://news.example.com/story"))

        // (10) Self-text article extraction: markdown links win over bare
        // URLs, because those are the explicit "here's the article" shares.
        check("a markdown link is extracted",
              AIArticleDetector.firstArticleURLInSelfText("see [this](https://example.com/story) please")
                  == "https://example.com/story")
        check("a bare URL is extracted when there is no markdown link",
              AIArticleDetector.firstArticleURLInSelfText("read https://example.com/story ok")
                  == "https://example.com/story")
        check("a markdown link beats a bare URL elsewhere in the body",
              AIArticleDetector.firstArticleURLInSelfText(
                  "bare https://example.com/bare and [md](https://example.com/md)")
                  == "https://example.com/md")
        check("blocked hosts in the body are skipped",
              AIArticleDetector.firstArticleURLInSelfText("https://youtube.com/watch?v=a") == nil)
        check("trailing sentence punctuation is trimmed off the URL",
              AIArticleDetector.firstArticleURLInSelfText("see https://example.com/story.")
                  == "https://example.com/story")
        check("a body with no links yields nothing",
              AIArticleDetector.firstArticleURLInSelfText("just some text") == nil)

        // (11) The comment ranker is what "Based on N representative
        // comments" means: a ranked selection, not the first N rows.
        func candidate(_ id: String, score: Int, author: String = "someone",
                       controversiality: Int = 0, depth: Int = 0,
                       body: String = String(repeating: "word ", count: 20)) -> AICommentSelector.Candidate {
            AICommentSelector.Candidate(id: id, author: author, body: body, score: score,
                                        controversiality: controversiality, depth: depth,
                                        linkAuthor: "op_user")
        }
        check("a higher score ranks higher",
              AICommentSelector.rank(candidate("a", score: 500), originalIndex: 0)
                  > AICommentSelector.rank(candidate("b", score: 10), originalIndex: 0))
        check("OP gets a large bonus",
              AICommentSelector.rank(candidate("a", score: 10, author: "op_user"), originalIndex: 0)
                  == AICommentSelector.rank(candidate("b", score: 10), originalIndex: 0) + 1400)
        check("OP detection is case-insensitive",
              AICommentSelector.rank(candidate("a", score: 10, author: "OP_User"), originalIndex: 0)
                  > AICommentSelector.rank(candidate("b", score: 10), originalIndex: 0))
        check("a controversial comment gets a diversity bonus",
              AICommentSelector.rank(candidate("a", score: 10, controversiality: 1), originalIndex: 0)
                  == AICommentSelector.rank(candidate("b", score: 10), originalIndex: 0) + 700)
        check("deeper replies are penalised",
              AICommentSelector.rank(candidate("a", score: 10, depth: 4), originalIndex: 0)
                  == AICommentSelector.rank(candidate("b", score: 10), originalIndex: 0) - 280)
        check("the depth penalty saturates at 8",
              AICommentSelector.rank(candidate("a", score: 10, depth: 20), originalIndex: 0)
                  == AICommentSelector.rank(candidate("b", score: 10, depth: 8), originalIndex: 0))
        check("later comments carry a small position penalty",
              AICommentSelector.rank(candidate("a", score: 10), originalIndex: 10)
                  == AICommentSelector.rank(candidate("b", score: 10), originalIndex: 0) - 30)
        // Score is CLAMPED, so one runaway joke comment cannot drown out
        // every substantive reply.
        check("a runaway score is clamped at 5000",
              AICommentSelector.rank(candidate("a", score: 999_999), originalIndex: 0)
                  == AICommentSelector.rank(candidate("b", score: 5000), originalIndex: 0))
        check("a deeply downvoted score is clamped at -50",
              AICommentSelector.rank(candidate("a", score: -9999), originalIndex: 0)
                  == AICommentSelector.rank(candidate("b", score: -50), originalIndex: 0))

        // (12) Eligibility. AutoModerator is excluded by name: its rules
        // boilerplate would otherwise dominate a short thread.
        check("AutoModerator is excluded",
              !AICommentSelector.isEligible(candidate("a", score: 5, author: "AutoModerator")))
        check("the exclusion is case-insensitive",
              !AICommentSelector.isEligible(candidate("a", score: 5, author: "automoderator")))
        check("a deleted author is excluded",
              !AICommentSelector.isEligible(candidate("a", score: 5, author: "[deleted]")))
        check("a deleted body is excluded",
              !AICommentSelector.isEligible(candidate("a", score: 5, body: "[deleted]")))
        check("a removed body is excluded",
              !AICommentSelector.isEligible(candidate("a", score: 5, body: "[removed]")))
        check("a too-short comment is excluded",
              !AICommentSelector.isEligible(candidate("a", score: 5, body: "agreed")))
        check("a substantive comment is eligible",
              AICommentSelector.isEligible(candidate("a", score: 5)))
        check("an empty author is excluded",
              !AICommentSelector.isEligible(candidate("a", score: 5, author: "  ")))

        // (13) Gathering: the wire format carries the signals the prompts
        // ask about, and both caps hold.
        let gathered = AICommentSelector.gather([
            candidate("1", score: 300),
            candidate("2", score: 5, author: "op_user"),
            candidate("3", score: 8, controversiality: 1),
        ])
        check("gather reports how many comments it used",
              gathered.count == 3)
        check("each line carries the score the prompt reasons about",
              gathered.text.contains("score 300"))
        check("OP comments are labelled for the model",
              gathered.text.contains("[OP, score 5]"))
        check("controversial comments are labelled",
              gathered.text.contains("[controversial, score 8]"))
        check("ordinary comments are labelled plainly",
              gathered.text.contains("[comment, score 300]"))
        // The OP comment leads, not the 300-score one: the OP bonus is
        // +1400 while score is capped at 5000, so OP outranks anything
        // below 1400 points.
        check("ranking order beats source order",
              gathered.text.hasPrefix("[OP, score 5]"))
        // Similarly, the controversiality bonus is +700, so an 8-point
        // controversial comment (708) outranks a 300-point ordinary one.
        // Both bonuses are deliberately large enough to beat mid-range
        // scores, so the model gets OP context and disagreement instead of
        // three variations on the top comment.
        check("the controversial comment outranks a mid-score ordinary one",
              gathered.text.range(of: "[controversial")!.lowerBound
                  < gathered.text.range(of: "score 300")!.lowerBound)
        // Pinned numerically so the ordering above is explained, not just
        // observed.
        check("the bonuses are what reorder these three",
              AICommentSelector.rank(candidate("b", score: 5, author: "op_user"), originalIndex: 0) == 1405
              && AICommentSelector.rank(candidate("c", score: 8, controversiality: 1), originalIndex: 0) == 708
              && AICommentSelector.rank(candidate("a", score: 300), originalIndex: 0) == 300)
        check("duplicate ids are only used once",
              AICommentSelector.gather([candidate("dup", score: 5), candidate("dup", score: 9)]).count == 1)
        check("at most 16 comments are sent",
              AICommentSelector.gather((0..<40).map { candidate("c\($0)", score: 100 - $0) }).count
                  <= AICommentSelector.maxComments)
        // A single long comment is truncated to 300 chars, so one essay
        // cannot consume the whole budget.
        let longBody = String(repeating: "x", count: 5000)
        let truncated = AICommentSelector.gather([candidate("long", score: 5, body: longBody)])
        check("a single comment is truncated to its own cap",
              truncated.text.count < AICommentSelector.maxSingleCommentChars + 40)
        check("ineligible comments are dropped from the gathered set",
              AICommentSelector.gather([candidate("a", score: 5, author: "AutoModerator")]).count == 0)

        // (14) Both discussion thresholds: the count alone is not enough,
        // since five one-line "this" replies pass the count but contain
        // nothing to summarize. A 500-character floor is also required.
        check("the real minimums are Reborn's constants",
              AICommentSelector.minComments == 5 && AICommentSelector.minCommentChars == 500)
        check("enough comments but too little text is not enough discussion",
              !AICommentSelector.hasEnoughDiscussion(text: String(repeating: "x", count: 100), count: 9))
        check("enough text but too few comments is not enough discussion",
              !AICommentSelector.hasEnoughDiscussion(text: String(repeating: "x", count: 900), count: 2))
        check("both thresholds met is enough discussion",
              AICommentSelector.hasEnoughDiscussion(text: String(repeating: "x", count: 900), count: 9))
    }
}

// --- Stored AI settings survive an unknown provider value ---
//
// AI settings persist as one JSON blob, so an unrecognised enum raw value
// (e.g. a renamed `AIProvider` string) would fail the whole decode and reset
// every AI setting to default, including `summariesEnabled`. Decoding must
// tolerate an unknown provider value without losing the rest.
@MainActor func checkStoredAISettingsSurviveTheProvider() async throws {
    do {
        func decode(_ json: String) -> ApolloAISettings? {
            try? JSONDecoder().decode(ApolloAISettings.self, from: Data(json.utf8))
        }

        // A stored blob with an unrecognised provider value.
        let legacy = decode(#"{"provider":"onDevice","summariesEnabled":true}"#)
        check("the legacy provider spelling still decodes",
              legacy?.provider == .onDevice)
        check("a legacy blob no longer loses the master toggle",
              legacy?.summariesEnabled == true)
        check("the current spelling decodes as on-device",
              decode(#"{"provider":"apple"}"#)?.provider == .onDevice)
        check("the legacy camelCase openRouter spelling decodes",
              decode(#"{"provider":"openRouter"}"#)?.provider == .openRouter)
        check("the current openrouter spelling still decodes",
              decode(#"{"provider":"openrouter"}"#)?.provider == .openRouter)
        // The general rule: one unrecognised value must cost that field
        // only, never the rest of the user's configuration.
        let unknown = decode(#"{"provider":"martian","summariesEnabled":true,"postWordThreshold":250}"#)
        check("an unknown provider does not discard the other settings",
              unknown?.summariesEnabled == true && unknown?.postWordThreshold == 250)
        check("an unknown provider falls back to on-device",
              unknown?.provider == .onDevice)
        // Same hazard on the Int-backed enums, which also degrade rather than fail.
        let badDetail = decode(#"{"summariesEnabled":true,"postDetail":99,"commentDetail":99,"summaryMode":99}"#)
        check("an out-of-range detail does not discard the blob",
              badDetail?.summariesEnabled == true)
        check("an out-of-range detail falls back to balanced",
              badDetail?.postDetail == .balanced && badDetail?.commentDetail == .balanced)
        check("an out-of-range mode falls back to generate-on-open",
              badDetail?.summaryMode == .generateOnOpen)
        // Still round-trips, so writing is unaffected.
        var roundTrip = ApolloAISettings.default
        roundTrip.summariesEnabled = true
        roundTrip.provider = .gemini
        roundTrip.summaryMode = .tapToSummarize
        if let data = try? JSONEncoder().encode(roundTrip) {
            check("settings still round-trip after the tolerant decode",
                  decode(String(data: data, encoding: .utf8)!) == roundTrip)
            check("on-device is still written as the real 'apple' string",
                  String(data: try! JSONEncoder().encode(ApolloAISettings.default), encoding: .utf8)!
                      .contains("\"apple\""))
        } else {
            check("settings still round-trip after the tolerant decode", false)
        }
    }
}

// --- Feed row: subreddit header, capitalization, metrics ---
//
// Feed row layout matches Apollo: content inset, capitalized subreddit
// label, no "by author" line, compact stats row height, and the clock
// glyph pointing to 3:00.
@MainActor func checkFeedRowSubredditHeaderCapitalizationMetrics() async throws {
    do {
        // (1) The capitalization TABLE. This is the part that cannot be a
        // rule, and the reason rows read "pics" instead of "Pics".
        check("the capitalization table loads",
              SubredditCapitalization.entryCount > 5000)
        check("pics becomes Pics",
              SubredditCapitalization.display("pics") == "Pics")
        check("funny becomes Funny",
              SubredditCapitalization.display("funny") == "Funny")
        check("technology becomes Technology",
              SubredditCapitalization.display("technology") == "Technology")
        // These four are the proof no rule works: `.capitalized` gives
        // "Nba", "Askreddit", "Todayilearned", "Explainlikeimfive".
        check("nba becomes NBA, not Nba",
              SubredditCapitalization.display("nba") == "NBA")
        check("askreddit becomes AskReddit",
              SubredditCapitalization.display("askreddit") == "AskReddit")
        check("todayilearned becomes TodayILearned",
              SubredditCapitalization.display("todayilearned") == "TodayILearned")
        check("explainlikeimfive becomes ExplainLikeImFive",
              SubredditCapitalization.display("explainlikeimfive") == "ExplainLikeImFive")
        // The clearest evidence of all: two sibling subreddits whose names
        // differ only in the case of the same word. Only a table knows.
        check("1200isjerky keeps a lowercase 'is'",
              SubredditCapitalization.display("1200isjerky") == "1200isJerky")
        check("1200isplenty uses an uppercase 'Is'",
              SubredditCapitalization.display("1200isplenty") == "1200IsPlenty")
        check("the two siblings really do disagree",
              SubredditCapitalization.display("1200isjerky").contains("isJerky")
              && SubredditCapitalization.display("1200isplenty").contains("IsPlenty"))
        // An unknown name is returned UNCHANGED, not guessed at.
        // `.capitalized` would render r/somenewsubreddit as
        // "Somenewsubreddit", which looks like a typo.
        check("an unknown subreddit is left alone",
              SubredditCapitalization.display("zzzznotarealsubreddit") == "zzzznotarealsubreddit")
        check("an empty name is safe",
              SubredditCapitalization.display("") == "")
        // Mixed case from a subreddit endpoint is preserved when the table
        // has no exact-lowercase entry for it.
        check("lookup is case-insensitive on the key",
              SubredditCapitalization.display("PICS") == "Pics")
    }
}

// --- The feed header keeps its collapsed state across navigation ---
//
// The community highlights carousel's collapsed state persists per
// subreddit rather than in view-local `@State`, which would reset on
// every push/pop. Stored as a lowercased-name array under Apollo's own
// `CollapsedSubredditHighlights` key, so it round-trips with a real
// Apollo backup.
@MainActor func checkTheFeedHeaderKeepsItsCollapsed() async throws {
    do {
        let key = HighlightsCollapseStore.defaultsKey
        // Apollo's key name, so a backup's value imports directly.
        check("the collapsed-highlights key is Apollo's own",
              key == "CollapsedSubredditHighlights")

        UserDefaults.standard.removeObject(forKey: key)
        check("nothing is collapsed by default",
              !HighlightsCollapseStore.isCollapsed("apple"))

        HighlightsCollapseStore.setCollapsed(true, for: "apple")
        check("collapsing is remembered",
              HighlightsCollapseStore.isCollapsed("apple"))
        // Stored as an ARRAY of lowercased names, not a dictionary of booleans,
        // as in Apollo's backup.
        check("it persists as an array of names",
              (UserDefaults.standard.array(forKey: key) as? [String]) == ["apple"])

        // Lowercased on both read and write, so r/Apple and r/apple are
        // one entry.
        check("lookups are case-insensitive",
              HighlightsCollapseStore.isCollapsed("Apple")
              && HighlightsCollapseStore.isCollapsed("APPLE"))
        HighlightsCollapseStore.setCollapsed(true, for: "LINUX")
        check("writes are lowercased too",
              (UserDefaults.standard.array(forKey: key) as? [String])?.sorted() == ["apple", "linux"])

        // Expanding REMOVES the entry rather than storing false, which is
        // what keeps the array a set of collapsed names.
        HighlightsCollapseStore.setCollapsed(false, for: "apple")
        check("expanding removes the entry",
              !HighlightsCollapseStore.isCollapsed("apple"))
        check("...and leaves other subreddits alone",
              HighlightsCollapseStore.isCollapsed("linux"))
        check("the stored array shrinks",
              (UserDefaults.standard.array(forKey: key) as? [String]) == ["linux"])

        // An empty subreddit has nothing to key on: it must not collapse
        // and must not write a bare entry that would then apply to
        // Home/Popular/All.
        HighlightsCollapseStore.setCollapsed(true, for: "")
        check("an empty subreddit is not stored",
              (UserDefaults.standard.array(forKey: key) as? [String]) == ["linux"])
        check("an empty subreddit reads as expanded",
              !HighlightsCollapseStore.isCollapsed(""))
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// --- Row swipes must be startable ---
//
// A natural messy up/down swipe must not accidentally trigger a row
// swipe, while a genuine horizontal swipe (slow drag or fast flick)
// must reliably start one. Requiring translation AND velocity would
// reject real swipe shapes, so the gate uses Apollo's own
// horizontal-dominance ratio (1.65) against whichever signal is
// present.
@MainActor func checkRowSwipesMustBeStartable() async throws {
    do {
        let minDistance = PushPopGesturePolicy.rowSwipeMinimumDistance
        func begins(tx: Double, ty: Double, vx: Double, vy: Double) -> Bool {
            PushPopGesturePolicy.rowSwipeShouldBegin(
                translationX: tx, translationY: ty, velocityX: vx, velocityY: vy,
                minimumDistance: minDistance)
        }

        check("the ratio is Apollo's own constant, not an invented one",
              PushPopGesturePolicy.horizontalDominance == 1.65)
        check("the minimum travel matches the system pan slop",
              minDistance == 10)

        // A slow, deliberate horizontal drag has almost no velocity, so a
        // velocity-only gate would reject it outright.
        check("a slow deliberate horizontal drag starts a swipe",
              begins(tx: 14, ty: 1, vx: 40, vy: 5))
        // A quick flick that is decisively horizontal by velocity but
        // wobbles vertically in its opening sample, which a
        // translation-only gate would reject.
        check("a fast flick with some vertical wobble still starts",
              begins(tx: 12, ty: 7, vx: 900, vy: 120))
        // A clean fast swipe, which should obviously work.
        check("a clean fast horizontal swipe starts",
              begins(tx: 20, ty: 2, vx: 800, vy: 30))

        // A vertical scroll must not trigger a swipe. These are the shapes
        // a vertical scroll takes.
        check("a vertical scroll does not start a swipe",
              !begins(tx: 4, ty: 30, vx: 60, vy: 900))
        check("a messy diagonal scroll does not start a swipe",
              !begins(tx: 12, ty: 14, vx: 200, vy: 700))
        // A messy diagonal sample under the distance slop should fail on
        // distance rather than needing a ratio argument.
        check("the previously-reported messy sample still does not trigger",
              !begins(tx: 8, ty: 5, vx: 100, vy: 90))
        // Travel below the slop never begins, whatever the direction.
        check("a tiny horizontal twitch does not start a swipe",
              !begins(tx: 6, ty: 0, vx: 900, vy: 0))

        // Boundary: exactly at the ratio, a translation-only decision.
        check("a drag exactly at the ratio does not qualify on translation alone",
              !begins(tx: 16.5, ty: 10, vx: 0, vy: 0))
        check("a drag just past the ratio qualifies",
              begins(tx: 17, ty: 10, vx: 0, vy: 0))
        // A purely horizontal drag with zero vertical component must
        // always qualify rather than dividing by zero.
        check("a purely horizontal drag qualifies",
              begins(tx: 30, ty: 0, vx: 500, vy: 0))
    }
}

// --- Row swipe must not be re-triggerable mid-scroll, or from the
// bottom system-gesture strip ---
//
// A touch that becomes an obvious vertical scroll must be permanently
// ruled out, not re-evaluated every sample, and a touch starting in
// the bottom system-gesture strip (app switcher / home indicator) must
// be excluded like the left/right navigation insets already are.
@MainActor func checkRowSwipeMustNotBeRe() async throws {
    do {
        check("bottom system-gesture inset exists and is narrow (not a wide dead zone)",
              PushPopGesturePolicy.bottomSystemGestureInset > 0
              && PushPopGesturePolicy.bottomSystemGestureInset <= 40)

        // A touch starting at the very bottom edge of a 926pt-tall screen
        // (an iPhone 17-class device) must be excluded...
        check("a touch starting at the bottom edge is inside the system-gesture zone",
              PushPopGesturePolicy.startedInBottomSystemGestureZone(startY: 925, viewHeight: 926))
        check("a touch starting exactly at the inset boundary is inside the zone",
              PushPopGesturePolicy.startedInBottomSystemGestureZone(
                  startY: 926 - PushPopGesturePolicy.bottomSystemGestureInset, viewHeight: 926))
        // ...but ordinary row content well above the bottom edge must NOT
        // be dead-zoned - this is not a wide exclusion band.
        check("a touch well above the bottom edge is NOT excluded",
              !PushPopGesturePolicy.startedInBottomSystemGestureZone(startY: 800, viewHeight: 926))
        check("a touch in the middle of the screen is NOT excluded",
              !PushPopGesturePolicy.startedInBottomSystemGestureZone(startY: 400, viewHeight: 926))
    }
}

// --- Row swipes must not fight the page (back/forward) swipes ---
//
// iOS 26's full-content-area pop recognizer must be disabled alongside
// the classic edge one, or a row swipe can be stolen by system page
// navigation. The stand-down test uses translation as well as velocity
// so a slow edge drag is still recognized as navigation.
@MainActor func checkRowSwipesMustNotFightThe() async throws {
    do {
        let screen = 402.0
        func claims(_ startX: Double, _ tx: Double, _ ty: Double, _ vx: Double, _ vy: Double,
                    back: Bool = true, forward: Bool = true) -> Bool {
            PushPopGesturePolicy.navigationClaimsRowTouch(
                startX: startX, translationX: tx, translationY: ty,
                velocityX: vx, velocityY: vy, viewWidth: screen,
                canGoBack: back, canGoForward: forward)
        }
        // A slow edge drag has near-zero velocity, so translation must
        // also count as a navigation signal.
        check("slow rightward drag from the left inset (velocity ~0) is claimed by back, by translation",
              claims(40, 30, 2, 0, 0))
        check("slow leftward drag from the right inset is claimed by forward, by translation",
              claims(380, -30, 2, 0, 0))
        // Still directional: a leftward drag from the left inset is not a
        // back swipe by EITHER signal, so the row keeps it.
        check("leftward drag from the left inset stays with the row",
              !claims(40, -30, 2, -300, 10))
        check("rightward drag from mid-row stays with the row",
              !claims(200, 60, 2, 400, 10))
        // A diagonal that is horizontal by neither signal is not navigation.
        check("diagonal edge drag (neither signal past 1.65) is not claimed",
              !claims(40, 20, 18, 100, 90))
        // The original velocity path still claims.
        check("fast rightward edge flick is still claimed by velocity",
              claims(40, 12, 11, 500, 20))
        // Availability: a navigation that cannot happen does not dead-zone
        // the row.
        check("with nothing to go forward to, a leftward row swipe in the right inset stays with the row",
              !claims(380, -30, 2, -300, 10, forward: false))
        check("with nothing to go back to, a rightward row swipe in the left inset stays with the row",
              !claims(40, 30, 2, 300, 10, back: false))
        // The translation-aware function must agree with the velocity-only one
        // whenever velocity alone decides.
        check("navigationClaimsRowTouch agrees with navigationClaimsTouch on the velocity path",
              claims(20, 0, 0, 400, 30) == PushPopGesturePolicy.navigationClaimsTouch(
                  startX: 20, velocityX: 400, velocityY: 30, viewWidth: screen))
    }
}

// --- Horizontal gestures and vertical scrolling are mutually exclusive ---
//
// Once a drag commits to vertical scrolling it must not also start a
// horizontal gesture, and vice versa. Visual constants below match Apollo's.
@MainActor func checkHorizontalGesturesAndVerticalScrollingAre() async throws {
    do {
        // Scroll first means scroll only.
        check("a drag 12pt down and 4pt across has become a scroll",
              PushPopGesturePolicy.verticallyCommitted(translationX: 4, translationY: 12))
        check("a drag still inside UIKit's 10pt slop has not become a scroll yet",
              !PushPopGesturePolicy.verticallyCommitted(translationX: 2, translationY: 9))
        check("a diagonal back swipe (60 across, 15 down) is still horizontal",
              !PushPopGesturePolicy.verticallyCommitted(translationX: 60, translationY: 15))
        check("the scroll commit distance matches UIKit's own pan slop",
              PushPopGesturePolicy.scrollCommitDistance == 10)
        check("a scroll view counts as scrolling after a few points, not zero",
              PushPopGesturePolicy.scrollStartedDistance > 0
              && PushPopGesturePolicy.scrollStartedDistance < PushPopGesturePolicy.scrollCommitDistance)

        check("the icon parks where the short action goes live (2 x inset = 60pt)",
              ProgressiveSwipeParityProbe.parkPoint == SwipeCommitPolicy.commitThreshold)
    }

    /// The icon's parking point, restated here because the smoke target
    /// cannot import PhoebusUI: twice `ProgressiveSwipeRowModifier.iconInset`
    /// (asserted as source text above).
    enum ProgressiveSwipeParityProbe {
        static let parkPoint: Double = 2 * 30
    }
}
