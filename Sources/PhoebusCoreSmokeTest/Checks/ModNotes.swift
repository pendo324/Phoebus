import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Mod notes
//
// Decoding, paging, request building and validation against a synthetic
// response in Reddit's `GET /api/mod/notes` shape.
@MainActor func checkModNotes() async throws {
    let fixture = "Tests/Fixtures/mod-notes.json"
    guard let data = FileManager.default.contents(atPath: fixture),
          let page = try? JSONDecoder().decode(ModNotePage.self, from: data) else {
        check("the mod notes fixture decodes", false)
        return
    }
    check("the mod notes fixture decodes four entries", page.notes.count == 4)
    check("a page with more notes hands back its end cursor", page.nextCursor == "cur4")

    let first = page.notes[0]
    check("a note reads its text, label and operator",
          first.type == .note && first.note == "Keeps reposting the megathread"
              && first.label == .spamWatch && first.operator == "modone")
    check("a note's created_at is epoch seconds", first.created == Date(timeIntervalSince1970: 1_760_000_000))
    check("a note on a post links its fullname", first.redditID == "t3_abc123")
    check("a note on a comment links its fullname", page.notes[1].redditID == "t1_def456")
    check("hand-written notes can be deleted", first.isDeletable)

    let removal = page.notes[2]
    check("an action entry reads action, details and description",
          removal.type == .removal && removal.action == "removelink" && removal.details == "remove"
              && removal.actionDescription == "Rule 2")
    check("an action entry links the item it acted on", removal.redditID == "t3_zzz999")
    check("an action entry has no note text or label", removal.note == nil && removal.label == nil)
    check("an action entry can't be deleted", !removal.isDeletable)

    check("an unknown type falls back instead of failing", page.notes[3].type == .unknown)
    check("an entry without data blocks still decodes", page.notes[3].note == nil && page.notes[3].redditID == nil)

    let last = """
    {"mod_notes": [], "start_cursor": null, "end_cursor": null, "has_next_page": false}
    """.data(using: .utf8)!
    let empty = try JSONDecoder().decode(ModNotePage.self, from: last)
    check("the last page has no next cursor", empty.notes.isEmpty && empty.nextCursor == nil)

    check("every label has Reddit's wording and a colour",
          ModNoteLabel.allCases.count == 8 && ModNoteLabel.permaBan.title == "Permaban"
              && ModNoteLabel.helpfulUser.colorHex == ModNoteLabel.solidContributor.colorHex
              && ModNoteLabel.ban.colorHex != ModNoteLabel.helpfulUser.colorHex)
    check("labels round-trip through their API names", ModNoteLabel(rawValue: "BOT_BAN") == .botBan)
    check("the filter picker covers ALL plus the nine types", ModNoteFilter.allCases.count == 10)

    let all = ModNoteRequest.listParameters(subreddit: "testsub", user: "someuser")
    check("an unfiltered list sends no filter or cursor",
          all == ["subreddit": "testsub", "user": "someuser", "limit": "25"])
    let filtered = ModNoteRequest.listParameters(subreddit: "testsub", user: "someuser", filter: .ban, before: "cur4")
    check("a filtered, paged list sends both", filtered["filter"] == "BAN" && filtered["before"] == "cur4")

    let create = try ModNoteRequest.createParameters(subreddit: "testsub", user: "someuser",
                                                     note: "  hello  ", label: .abuseWarning, redditID: "t1_def456")
    check("a created note is trimmed and carries label and target",
          create["note"] == "hello" && create["label"] == "ABUSE_WARNING" && create["reddit_id"] == "t1_def456")
    let bare = try ModNoteRequest.createParameters(subreddit: "testsub", user: "someuser", note: "hi", label: nil)
    check("a bare note sends neither label nor target", bare["label"] == nil && bare["reddit_id"] == nil)

    check("an empty note is refused",
          (try? ModNoteRequest.validatedNote("   \n")) == nil)
    check("250 characters are accepted", (try? ModNoteRequest.validatedNote(String(repeating: "a", count: 250))) != nil)
    var tooLong: ModNoteError?
    do { _ = try ModNoteRequest.validatedNote(String(repeating: "a", count: 251)) } catch { tooLong = error as? ModNoteError }
    check("251 characters are refused", tooLong == .tooLong(250))
    var badTarget: ModNoteError?
    do {
        _ = try ModNoteRequest.createParameters(subreddit: "s", user: "u", note: "x", label: nil, redditID: "t5_abc")
    } catch { badTarget = error as? ModNoteError }
    check("a note can't target a subreddit fullname", badTarget == .badTarget)

    check("a delete names the note", ModNoteRequest.deleteParameters(subreddit: "s", user: "u", noteID: "ModNote_x")
          == ["subreddit": "s", "user": "u", "note_id": "ModNote_x"])

    let created = """
    {"created": {"id": "ModNote_new", "created_at": 1760000100, "type": "NOTE", "subreddit": "testsub",
                 "user": "someuser", "operator": "me", "user_note_data": {"note": "x", "label": "BAN"}}}
    """.data(using: .utf8)!
    check("a create response decodes its note", ModNoteRequest.decodeCreated(created)?.id == "ModNote_new")
    check("a malformed create response is nil", ModNoteRequest.decodeCreated(Data("{}".utf8)) == nil)

    check("the sign-in requests the modnote scope", RedditOAuthConfig.scope.split(separator: " ").contains("modnote"))
}
