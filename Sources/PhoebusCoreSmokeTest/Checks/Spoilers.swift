import Foundation
import PhoebusCore

// --- Inline spoilers ---
//
// `>!hidden!<` hides behind Apollo's "SPOILER" label until tapped. The bodies
// below are phrased like public r/gameofthrones, r/anime and r/movies comments.
@MainActor func checkSpoilers() async throws {
    func shown(_ raw: String, revealing: Set<Int> = []) -> String {
        String(RedditMarkdown.render(raw, codeScale: 1, revealing: revealing).characters)
    }
    let label = "\u{A0}SPOILER\u{A0}"
    let finale = "Honestly the finale ruined it for me >!when Jon killed Daenerys!< but I get why they wrote it that way."

    check("a spoiler is hidden behind the SPOILER label",
          shown(finale) == "Honestly the finale ruined it for me \(label) but I get why they wrote it that way.")
    check("...and the hidden words are not in the drawn text", !shown(finale).contains("Daenerys"))
    check("...nor in the plain render", !String(RedditMarkdown.render(finale).characters).contains("Jon"))
    check("a body counts its spoilers", RedditMarkdown.spoilerCount(in: finale) == 1)
    check("revealing a spoiler shows its words and drops the markers",
          shown(finale, revealing: [0]) == "Honestly the finale ruined it for me when Jon killed Daenerys but I get why they wrote it that way.")

    let two = "Ep 3 was wild: >!the Hokage dies!< and then >!Naruto goes after the Akatsuki!<, no regrets."
    check("two spoilers in a paragraph are two", RedditMarkdown.spoilerCount(in: two) == 2)
    check("revealing the second leaves the first hidden",
          shown(two, revealing: [1]) == "Ep 3 was wild: \(label) and then Naruto goes after the Akatsuki, no regrets.")
    check("adjacent spoilers are two", RedditMarkdown.spoilerCount(in: ">!a!<>!b!<") == 2)

    check("punctuation inside a spoiler stays inside it",
          shown("Wow >!Wait, what?! He's dead!!< no way", revealing: [0]) == "Wow Wait, what?! He's dead! no way"
          && RedditMarkdown.spoilerCount(in: "Wow >!Wait, what?! He's dead!!< no way") == 1)
    check("an HTML-escaped spoiler is a spoiler",
          RedditMarkdown.spoilerCount(in: "&gt;!Snape kills Dumbledore!&lt;") == 1
          && !shown("They say &gt;!Snape kills Dumbledore!&lt; in book six").contains("Snape"))
    check("a spoiler can run over a line break inside its paragraph",
          RedditMarkdown.spoilerCount(in: "Last scene: >!she walks away\nand never looks back!< sigh") == 1)
    check("a spoiler does not run over a blank line",
          RedditMarkdown.spoilerCount(in: "a >!b\n\nc!< d") == 0)
    check("an unclosed opener stays literal", shown("so >!this never closes") == "so >!this never closes")
    check("an empty pair stays literal", RedditMarkdown.spoilerCount(in: "a >!!< b") == 0)
    check("an escaped opener stays literal", RedditMarkdown.spoilerCount(in: #"\>!not hidden!<"#) == 0)
    check("a spoiler in an inline code span stays literal",
          RedditMarkdown.spoilerCount(in: "write `>!text!<` to hide text") == 0)
    check("...and in a fenced block", RedditMarkdown.spoilerCount(in: "```\n>!text!<\n```") == 0)
    check("...and in an indented block", RedditMarkdown.spoilerCount(in: "Example:\n\n    >!text!<") == 0)
    check("a spoiler beside code is still one",
          RedditMarkdown.spoilerCount(in: "`x` >!y!<") == 1)
    check("the legacy [text](/spoiler) link is not read as a spoiler",
          RedditMarkdown.spoilerCount(in: "[the twist](/spoiler)") == 0)
    check("markers typed into a body are dropped", SpoilerMarkup.fence("a\u{E000}b\u{E001}c") == "abc")
    check("fence leaves a body with no spoiler as it is", SpoilerMarkup.fence("2 > 1 and 3 < 4!") == "2 > 1 and 3 < 4!")

    // Emphasis and links inside a spoiler reach the parser as they were written.
    check("a spoiler around emphasis keeps the asterisks for the parser",
          SpoilerMarkup.fence("it was >!**Tywin**!< all along") == "it was \u{E000}**Tywin**\u{E001} all along")
    check("a spoiler inside emphasis keeps the asterisks for the parser",
          SpoilerMarkup.fence("**the end: >!he lives!<**") == "**the end: \u{E000}he lives\u{E001}**")
    check("an escaped body's markers are rewritten the same way",
          SpoilerMarkup.fence("&gt;!x!&lt;") == "\u{E000}x\u{E001}")

    // A line that starts with `>!` is a spoiler, a `>` followed by `!text` with no closer is a quote.
    typealias Block = QuoteBlock
    check("a line that starts with a spoiler is not a quote",
          QuoteBlocks.split(">!Rosebud is a sled!<") == [Block(depth: 0, text: ">!Rosebud is a sled!<")])
    check("...nor an escaped one", QuoteBlocks.split("&gt;!Rosebud is a sled!&lt;").map(\.depth) == [0])
    check("...nor one that closes on a later line",
          QuoteBlocks.split(">!Rosebud\nis a sled!<").map(\.depth) == [0])
    check("a quote and a spoiler line are two blocks",
          QuoteBlocks.split("> he said it was Keyser Soze\n\n>!it was!<")
          == [Block(depth: 1, text: "he said it was Keyser Soze"), Block(depth: 0, text: ">!it was!<")])
    check("a spoiler inside a quote stays in the quote",
          QuoteBlocks.split("> he said >!the butler did it!<") == [Block(depth: 1, text: "he said >!the butler did it!<")])
    check("a quote of a spoiler line is a quote of the spoiler",
          QuoteBlocks.split("> >!twist!<") == [Block(depth: 1, text: ">!twist!<")])
    check("an unclosed >! line is an ordinary quote",
          QuoteBlocks.split(">!never closed") == [Block(depth: 1, text: "!never closed")])
    check("a space after > makes it a quote of text that happens to start with !",
          QuoteBlocks.split("> !wow!<").map(\.depth) == [1])
    check("normalizing a spoiler line does not turn it into a quote",
          RedditMarkdown.normalizeBlockquotes(">!twist!<\n>real quote") == ">!twist!<\n> real quote")
    check("...but an unclosed >! still normalizes as a quote",
          RedditMarkdown.normalizeBlockquotes(">!never closed") == "> !never closed")

    // What each reader hears or sees in place of the words.
    check("VoiceOver says spoiler, not the words",
          AccessibilitySummary.spoken(markdown: "He dies >!at the end!< sadly") == "He dies spoiler sadly")
    check("an escaped spoiler is spoken the same way",
          AccessibilitySummary.spoken(markdown: "He dies &gt;!at the end!&lt; sadly") == "He dies spoiler sadly")
    check("Read More and inbox snippets keep the words out",
          GoogleSearch.plainText(fromMarkdown: "He dies >!at the end!< sadly") == "He dies [spoiler] sadly"
          && InboxRowText.quoteSnippet("He dies >!at the end!< sadly") == "He dies [spoiler] sadly")
    check("redacted leaves a body with no spoiler as it is",
          SpoilerMarkup.redacted("5 > 3, wow!") == "5 > 3, wow!")
    check("contains finds a spoiler and not a lone opener",
          SpoilerMarkup.contains(finale) && !SpoilerMarkup.contains("a >!b"))

    // The label of an interactive body carries the link that opens its spoiler.
    let links = RedditMarkdown.render(two, codeScale: 1, revealing: [], interactive: true).runs
        .compactMap(\.link).compactMap(SpoilerMarkup.index(of:))
    check("each hidden spoiler's label links to its number", links == [0, 1])
    let partly = RedditMarkdown.render(two, codeScale: 1, revealing: [0], interactive: true).runs
        .compactMap(\.link).compactMap(SpoilerMarkup.index(of:))
    check("a revealed spoiler's text links to its number too, so a tap on it hides it", partly == [0, 1])
    check("a body that is not interactive has no links even with a spoiler open",
          RedditMarkdown.render(two, codeScale: 1, revealing: [0, 1]).runs.compactMap(\.link).isEmpty)
    check("a body that is not interactive has no spoiler links",
          RedditMarkdown.render(two).runs.compactMap(\.link).isEmpty)
    check("a link that is not a spoiler's is not read as one",
          SpoilerMarkup.index(of: URL(string: "https://reddit.com/r/anime")!) == nil)

    // A second tap hides an open spoiler again; each spoiler toggles on its own.
    var reveal = SpoilerReveal()
    reveal.toggle(0)
    check("a tap opens a hidden spoiler", reveal.isOpen(0) && !reveal.isOpen(1))
    reveal.toggle(1)
    reveal.toggle(0)
    check("a second tap hides it again and leaves the other open", !reveal.isOpen(0) && reveal.isOpen(1))
    check("an open spoiler reads as revealed",
          shown(two, revealing: reveal.revealing(base: 0, count: 2)) == "Ep 3 was wild: \(label) and then Naruto goes after the Akatsuki, no regrets.")
    check("a piece reads the spoilers that are its own",
          reveal.revealing(base: 1, count: 2) == [0] && reveal.revealing(base: 5, count: 2).isEmpty)

    // A link inside a revealed spoiler opens on a tap; the plain words around it hide the spoiler.
    var linked = AttributedString("read the wiki first")
    linked[SpoilerAttribute.self] = 0
    let wiki = linked.range(of: "the wiki")!
    linked[wiki].link = URL(string: "https://example.com/wiki")
    let linkedRuns = SpoilerMarkup.apply(linked, revealing: [0], interactive: true).runs
    let destinations = linkedRuns.compactMap(\.link)
    check("a link inside a revealed spoiler keeps its destination",
          destinations.contains(URL(string: "https://example.com/wiki")!))
    check("...and the words around it re-spoil",
          destinations.compactMap(SpoilerMarkup.index(of:)) == [0, 0])
    check("a hidden spoiler's link is only the label's",
          SpoilerMarkup.apply(linked, revealing: [], interactive: true).runs.compactMap(\.link).count == 1)
    check("a rendered body names the spoilers it links to, once each",
          SpoilerMarkup.numbers(in: RedditMarkdown.render(two, codeScale: 1, revealing: [1], interactive: true)) == [0, 1])

    // VoiceOver: an action per spoiler that says what a tap does.
    var voiceOver = SpoilerReveal()
    check("a lone hidden spoiler offers Reveal spoiler", voiceOver.actionName(for: 0, total: 1) == "Reveal spoiler")
    voiceOver.toggle(0)
    check("...an open one Hide spoiler", voiceOver.actionName(for: 0, total: 1) == "Hide spoiler")
    check("several spoilers are numbered", voiceOver.actionName(for: 1, total: 2) == "Reveal spoiler 2"
          && voiceOver.actionName(for: 0, total: 2) == "Hide spoiler 1")

    // An over-long paragraph is drawn as pieces; a spoiler cut across two stays one.
    let words = (1...260).map { "secret\($0)" }.joined(separator: " ")
    let long = "Intro. " + String(repeating: "Filler words fill this line. ", count: 10) + ">!\(words)!< and then the end."
    let split = BodyParagraphs.pieces(of: long)
    check("a long paragraph with a spoiler across the cut is cut", split.count >= 2)
    check("...and no piece draws the hidden words or a stray marker",
          split.allSatisfy { piece in
              let drawn = String(RedditMarkdown.render(piece.text).characters)
              return !drawn.contains("secret") && !drawn.contains(">!") && !drawn.contains("!<")
          })
    check("...a piece that starts inside the spoiler says so",
          split.first?.continuesSpoiler == false && split.dropFirst().first?.continuesSpoiler == true)
    let counts = split.map { RedditMarkdown.spoilerCount(in: $0.text) }
    let bases = SpoilerReveal.bases(counts: counts, continues: split.map(\.continuesSpoiler))
    check("...the pieces number it as one spoiler", counts.allSatisfy { $0 == 1 } && Set(bases) == [0])
    var straddle = SpoilerReveal()
    straddle.toggle(0)
    check("...so opening it opens every piece of it",
          zip(bases, counts).allSatisfy { straddle.revealing(base: $0, count: $1) == [0] })

    let first = "First >!one!< then a very long run of text. " + String(repeating: "More words follow here. ", count: 60) + ">!two!< ends"
    let two2 = BodyParagraphs.pieces(of: first)
    let counts2 = two2.map { RedditMarkdown.spoilerCount(in: $0.text) }
    let bases2 = SpoilerReveal.bases(counts: counts2, continues: two2.map(\.continuesSpoiler))
    check("spoilers in different pieces are numbered one after another",
          counts2.reduce(0, +) == 2 && bases2.first == 0 && bases2.last == 1 && two2.allSatisfy { !$0.continuesSpoiler })
    check("a cut avoids the inside of a spoiler when it can",
          BodyParagraphs.pieces(of: String(repeating: "word ", count: 150) + ">!" + String(repeating: "hidden ", count: 40) + "!< " + String(repeating: "tail ", count: 150))
              .allSatisfy { !$0.continuesSpoiler })
    check("an escaped spoiler across a cut is closed and reopened by `the escaped-agnostic waygt;!` too",
          BodyParagraphs.pieces(of: "x &gt;!" + words + "!&lt; y").dropFirst().first?.continuesSpoiler == true)
}
