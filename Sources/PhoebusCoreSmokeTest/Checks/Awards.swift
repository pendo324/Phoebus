import Foundation
import PhoebusCore

// MARK: - Reddit awards
//
// Fixtures in Tests/Fixtures/awards-* are trimmed captures of Shreddit's
// comment-tree fragment, award dialog, leaderboard and CreateAwardOrder reply,
// with usernames, signatures and ids of the account scrubbed.

private func tally(_ id: String, count: Int, gold: Int) -> AwardTally {
    AwardTally(id: id, name: id, count: count, gold: gold, iconURL: nil)
}

@MainActor func checkAwards() async {
    // The decided rule for the featured award.
    check("awards: nothing given features nothing", AwardSummary.featured(from: []) == nil
          && AwardSummary.featured(from: [tally("a", count: 0, gold: 0)]) == nil)
    check("awards: a paid award beats a more-given free one",
          AwardSummary.featured(from: [tally("free", count: 119, gold: 0), tally("paid", count: 3, gold: 45)])?.id == "paid")
    check("awards: the paid award with the most gold beats a more-given paid one",
          AwardSummary.featured(from: [tally("many", count: 10, gold: 50), tally("rich", count: 1, gold: 500)])?.id == "rich")
    check("awards: equal gold goes to the higher count",
          AwardSummary.featured(from: [tally("one", count: 1, gold: 100), tally("two", count: 2, gold: 100)])?.id == "two")
    check("awards: equal gold and count goes to the earlier row",
          AwardSummary.featured(from: [tally("first", count: 2, gold: 100), tally("second", count: 2, gold: 100)])?.id == "first")
    check("awards: free awards only features the most given",
          AwardSummary.featured(from: [tally("a", count: 2, gold: 0), tally("b", count: 9, gold: 0), tally("c", count: 4, gold: 0)])?.id == "b")
    check("awards: free awards tie to the earlier row",
          AwardSummary.featured(from: [tally("a", count: 3, gold: 0), tally("b", count: 3, gold: 0)])?.id == "a")

    // The thread fragment.
    let fragment = String(decoding: fixture("awards-thread-fragment.html"), as: UTF8.self)
    check("awards: the fragment fixture loads", fragment.contains("award-button"))
    let badges = AwardHTML.badges(inFragment: fragment)
    check("awards: only awarded comments get a badge", badges.count == 4 && badges["t1_pgv4oq3"] == nil)
    let lol = badges["t1_pgtttt2"]
    check("awards: a badge carries Reddit's featured award, icon and total",
          lol?.count == 137 && lol?.awardID == "award_lol_2"
          && lol?.iconURL?.absoluteString == "https://i.redd.it/snoovatar/snoo_assets/marketing/Lol_40.png")
    check("awards: has-paid-award marks the paid badge", lol?.hasPaidAward == true && badges["t1_pgtuly4"]?.hasPaidAward == true)
    check("awards: a free-only comment shows Bravo, not paid",
          badges["t1_pgtuwpd"]?.awardID == "award_free_bravo" && badges["t1_pgtuwpd"]?.count == 12
          && badges["t1_pgtuwpd"]?.hasPaidAward == false)

    let messy = """
    <shreddit-comment thingId="t1_a" award-count="4"><award-button thing-id="t1_a" count="4" award-id="award_free_bravo" icon-url="https://i.redd.it/x.png?a=1&amp;b=2"></award-button></shreddit-comment>
    <award-button thing-id="t1_zero" count="0" award-id="award_free_bravo" icon-url="https://i.redd.it/x.png"></award-button>
    <award-button thing-id="t1_nan" count="many" award-id="award_free_bravo"></award-button>
    <award-button count="3" award-id="award_free_bravo"></award-button>
    <award-button thing-id="t1_http" count="2" award-id="award_lol_2" icon-url="http://i.redd.it/x.png"></award-button>
    <shreddit-comment thingId="t1_nobutton" award-count="1" has-paid-award></shreddit-comment>
    <award-button thing-id="t1_cut" count="5" award-id="award_lol
    """
    let found = AwardHTML.badges(inFragment: messy)
    check("awards: an escaped ampersand in an icon URL is decoded", found["t1_a"]?.iconURL?.absoluteString == "https://i.redd.it/x.png?a=1&b=2")
    check("awards: zero, non-numeric and id-less buttons are dropped",
          found["t1_zero"] == nil && found["t1_nan"] == nil && found.keys.sorted() == ["t1_a", "t1_http", "t1_nobutton"])
    check("awards: a non-https icon is not used, the count still is",
          found["t1_http"]?.iconURL == nil && found["t1_http"]?.count == 2 && found["t1_http"]?.hasPaidAward == true)
    check("awards: a counted comment without a button keeps its count and paid flag",
          found["t1_nobutton"]?.count == 1 && found["t1_nobutton"]?.awardID == nil && found["t1_nobutton"]?.hasPaidAward == true)
    check("awards: a truncated tag and an empty page give nothing",
          found["t1_cut"] == nil && AwardHTML.badges(inFragment: "").isEmpty
          && AwardHTML.badges(inFragment: "<html>Prove your humanity</html>").isEmpty)

    // The leaderboard.
    let boardHTML = String(decoding: fixture("awards-leaderboard.html"), as: UTF8.self)
    let board = AwardHTML.leaderboard(html: boardHTML)
    check("awards: leaderboard totals", board?.totalAwards == 137 && board?.totalGold == 45)
    check("awards: leaderboard rows keep Reddit's order, counts and gold",
          board?.tallies.map(\.name) == ["LOL", "Bravo", "Popcorn", "Mindblown", "Heartwarming", "Regret"]
          && board?.tallies.map(\.count) == [3, 119, 8, 4, 2, 1]
          && board?.tallies.map(\.gold) == [45, 0, 0, 0, 0, 0])
    check("awards: leaderboard rows carry award ids and 128px icons",
          board?.tallies.first?.id == "award_lol_2"
          && board?.tallies.first?.iconURL?.absoluteString == "https://i.redd.it/snoovatar/snoo_assets/marketing/men5kjSXS0w_lol_128.png"
          && board?.tallies[1].iconURL?.absoluteString.hasSuffix("_bravo_128.png") == true)
    check("awards: t1_pgtttt2 features LOL, not the more-given Bravo", board?.featured?.name == "LOL")
    check("awards: top awarders, anonymous ones without a name",
          board?.topAwarders == [AwardGiver(username: nil, gold: 15), AwardGiver(username: "example_giver_one", gold: 15),
                                 AwardGiver(username: "example_giver_two", gold: 15)])
    check("awards: a page that isn't the leaderboard gives nothing",
          AwardHTML.leaderboard(html: "<html>login</html>") == nil)

    // The dialog.
    let dialogHTML = String(decoding: fixture("awards-dialog.html"), as: UTF8.self)
    let dialog = AwardHTML.dialog(html: dialogHTML)
    check("awards: the dialog lists the whole catalogue", dialog?.catalogue.count == 25)
    check("awards: free awards are price 0 and quick give",
          dialog?.catalogue.filter(\.isFree).map(\.id) ==
          ["award_free_bravo", "award_free_heartwarming", "award_free_mindblown", "award_free_regret_2", "award_free_popcorn_2"]
          && dialog?.catalogue.filter(\.isFree).allSatisfy(\.isQuickGive) == true)
    check("awards: a paid award has its price and 128px icon",
          dialog?.catalogue.first { $0.id == "award_hooray_3" }?.goldPrice == 15
          && dialog?.catalogue.first { $0.id == "award_hooray_3" }?.isQuickGive == false
          && dialog?.catalogue.first { $0.id == "award_hooray_3" }?.iconURL?.absoluteString.hasSuffix("FTUE_128.png") == true)
    check("awards: the dialog states the user's Gold", dialog?.goldBalance == 120)
    check("awards: the leaderboard link is Reddit's own signed partial",
          dialog?.leaderboardURL?.absoluteString
          == "https://www.reddit.com/svc/shreddit/partial/HBSq47/award-leaderboard?params=thingId%3Dt1_pgtttt2&sig=v1.SCRUBBED")
    let hooray = dialog?.catalogue.first { $0.id == "award_hooray_3" }
    let bravo = dialog?.catalogue.first { $0.id == "award_free_bravo" }
    check("awards: free is always affordable, paid depends on the Gold balance",
          bravo.flatMap { dialog?.canAfford($0) } == true && hooray.flatMap { dialog?.canAfford($0) } == true
          && dialog.flatMap { d in hooray.flatMap { AwardDialog(catalogue: d.catalogue, goldBalance: 14, leaderboardURL: nil).canAfford($0) } } == false)
    check("awards: with no stated balance a paid award is undecided",
          dialog.flatMap { d in hooray.flatMap { AwardDialog(catalogue: d.catalogue, goldBalance: nil, leaderboardURL: nil).canAfford($0) } } == nil)
    check("awards: a page without awards is not a dialog", AwardHTML.dialog(html: "<html>login</html>") == nil)

    // CreateAwardOrder.
    let variables = AwardWebService.orderVariables(thingID: "t1_pgtttt2", awardID: "award_free_bravo", isAnonymous: true, nonce: "n-1")
    let input = variables["input"] as? [String: Any]
    check("awards: the order input is nonce, thingId, awardId and isAnonymous only",
          input?.keys.sorted() == ["awardId", "isAnonymous", "nonce", "thingId"]
          && input?["thingId"] as? String == "t1_pgtttt2" && input?["awardId"] as? String == "award_free_bravo"
          && input?["isAnonymous"] as? Bool == true && input?["nonce"] as? String == "n-1")
    let fresh = AwardWebService.orderVariables(thingID: "t1_a", awardID: "x", isAnonymous: false)
    let other = AwardWebService.orderVariables(thingID: "t1_a", awardID: "x", isAnonymous: false)
    check("awards: every order gets a fresh nonce",
          (fresh["input"] as? [String: Any])?["nonce"] as? String != (other["input"] as? [String: Any])?["nonce"] as? String)

    let orderJSON = (try? JSONSerialization.jsonObject(with: fixture("awards-create-order.json"))) as? [String: Any] ?? [:]
    let order = try? AwardWebService.decodeOrder(from: orderJSON)
    check("awards: an accepted order names the award, price and icon",
          order == AwardOrderResult(awardID: "award_free_bravo", name: "Bravo", goldPrice: 0,
                                    iconURL: URL(string: "https://i.redd.it/snoovatar/snoo_assets/marketing/bravo_40.png")))
    func failure(_ json: [String: Any]) -> AwardError? {
        do { _ = try AwardWebService.decodeOrder(from: json); return nil } catch { return error as? AwardError }
    }
    check("awards: ok false is a refusal carrying Reddit's message",
          failure(["data": ["createAwardOrder": ["ok": false, "errors": [["message": "Not enough Gold"]]]]])
          == .rejected("Not enough Gold"))
    check("awards: ok true with a warning, a missing award or a null payload is not a success",
          (failure(["data": ["createAwardOrder": ["ok": true, "errors": NSNull(), "awarding": NSNull()]]]) != nil)
          && failure(["data": ["createAwardOrder": NSNull()]]) != nil
          && failure(["data": ["createAwardOrder": ["ok": true, "awarding": ["award": ["id": "a"]]]],
                      "extensions": ["warnings": [["extensions": ["code": "BAD_REQUEST"]]]]]) != nil)

    // The badge after the user gives an award.
    let bravoResult = AwardOrderResult(awardID: "award_free_bravo", name: "Bravo", goldPrice: 0, iconURL: nil)
    let paidResult = AwardOrderResult(awardID: "award_lol_2", name: "LOL", goldPrice: 15,
                                      iconURL: URL(string: "https://i.redd.it/lol_40.png"))
    let freeBadge = AwardBadge(thingID: "t1_a", count: 12, awardID: "award_free_bravo",
                               iconURL: URL(string: "https://i.redd.it/bravo_40.png"), hasPaidAward: false)
    let paidBadge = AwardBadge(thingID: "t1_a", count: 3, awardID: "award_galaxy_brain_2", iconURL: nil, hasPaidAward: true)
    check("awards: a free award adds one and keeps the icon", freeBadge.givingAward(bravoResult).count == 13
          && freeBadge.givingAward(bravoResult).awardID == "award_free_bravo")
    check("awards: a paid award takes over a free badge's icon",
          freeBadge.givingAward(paidResult).awardID == "award_lol_2" && freeBadge.givingAward(paidResult).hasPaidAward)
    check("awards: a paid award does not replace another paid award's icon without the gold totals",
          paidBadge.givingAward(paidResult).awardID == "award_galaxy_brain_2" && paidBadge.givingAward(paidResult).count == 4)
    let empty = AwardBadge(thingID: "t1_b", count: 0, awardID: nil, iconURL: nil, hasPaidAward: false)
    check("awards: the first award on a thing sets its icon",
          empty.givingAward(bravoResult).count == 1 && empty.givingAward(bravoResult).awardID == "award_free_bravo")

    // Fragment URLs.
    check("awards: the thread fragment URL",
          AwardWebService.threadFragmentURL(subreddit: "whatisit", postID: "1x6b3tg", sort: "confidence")?.absoluteString
          == "https://www.reddit.com/svc/shreddit/comments/r/whatisit/1x6b3tg?render-mode=partial&sort=CONFIDENCE")
    check("awards: a sort Shreddit has no name for leaves its default",
          AwardWebService.threadFragmentURL(subreddit: "a", postID: "b", sort: "random")?.absoluteString
          == "https://www.reddit.com/svc/shreddit/comments/r/a/b?render-mode=partial")
    check("awards: a subreddit or id that isn't a plain slug builds no URL",
          AwardWebService.threadFragmentURL(subreddit: "a/../b", postID: "x", sort: "top") == nil
          && AwardWebService.threadFragmentURL(subreddit: "a", postID: "x?y", sort: "top") == nil
          && AwardWebService.threadFragmentURL(subreddit: "", postID: "x", sort: "top") == nil)
    check("awards: the thread's trailing stub asks for the next top-level comments",
          AwardWebService.moreCommentsURL(subreddit: "whatisit", postID: "1x6b3tg", sort: "confidence",
                                          position: .init(parentPath: [], loaded: 14, remaining: 100))?.absoluteString
          == "https://www.reddit.com/svc/shreddit/more-comments/r/whatisit/t3_1x6b3tg?sort=CONFIDENCE&top-level=1&comments-remaining=100&commentPositionOffset=14")
    check("awards: a nested stub is addressed by its parent's position",
          AwardWebService.moreCommentsURL(subreddit: "whatisit", postID: "1x6b3tg", sort: "confidence",
                                          position: .init(parentPath: [2, 0], loaded: 3, remaining: 0))?.absoluteString
          == "https://www.reddit.com/svc/shreddit/more-comments/r/whatisit/t3_1x6b3tg?sort=CONFIDENCE&startingDepth=2&commentPositionOffset=3&commentParentPositions=2,0")
    check("awards: a stub with no loaded replies sends no offset",
          AwardWebService.moreCommentsURL(subreddit: "whatisit", postID: "1x6b3tg", sort: "confidence",
                                          position: .init(parentPath: [0, 0, 0], loaded: 0, remaining: 0))?.absoluteString
          == "https://www.reddit.com/svc/shreddit/more-comments/r/whatisit/t3_1x6b3tg?sort=CONFIDENCE&startingDepth=3&commentParentPositions=0,0,0")

    // Where a stub sits in the loaded tree.
    let deepStub = MoreStub(id: "m2", count: 4, children: ["x"], parentID: "t1_c", depth: 2)
    let replyStub = MoreStub(id: "m1", count: 2, children: ["y"], parentID: "t1_b", depth: 1)
    let rootStub = MoreStub(id: "m0", count: 80, children: ["z"], parentID: "t3_p", depth: 0)
    let grandchild = CommentTreeNode(comment: makeComment(id: "c"), depth: 2, moreStub: deepStub)
    let child = CommentTreeNode(comment: makeComment(id: "b"), depth: 1)
    let mid = CommentTreeNode(comment: makeComment(id: "a2"), depth: 1, children: [grandchild])
    let first = CommentTreeNode(comment: makeComment(id: "a"), depth: 0, children: [mid, child], moreStub: replyStub)
    let second = CommentTreeNode(comment: makeComment(id: "d"), depth: 0)
    let tree = [first, second]
    check("awards: the thread's trailing stub is positioned by the top-level count",
          tree.awardMorePosition(of: rootStub, rootStub: rootStub) == .init(parentPath: [], loaded: 2, remaining: 80))
    check("awards: a reply stub is positioned by its parent's path and loaded replies",
          tree.awardMorePosition(of: replyStub, rootStub: rootStub) == .init(parentPath: [0], loaded: 2, remaining: 2))
    check("awards: a deeper stub gets the full parent path",
          tree.awardMorePosition(of: deepStub, rootStub: nil) == .init(parentPath: [0, 0, 0], loaded: 0, remaining: 4))
    check("awards: a stub that isn't in the tree has no position",
          tree.awardMorePosition(of: MoreStub(id: "gone", count: 1, children: [], parentID: "t1_q", depth: 1), rootStub: rootStub) == nil)

    // The side table.
    let store = AwardStore.shared
    let start = Date(timeIntervalSince1970: 1_000_000)
    let parsed = AwardHTML.fragment(fragment)
    check("awards: the fragment lists every comment, awarded or not",
          parsed.listed.count == 6 && parsed.listed.contains("t1_pgv4oq3") && parsed.badges.count == 4)
    check("awards: a thread loads once", store.beginLoad(thread: "smoke1", now: start) && !store.beginLoad(thread: "smoke1", now: start))
    store.finishLoad(thread: "smoke1", found: parsed, replacing: true, now: start)
    check("awards: loaded badges are readable by fullname", store.badge(for: "t1_pgtttt2")?.count == 137)
    check("awards: reopening within the lifetime asks for nothing",
          !store.beginLoad(thread: "smoke1", now: start.addingTimeInterval(AwardStore.lifetime - 1)))
    check("awards: after the lifetime, or on a refresh, it asks again",
          store.beginLoad(thread: "smoke1", now: start.addingTimeInterval(AwardStore.lifetime + 1)))
    store.failLoad(thread: "smoke1", now: start.addingTimeInterval(AwardStore.lifetime + 2))
    check("awards: a failed load keeps the badges and waits before retrying",
          store.badge(for: "t1_pgtttt2")?.count == 137
          && !store.beginLoad(thread: "smoke1", now: start.addingTimeInterval(AwardStore.lifetime + 3))
          && store.beginLoad(thread: "smoke1", force: true, now: start.addingTimeInterval(AwardStore.lifetime + 3)))
    store.finishLoad(thread: "smoke1", found: .init(badges: ["t1_pgtuwpd": parsed.badges["t1_pgtuwpd"]!],
                                                    listed: ["t1_pgtuwpd", "t1_quiet"]), replacing: true, now: start)
    check("awards: a refresh replaces the thread's badges", store.badge(for: "t1_pgtttt2") == nil && store.badge(for: "t1_pgtuwpd") != nil)
    store.merge(.init(badges: ["t1_pgtttt2": lol!], listed: ["t1_pgtttt2"]), thread: "smoke1")
    check("awards: a more-comments answer adds to the thread", store.badge(for: "t1_pgtttt2") != nil && store.badge(for: "t1_pgtuwpd") != nil)
    store.recordGiven(bravoResult, to: "t1_pgtuwpd")
    check("awards: giving updates the row without a fetch", store.badge(for: "t1_pgtuwpd")?.count == 13)
    store.recordGiven(bravoResult, to: "t1_quiet")
    check("awards: the first award on a listed thing without awards shows at once",
          store.badge(for: "t1_quiet")?.count == 1 && store.badge(for: "t1_quiet")?.awardID == "award_free_bravo")
    store.recordGiven(bravoResult, to: "t3_neverlisted")
    check("awards: a thing the listing never covered shows nothing rather than a guessed count",
          store.badge(for: "t3_neverlisted") == nil)
    for index in 0..<AwardStore.maxThreads + 1 {
        _ = store.beginLoad(thread: "evict\(index)", now: start)
    }
    check("awards: the oldest threads give up their badges", store.badge(for: "t1_pgtuwpd") == nil && store.badge(for: "t1_quiet") == nil)
}
