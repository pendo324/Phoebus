import Foundation
import PhoebusCore

// --- Per-community achievements (Shreddit UserCommunityAchievements) ---
func checkCommunityAchievements() async throws {
    let normal = CommunityAchievementsService.parse(Data("""
    {"data":{"redditorInfoByName":{"__typename":"Redditor","trophyCase":{"totalUnlocked":18,"trophiesBySubredditId":[
      {"__typename":"AchievementRepeatableImageTrophy","id":"elder","name":"Elder","gridImage":{"url":"https://preview.redd.it/elder.png?width=100&amp;s=abc"}},
      {"__typename":"AchievementSomethingNew","id":"brand-new-kind","name":"Brand New","gridImage":null},
      {"__typename":"AchievementBroken","name":"No Id"}
    ]}}},"errors":[]}
    """.utf8))
    check("CommunityAchievements parses totalUnlocked", normal.totalUnlocked == 18)
    check("CommunityAchievements keeps trophies with an id and name", normal.trophies.map(\.id) == ["elder", "brand-new-kind"])
    check("CommunityAchievements unescapes the image URL", normal.trophies.first?.imageURL?.absoluteString == "https://preview.redd.it/elder.png?width=100&s=abc")
    check("CommunityAchievements keeps the typename", normal.trophies.first?.typename == "AchievementRepeatableImageTrophy")
    check("CommunityAchievements tolerates a null image", normal.trophies.last?.imageURL == nil)
    check("CommunityAchievements links a trophy to its Badge Book entry", normal.trophies.first?.catalogEntry?.id == "elder")
    check("CommunityAchievements leaves an unmapped trophy unlinked", normal.trophies.last?.catalogEntry == nil)

    let emptyList = CommunityAchievementsService.parse(Data("""
    {"data":{"redditorInfoByName":{"__typename":"Redditor","trophyCase":{"totalUnlocked":0,"trophiesBySubredditId":[]}}},"errors":[]}
    """.utf8))
    check("CommunityAchievements parses an empty list", emptyList.trophies.isEmpty && emptyList.totalUnlocked == 0)

    let errors = CommunityAchievementsService.parse(Data("""
    {"data":null,"errors":[{"message":"boom"}]}
    """.utf8))
    check("CommunityAchievements reads GraphQL errors as empty", errors == .empty)

    let anonymous = CommunityAchievementsService.parse(Data("""
    {"data":{"redditorInfoByName":null},"errors":[]}
    """.utf8))
    check("CommunityAchievements reads an anonymous reply as empty", anonymous == .empty)
    check("CommunityAchievements reads non-JSON as empty", CommunityAchievementsService.parse(Data("<html>".utf8)) == .empty)

    let variables = CommunityAchievementsService.variables(username: "someone", subredditID: "2qh1i")
    check("CommunityAchievements request prefixes the subreddit id", variables["subredditId"] as? String == "t5_2qh1i")
    check("CommunityAchievements request keeps an existing t5_ prefix",
          CommunityAchievementsService.variables(username: "someone", subredditID: "t5_2qh1i")["subredditId"] as? String == "t5_2qh1i")
    check("CommunityAchievements request asks for 100pt images", variables["imageMaxWidth"] as? Int == 100)
    check("CommunityAchievements referer names the subreddit", CommunityAchievementsService.referer(subreddit: "pics") == "https://www.reddit.com/r/pics/")

    let key = CommunityAchievementsCache.key(username: "Someone", subredditID: "2qh1i")
    check("CommunityAchievements cache key ignores case and t5_ prefix",
          key == CommunityAchievementsCache.key(username: "someone", subredditID: "t5_2QH1I"))
    await CommunityAchievementsCache.shared.store(normal, for: key)
    let stored = await CommunityAchievementsCache.shared.value(for: key)
    check("CommunityAchievements cache returns the stored value", stored == normal)
    let other = await CommunityAchievementsCache.shared.value(for: CommunityAchievementsCache.key(username: "someone", subredditID: "t5_other"))
    check("CommunityAchievements cache is per subreddit", other == nil)
}
