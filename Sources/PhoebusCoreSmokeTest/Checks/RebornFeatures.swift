import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Comment Vote Insights
//
// Reddit's OAuth comment model has no upvote ratio; the only source is the
// author-only /commentstats/t1_<id> page. The fixtures mirror the upstream
// parser's own self-test markup.
@MainActor func checkCommentVoteInsights() async throws {
    func insightsPage(_ fields: String) -> String {
        "<shreddit-app><section data-testid='engagement-section'>\(fields)</section></shreddit-app>"
    }

    let insDecimal = CommentVoteInsightsClient.parse(html: insightsPage(
        "<i aria-label=\"25 upvotes\"></i><i aria-label=\"87.9% upvote ratio\"></i>"))
    check("a plain count and ratio parse",
          insDecimal?.reportedUpvotes == 25 && abs((insDecimal?.upvotePercent ?? 0) - 87.9) < 0.001)

    let insSpaced = CommentVoteInsightsClient.parse(html: insightsPage(
        "<i aria-label = '1.2k upvotes'></i><i aria-label = '60 % upvote ratio'></i>"))
    check("an abbreviated count expands and is flagged",
          insSpaced?.reportedUpvotes == 1200 && insSpaced?.reportedUpvotesAreAbbreviated == true)
    check("...and a spaced percent still parses",
          abs((insSpaced?.upvotePercent ?? 0) - 60.0) < 0.001)

    let insCountOnly = CommentVoteInsightsClient.parse(html: insightsPage("<i aria-label='7 upvotes'></i>"))
    check("a count with no ratio parses, leaving the ratio absent",
          insCountOnly?.reportedUpvotes == 7 && insCountOnly?.upvotePercent == nil)

    let insZero = CommentVoteInsightsClient.parse(html: insightsPage("<i aria-label='0% upvote ratio'></i>"))
    check("a 0% ratio is a real value, not a missing one",
          insZero?.upvotePercent == 0 && insZero?.reportedUpvotes == nil)

    // Reddit writes these labels in both orders.
    let insLeading = CommentVoteInsightsClient.parse(html: insightsPage(
        "<i aria-label='Upvotes: 42'></i><i aria-label='Upvote Ratio: 75.5%'></i>"))
    check("the leading-label order parses too",
          insLeading?.reportedUpvotes == 42 && abs((insLeading?.upvotePercent ?? 0) - 75.5) < 0.001)

    let insDiv = CommentVoteInsightsClient.parse(html:
        "<shreddit-app><div data-testid='engagement-section'><div><i aria-label='3 upvotes'></i></div>" +
        "<i aria-label='66.7% upvote ratio'></i></div></shreddit-app>")
    check("the div-card markup variant parses",
          insDiv?.reportedUpvotes == 3 && abs((insDiv?.upvotePercent ?? 0) - 66.7) < 0.001)

    check("markup with no vote labels yields nothing",
          CommentVoteInsightsClient.parse(html: insightsPage("<i aria-label='votes unavailable'></i>")) == nil)

    // Reddit's bot-check interstitial for `/commentstats/t1_...`. It returns
    // HTTP 200 with an HTML challenge page instead of JSON, which must be
    // detected rather than treated as vote data.
    let insChallenge = "\n  <!DOCTYPE html>\n  <html lang=\"en\">\n    <head>\n      <meta charset=\"UTF-8\" />\n      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n      <link href=\"https://www.redditstatic.com/shreddit/assets/favicon/64x64.png\" rel=\"icon shortcut\" sizes=\"64x64\" />\n      <title>Reddit</title>\n      <script nonce=\"9e0327dc-affc-4e7d-b52c-dbf06f89a124\">\n        document.addEventListener(\"DOMContentLoaded\",async function(){var e=document.forms[0],n=(e.onsubmit=function(t){return new URLSearchParams(document.location.search).forEach((e,n)=>t.target.appendChild(Object.assign(document.createElement(\"input\"),{name:n,type:\"hidden\",value:e}))),!0},await(async e=>e+e)(\"d554b06c5111c214\"));e.elements.namedItem(\"solution\").value=n,e.requestSubmit()},{once:!0});\n      </script>\n      <style>\n        main{align-items:center;display:flex;height:100vh;isolation:isolate;justify-content:center;position:relative;width:100vw}main:before{animation:scaleout 1.5s infinite ease-in-out;background-color:#d93900;border-radius:100%;content:'';height:8rem;opacity:.75;position:absolute;width:8rem}.logo{align-items:center;display:flex;fill:currentColor;font-size:4rem;justify-content:center;z-index:1}.logo svg{fill:currentColor;height:8rem;width:auto}@keyframes scaleout{0%{transform:scale(1)}100%{transform:scale(1.5);opacity:0}}.snoo-cls-1{fill:url(#snoo-radial-gragient) white}.snoo-cls-1,.snoo-cl"

    check("the live bot-check interstitial is recognised, not read as empty stats",
          CommentVoteInsightsClient.isChallengePage(insChallenge))
    check("...and it parses to no insight, so the two signals agree",
          CommentVoteInsightsClient.parse(html: insChallenge) == nil)
    check("a real stats page is never mistaken for the interstitial",
          !CommentVoteInsightsClient.isChallengePage(insightsPage("<i aria-label='7 upvotes'></i>")))
    check("label-free stats markup is 'not reported', which is distinct from blocked",
          !CommentVoteInsightsClient.isChallengePage(insightsPage("<i aria-label='votes unavailable'></i>")))

    // Reddit's "unavailable" page for an old comment: a definite answer,
    // not missing data.
    let insUnavailable = "<shreddit-app routename=\"commentstats\" route-type=\"\" pagetype=\"comment_insights\" devicetype=\"desktop\"><main class=\"main w-full min-w-0 flex flex-col\" id=\"main-content\" dir=\"ltr\">\n    \n    <div class=\"flex-1 flex flex-col items-center text-center h-100 justify-center\">\n    <span class=\"text-24 font-bold text-neutral-content-strong\">Insights unavailable for this comment</span>\n    <span class=\"text-16 text-neutral-content-weak mt-xs\">Comment insights are only available for 90 days.</span>\n  </div>\n    \n    </main></shreddit-app>"

    check("Reddit's explicit unavailable page is recognised",
          CommentVoteInsightsClient.unavailableReason(html: insUnavailable) != nil)
    check("...and surfaces Reddit's own reason, not a paraphrase of ours",
          CommentVoteInsightsClient.unavailableReason(html: insUnavailable)
            == "Comment insights are only available for 90 days.")
    check("...and is never mistaken for the bot-check interstitial",
          !CommentVoteInsightsClient.isChallengePage(insUnavailable))
    check("a real stats page is not reported as unavailable",
          CommentVoteInsightsClient.unavailableReason(
            html: "<shreddit-app pagetype=\"comment_insights\"><main><i aria-label='7 upvotes'></i></main></shreddit-app>") == nil)
    // The interstitial check must not be defeated by the mere word
    // "upvote", which every Reddit page carries in its stylesheet
    // (`--color-action-upvote`).
    check("the interstitial check is not defeated by stylesheet 'upvote' text",
          CommentVoteInsightsClient.isChallengePage(
            "<style>.border-action-upvote{border-color:var(--color-action-upvote)}</style>"
            + "<script>e.requestSubmit()</script>"))

    // Eligibility: author-only, comments only.
    check("the author of a comment is eligible",
          CommentVoteInsightsClient.isEligible(fullname: "t1_abc", author: "me", currentUsername: "me"))
    check("...case-insensitively on the username",
          CommentVoteInsightsClient.isEligible(fullname: "t1_abc", author: "Me", currentUsername: "mE"))
    check("someone else's comment is NOT eligible",
          !CommentVoteInsightsClient.isEligible(fullname: "t1_abc", author: "them", currentUsername: "me"))
    check("a POST is not eligible - this is comment-only",
          !CommentVoteInsightsClient.isEligible(fullname: "t3_abc", author: "me", currentUsername: "me"))
    check("signed out, nothing is eligible",
          !CommentVoteInsightsClient.isEligible(fullname: "t1_abc", author: "me", currentUsername: nil))

    check("the real endpoint is used",
          CommentVoteInsightsClient.statsURL(commentID: "abc")?.absoluteString ==
            "https://www.reddit.com/commentstats/t1_abc")
    check("...and an already-prefixed id is not double-prefixed",
          CommentVoteInsightsClient.statsURL(commentID: "t1_abc")?.absoluteString ==
            "https://www.reddit.com/commentstats/t1_abc")
    check("the real cache lifetime is 120s", CommentVoteInsightsClient.cacheLifetime == 120)
}

