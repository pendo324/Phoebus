import Foundation
import PhoebusCore

// MARK: - Post Insights
//
// The author-only /poststats/<id>/ page. The fixture is a synthetic page that
// mirrors the structure of a real one (chart tooltip JSON, aria-labelled
// metric rows, country rows, top-comment blocks).
func checkPostInsights() {
    let html = String(decoding: fixture("poststats-synthetic.html"), as: UTF8.self)
    check("post insights: the fixture loads", html.contains("post_stats"))

    let insights = try? PostInsightsParser.parse(html: html)
    check("post insights: title is the post's, entities decoded", insights?.postTitle == "Example & post title")
    check("post insights: views total with a grouping separator", insights?.views == 1234)
    check("post insights: hourly views come from the chart JSON",
          insights?.hourlyViews.count == 48 && insights?.hourlyViews[0] == 12 && insights?.hourlyViews[10] == 1)
    check("post insights: countries keep flags and percentages",
          insights?.countries.map(\.name) == ["United States", "Germany", "Other"]
          && insights?.countries.first?.flag == "🇺🇸" && insights?.countries.first?.percent == 60)
    check("post insights: the Other bucket has no flag", insights?.countries.last?.flag == nil)
    check("post insights: engagement metrics",
          insights?.upvotes == 42 && insights?.upvoteRatioPercent == 93 && insights?.comments == 3)
    check("post insights: shares, reposts and awards after the top comments are read",
          insights?.shares == 4 && insights?.reposts == 1 && insights?.awards == 2)
    check("post insights: top comments carry author, age, votes, text and id",
          insights?.topComments.count == 2
          && insights?.topComments.first?.author == "commenter_one"
          && insights?.topComments.first?.ageText == "2 days ago"
          && insights?.topComments.first?.votes == 5
          && insights?.topComments.first?.text.hasPrefix("First top comment") == true
          && insights?.topComments.first?.commentID == "c1aaaaa")
    check("post insights: a top comment's permalink resolves to an absolute URL",
          insights?.topComments.first?.url?.absoluteString
          == "https://www.reddit.com/user/exampleuser/comments/abc123/example_post/c1aaaaa/")
    check("post insights: a top comment's upvote label is not mistaken for the post's",
          insights?.upvotes == 42)

    check("post insights: hour label is singular for one view",
          insights?.hourLabel(11) == "Hour 11: 1 view" && insights?.hourLabel(1) == "Hour 1: 12 views"
          && insights?.hourLabel(0) == nil && insights?.hourLabel(49) == nil)
    check("post insights: chart summary names the total and the busiest hour",
          insights?.chartAccessibilitySummary
          == "Views for the first 48 hours: 23 in total, most at hour 1 with 12")

    // The screen-reader list is the fallback when the tooltip JSON is absent.
    let withoutJSON = html.replacingOccurrences(of: "tooltip-data=", with: "data-x=")
    let fallback = try? PostInsightsParser.parse(html: withoutJSON)
    check("post insights: hourly views fall back to the screen-reader list",
          fallback?.hourlyViews == insights?.hourlyViews)

    // Missing sections stay nil/empty, not an error.
    let sparse = """
    <html><body pageType="post_stats"><h1>Post Insights</h1>
    <div aria-label="10 views"></div></body></html>
    """
    let sparseInsights = try? PostInsightsParser.parse(html: sparse)
    check("post insights: a page with only views parses",
          sparseInsights?.views == 10 && sparseInsights?.hourlyViews.isEmpty == true
          && sparseInsights?.countries.isEmpty == true && sparseInsights?.upvotes == nil
          && sparseInsights?.topComments.isEmpty == true && sparseInsights?.isEmpty == false)
    check("post insights: a page with no sections is empty",
          (try? PostInsightsParser.parse(html: "<body pageType=\"post_stats\"></body>"))?.isEmpty == true)
    check("post insights: an empty chart summary says so",
          PostInsights().chartAccessibilitySummary == "No views in the first 48 hours")

    // Non-insights pages: a login redirect, and the bot-check interstitial.
    func parseError(_ page: String) -> PostInsightsError? {
        do { _ = try PostInsightsParser.parse(html: page) } catch { return error as? PostInsightsError }
        return nil
    }
    check("post insights: a login page is a clear error",
          parseError("<html><body><form action=\"/login\"><input name=\"username\"></form></body></html>")
          == .notInsightsPage)
    check("post insights: the bot-check page is retryable",
          parseError("<html><script>document.forms.namedItem(\"solution\").requestSubmit()</script></html>")
          == .blocked)
    check("post insights: the error text is user-readable",
          PostInsightsError.notInsightsPage.errorDescription?.contains("Insights") == true)

    check("post insights: stats URL accepts a fullname or bare id",
          PostInsightsParser.statsURL(postID: "t3_abc123")?.absoluteString == "https://www.reddit.com/poststats/abc123/"
          && PostInsightsParser.statsURL(postID: "abc123")?.absoluteString == "https://www.reddit.com/poststats/abc123/")
    check("post insights: stats URL rejects a malformed id",
          PostInsightsParser.statsURL(postID: "../x") == nil && PostInsightsParser.statsURL(postID: "") == nil)
    check("post insights: only your own posts are eligible",
          PostInsightsParser.isEligible(author: "Me", currentUsername: "me")
          && !PostInsightsParser.isEligible(author: "other", currentUsername: "me")
          && !PostInsightsParser.isEligible(author: "me", currentUsername: nil))
    check("post insights: the menu item is catalogued for posts and the comments view",
          ActionMenuCatalog.item("post-insights", in: .post) != nil
          && ActionMenuCatalog.item("post-insights", in: .postDetail) != nil
          && ActionMenuCatalog.item("post-insights", in: .comment) == nil)
}
