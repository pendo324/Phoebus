import Foundation
import PhoebusCore

// MARK: - Post requirements
//
// The fixture is synthetic: it carries every field the composer reads, an
// invalid regex and an unknown field, so each rule has something to trip.
@MainActor func checkPostRequirements() async throws {
    let data = fixture("post-requirements-synthetic.json")
    check("the post requirements fixture is present", !data.isEmpty)
    guard let rules = try? JSONDecoder().decode(PostRequirements.self, from: data) else {
        check("the post requirements fixture decodes", false)
        return
    }
    check("title limits and flair decode",
          rules.titleTextMinLength == 10 && rules.titleTextMaxLength == 40 && rules.isFlairRequired)
    check("null and empty fields decode as absent",
          rules.linkRepostAge == nil && rules.domainWhitelist.isEmpty)
    check("guidelines are trimmed and expanded by the 'full' policy",
          rules.guidelines == "Please search before posting." && rules.guidelinesStartExpanded)

    let shownToAll = try? JSONDecoder().decode(PostRequirements.self, from: Data(
        #"{"guidelines_text": "Ask a question.", "guidelines_display_policy": "all"}"#.utf8))
    check("Reddit's 'all' guidelines policy starts expanded", shownToAll?.guidelinesStartExpanded == true)

    let empty = (try? JSONDecoder().decode(PostRequirements.self, from: Data("{}".utf8))) ?? PostRequirements()
    check("an empty object imposes nothing",
          empty.violations(for: PostDraft(kind: .text, title: "x")).isEmpty)
    let odd = try? JSONDecoder().decode(PostRequirements.self, from: Data(
        #"{"title_text_max_length":"12","title_regexes":null,"is_flair_required":"yes","body_restriction_policy":7}"#.utf8))
    check("mistyped fields are tolerated",
          odd?.titleTextMaxLength == 12 && odd?.titleRegexes.isEmpty == true
              && odd?.isFlairRequired == false && odd?.bodyRestrictionPolicy == nil)

    func problems(_ draft: PostDraft) -> [PostRequirementViolation] { rules.violations(for: draft) }
    func messages(_ draft: PostDraft) -> String { problems(draft).map(\.message).joined(separator: "\n") }

    let good = PostDraft(kind: .text, title: "[Q] I need help with a question",
                         body: "Error 404 on my router, thanks for any hints", flairSelected: true)
    check("a draft meeting every rule has no problems", problems(good).isEmpty)

    var long = good
    long.title = "[Q] I need help with a really long question here"
    check("a title over the maximum blocks",
          problems(long).first?.field == .title && problems(long).first?.isBlocking == true)

    var short = good
    short.title = "[Q] help"
    check("a short title warns without blocking",
          messages(short).contains("at least 10") && !problems(short).contains { $0.isBlocking })

    var banned = good
    banned.title = "[Q] help: GIVEAWAY now"
    check("blacklisted title strings match case-insensitively", messages(banned).contains("GIVEAWAY") || messages(banned).contains("Giveaway"))

    var missing = good
    missing.title = "[Q] something else entirely"
    check("a title needs one of the required strings", messages(missing).contains("must contain one of"))

    var unformatted = good
    unformatted.title = "I need help with a question"
    check("a title failing the regex warns; the invalid regex is ignored",
          messages(unformatted).contains("required format") && !problems(unformatted).contains { $0.isBlocking })

    var noBody = good
    noBody.body = "  "
    check("a required body that is empty blocks",
          problems(noBody).contains { $0.field == .body && $0.isBlocking })

    var bodyRules = good
    bodyRules.body = "spoiler"
    let bodyText = messages(bodyRules)
    check("body length, blacklist, required string and regex each warn",
          bodyText.contains("at least 20") && bodyText.contains("spoiler")
              && bodyText.contains("must contain one of: thanks") && bodyText.contains("required format"))

    var bodyLong = good
    bodyLong.body = String(repeating: "123 thanks ", count: 12)
    check("a body over the maximum warns without blocking",
          messages(bodyLong).contains("over the 100") && !problems(bodyLong).contains { $0.isBlocking })

    var notAllowed = PostRequirements()
    notAllowed.bodyRestrictionPolicy = "notAllowed"
    check("a body where none is allowed blocks",
          notAllowed.violations(for: PostDraft(kind: .text, title: "t", body: "hi")).first?.isBlocking == true)
    check("body rules don't apply to link posts",
          notAllowed.violations(for: PostDraft(kind: .link, title: "t", url: "https://example.com")).isEmpty)

    var noFlair = good
    noFlair.flairSelected = false
    check("a missing required flair blocks",
          problems(noFlair).last?.field == .flair && problems(noFlair).last?.isBlocking == true)

    func link(_ url: String) -> [PostRequirementViolation] {
        rules.violations(for: PostDraft(kind: .link, title: "[Q] I need help with a question", url: url, flairSelected: true))
    }
    check("a blacklisted domain blocks, including subdomains and bare hosts",
          link("https://news.spam.example/a").first?.isBlocking == true
              && link("bad.test/x").first?.isBlocking == true)
    check("an unlisted domain passes", link("https://example.com/a").isEmpty)

    var whitelist = PostRequirements()
    whitelist.domainWhitelist = ["example.com"]
    let wl = { (url: String) in whitelist.violations(for: PostDraft(kind: .link, title: "t", url: url)) }
    check("a whitelist warns about other domains and accepts www and subdomains",
          wl("https://other.org").first?.isBlocking == false && wl("https://www.example.com").isEmpty
              && wl("https://a.example.com").isEmpty)

    var linksBanned = PostRequirements()
    linksBanned.linkRestrictionPolicy = "notAllowed"
    check("links where none are allowed warn",
          linksBanned.violations(for: PostDraft(kind: .link, title: "t", url: "")).first?.isBlocking == false)

    func gallery(_ count: Int, captions: Bool) -> [PostRequirementViolation] {
        rules.violations(for: PostDraft(kind: .gallery, title: "[Q] I need help with a question",
                                        flairSelected: true, galleryItemCount: count, galleryHasCaptions: captions))
    }
    check("gallery counts and required captions warn",
          gallery(1, captions: true).first?.message.contains("at least 2") == true
              && gallery(5, captions: true).first?.message.contains("at most 4") == true
              && gallery(3, captions: false).first?.message.contains("caption") == true
              && gallery(3, captions: true).isEmpty)

    var seen: [PostRequirementViolation.Field] = []
    for problem in problems(PostDraft(kind: .text, title: "x")) where !seen.contains(problem.field) {
        seen.append(problem.field)
    }
    check("problems come out title, body, flair", seen == [.title, .body, .flair])
}