// MARK: - Hide Moderated Subreddits
//
// Reddit has no way to leave a dead subreddit you moderate, so it stays in
// the MODERATOR section. Hiding is a display filter only (mod powers are
// untouched) and is bypassed in Edit mode so rows can be unhidden.
@MainActor func checkHideModeratedSubreddits() async throws {
    struct ModSub { let displayName: String }
    let modSubs = [ModSub(displayName: "DeadSub"), ModSub(displayName: "ActiveSub")]
    let hiddenMods: Set<String> = ["deadsub"]

    check("a hidden moderated subreddit is filtered out",
          HiddenModeratorSubredditsStore.visible(modSubs, hidden: hiddenMods, isEditing: false) { $0.displayName }
            .map(\.displayName) == ["ActiveSub"])
    // The filter is bypassed in Edit mode so the row can be unhidden.
    check("...but reappears in Edit mode",
          HiddenModeratorSubredditsStore.visible(modSubs, hidden: hiddenMods, isEditing: true) { $0.displayName }
            .count == 2)
    // Compared case-insensitively.
    check("hiding is case-insensitive",
          HiddenModeratorSubredditsStore.isHidden("DEADSUB", in: hiddenMods) &&
          HiddenModeratorSubredditsStore.isHidden("deadsub", in: hiddenMods))
    check("an unhidden subreddit is not matched",
          !HiddenModeratorSubredditsStore.isHidden("ActiveSub", in: hiddenMods))
    check("nothing hidden means nothing filtered",
          HiddenModeratorSubredditsStore.visible(modSubs, hidden: [], isEditing: false) { $0.displayName }.count == 2)

    let modDefaults = UserDefaults(suiteName: "hidden-mods-test")!
    modDefaults.removePersistentDomain(forName: "hidden-mods-test")
    HiddenModeratorSubredditsStore.toggle("DeadSub", defaults: modDefaults)
    check("hiding persists, lowercased",
          HiddenModeratorSubredditsStore.load(defaults: modDefaults) == ["deadsub"])
    HiddenModeratorSubredditsStore.toggle("deadsub", defaults: modDefaults)
    check("unhiding persists too",
          HiddenModeratorSubredditsStore.load(defaults: modDefaults).isEmpty)
}

// MARK: - Extra playback speeds (Reborn #445)
//
// Apollo ships five speeds; Reborn adds 0.75x after 0.5x and 1.25x before
// 1.5x, keeping the menu ascending.
@MainActor func checkExtraPlaybackSpeedsReborn445() async throws {
    check("the speed menu now has seven entries",
          VideoPlaybackSpeeds.all.count == 7)
    check("0.75x sits after 0.5x, per the real insertion point",
          VideoPlaybackSpeeds.all.firstIndex(of: 0.75) ==
          (VideoPlaybackSpeeds.all.firstIndex(of: 0.5)! + 1))
    check("1.25x sits before 1.5x",
          VideoPlaybackSpeeds.all.firstIndex(of: 1.25) ==
          (VideoPlaybackSpeeds.all.firstIndex(of: 1.5)! - 1))
    check("the menu stays in ascending order",
          VideoPlaybackSpeeds.all == VideoPlaybackSpeeds.all.sorted())
    // Apollo's own five must all survive.
    check("Apollo's original five speeds are all still present",
          [0.25, 0.5, 1, 1.5, 2].allSatisfy(VideoPlaybackSpeeds.all.contains))
    // Titles use "0.75×" (U+00D7); 1x is the labelled default.
    check("the new speeds use the real title format",
          VideoPlaybackSpeeds.title(0.75) == "Playback Speed (0.75\u{00D7})" &&
          VideoPlaybackSpeeds.title(1.25) == "Playback Speed (1.25\u{00D7})")
}

