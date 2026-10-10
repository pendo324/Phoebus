import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Reddit Answers (Phoebus-only)
//
// The stream fixture is synthetic: it reproduces the structure of what
// Reddit's Answers endpoint sends (a quota event, JSON Patch events that
// replace, add, copy, move and remove, then success) with invented content.

@MainActor func checkRedditAnswers() async throws {
    func file(_ name: String) -> Data {
        let path = "Tests/Fixtures/answers/\(name)"
        return FileManager.default.contents(atPath: path)
            ?? FileManager.default.contents(atPath: FileManager.default.currentDirectoryPath + "/" + path) ?? Data()
    }
    func events(_ bytes: [UInt8], chunk: Int) -> [ServerSentEvent] {
        var parser = ServerSentEventParser()
        var found: [ServerSentEvent] = []
        var index = 0
        while index < bytes.count {
            found += parser.feed(bytes[index..<min(index + chunk, bytes.count)])
            index += chunk
        }
        return found + parser.finish()
    }
    func json(_ text: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    // Server-sent events.
    do {
        let text = "id: 1\nevent: patch\ndata: [1,\ndata: 2]\n\n: keep-alive\nretry: 5\nid: 2\ndata: plain\n\nevent: success\ndata: {}\n\n"
        let bytes = Array(text.utf8)
        let whole = events(bytes, chunk: bytes.count)
        check("answers sse: events carry id, name and multi-line data; comments and retry are skipped; a nameless event is a message",
              whole == [ServerSentEvent(id: "1", event: "patch", data: "[1,\n2]"),
                        ServerSentEvent(id: "2", event: "message", data: "plain"),
                        ServerSentEvent(id: "2", event: "success", data: "{}")])
        check("answers sse: the same events come out of 1-byte and 7-byte chunks",
              events(bytes, chunk: 1) == whole && events(bytes, chunk: 7) == whole)
        let crlf = Array("event: userQuota\r\ndata: {}\r\n\r\ndata: a\rdata: b\r\r".utf8)
        check("answers sse: CRLF and bare CR end lines, split anywhere",
              events(crlf, chunk: 1) == [ServerSentEvent(event: "userQuota", data: "{}"), ServerSentEvent(id: nil, event: "message", data: "a\nb")]
                && events(crlf, chunk: 100).count == 2)
        let accented = Array("data: caf\u{E9} \u{1F600}\n\n".utf8)
        check("answers sse: a multi-byte character split across chunks survives",
              events(accented, chunk: 1).first?.data == "caf\u{E9} \u{1F600}")
        check("answers sse: an event whose blank line never came is dropped",
              events(Array("event: success\ndata: {}\n".utf8), chunk: 3).isEmpty)
    }

    // JSON Patch.
    do {
        func patched(_ document: String, _ patch: String) -> JSONValue? {
            var value = json(document)
            guard (try? JSONPatch.apply(json(patch), to: &value)) != nil else { return nil }
            return value
        }
        check("answers patch: add sets a key, inserts into an array and appends with -",
              patched(#"{"a":[1,3]}"#, #"[{"op":"add","path":"/b","value":true},{"op":"add","path":"/a/1","value":2},{"op":"add","path":"/a/-","value":4}]"#)
                == json(#"{"a":[1,2,3,4],"b":true}"#))
        check("answers patch: replace swaps a value, the root, and sets an index just past the end",
              patched(#"{"a":[1]}"#, #"[{"op":"replace","path":"/a/0","value":9},{"op":"replace","path":"/a/1","value":8}]"#) == json(#"{"a":[9,8]}"#)
                && patched(#"{"a":1}"#, #"[{"op":"replace","path":"","value":{"z":[]}}]"#) == json(#"{"z":[]}"#))
        check("answers patch: remove deletes a key or shifts an array",
              patched(#"{"a":[1,2,3],"b":1}"#, #"[{"op":"remove","path":"/a/0"},{"op":"remove","path":"/b"}]"#) == json(#"{"a":[2,3]}"#))
        check("answers patch: copy adds a duplicate and move relocates",
              patched(#"{"a":[1,2]}"#, #"[{"op":"copy","from":"/a/0","path":"/a/2"}]"#) == json(#"{"a":[1,2,1]}"#)
                && patched(#"{"a":[1,2],"b":{}}"#, #"[{"op":"move","from":"/a/0","path":"/b/x"}]"#) == json(#"{"a":[2],"b":{"x":1}}"#))
        check("answers patch: test passes on equal values and throws on different ones",
              patched(#"{"a":1}"#, #"[{"op":"test","path":"/a","value":1}]"#) != nil
                && patched(#"{"a":1}"#, #"[{"op":"test","path":"/a","value":2}]"#) == nil)
        check("answers patch: ~0 and ~1 unescape in pointers",
              patched(#"{"a/b":1,"c~d":2}"#, #"[{"op":"replace","path":"/a~1b","value":5},{"op":"replace","path":"/c~0d","value":6}]"#)
                == json(#"{"a/b":5,"c~d":6}"#))
        check("answers patch: a bad path, an unknown op and a non-array patch all throw",
              patched(#"{"a":1}"#, #"[{"op":"remove","path":"/zzz"}]"#) == nil
                && patched(#"{"a":1}"#, #"[{"op":"frob","path":"/a"}]"#) == nil
                && patched(#"{"a":1}"#, #"{"op":"remove","path":"/a"}"#) == nil
                && patched(#"{"a":[1]}"#, #"[{"op":"add","path":"/a/5","value":0}]"#) == nil)
        var partial = json(#"{"a":{"b":[1]}}"#)
        try? JSONPatch.apply(json(#"[{"op":"replace","path":"/a/b/0","value":2},{"op":"remove","path":"/a/q/0"}]"#), to: &partial)
        check("answers patch: operations before a failing one stay applied and the failing one leaves the document whole",
              partial == json(#"{"a":{"b":[2]}}"#))
    }

    // The synthetic stream, end to end.
    do {
        let bytes = Array(file("stream.txt"))
        let parsed = events(bytes, chunk: 13)
        check("answers stream: the fixture frames into its events", parsed.count == 12 && parsed.last?.event == "success")
        var stream = RedditAnswerStream()
        var titles: [String] = []
        for event in parsed {
            stream.handle(event)
            if let title = stream.content.thinkingTitle, titles.last != title { titles.append(title) }
        }
        check("answers stream: quota, completion and the skipped bad patch",
              stream.quota == RedditAnswerQuota(remaining: 42, secondsUntilReset: 3725)
                && stream.isComplete && stream.failure == nil && stream.skippedPatches == 1)
        check("answers stream: the thinking line moves through the steps and ends on the last one",
              titles == ["Thinking...", "Searching for sourdough starter", "Consolidating what redditors are saying"])

        let document = stream.document
        check("answers document: ids and follow-ups",
              document.commentIDs == ["t1_ccc333"] && document.postIDs == ["t3_aaa111", "t3_bbb222"]
                && document.subredditIDs == ["t5_sour1", "t5_bake2"]
                && document.followUps == ["how to revive a dead starter", "best flour for starter"])

        let content = stream.content
        check("answers content: reasoning is complete, with no answer-state step left running",
              !content.isThinking && content.steps.count == 1 && content.steps[0].isComplete)
        check("answers content: consulted posts and communities, named from the source bar",
              content.consultedPostIDs == ["t3_aaa111", "t3_bbb222"]
                && content.consultedSubreddits == [
                    AnswerSubreddit(id: "t5_sour1", name: "r/Sourdough", iconURL: URL(string: "https://example.invalid/icon-sourdough.png")),
                    AnswerSubreddit(id: "t5_bake2", name: "r/Breadit", iconURL: nil)])
        check("answers content: citations number by first appearance and keep the link before the chip",
              content.citations.map(\.id) == ["t3_aaa111", "t1_ccc333"]
                && content.citations.map(\.number) == [1, 2]
                && content.citations[1].kind == .comment && content.citations[0].subreddit == "r/Sourdough"
                && content.citations[1].permalink?.absoluteString == "https://www.reddit.com/r/Breadit/comments/bbb222/comment/ccc333/")
        check("answers content: the blocks follow the document (move put the paragraph after the heading)",
              content.blocks.count == 6
                && { if case .heading(3, _) = content.blocks[0] { return true } else { return false } }()
                && { if case .paragraph = content.blocks[1] { return true } else { return false } }()
                && { if case .list(true, let items) = content.blocks[2] { return items.count == 2 } else { return false } }()
                && { if case .references(let label, let refs) = content.blocks[3] {
                        return label == "Related images from across Reddit" && refs.map(\.id) == ["t1_ccc333"]
                            && refs[0].imageURL?.absoluteString == "https://example.invalid/starter.jpg"
                    } else { return false } }()
                && content.blocks[4] == .rule && content.blocks[5] == .subreddits(["t5_sour1", "t5_bake2"]))
        if case .paragraph(let inlines) = content.blocks[1] {
            check("answers content: format ranges split the text into styled runs",
                  inlines == [.text("Feed it equal weights of flour and water", .bold),
                              .text(" daily. Keep it warm.", [])])
        }
        if case .list(_, let items) = content.blocks[2], case .paragraph(let inlines) = items[0][0] {
            check("answers content: list items hold bold and italic runs, a link and a citation chip",
                  inlines.first == .text("Room temperature", .bold)
                    && inlines.contains(.text("starte", .italic))
                    && inlines.contains(where: { if case .link(let text, let url) = $0 { return text.hasPrefix("\"Mine doubles") && url?.host == "www.reddit.com" } else { return false } })
                    && { if case .citation(let citation)? = inlines.last { return citation.number == 1 } else { return false } }())
        }
        if case .list(_, let items) = content.blocks[2], case .paragraph(let inlines) = items[1][0] {
            let numbers = inlines.compactMap { inline -> Int? in if case .citation(let citation) = inline { return citation.number } else { return nil } }
            check("answers content: a repeated source keeps its first number", numbers == [2, 1])
        }
        let plain = content.plainText
        check("answers content: plain text for Copy has the heading, numbered items and [n] chips and none of the media",
              plain.hasPrefix("Feeding Schedule") && plain.contains("1. Room temperature starters want feeding every 12 hours.")
                && plain.contains("[1]") && plain.contains("[2] [1]") && !plain.contains("starter.jpg"))
    }

    // Elements Phoebus doesn't know never crash and keep their text.
    do {
        let document = RedditAnswerDocument(json: json("""
        {"richtext":{"document":[
          {"e":"ra:mystery","c":[{"e":"par","c":[{"e":"text","t":"inside "},{"e":"ra:widget","c":[{"e":"text","t":"widget"}]}]}]},
          {"e":"ra:product","c":[{"e":"par","c":[{"e":"text","t":"A product"}]}]},
          {"e":"blockquote","c":[{"e":"par","c":[{"e":"ra:inline_quote","c":[{"e":"text","t":"quoted"}]}]}]},
          {"e":"par","c":[{"e":"link","u":"https://example.com","c":[{"e":"text","t":"label"}]},{"e":"br"},{"e":"ra:source"}]},
          {"e":"par","c":[]},
          {"e":"code","c":[{"e":"raw","t":"let x = 1"}]},
          {"e":"list","o":false,"c":[{"e":"li","c":[{"e":"par","c":[{"e":"text","t":"one"}]}]}]},
          {"e":"ra:grid","content_type":"post","c":[{"e":"ra:post","id":"t3_zzz999"}]},
          "stray", 7, null,
          {"t":"orphan text"}
        ]}}
        """))
        let content = RedditAnswerContent(document: document)
        check("answers content: an unknown element renders its children",
              content.blocks.first == .paragraph([.text("inside ", []), .text("widget", [])]))
        check("answers content: a product with only text degrades to that text", content.blocks.contains(.paragraph([.text("A product", [])])))
        check("answers content: block quotes, inline quotes, labelled links, code and lists decode",
              content.blocks.contains(.quote([.paragraph([.text("quoted", .quoted)])]))
                && content.blocks.contains(.paragraph([.link(text: "label", url: URL(string: "https://example.com")), .lineBreak]))
                && content.blocks.contains(.code("let x = 1"))
                && content.blocks.contains(.list(ordered: false, items: [[.paragraph([.text("one", [])])]])))
        check("answers content: empty paragraphs, a source with no id and non-object items are dropped; a grid of posts becomes references; bare text becomes a paragraph",
              content.blocks.contains(.references(label: nil, [AnswerReference(id: "t3_zzz999", imageURL: nil)]))
                && content.blocks.last == .paragraph([.text("orphan text", [])])
                && !content.blocks.contains(.paragraph([])) && content.citations.isEmpty)
        check("answers content: overlong format ranges are clamped",
              RedditAnswerContent(document: RedditAnswerDocument(json: json(#"{"richtext":{"document":[{"e":"par","c":[{"e":"text","t":"abc","f":[[1,1,99],[2,-1,3]]}]}]}}"#))).blocks
                == [.paragraph([.text("a", .italic), .text("b", [.bold, .italic]), .text("c", .bold)])])
        check("answers content: a document that isn't an object is empty", RedditAnswerContent(document: RedditAnswerDocument(json: .null)).blocks.isEmpty)
    }

    // Errors and quota.
    do {
        var stream = RedditAnswerStream()
        for event in events(Array(file("error.txt")), chunk: 11) { stream.handle(event) }
        check("answers error: a quota error event says when to ask again",
              stream.failure == .quotaExhausted(secondsUntilReset: 125) && !stream.isComplete
                && stream.failure?.errorDescription == "You're out of Reddit Answers questions for now. You can ask again in 3 min.")
        var other = RedditAnswerStream()
        other.handle(ServerSentEvent(event: "error", data: #"{"message":"Model unavailable"}"#))
        var bare = RedditAnswerStream()
        bare.handle(ServerSentEvent(event: "error", data: "upstream exploded"))
        check("answers error: other errors keep Reddit's message, JSON or plain",
              other.failure == .server("Model unavailable") && bare.failure == .server("upstream exploded"))
        check("answers quota: the summary reads as counts",
              RedditAnswerQuota(remaining: 49, secondsUntilReset: 641).summary == "49 questions left"
                && RedditAnswerQuota(remaining: 1, secondsUntilReset: 0).summary == "1 question left"
                && RedditAnswerQuota(remaining: 0, secondsUntilReset: 0).summary == "No questions left"
                && RedditAnswerQuota(remaining: 3, secondsUntilReset: 641).resetDescription == "11 min"
                && RedditAnswerQuota(remaining: 3, secondsUntilReset: 30).resetDescription == "under a minute"
                && RedditAnswerQuota(remaining: 3, secondsUntilReset: 5400).resetDescription == "1 hr 30 min")
        check("answers error: only a refused sign-in or no session asks for a sign-in",
              RedditAnswersError.needsWebSession.needsSignIn && RedditAnswersError.tokenRefused(403).needsSignIn
                && !RedditAnswersError.tokenRefused(500).needsSignIn && !RedditAnswersError.unauthorized.needsSignIn)
        var broken = RedditAnswerStream()
        broken.handle(ServerSentEvent(event: "patch", data: "not json"))
        broken.handle(ServerSentEvent(event: "userQuota", data: "{}"))
        broken.handle(ServerSentEvent(event: "somethingNew", data: "{}"))
        check("answers stream: unreadable patches are counted, odd events ignored", broken.skippedPatches == 1 && broken.quota == nil && !broken.isComplete)
    }

    // Token and request.
    do {
        let session = WebSessionCredential(username: "Someone", cookieHeader: "reddit_session=abc; csrf_token=csrf123; loid=x", modhash: "m")
        let conversation = "5517cc62-1990-49ae-a8db-125f535c03a0"
        let mint = RedditAnswers.tokenRequest(session: session, conversationID: conversation)
        check("answers token: a POST to the shreddit token endpoint with the csrf token in the body and the cookie header set by hand",
              mint?.httpMethod == "POST" && mint?.url?.absoluteString == "https://www.reddit.com/svc/shreddit/token"
                && mint?.httpBody.flatMap { String(data: $0, encoding: .utf8) } == #"{"csrf_token":"csrf123"}"#
                && mint?.value(forHTTPHeaderField: "Cookie") == session.cookieHeader && mint?.httpShouldHandleCookies == false
                && mint?.value(forHTTPHeaderField: "Origin") == "https://www.reddit.com"
                && mint?.value(forHTTPHeaderField: "Referer") == "https://www.reddit.com/answers/\(conversation)"
                && mint?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        check("answers token: no csrf cookie, no request",
              RedditAnswers.tokenRequest(session: WebSessionCredential(username: "x", cookieHeader: "reddit_session=abc", modhash: nil),
                                         conversationID: conversation) == nil)
        let token = RedditAnswers.parseToken(Data(#"{"token":"jwt.jwt.jwt","expires":1800000000000}"#.utf8))
        check("answers token: the reply's expiry is milliseconds since the epoch",
              token == RedditAnswers.Token(value: "jwt.jwt.jwt", expires: Date(timeIntervalSince1970: 1_800_000_000))
                && RedditAnswers.parseToken(Data(#"{"token":""}"#.utf8)) == nil && RedditAnswers.parseToken(Data("<html>".utf8)) == nil)

        let cache = RedditAnswersTokenCache()
        let now = Date(timeIntervalSince1970: 1_000)
        cache.store(RedditAnswers.Token(value: "t", expires: now.addingTimeInterval(300)), for: "Someone")
        check("answers token: cached per account until a minute before it expires",
              cache.token(for: "someone", now: now)?.value == "t"
                && cache.token(for: "someone", now: now.addingTimeInterval(239))?.value == "t"
                && cache.token(for: "someone", now: now.addingTimeInterval(241)) == nil
                && cache.token(for: "other", now: now) == nil)
        cache.invalidate(for: "SOMEONE")
        check("answers token: invalidate forgets it", cache.token(for: "someone", now: now) == nil)

        let sent = Date(timeIntervalSince1970: 1_760_054_958.5)
        let request = RedditAnswers.answerRequest(query: "sourdough starter", conversationID: conversation, token: "jwt", now: sent)
        let body = (request?.httpBody).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        check("answers request: POST to answers.reddit.com/v1/answers/<uuid> with the bearer token and the web app's headers",
              request?.httpMethod == "POST" && request?.url?.absoluteString == "https://answers.reddit.com/v1/answers/\(conversation)"
                && request?.value(forHTTPHeaderField: "Authorization") == "Bearer jwt"
                && request?.value(forHTTPHeaderField: "Content-Type") == "application/json"
                && request?.value(forHTTPHeaderField: "X-Reddit-App-Name") == "web3x"
                && request?.value(forHTTPHeaderField: "Origin") == "https://www.reddit.com"
                && request?.value(forHTTPHeaderField: "Referer") == "https://www.reddit.com/"
                && request?.value(forHTTPHeaderField: "Cookie") == nil)
        check("answers request: RTJSON, the query, the correlation id and only the features the screen draws",
              body?["format"] as? String == "RTJSON" && body?["query"] as? String == "sourdough starter"
                && body?["source"] as? String == RedditAnswers.source
                && (body?["correlationId"] as? String)?.hasPrefix("\(conversation)__2025-10-10T") == true
                && (body?["correlationId"] as? String)?.hasSuffix(".500Z") == true
                && (body?["supportedFeatures"] as? [String]) == RedditAnswers.supportedFeatures
                && !RedditAnswers.supportedFeatures.contains("ra:carousel") && RedditAnswers.supportedFeatures.contains("ra:source"))
    }

    // Source rows and the engine.
    do {
        let info = RedditAnswerSourceInfo.parse(Data("""
        {"kind":"Listing","data":{"children":[
          {"kind":"t3","data":{"name":"t3_aaa111","title":"Starter &amp; flour","subreddit":"Sourdough","author":"baker","score":120,"num_comments":14}},
          {"kind":"t1","data":{"name":"t1_ccc333","body":"First line\\nsecond line","subreddit":"Breadit","author":"other","score":7,"link_id":"t3_bbb222"}},
          {"kind":"t5","data":{"name":"t5_sour1","display_name":"Sourdough","community_icon":"https://example.invalid/i.png?x=1&amp;y=2","subscribers":5000}},
          {"kind":"t2","data":{"name":"t2_zzz"}}
        ]}}
        """.utf8))
        check("answers sources: posts, comments and communities read from an info listing",
              info.count == 3 && info["t3_aaa111"]?.title == "Starter & flour" && info["t3_aaa111"]?.commentCount == 14
                && info["t1_ccc333"]?.title == "First line second line" && info["t1_ccc333"]?.postID == "bbb222"
                && info["t5_sour1"]?.title == "r/Sourdough" && info["t5_sour1"]?.iconURL?.absoluteString == "https://example.invalid/i.png?x=1&y=2")
        check("answers sources: each row opens its own target",
              info["t3_aaa111"]?.target == .post(subreddit: "Sourdough", id: "aaa111")
                && info["t1_ccc333"]?.target == .comment(subreddit: "Breadit", postID: "bbb222", commentID: "ccc333")
                && info["t5_sour1"]?.target == .subreddit("Sourdough"))
        check("answers sources: garbage reads as nothing", RedditAnswerSourceInfo.parse(Data("nope".utf8)).isEmpty)

        check("answers engine: Reddit Answers is value 3 with its own title and prompt, and lists no external results",
              SearchEngine(rawValue: 3) == .answers && SearchEngine.answers.title == "Reddit Answers"
                && SearchEngine.answers.placeholder == "Ask Reddit Answers" && !SearchEngine.answers.isExternal
                && SearchEngine.answers.suggestionsURL(for: "x") == nil && SearchEngine.google.isExternal && SearchEngine.kagi.isExternal
                && SearchEngine.allCases.count == 4)
        check("answers engine: with no web session the row asks for a reddit.com sign-in and the choice reads back as Reddit",
              SearchEngine.answers.subtitle == "Needs a reddit.com sign-in" && !RedditAnswers.hasWebSession)
    }
}
