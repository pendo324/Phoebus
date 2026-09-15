import Foundation
import PhoebusCore

// MARK: - Rich Link Previews
//
// One fetch per link, from the source that knows it (as in Reborn), into one
// LinkPreview the card draws. The fixtures are trimmed real responses.
@MainActor func checkLinkPreviews() {
    func json(_ text: String) -> Any { try! JSONSerialization.jsonObject(with: Data(text.utf8)) }

    // Comment links that get cards.
    let body = """
    Test /r/apolloapp and u/pendo324, [GitHub](https://github.com/pendo324/) \
    https://x.com/shoe0nhead/status/2105684703235678418. Again https://github.com/pendo324/ \
    and an image https://i.redd.it/abc.jpg and [rel](/r/ios).
    """
    check("LinkCardDetector finds mentions, markdown links and bare URLs once each, in order, skipping inline media",
          LinkCardDetector.links(in: body).map(\.absoluteString) == [
              "https://www.reddit.com/r/apolloapp",
              "https://www.reddit.com/user/pendo324",
              "https://github.com/pendo324/",
              "https://x.com/shoe0nhead/status/2105684703235678418",
              "https://www.reddit.com/r/ios",
          ])
    check("LinkCardDetector.urls keeps every link in reading order, media and repeats included",
          LinkCardDetector.urls(in: "https://bsky.app/profile/a/post/b /u/pendo324 /r/apolloapp https://i.redd.it/x.jpg https://i.redd.it/x.jpg").map(\.absoluteString) == [
              "https://bsky.app/profile/a/post/b", "https://www.reddit.com/user/pendo324",
              "https://www.reddit.com/r/apolloapp", "https://i.redd.it/x.jpg", "https://i.redd.it/x.jpg",
          ])
    check("LinkCardDetector leaves r/ inside an address alone",
          LinkCardDetector.links(in: "see https://www.reddit.com/r/apolloapp/comments/abc/x/").count == 1)

    // Reddit targets.
    check("RedditLinkTarget reads profiles, subreddits and posts",
          RedditLinkTarget.parse(URL(string: "https://www.reddit.com/user/pendo324")!) == .user("pendo324")
            && RedditLinkTarget.parse(URL(string: "https://reddit.com/u/pendo324/")!) == .user("pendo324")
            && RedditLinkTarget.parse(URL(string: "https://www.reddit.com/r/apolloapp")!) == .subreddit("apolloapp")
            && RedditLinkTarget.parse(URL(string: "https://www.reddit.com/user/pendo324/comments/1wvy0pb/standards/")!) == .post(id: "1wvy0pb")
            && RedditLinkTarget.parse(URL(string: "https://redd.it/1wvy0pb")!) == .post(id: "1wvy0pb")
            && RedditLinkTarget.parse(URL(string: "https://www.reddit.com/r/a+b")!) == .other
            && RedditLinkTarget.parse(URL(string: "https://example.com/r/x")!) == nil)

    // Apollo's link-button icons.
    check("LinkButtonIcon picks Apollo's icon by link type",
          LinkButtonIcon.forURL(URL(string: "https://x.com/a/status/1")!) == .twitter
            && LinkButtonIcon.forURL(URL(string: "https://twitter.com/a")!) == .twitter
            && LinkButtonIcon.forURL(URL(string: "https://en.wikipedia.org/wiki/X")!) == .wikipedia
            && LinkButtonIcon.forURL(URL(string: "https://xkcd.com/927/")!) == .xkcd
            && LinkButtonIcon.forURL(URL(string: "https://www.reddit.com/r/ios")!) == .subreddit
            && LinkButtonIcon.forURL(URL(string: "https://www.reddit.com/r/ios/wiki/index")!) == .subredditWiki
            && LinkButtonIcon.forURL(URL(string: "https://www.reddit.com/user/a")!) == .profile
            && LinkButtonIcon.forURL(URL(string: "https://www.reddit.com/r/a+b")!) == .multireddit
            && LinkButtonIcon.forURL(URL(string: "https://www.reddit.com/r/a/comments/x/")!) == .reddit
            && LinkButtonIcon.forURL(URL(string: "https://example.com")!) == .safari)

    // X and twitter.com, and the fallback providers.
    check("TweetURL treats x.com, twitter.com and mobile.twitter.com alike",
          TweetURL.isTwitterHost(URL(string: "https://x.com/a")!)
            && TweetURL.isTwitterHost(URL(string: "https://mobile.twitter.com/a")!)
            && TweetURL.isTwitterHost(URL(string: "https://www.x.com/a")!)
            && !TweetURL.isTwitterHost(URL(string: "https://notx.com/a")!))
    check("Twitter fallback providers' endpoints",
          TwitterFallbackProvider.fxTwitter.apiURL(statusID: "21")?.absoluteString == "https://api.fxtwitter.com/status/21"
            && TwitterFallbackProvider.vxTwitter.apiURL(statusID: "21")?.absoluteString == "https://api.vxtwitter.com/Twitter/status/21"
            && TwitterFallbackProvider.none.apiURL(statusID: "21") == nil)
    let fx = TweetClient.parseFxTwitter(Data("""
    {"code":200,"tweet":{"text":"hello &amp; bye","author":{"name":"shoe","screen_name":"shoe0nhead","avatar_url":"https://pbs.twimg.com/a_200x200.jpg"},
     "media":{"all":[{"type":"photo","url":"https://pbs.twimg.com/m.jpg","width":1200,"height":800}]}}}
    """.utf8))
    check("FxTwitter parses author, text, avatar and photo size",
          fx?.name == "shoe" && fx?.username == "shoe0nhead" && fx?.text == "hello & bye"
            && fx?.mediaThumbnailURL?.absoluteString == "https://pbs.twimg.com/m.jpg"
            && fx?.mediaWidth == 1200 && fx?.mediaHeight == 800)
    let vx = TweetClient.parseVxTwitter(Data("""
    {"text":"hi","user_name":"shoe","user_screen_name":"shoe0nhead","user_profile_image_url":"https://pbs.twimg.com/J_normal.jpg",
     "media_extended":[{"thumbnail_url":"https://pbs.twimg.com/t.jpg","size":{"width":1920,"height":1080}}]}
    """.utf8))
    check("VxTwitter parses author, text, the larger avatar and media size",
          vx?.username == "shoe0nhead" && vx?.profilePictureURL?.absoluteString == "https://pbs.twimg.com/J_200x200.jpg"
            && vx?.mediaThumbnailURL?.absoluteString == "https://pbs.twimg.com/t.jpg" && vx?.mediaHeight == 1080)

    // Sources.
    let youTube = LinkPreviewFetcher.parseYouTubeOEmbed(json("""
    {"title":"Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)","author_name":"Rick Astley",
     "thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg","thumbnail_width":480,"thumbnail_height":360}
    """))
    check("YouTube oEmbed gives title, channel and thumbnail",
          youTube?.siteName == "YouTube" && youTube?.description == "Rick Astley" && youTube?.imageWidth == 480)
    let user = LinkPreviewFetcher.parseRedditUser(json("""
    {"data":{"name":"pendo324","icon_img":"https://styles.redditmedia.com/a.png?width=256&amp;s=1",
     "subreddit":{"title":"","public_description":"Guy that programs, reads books, and plays games"}}}
    """))
    check("Reddit profile card: name, u/handle, about text, unescaped avatar",
          user?.kind == .redditUser && user?.authorName == "pendo324" && user?.authorHandle == "u/pendo324"
            && user?.description == "Guy that programs, reads books, and plays games"
            && user?.avatarURL?.absoluteString == "https://styles.redditmedia.com/a.png?width=256&s=1")
    let subreddit = LinkPreviewFetcher.parseRedditSubreddit(json("""
    {"data":{"display_name":"apolloapp","title":"Apollo App","subscribers":736214,
     "public_description":"Apollo was an award-winning free Reddit app","community_icon":"https://styles.redditmedia.com/i.png?a=1&amp;b=2"}}
    """))
    check("Subreddit card: title, r/handle, member count as Reborn formats it",
          subreddit?.kind == .redditSubreddit && subreddit?.title == "Apollo App"
            && subreddit?.authorHandle == "r/apolloapp" && subreddit?.members == "736k members")
    check("Member counts: 1.2k, 736k, 1.5M, 12M",
          LinkPreviewRules.formattedMembers(1234) == "1.2k members" && LinkPreviewRules.formattedMembers(736_214) == "736k members"
            && LinkPreviewRules.formattedMembers(1_500_000) == "1.5M members" && LinkPreviewRules.formattedMembers(12_000_000) == "12M members")
    let post = LinkPreviewFetcher.parseRedditPost(json("""
    [{"data":{"children":[{"data":{"title":"Standards","selftext":"",
      "preview":{"images":[{"source":{"url":"https://preview.redd.it/x.png?a=1&amp;b=2","width":500,"height":283}}]}}}]}}]
    """))
    check("Reddit post link: title and Reddit's preview image",
          post?.title == "Standards" && post?.description == nil
            && post?.imageURL?.absoluteString == "https://preview.redd.it/x.png?a=1&b=2" && post?.imageHeight == 283)
    let gitHub = LinkPreviewFetcher.parseGitHub(json("""
    {"full_name":"pendo324/Phoebus","description":"A Reddit client","owner":{"avatar_url":"https://avatars.githubusercontent.com/u/1"}}
    """))
    check("GitHub repository: full name, description, owner avatar",
          gitHub?.siteName == "GitHub" && gitHub?.title == "pendo324/Phoebus" && gitHub?.imageURL != nil)
    let bluesky = BlueskyPost.parseThread(json("""
    {"thread":{"post":{"author":{"displayName":"Michael Warburton","handle":"michaelwarburton.bsky.social","avatar":"https://cdn.bsky.app/a.jpg"},
     "record":{"text":"René Magritte at work in his living room in 1964"},
     "embed":{"images":[{"thumb":"https://cdn.bsky.app/t.jpg","aspectRatio":{"width":1000,"height":800}}]}}}}
    """))
    check("Bluesky post: name, @handle, text, image and its shape",
          bluesky?.kind == .socialPost && bluesky?.authorName == "Michael Warburton"
            && bluesky?.authorHandle == "@michaelwarburton.bsky.social"
            && bluesky?.postText == "René Magritte at work in his living room in 1964"
            && bluesky?.imageAspect == 0.8)
    check("Bluesky post links parse to handle and record key",
          BlueskyPost.parts(from: URL(string: "https://bsky.app/profile/michaelwarburton.bsky.social/post/3mwviv6b3u22w")!)?.rkey == "3mwviv6b3u22w")
    check("DOIs from doi.org, Nature and /doi/ paths",
          CrossrefWork.doi(from: URL(string: "https://doi.org/10.1000/xyz123")!) == "10.1000/xyz123"
            && CrossrefWork.doi(from: URL(string: "https://www.nature.com/articles/s41586-024-07000-1")!) == "10.1038/s41586-024-07000-1"
            && CrossrefWork.doi(from: URL(string: "https://journals.example.org/doi/10.1126/science.abc")!) == "10.1126/science.abc")
    let info = LinkPreviewFetcher.parseRedditInfo(json("""
    {"data":{"children":[{"data":{"title":"No preview"}},{"data":{"title":"Headline","preview":{"images":[{"source":{"url":"https://external-preview.redd.it/p.jpg","width":1200,"height":630}}]}}}]}}
    """), url: URL(string: "https://www.reuters.com/a")!)
    check("Walled pages use the first Reddit submission with a preview image",
          info?.title == "Headline" && info?.siteName == "reuters.com")

    // Layout rules.
    check("Compact description lines: 2, then 1 from 70 characters, none from 110",
          LinkPreviewRules.compactDescriptionLines(titleLength: 40) == 2
            && LinkPreviewRules.compactDescriptionLines(titleLength: 70) == 1
            && LinkPreviewRules.compactDescriptionLines(titleLength: 110) == 0)
    let tall = LinkPreview(imageURL: URL(string: "https://a/b.jpg"), imageWidth: 400, imageHeight: 800)
    check("Full image: YouTube 16:9, tall images held to 0.6, poster sites shown whole up to 1.1",
          LinkPreviewRules.fullImageAspect(for: URL(string: "https://youtu.be/x")!, preview: tall).ratio == 9.0 / 16.0
            && LinkPreviewRules.fullImageAspect(for: URL(string: "https://example.com")!, preview: tall).ratio == 0.6
            && LinkPreviewRules.fullImageAspect(for: URL(string: "https://www.imdb.com/title/tt1")!, preview: tall) == (1.1, true))
    check("Numeric page titles become the site's name",
          LinkPreviewRules.displayTitle("285023 289273 400021448", url: URL(string: "https://www.fifa.com/x")!) == "FIFA")
    check("Use Community Icons defaults on, and an old settings blob without it decodes on",
          GeneralSettings.default.useCommunityIcons
            && ((try? JSONDecoder().decode(GeneralSettings.self, from: Data("{}".utf8)))?.useCommunityIcons ?? false))
    check("Badge Book trophy slugs match Reddit's icon names to Reborn's catalogue ids",
          BadgeBookArt.trophySlug("14_year_club-70.png") == "14_year_club"
            && BadgeBookArt.trophySlug("d1fed68c52a02fad_trophy_image_for_14_year_club") == "14_year_club"
            && BadgeBookArt.trophySlug("verified_email-70.png") == "verified_email")
    let art = BadgeBookArt(catalogJSON: Data(#"{"trophies":[{"id":"034d06bbd23e0a6d_trophy_image_for_verified_email","title":"Verified Email","image":"t_v.png","image_url":"https://i.redd.it/cms/x.png"}],"achievements":[{"id":"a","title":"A","image":"a_a.png","image_url":"https://i.redd.it/mgol2ep2mnwd1.png"}]}"#.utf8))
    check("Badge Book art: trophies by icon slug or title, achievements by image name",
          art.trophyFile(iconURL: "https://www.redditstatic.com/awards2/verified_email-70.png", title: nil) == "t_v.png"
            && art.trophyFile(iconURL: nil, title: "verified email") == "t_v.png"
            && art.file(imageURL: "https://i.redd.it/mgol2ep2mnwd1.png?x=1") == "a_a.png")
    check("Twitter fallback provider defaults to None",
          LinkPreviewSettings.default.twitterFallback == .none)
}