// MARK: - Post Filters (per-subreddit keywords / flairs / name fragments)
//
// Per-subreddit keyword and flair rules plus subreddit-name substring
// matching, on top of the flat global keyword/subreddit/author/domain filters.
@MainActor func checkPostFiltersPerSubredditKeywordsFlairs() async throws {
    var pf = PostFilterRules()
    pf.subreddits["movies"] = .init(keywords: ["spoiler"], flairs: ["trailer"])
    pf.nameSubstrings = ["circlejerk"]

    check("a keyword hides a matching post in THAT subreddit",
          pf.hides(subreddit: "movies", title: "Big spoiler inside", url: nil, flair: nil))
    // The whole point of per-subreddit rules: the same title elsewhere stays.
    check("...but the same title in another subreddit is untouched",
          !pf.hides(subreddit: "books", title: "Big spoiler inside", url: nil, flair: nil))
    check("subreddit matching is case-insensitive",
          pf.hides(subreddit: "MOVIES", title: "a SPOILER here", url: nil, flair: nil))
    // Keywords test the link as well as the title.
    check("a keyword also matches the post's link",
          pf.hides(subreddit: "movies", title: "clean title", url: "https://x.com/spoiler-page", flair: nil))

    // Flairs are an exact visible-label match, not a substring.
    check("an exact flair label hides the post",
          pf.hides(subreddit: "movies", title: "t", url: nil, flair: "Trailer"))
    check("a flair that merely CONTAINS the term does not",
          !pf.hides(subreddit: "movies", title: "t", url: nil, flair: "Not a Trailer"))
    // Snoomoji tokens are stripped and whitespace collapsed.
    check("flair matching ignores :emoji: tokens and extra whitespace",
          pf.hides(subreddit: "movies", title: "t", url: nil, flair: ":cat: Trailer  "))

    // Subreddit-name substrings apply to ANY subreddit.
    check("a name fragment hides a whole subreddit",
          pf.hides(subreddit: "carscirclejerk", title: "anything", url: nil, flair: nil))
    check("...and is not confused with an unrelated name",
          !pf.hides(subreddit: "cars", title: "anything", url: nil, flair: nil))

    // Fast-out: no rules configured means nothing is hidden.
    check("an empty rule set hides nothing",
          !PostFilterRules.empty.hides(subreddit: "movies", title: "spoiler", url: nil, flair: "Trailer"))
    check("an empty rule set reports itself empty", PostFilterRules.empty.isEmpty)

    // Rule count is keywords + flairs.
    check("a subreddit's rule count is keywords + flairs",
          pf.subreddits["movies"]?.ruleCount == 2)

    // Round-trips through the two-key store layout.
    let pfDefaults = UserDefaults(suiteName: "post-filters-test")!
    pfDefaults.removePersistentDomain(forName: "post-filters-test")
    PostFilterStore.save(pf, defaults: pfDefaults)
    let pfLoaded = PostFilterStore.load(defaults: pfDefaults)
    check("post filters persist", pfLoaded == pf)
}

// MARK: - Saved-items de-duplication
//
// Reborn #1005: Reddit can return the same item twice in one saved-items
// response and the list replaces its contents wholesale on refresh, so the
// duplicate shows as a repeated row. First occurrence wins, server order is
// kept, and items with no stable identity are retained.
@MainActor func checkSavedItemsDeDuplication() async throws {
    struct SavedThing { let name: String?; let tag: Int }
    let savedDupes = [
        SavedThing(name: "t3_a", tag: 1),
        SavedThing(name: "t1_b", tag: 2),
        SavedThing(name: "t3_a", tag: 3),   // duplicate of tag 1
        SavedThing(name: nil,   tag: 4),    // no identity
        SavedThing(name: nil,   tag: 5),    // no identity, must also survive
        SavedThing(name: "t1_b", tag: 6),   // duplicate of tag 2
    ]
    let savedDeduped = SavedItemsDeduplicator.deduplicate(savedDupes) { $0.name }
    check("duplicates are removed", savedDeduped.count == 4)
    check("the FIRST occurrence is the one kept, in server order",
          savedDeduped.map(\.tag) == [1, 2, 4, 5])
    check("items with no stable identity are retained, not dropped",
          savedDeduped.filter { $0.name == nil }.count == 2)
    // A response with nothing repeated must come back untouched.
    let savedUnique = [SavedThing(name: "t3_x", tag: 1), SavedThing(name: "t3_y", tag: 2)]
    check("a clean response is unchanged",
          SavedItemsDeduplicator.deduplicate(savedUnique) { $0.name }.map(\.tag) == [1, 2])
    check("a single item is unchanged",
          SavedItemsDeduplicator.deduplicate([savedUnique[0]]) { $0.name }.count == 1)
}

// MARK: - Reddit /s/ share links
//
// Reddit's share button emits `reddit.com/r/<sub>/s/<opaque>`, which carries
// no post id and must be resolved over the network rather than parsed as a
// `/r/<sub>` link.
@MainActor func checkRedditSShareLinks() async throws {
    check("a real share link is recognised",
          ShareLinkResolver.isShareLink(URL(string: "https://www.reddit.com/r/swift/s/aBcD3fG")!))
    check("...on any presentation host",
          ShareLinkResolver.isShareLink(URL(string: "https://old.reddit.com/r/swift/s/aBcD3fG")!) &&
          ShareLinkResolver.isShareLink(URL(string: "https://np.reddit.com/r/swift/s/aBcD3fG")!))
    check("...and for user share links too",
          ShareLinkResolver.isShareLink(URL(string: "https://www.reddit.com/user/someone/s/aBcD3fG")!) &&
          ShareLinkResolver.isShareLink(URL(string: "https://www.reddit.com/u/someone/s/aBcD3fG")!))
    check("...with a trailing slash or query",
          ShareLinkResolver.isShareLink(URL(string: "https://www.reddit.com/r/swift/s/aBcD3fG/?x=1")!))

    // Ordinary links still route directly.
    check("an ordinary post permalink is not a share link",
          !ShareLinkResolver.isShareLink(URL(string: "https://www.reddit.com/r/swift/comments/abc/title/")!))
    check("a plain subreddit link is not a share link",
          !ShareLinkResolver.isShareLink(URL(string: "https://www.reddit.com/r/swift")!))
    check("a non-Reddit host is not a share link",
          !ShareLinkResolver.isShareLink(URL(string: "https://example.com/r/swift/s/aBcD3fG")!))

    // A media share wraps the asset URL.
    check("a media share unwraps its real asset URL",
          ShareLinkResolver.mediaShareTarget(
            URL(string: "https://www.reddit.com/media?url=https%3A%2F%2Fi.redd.it%2Fabc.jpg")!
          )?.absoluteString == "https://i.redd.it/abc.jpg")
    check("an ordinary link has no media target",
          ShareLinkResolver.mediaShareTarget(URL(string: "https://i.redd.it/abc.jpg")!) == nil)

    // Network constants.
    check("the real redirect cap is 10", ShareLinkResolver.maximumRedirects == 10)
    check("the real timeout is 10s", ShareLinkResolver.timeout == 10)
}

