import Foundation
import PhoebusCore

// MARK: - What a refused read says
//
// When every route of a keyless read refuses, the 403 carries Reddit's block
// page. It is not a private community, and not a missing permission.

@MainActor func checkKeylessRefusalMessages() {
    let page = "<!DOCTYPE html><html lang=\"en\"><head><title>Blocked</title></head><body>whoa there, pardner!</body></html>"
    check("Reddit's block page is a page, a private community's answer is not",
          KeylessRouteResponse.isPageBody(page) && KeylessRouteResponse.isPageBody("<html>x</html>")
            && KeylessRouteResponse.isPageBody("<!doctype html><body></body>")
            && !KeylessRouteResponse.isPageBody(#"{"reason":"private","message":"Forbidden","error":403}"#)
            && !KeylessRouteResponse.isPageBody(""))
    // What www actually sent on 2026-11-04: ~190 KB of text/html that opens with a bare <body> fragment.
    let fragment = "<body class=theme-beta><div><style>.theme-light,:root{--rem360:22.5rem}</style><h1>You've been blocked by network security.</h1></div></body>"
    check("the block page's bare <body> fragment, with or without leading whitespace or a BOM, is a page; JSON and arrays are not",
          KeylessRouteResponse.isPageBody(fragment) && KeylessRouteResponse.isPageBody("\n  " + fragment)
            && KeylessRouteResponse.isPageBody("\u{FEFF}" + fragment)
            && !KeylessRouteResponse.isPageBody(#"  {"message": "Forbidden", "error": 403}"#) && !KeylessRouteResponse.isPageBody("[]"))
    check("a feed that got the bare <body> fragment says Reddit blocked it, even if the page mentions quarantine",
          FeedErrorCopy.message(status: 403, body: fragment, subreddit: "popular")
            == "Reddit blocked this request, so r/popular couldn't load. Try again in a while."
            && FeedErrorCopy.message(status: 403, body: fragment + "<p>quarantined</p>", subreddit: "popular")
            == "Reddit blocked this request, so r/popular couldn't load. Try again in a while.")
    check("only Reddit's JSON reason says private: a 403 with no body or another JSON answer says blocked",
          KeylessRouteResponse.jsonReason(#"{"reason": "Private", "error": 403}"#) == "private"
            && KeylessRouteResponse.jsonReason(page) == nil && KeylessRouteResponse.jsonReason("") == nil
            && KeylessRouteResponse.jsonReason(#"{"message": "Forbidden"}"#) == nil
            && FeedErrorCopy.message(status: 403, body: "", subreddit: "pics")
            == "Reddit blocked this request, so r/pics couldn't load. Try again in a while."
            && FeedErrorCopy.message(status: 403, body: #"{"message": "Forbidden", "error": 403}"#, subreddit: "pics")
            == "Reddit blocked this request, so r/pics couldn't load. Try again in a while.")
    check("a feed that got the block page says Reddit blocked it, not that it is private",
          FeedErrorCopy.message(status: 403, body: page, subreddit: "all")
            == "Reddit blocked this request, so r/all couldn't load. Try again in a while."
            && FeedErrorCopy.message(status: 403, body: page, subreddit: "")
            == "Reddit blocked this request, so This feed couldn't load. Try again in a while.")
    check("...while a 403 whose JSON says private is a private community, and a quarantine still says so",
          FeedErrorCopy.message(status: 403, body: #"{"reason":"private"}"#, subreddit: "pics")
            == "r/pics has been set to private by its subreddit moderators"
            && FeedErrorCopy.message(status: 403, body: #"{"reason":"quarantined"}"#, subreddit: "pics")
            == "r/pics has been quarantined by Reddit Administrators for offensive content")
    check("any other screen's error says it too, and an ordinary 403 keeps its message",
          UserFacingError.message(for: RedditAPIError.httpError(status: 403, body: page)) == "Reddit blocked this request. Try again in a while."
            && UserFacingError.message(for: RedditAPIError.httpError(status: 403, body: fragment)) == "Reddit blocked this request. Try again in a while."
            && UserFacingError.message(for: RedditAPIError.httpError(status: 403, body: #"{"reason":"private"}"#)) == "You don't have permission to do that."
            && UserFacingError.message(for: RedditAPIError.httpError(status: 500, body: page)) == "Reddit is having trouble right now (HTTP 500). Try again soon.")
}
