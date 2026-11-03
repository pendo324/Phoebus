import Foundation
import PhoebusCore

// MARK: - Long bodies
//
// A `Text` stops drawing past a certain height, so a body is drawn as pieces.
// A single wall of text or one giant code block has no blank line to cut at.
@MainActor func checkLongBodyPieces() async throws {
    let limit = BodyParagraphs.maxPieceLength
    let sentence = "The quick brown fox jumps over the lazy dog near the riverbank. "
    let wall = String(repeating: sentence, count: 8000 / sentence.count + 1)

    let wallPieces = BodyParagraphs.split(wall)
    check("a single 8k paragraph is cut into pieces", wallPieces.count >= 8)
    check("...none longer than the piece limit", wallPieces.allSatisfy { $0.count <= limit })
    check("...cut after a sentence, so each starts at a capital",
          wallPieces.allSatisfy { $0.hasPrefix("The quick") })
    check("...and no word is lost",
          wallPieces.joined(separator: " ").split(separator: " ") == wall.split(separator: " "))

    let flags = BodyParagraphs.pieces(of: wall).map(\.continuesPrevious)
    check("the first piece starts a paragraph and the rest continue it", flags.first == false && flags.dropFirst().allSatisfy { $0 })

    let paragraphs = (0..<5).map { _ in String(wall.prefix(3000)) }.joined(separator: "\n\n")
    let multi = BodyParagraphs.pieces(of: paragraphs)
    check("a 15k body of long paragraphs stays within the limit", multi.allSatisfy { $0.text.count <= limit })
    check("...and each paragraph's first piece starts it", multi.filter { !$0.continuesPrevious }.count == 5)

    check("a short body is still one piece", BodyParagraphs.split("A short body.") == ["A short body."])

    let noSpaces = String(repeating: "x", count: 5000)
    check("a line with no space is cut at the limit",
          BodyParagraphs.split(noSpaces).map(\.count) == [1000, 1000, 1000, 1000, 1000])

    let link = String(repeating: "a ", count: 480) + "see [a long link label here](https://example.com/page) and then " + String(repeating: "b ", count: 400)
    let linkPieces = BodyParagraphs.split(link)
    check("a link is not cut through its label",
          linkPieces.allSatisfy { $0.filter { $0 == "[" }.count == $0.filter { $0 == "]" }.count })

    let codeLines = (1...2000).map { "let value\($0) = compute(\($0))" }
    let code = "```swift\n" + codeLines.joined(separator: "\n") + "\n```"
    let codePieces = BodyParagraphs.split(code)
    check("a 2000-line code block is cut into pieces", codePieces.count > 20)
    check("...each within the limit plus its reopened fence", codePieces.allSatisfy { $0.count <= limit + 4 })
    check("...all pieces after the first reopen the fence", codePieces.dropFirst().allSatisfy { $0.hasPrefix("```\n") })
    check("...the last one closes it", codePieces.last?.hasSuffix("\n```") == true)
    check("...and every line of code survives",
          codePieces.flatMap { $0.components(separatedBy: "\n") }.filter { $0.hasPrefix("let value") } == codeLines)

    let blankInside = "```\nfirst\n\nsecond\n```\n\nafter"
    check("a blank line inside a code fence does not split it",
          BodyParagraphs.split(blankInside) == ["```\nfirst\n\nsecond\n```", "after"])
    check("a tilde fence is a fence too", BodyParagraphs.split("~~~\na\n\nb\n~~~") == ["~~~\na\n\nb\n~~~"])
    check("inline triple backticks are not a fence", BodyParagraphs.split("```x``` a\n\nb") == ["```x``` a", "b"])
    check("an unclosed fence runs to the end", BodyParagraphs.split("```\na\n\nb") == ["```\na\n\nb"])

    let list = (1...400).map { "- item number \($0) with some words" }.joined(separator: "\n")
    let listPieces = BodyParagraphs.split(list)
    check("a long list is cut between items", listPieces.count > 5 && listPieces.allSatisfy { $0.count <= limit })
    check("...and every item starts a line",
          listPieces.flatMap { $0.components(separatedBy: "\n") }.count == 400)
}

// MARK: - Chunks of rendered text
@MainActor func checkRenderedTextChunks() async throws {
    let sentence = "Rendered words keep going without a paragraph break at all. "
    let wall = String(repeating: sentence, count: 10000 / sentence.count + 1)
    let ends = BodyParagraphs.chunkEnds(of: wall, softLength: 1200, hardLength: 2000)
    check("a 10k wall of text with no blank line is cut", ends.count >= 5)
    check("...every chunk within the hard limit",
          zip([0] + ends, ends).allSatisfy { $1 - $0 <= 2000 && $1 > $0 })
    check("...ending at the text's length", ends.last == wall.count)

    let paragraph = String(repeating: "word ", count: 250)
    let paragraphs = (0..<4).map { _ in paragraph }.joined(separator: "\n\n")
    let paragraphEnds = BodyParagraphs.chunkEnds(of: paragraphs, softLength: 1200, hardLength: 2000)
    check("paragraphs still break at the first blank line after the soft length",
          paragraphEnds == [1252, 2504, 3756, 5006])
    check("a short text is one chunk", BodyParagraphs.chunkEnds(of: "short", softLength: 1200, hardLength: 2000) == [5])
}