// MARK: - Inbox reply -> isolated comment thread
//
// Tapping an Inbox reply opens the linked comment's own thread, decoded from
// Reddit's `context` permalink (`data.context`), in Apollo's format
// `https://reddit.com/r/%@/comments/%@/_/%@/?context=1`.
@MainActor func checkInboxReplyIsolatedCommentThread() async throws {
    func inboxMessage(context: String?, wasComment: Bool = true) -> RedditMessage {
        let ctx = context.map { "\"context\": \"\($0)\"," } ?? ""
        let json = """
        {"id":"m1","name":"t1_m1","author":"someone","subject":"comment reply",
         "body":"hi","created_utc":1,"new":true,"was_comment":\(wasComment),
         \(ctx) "subreddit":"swift"}
        """
        return try! JSONDecoder.reddit.decode(RedditMessage.self, from: Data(json.utf8))
    }

    let replyMessage = inboxMessage(context: "/r/swift/comments/abc123/some_title/def456/?context=3")
    check("a comment reply resolves the thread it points at",
          replyMessage.commentTarget != nil)
    check("...with the right subreddit", replyMessage.commentTarget?.subreddit == "swift")
    check("...the right post", replyMessage.commentTarget?.postID == "abc123")
    check("...and the right comment", replyMessage.commentTarget?.commentID == "def456")

    // Apollo's format string uses a literal "_" for the slug; it must parse
    // identically.
    let underscoreSlug = inboxMessage(context: "/r/swift/comments/abc123/_/def456/?context=1")
    check("Apollo's own _-slug context parses the same",
          underscoreSlug.commentTarget?.commentID == "def456" &&
          underscoreSlug.commentTarget?.postID == "abc123")

    // A private message has no context and must not navigate.
    check("a plain private message has no comment target",
          inboxMessage(context: nil, wasComment: false).commentTarget == nil)
    // A malformed or non-comment context must not produce a target.
    check("a subreddit-only context is not a comment target",
          inboxMessage(context: "/r/swift/").commentTarget == nil)
}

// MARK: - Hide Header on Scroll
@MainActor func checkApolloReborn370Parity3() async throws {
    check("Hide Header on Scroll defaults OFF, matching the real key",
          !GeneralSettings.default.hideTopBarOnScroll)
    // The remembered choice is kept while Hide Bars is off (only the settings
    // row hides), so it is an independent stored value.
    var topBar = GeneralSettings.default
    topBar.hideTopBarOnScroll = true
    topBar.hideBarsOnScroll = false
    let topBarRoundTrip = try! JSONDecoder().decode(
        GeneralSettings.self, from: try! JSONEncoder().encode(topBar)
    )
    check("the remembered choice survives Hide Bars being off",
          topBarRoundTrip.hideTopBarOnScroll && !topBarRoundTrip.hideBarsOnScroll)
    let topBarSparse = try! JSONDecoder().decode(GeneralSettings.self, from: Data("{}".utf8))
    check("an older saved blob defaults Hide Top Bar off", !topBarSparse.hideTopBarOnScroll)
}

// MARK: - ExpandedMultireddits (stock Apollo)
//
// `ExpandedMultireddits` is in Apollo's own registration dictionary and adds
// inline expansion rows under each multireddit in the subreddit list.
@MainActor func checkExpandedMultiredditsStockApollo() async throws {
    let expandDefaults = UserDefaults(suiteName: "expanded-multis-test")!
    expandDefaults.removePersistentDomain(forName: "expanded-multis-test")
    check("nothing is expanded by default, matching the real empty dict",
          ExpandedMultiredditsStore.load(defaults: expandDefaults).isEmpty)
    ExpandedMultiredditsStore.save(["music_mix"], defaults: expandDefaults)
    check("an expanded multireddit persists",
          ExpandedMultiredditsStore.load(defaults: expandDefaults) == ["music_mix"])
    ExpandedMultiredditsStore.save([], defaults: expandDefaults)
    check("collapsing it persists too",
          ExpandedMultiredditsStore.load(defaults: expandDefaults).isEmpty)
}

// MARK: - Collapsible navigation actions
//
// A screen with fewer than two actionable trailing items keeps them native;
// two or more collapse into one "..." pill.
@MainActor func checkApolloReborn370Parity4() async throws {
    check("a single action stays inline, with no pill",
          !NavigationActionsPolicy.shouldCollapse(actionableCount: 1))
    check("no actions means no pill",
          !NavigationActionsPolicy.shouldCollapse(actionableCount: 0))
    check("two actions collapse into the pill",
          NavigationActionsPolicy.shouldCollapse(actionableCount: 2))
    check("so do three", NavigationActionsPolicy.shouldCollapse(actionableCount: 3))

    // Spring: mass 1, stiffness 644, damping ratio 0.78, 0.36s.
    check("the real spring duration is 0.36s", NavigationActionsPolicy.animationDuration == 0.36)
    check("the real spring stiffness is 644", NavigationActionsPolicy.springStiffness == 644)
    check("the real spring mass is 1", NavigationActionsPolicy.springMass == 1)
    check("the real damping ratio is 0.78", NavigationActionsPolicy.springDampingRatio == 0.78)
    // The module writes `2 * 0.78 * sqrt(644)`; check the conversion, since
    // that is the value handed to CoreAnimation.
    check("the damping coefficient matches 2 * ratio * sqrt(stiffness)",
          abs(NavigationActionsPolicy.springDamping - (2 * 0.78 * (644.0).squareRoot())) < 0.0001)

    // Scrolling collapses with the spring; the back gesture and resigning
    // active must not animate, since the spring is skipped during an
    // interactive transition.
    check("a scroll collapses with animation",
          NavigationActionsPolicy.animatesCollapse(for: .scrolled))
    check("a back-swipe collapses WITHOUT animation",
          !NavigationActionsPolicy.animatesCollapse(for: .backGesture))
    check("resigning active collapses WITHOUT animation",
          !NavigationActionsPolicy.animatesCollapse(for: .resignActive))
}

// MARK: - Subreddit header bands
//
// Defaults: Subtitle and Description ON, Sidebar and User Flair buttons OFF.
@MainActor func checkApolloReborn370Parity5() async throws {
    check("Subtitle defaults ON", SubredditLayoutSettings.default.subredditShowSubtitle)
    check("Description defaults ON", SubredditLayoutSettings.default.subredditShowDescription)
    check("the Sidebar button defaults OFF", !SubredditLayoutSettings.default.subredditShowSidebarButton)
    check("the User Flair button defaults OFF", !SubredditLayoutSettings.default.subredditShowUserFlairButton)
    check("the real collapsed description is 3 lines",
          SubredditLayoutSettings.aboutCollapsedLines == 3)

    // An older saved blob picks up the defaults, not false.
    let layoutSparse = try! JSONDecoder().decode(SubredditLayoutSettings.self, from: Data("{}".utf8))
    check("an older saved layout blob keeps the two ON-by-default bands",
          layoutSparse.subredditShowSubtitle && layoutSparse.subredditShowDescription)
    check("...and leaves the two OFF-by-default buttons off",
          !layoutSparse.subredditShowSidebarButton && !layoutSparse.subredditShowUserFlairButton)

    // The hub summary lists bands that are OFF but shipped ON.
    var layoutBands = SubredditLayoutSettings.default
    layoutBands.showSubredditHeaders = true
    layoutBands.subredditShowSubtitle = false
    check("the hub summary reports a hidden Subtitle",
          layoutBands.summaryText.contains("Subtitle"))
    check("...and, as Reborn's, the buttons that are off",
          layoutBands.summaryText.contains("User Flair Button, Sidebar Button"))
}

// MARK: - Moderator green
//
// Stock Apollo's #00940F suits opaque pre-iOS-26 chrome; Reborn replaces it
// app-wide for legibility on Liquid Glass.
@MainActor func checkApolloReborn370Parity6() async throws {
    check("moderator green is Reborn 3.7.0's #30D158",
          ApolloPalette.moderatorGreenHex == "30D158")
    check("...which is not stock Apollo's legacy #00940F",
          ApolloPalette.moderatorGreenHex != ApolloPalette.legacyModeratorGreenHex)
    check("the legacy value is recorded as Apollo's real old one",
          ApolloPalette.legacyModeratorGreenHex == "00940F")
}

// MARK: - Safari dark-mode loading shield
@MainActor func checkApolloReborn370Parity7() async throws {
    check("the shield only applies in dark mode",
          SafariDarkLoadingPolicy.shouldShield(isDarkMode: true) &&
          !SafariDarkLoadingPolicy.shouldShield(isDarkMode: false))
    check("the real fallback hold is 1.5s", SafariDarkLoadingPolicy.holdFallback == 1.5)
    check("the real post-web-view hold is 0.8s", SafariDarkLoadingPolicy.holdAfterWebView == 0.8)
    check("the real ramp is 1.4s", SafariDarkLoadingPolicy.rampDuration == 1.4)
    check("a finished load fades faster than a still-blank one",
          SafariDarkLoadingPolicy.finishDuration < SafariDarkLoadingPolicy.rampDuration)
}

// MARK: - AI summaries skip Devvit bodies

// Uses the fixtures built above for `DevvitPostDetector.isDevvitPost`
// (`devvitPost` is the old-Reddit fallback body; `textPost` is a self post).
@MainActor func checkApolloReborn370Parity8() async throws {
    check("a live interactive post is treated as bodyless for AI",
          DevvitPostDetector.aiShouldTreatAsBodyless(post: devvitPost, devvitInteractivePosts: true))
    check("an ordinary text post is NOT",
          !DevvitPostDetector.aiShouldTreatAsBodyless(post: textPost, devvitInteractivePosts: true))
    // Gated on the master switch only; where the widget is displayed is
    // irrelevant to whether the body is a data blob.
    check("with interactive posts off, nothing is treated as bodyless",
          !DevvitPostDetector.aiShouldTreatAsBodyless(post: devvitPost, devvitInteractivePosts: false))
    check("the feed-widget decision still honours its own separate toggle",
          !DevvitPostDetector.feedShouldShowWidget(post: devvitPost, devvitInteractivePosts: true, devvitFeedWidgets: false))
}

// MARK: - "Sign In to X" alerts
//
// Apollo names the action in a titled alert when a signed-out user tries to
// write, instead of applying the vote optimistically and reverting it.
@MainActor func checkSignInToXAlerts() async throws {
    check("upvote title is verbatim", SignInRequiredCopy.Action.upvote.title == "Sign In to Upvote")
    check("upvote message is verbatim", SignInRequiredCopy.Action.upvote.message == "You need to be signed in to upvote.")
    check("downvote title is verbatim", SignInRequiredCopy.Action.downvote.title == "Sign In to Downvote")
    check("downvote message is verbatim", SignInRequiredCopy.Action.downvote.message == "You need to be signed in to downvote.")
    check("reply title is verbatim", SignInRequiredCopy.Action.reply.title == "Sign In to Reply")
    check("reply message is verbatim", SignInRequiredCopy.Action.reply.message == "You need to be signed in to reply.")
    check("block message is verbatim", SignInRequiredCopy.Action.block.message == "You need to be signed in to block users.")
    check("filter message is verbatim", SignInRequiredCopy.Action.filter.message == "You need to be signed in to filter subreddits.")

    // Apollo ships the save message but no title string, so the alert is
    // message-only.
    check("save message is verbatim", SignInRequiredCopy.Action.save.message == "You need to be signed in to save.")
    check("save has no invented title", SignInRequiredCopy.Action.save.title.isEmpty)

    // The alert names the direction taken.
    check("a downvote asks you to sign in to DOWNVOTE",
          SignInRequiredCopy.voteAction(direction: -1) == .downvote)
    check("an upvote asks you to sign in to UPVOTE",
          SignInRequiredCopy.voteAction(direction: 1) == .upvote)
    check("clearing a vote is presented as an upvote sign-in",
          SignInRequiredCopy.voteAction(direction: 0) == .upvote)

    // Only the signed-out case becomes this alert; a network failure must
    // still surface as an error.
    check("a not-authenticated error raises the sign-in alert",
          SignInRequiredCopy.isSignedOut(RedditAPIError.notAuthenticated))
    check("an HTTP failure does NOT",
          !SignInRequiredCopy.isSignedOut(RedditAPIError.httpError(status: 503, body: "")))
    check("a transport failure does NOT",
          !SignInRequiredCopy.isSignedOut(URLError(.notConnectedToInternet)))
}

// MARK: - "Continue thread..." (Reddit's depth-limit `more` object)
//
// Reddit has two kinds of `more`: the resolvable kind that lists ids, and
// `id: "_"` with count 0 and no children, meaning the thread runs past the
// response's depth limit. The decoder keeps the second kind and renders
// it as "Continue thread...".
@MainActor func checkContinueThreadRedditSDepthLimit() async throws {
    func moreObject(id: String, count: Int, children: [String]) -> Data {
        let childList = children.map { "\"\($0)\"" }.joined(separator: ",")
        return Data("""
        [{"kind":"t1","data":{"id":"root1","name":"t1_root1","author":"a","body":"b","score":1,
          "created_utc":1,"parent_id":"t3_post","link_id":"t3_post","saved":false,
          "score_hidden":false,"stickied":false,
          "replies":{"kind":"Listing","data":{"children":[
            {"kind":"more","data":{"id":"\(id)","count":\(count),"children":[\(childList)]}}
          ]}}}}]
        """.utf8)
    }

    func stubFromResponse(_ data: Data) -> MoreStub? {
        let values = try! JSONDecoder().decode([JSONValue].self, from: data)
        let built = CommentTreeBuilder.buildRoots(from: values, postFullname: "t3_post")
        return built.roots.first?.moreStub
    }

    let resolvableStub = stubFromResponse(moreObject(id: "abc", count: 3, children: ["c1", "c2", "c3"]))
    check("a normal `more` object still decodes", resolvableStub != nil)
    check("...keeps its real reply count", resolvableStub?.count == 3)
    check("...carries the ids to resolve", resolvableStub?.children.count == 3)
    check("...and is NOT a continue-thread stub", resolvableStub?.isContinueThread == false)

    let continueStub = stubFromResponse(moreObject(id: "_", count: 0, children: []))
    check("Reddit's depth-limit `more` is no longer dropped", continueStub != nil)
    check("...is recognised as a continue-thread stub", continueStub?.isContinueThread == true)
    check("...has no ids to resolve, so morechildren cannot answer it",
          continueStub?.children.isEmpty == true)
    check("...and remembers the comment to re-root the fetch at",
          continueStub?.parentID == "t1_root1")

    // An id-less `more` that is not Reddit's "_" marker is junk and stays
    // dropped.
    check("a childless non-\"_\" more object is still ignored",
          stubFromResponse(moreObject(id: "xyz", count: 0, children: [])) == nil)
}

// MARK: - Load next page row (manual pagination)
//
// With Infinite Scrolling off, a "Load next page" row drives manual pagination.
@MainActor func checkLoadNextPageCellNodeManualPagination() async throws {
    check("with infinite scrolling ON there is no manual row",
          !FeedPaginationPolicy.shouldOfferManualNextPage(infiniteScrollingEnabled: true, reachedEnd: false, isLoadingMore: false, isLoading: false, loadedCount: 25))
    check("with it OFF the feed offers the next page",
          FeedPaginationPolicy.shouldOfferManualNextPage(infiniteScrollingEnabled: false, reachedEnd: false, isLoadingMore: false, isLoading: false, loadedCount: 25))
    check("no manual row once the listing has genuinely ended",
          !FeedPaginationPolicy.shouldOfferManualNextPage(infiniteScrollingEnabled: false, reachedEnd: true, isLoadingMore: false, isLoading: false, loadedCount: 25))
    check("no manual row while the first page is still loading",
          !FeedPaginationPolicy.shouldOfferManualNextPage(infiniteScrollingEnabled: false, reachedEnd: false, isLoadingMore: false, isLoading: true, loadedCount: 0))
    check("no manual row on an empty feed",
          !FeedPaginationPolicy.shouldOfferManualNextPage(infiniteScrollingEnabled: false, reachedEnd: false, isLoadingMore: false, isLoading: false, loadedCount: 0))
    // The row stays put and shows its own progress rather than disappearing
    // mid-fetch.
    check("the row stays while its own page is loading",
          FeedPaginationPolicy.shouldOfferManualNextPage(infiniteScrollingEnabled: false, reachedEnd: false, isLoadingMore: true, isLoading: false, loadedCount: 25))

    // Page number to load, against Reddit's 25-item default page.
    check("after one page the row offers page 2", FeedPaginationPolicy.nextPageNumber(loadedCount: 25) == 2)
    check("after three pages it offers page 4", FeedPaginationPolicy.nextPageNumber(loadedCount: 75) == 4)
    check("a partial page still offers the next one", FeedPaginationPolicy.nextPageNumber(loadedCount: 30) == 2)
    check("it never offers to load page 1 again", FeedPaginationPolicy.nextPageNumber(loadedCount: 3) == 2)
}

// MARK: - ReachedEndCopy
//
// End-of-feed cell; every string is Apollo's own wording.
@MainActor func checkReachedEndCopy() async throws {
    check("the real visit-counter key is EndsOfRedditsReached3",
          ReachedEndCopy.visitCountKey == "EndsOfRedditsReached3")
    check("the short headline is verbatim",
          ReachedEndCopy.shortHeadline == "The Great Scrolls of Reddit claim you\u{2019}ve reached the end of this feed.")
    check("the long headline is verbatim",
          ReachedEndCopy.longHeadline == "The Great Scrolls of Reddit claim there\u{2019}s no more content past this point. Try loading a new subreddit, or if it\u{2019}s been a bit, refreshing this one.")
    check("the beast intro keeps the real leading newlines and open quote",
          ReachedEndCopy.beastIntro == "\n\nSuddenly, the ground shakes, and a large beast emerges, saying:\n\n\u{201C}")
    check("the first-visit line is verbatim",
          ReachedEndCopy.firstVisitLine == "Not many people visit me all the way down here. It\u{2019}s great to meet another soul.")
    check("the accessibility label is verbatim",
          ReachedEndCopy.accessibilityLabel == "Wow. You reached the bottom.")
    check("the accessibility hint is verbatim",
          ReachedEndCopy.accessibilityHint == "Double tap to communicate to Chumbus")
    check("all 50 of the beast's lines are present", ReachedEndCopy.beastLines.count == 50)
    check("the beast's lines are in Apollo's order",
          ReachedEndCopy.beastLines.first == "You again, huh? Are you making a habit of visiting me?" &&
          ReachedEndCopy.beastLines.last == "If you could interview any human living or dead, who would you choose? For me it would be Nigel Thornberry.")

    // 1 -> the meeting line, then the table in order from `count - 2`, then
    // random forever.
    check("the first ever visit meets the beast for the first time",
          ReachedEndCopy.beastLine(visitCount: 1) == ReachedEndCopy.firstVisitLine)
    check("the second visit starts the table at its first line",
          ReachedEndCopy.beastLine(visitCount: 2) == ReachedEndCopy.beastLines[0])
    check("the third visit advances one line",
          ReachedEndCopy.beastLine(visitCount: 3) == ReachedEndCopy.beastLines[1])
    check("visits walk the table in order to its second-to-last line",
          ReachedEndCopy.beastLine(visitCount: 50) == ReachedEndCopy.beastLines[48])
    check("past the end of the table the line is chosen randomly",
          ReachedEndCopy.beastLine(visitCount: 999, randomIndex: { _ in 7 }) == ReachedEndCopy.beastLines[7])

    // A short feed gets the plain headline and no beast; the initializer
    // gates the passage on its own flag.
    let shortMessage = ReachedEndCopy.message(likelyReachedEndOfLoadablePosts: false, visitCount: 5)
    check("a merely-finished feed gets the short headline alone",
          shortMessage == ReachedEndCopy.shortHeadline)
    check("...and no beast", !shortMessage.contains("beast"))

    let longMessage = ReachedEndCopy.message(likelyReachedEndOfLoadablePosts: true, visitCount: 1)
    check("the end of everything loadable summons the beast", longMessage.contains("a large beast emerges"))
    check("...with the real first-visit line", longMessage.contains(ReachedEndCopy.firstVisitLine))
    check("...and closes its quotation", longMessage.hasSuffix("\u{201D}"))
}

// MARK: - SavedIndicator
//
// Apollo's saved-indicator geometry, matching its saved-triangle artwork.
@MainActor func checkSavedIndicator() async throws {
    check("the regular saved wedge is the real saved-triangle's 24pt",
          SavedIndicator.regularSize == 24)
    check("the small saved wedge is the real saved-triangle-small's 18pt",
          SavedIndicator.smallSize == 18)
    check("post cells use the regular asset", SavedIndicator.Size.regular.assetName == "saved-triangle")
    check("comment cells use the small asset", SavedIndicator.Size.small.assetName == "saved-triangle-small")
    check("the comment wedge is the smaller of the two",
          SavedIndicator.Size.small.points < SavedIndicator.Size.regular.points)

    // The artwork path is `24 24 m  24 0 l  0 0 l  24 24 l h` in PDF space
    // (origin bottom-left); flipped into UIKit space the right angle sits at
    // the bottom-right, putting the wedge in the cell's trailing-bottom corner.
    let wedge = SavedIndicator.points(size: 24)
    check("the saved wedge is a triangle", wedge.count == 3)
    check("its right angle sits at the bottom-right corner",
          wedge[0] == CGPoint(x: 24, y: 24))
    check("one leg runs up the trailing edge", wedge[1] == CGPoint(x: 24, y: 0))
    check("the other runs along the bottom edge", wedge[2] == CGPoint(x: 0, y: 24))

    // Both legs are the full box, giving the artwork's 45 degree hypotenuse.
    check("the wedge's legs are equal, so its hypotenuse is 45 degrees",
          abs(wedge[0].y - wedge[1].y) == abs(wedge[0].x - wedge[2].x))

    // Scales with the asset rather than being hardcoded to 24.
    let smallWedge = SavedIndicator.points(size: SavedIndicator.smallSize)
    check("the small wedge is built at the small asset's size",
          smallWedge[0] == CGPoint(x: 18, y: 18))
    // The short action stays within one-thumb reach everywhere.
    check("the short action commits within a fifth of even a 320pt screen",
          SwipeCommitPolicy.commitThreshold(width: 320) < 320 * 0.2)

    // Both tiers stay within reach on the narrowest common iPhone.
    check("the long action is reachable on a 320pt screen",
          SwipeCommitPolicy.longThreshold(fraction: 0.7, width: 320) < 320 * 0.6)

    // The window in which the short action (Upvote on the Posts default) fires
    // must not be empty.
    let normal = 0.5
    let commitPoint = SwipeCommitPolicy.commitThreshold
    let longPoint = SwipeCommitPolicy.longThreshold(fraction: normal)
    check("a just-committing swipe performs the SHORT action",
          SwipeCommitPolicy.commits(distance: commitPoint) && !SwipeCommitPolicy.isLong(distance: commitPoint, fraction: normal))
    check("a swipe mid-window still performs the SHORT action",
          !SwipeCommitPolicy.isLong(distance: (commitPoint + longPoint) / 2, fraction: normal))
    check("a swipe past the long point performs the LONG action",
          SwipeCommitPolicy.isLong(distance: longPoint, fraction: normal))
    check("the short-action window is non-empty at every trigger point",
          LongSwipeTriggerPoint.allCases.allSatisfy {
              SwipeCommitPolicy.longThreshold(fraction: $0.fraction) > SwipeCommitPolicy.commitThreshold
          })

    // "Early" must trigger the long action sooner than "Late".
    check("Early triggers the long action before Normal",
          SwipeCommitPolicy.longThreshold(fraction: 0.3) < SwipeCommitPolicy.longThreshold(fraction: 0.5))
    check("Normal triggers the long action before Late",
          SwipeCommitPolicy.longThreshold(fraction: 0.5) < SwipeCommitPolicy.longThreshold(fraction: 0.7))

    // The long action must be achievable on a real screen.
    check("the long action is reachable within an iPhone 17's 393pt width",
          SwipeCommitPolicy.longThreshold(fraction: 0.7) < 393)

    // Upvote is the short post action by default.
    check("Posts left-short is Upvote", SwipeActionSettings.postsDefault.leftShort == .upvote)
    check("Posts left-long is Downvote", SwipeActionSettings.postsDefault.leftLong == .downvote)
}

// MARK: - Settings search (Reborn's settings search)

// The index is generated from the app's screen sources by
// scripts/generate/gen-settings-search-index.py; these assert against the
// shipped table rather than a fixture.
@MainActor func checkSettingsSearchApolloRebornSApolloSettingsSearch() async throws {
    check("the settings search index is populated",
          SettingsSearch.index.count > 200)

    func searchTitles(_ q: String, _ n: Int = 5) -> [String] {
        SettingsSearch.results(for: q).prefix(n).map(\.title)
    }

    check("an exact screen name is the top result",
          searchTitles("Gestures").first == "Gestures")
    check("a prefix finds its screen",
          searchTitles("Pictu").contains("Picture-in-Picture"))

    // Initialism rule.
    check("'pip' finds Picture-in-Picture by initialism",
          searchTitles("pip", 8).contains("Picture-in-Picture"))

    // Fuzzy rule: 4+ chars, one typo forgiven.
    check("a single substitution still finds the screen",
          searchTitles("gesteres", 8).contains("Gestures"))
    // Deliberate improvement on upstream: a transposition costs 1, not 2, so
    // the most common typo ("gestrues") still matches.
    check("a transposition still finds the screen, which upstream misses",
          searchTitles("gestrues", 8).contains("Gestures"))
    check("...and that is exactly what the distance function now says",
          SettingsSearch.editDistanceAtMost(Array("gestrues"), Array("gestures"), limit: 1) == 1)
    check("two separate typos are still rejected, so the cap did not widen",
          SettingsSearch.editDistanceAtMost(Array("gastrues"), Array("gestures"), limit: 1) > 1)
    check("a two-typo query does NOT match, matching the real one-edit cap",
          !searchTitles("gzstrxes", 20).contains("Gestures"))
    check("a short query is not fuzzily matched, per the 4-character floor",
          SettingsSearch.tokenFuzzyMatchesWord("abc", "abcd") == false)

    // Punctuation folds to spaces, so hyphens and ampersands need not be typed.
    check("punctuation need not be typed",
          searchTitles("picture in picture", 8).contains("Picture-in-Picture"))
    check("normalisation folds punctuation to single spaces",
          SettingsSearch.normalized("Picture-in-Picture") == "picture in picture")
    check("...and folds ampersands the same way",
          SettingsSearch.normalized("Backup & Restore") == "backup restore")

    // A screen and the row that opens it share a title; the screen wins
    // because it pushes where the row only flashes.
    let translationTop = SettingsSearch.results(for: "Translation").first
    check("a screen outranks the root row of the same name",
          translationTop?.title == "Translation" && translationTop?.rowTitle == nil)

    check("an unmatched query returns nothing rather than everything",
          SettingsSearch.results(for: "zzzqqqxx").isEmpty)
    check("an empty query returns nothing, so the list is not replaced by all 245 rows",
          SettingsSearch.results(for: "   ").isEmpty)

    // Breadcrumbs disambiguate identically named rows on different screens.
    let providers = SettingsSearch.index.filter { $0.title == "Provider" }
    check("identically named rows are kept apart by breadcrumb",
          providers.count < 2 || Set(providers.map(\.breadcrumb)).count == providers.count)

    // Every entry resolves to a real screen case.
    check("every index entry names a known screen",
          SettingsSearch.index.allSatisfy { SettingsSearchScreen(rawValue: $0.screen.rawValue) != nil })
}

// MARK: - Pinned settings preview cards

// Per-screen defaults keys.
@MainActor func checkPinnedSettingsPreviewCardsApolloSettingsPinnedPreview() async throws {
    check("the real per-screen defaults keys are used verbatim",
          SettingsPreviewScreen.subredditSections.rawValue == "SubredditSectionsPreviewPinned"
            && SettingsPreviewScreen.linkPreview.rawValue == "LinkPreviewPreviewPinned"
            && SettingsPreviewScreen.inlineMedia.rawValue == "InlineMediaPreviewPinned")
    check("the three layout previews get their own per-screen keys too",
          SettingsPreviewScreen.feedShortcuts.rawValue == "FeedShortcutsPreviewPinned"
            && SettingsPreviewScreen.subredditLayout.rawValue == "SubredditLayoutPreviewPinned"
            && SettingsPreviewScreen.profileLayout.rawValue == "ProfileLayoutPreviewPinned")
    check("no two preview screens share a defaults key",
          Set(SettingsPreviewScreen.allCases.map { SettingsPreviewPinStore.defaultsKey(for: $0) }).count
            == SettingsPreviewScreen.allCases.count)

    // Default is pinned (absent == YES), so a plain bool(forKey:) read, which
    // returns false for "never set", would ship the opposite default.
    for previewScreen in SettingsPreviewScreen.allCases {
        UserDefaults.standard.removeObject(forKey: SettingsPreviewPinStore.defaultsKey(for: previewScreen))
    }
    check("an absent preference means PINNED, not unpinned",
          SettingsPreviewScreen.allCases.allSatisfy { SettingsPreviewPinStore.isPinned($0) })

    SettingsPreviewPinStore.setPinned(false, for: .inlineMedia)
    check("an explicit unpin is honoured",
          SettingsPreviewPinStore.isPinned(.inlineMedia) == false)
    check("...and does not leak into another screen's preference",
          SettingsPreviewPinStore.isPinned(.linkPreview))
    SettingsPreviewPinStore.setPinned(true, for: .inlineMedia)
    check("re-pinning restores the pinned state",
          SettingsPreviewPinStore.isPinned(.inlineMedia))
    for previewScreen in SettingsPreviewScreen.allCases {
        UserDefaults.standard.removeObject(forKey: SettingsPreviewPinStore.defaultsKey(for: previewScreen))
    }

    // Strings.
    check("the pin glyph matches the real symbols",
          SettingsPreviewPinStore.symbolName(pinned: true) == "pin.fill"
            && SettingsPreviewPinStore.symbolName(pinned: false) == "pin")
    check("the caption matches the real wording",
          SettingsPreviewPinStore.caption(pinned: true) == "Pinned"
            && SettingsPreviewPinStore.caption(pinned: false) == "Unpinned")
    // The label describes the action, so it is the opposite of the state.
    check("the accessibility label names the action, not the state",
          SettingsPreviewPinStore.accessibilityLabel(pinned: true) == "Unpin preview"
            && SettingsPreviewPinStore.accessibilityLabel(pinned: false) == "Pin preview")

    // The preview mock's size detents are the setting's own, so the card
    // cannot disagree with the control driving it.
    check("the preview's size detents are the real 50/75/100%",
          InlineMediaSize.small.fraction == 0.5
            && InlineMediaSize.medium.fraction == 0.75
            && InlineMediaSize.large.fraction == 1.0)

    // Auto-contrast rule for custom link-preview card colors, promised by the
    // Rich Link Previews footer.
    check("luminance uses the real Rec. 709 coefficients",
          abs((HexContrast.luminance(ofHex: "00FF00") ?? 0) - 0.7152) < 0.0001)
    check("white needs dark text",
          HexContrast.needsDarkText(onHex: "FFFFFF"))
    check("black needs light text",
          !HexContrast.needsDarkText(onHex: "000000"))
    // The threshold is 0.6, not the 0.5 midpoint; this colour sits between
    // the two.
    check("a mid-tone above 0.5 but below 0.6 still gets LIGHT text, per the real 0.6 threshold",
          (HexContrast.luminance(ofHex: "999999") ?? 0) > 0.5
            && !HexContrast.needsDarkText(onHex: "999999"))
    check("the dark text colour is the real near-black, not pure black",
          HexContrast.darkTextRGB.red == 0.10 && HexContrast.darkTextRGB.blue == 0.11)
    check("a leading # is tolerated",
          HexContrast.needsDarkText(onHex: "#FFFFFF"))
    check("a malformed hex does not claim a contrast decision",
          HexContrast.luminance(ofHex: "nope") == nil)
}
