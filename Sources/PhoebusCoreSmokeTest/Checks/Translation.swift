import Foundation
import PhoebusCore

// MARK: - Translation source language (Reborn #1345)
//
// The "Translated from" marker names the language the provider reported, and
// text the provider hands back unchanged gets no marker. The responses below
// are the shapes each provider answers with; the Google pair is Reborn's
// "Hi Victoria" report (Google read it as Romanian and echoed it).

@MainActor func checkTranslationSourceLanguage() async throws {
    typealias C = BulkTranslationClient
    let english = Locale(identifier: "en_US")

    // Provider responses.
    let googleSpanish = Data(#"[[["Hello how are you? ","Hola, ¿cómo estás? ",null,null,10],["Very well thank you","Muy bien gracias",null,null,10]],null,"es",null,null,null,1,[],[["es"],null,[1],["es"]]]"#.utf8)
    check("Google reports its detected source", C.parseGoogleSourceLanguage(googleSpanish) == "es")
    let googleEcho = Data(#"[[["Hi Victoria","Hi Victoria",null,null,3]],null,"ro",null,null,null,0.46,[],[["ro"],null,[0.46],["ro"]]]"#.utf8)
    check("Google names a source even when it echoes the text", C.parseGoogleSourceLanguage(googleEcho) == "ro")
    check("a Google answer with no source reports none",
          C.parseGoogleSourceLanguage(Data(#"[[["a","b"]]]"#.utf8)) == nil)

    let azure = Data(#"[{"detectedLanguage":{"language":"af","score":0.97},"translations":[{"text":"Thanks for everything my friend","to":"en"}]}]"#.utf8)
    let azureReply = try C.parseMicrosoftResponse(azure)
    check("Microsoft reply carries its translation", azureReply.text == "Thanks for everything my friend")
    check("Microsoft reply carries detectedLanguage", azureReply.sourceLanguage == "af")
    let azureNoDetect = try C.parseMicrosoftResponse(Data(#"[{"translations":[{"text":"x","to":"en"}]}]"#.utf8))
    check("a Microsoft reply without detectedLanguage reports none", azureNoDetect.sourceLanguage == nil)

    let libre = Data(#"{"detectedLanguage":{"confidence":92,"language":"ca"},"translatedText":"Good morning"}"#.utf8)
    let libreReply = try C.parseLibreTranslateResponse(libre)
    check("LibreTranslate reply carries its translation", libreReply.text == "Good morning")
    check("LibreTranslate reply carries detectedLanguage", libreReply.sourceLanguage == "ca")
    let libreNoDetect = try C.parseLibreTranslateResponse(Data(#"{"translatedText":"x"}"#.utf8))
    check("a LibreTranslate reply without detectedLanguage reports none", libreNoDetect.sourceLanguage == nil)
    check("a LibreTranslate error body is an invalid response",
          (try? C.parseLibreTranslateResponse(Data(#"{"error":"Too many requests"}"#.utf8))) == nil)

    // Reported-code normalisation.
    let codes: [(String?, String?)] = [
        ("es", "es"), ("EN", "en"), ("zh-CN", "zh"), ("zh-Hans", "zh"), ("pt-PT", "pt"),
        ("mni-Mtei", "mni"), ("haw", "haw"), ("iw", "he"), ("jw", "jv"), ("in", "id"),
        ("und", nil), ("auto", nil), ("e1", nil), ("", nil), (nil, nil),
    ]
    for (reported, expected) in codes {
        check("reported language \(reported ?? "nil") folds to \(expected ?? "nil")",
              TranslationSource.normalizedReportedLanguage(reported) == expected)
    }

    // Marker text.
    check("Afrikaans is named, not Dutch", TranslationSource.markerLanguageName(code: "af", locale: english) == "Afrikaans")
    check("a regional code names its base language", TranslationSource.markerLanguageName(code: "pt-PT", locale: english) == "Portuguese")
    check("no code reads another language", TranslationSource.markerLanguageName(code: nil, locale: english) == "another language")
    check("an unknown code reads another language", TranslationSource.markerLanguageName(code: "qq", locale: english) == "another language")

    // Unchanged-text compare.
    for body in ["Hi Victoria", "Romanceslop", "YO ADEEEEEEE"] {
        check("'\(body)' echoed is unchanged", !TranslationSource.textChanged(from: body, to: body))
    }
    check("case and spacing are not a translation", !TranslationSource.textChanged(from: "Wordslop ", to: "wordslop"))
    check("a media token the provider never saw is not a change",
          !TranslationSource.textChanged(from: "lol\n\n![gif](giphy|ECtLJKdGj8jfy)", to: "lol"))
    check("a media-only body has nothing to translate", !TranslationSource.textChanged(from: "![gif](giphy|abc)", to: "x"))
    check("a translation is a change",
          TranslationSource.textChanged(from: "Dankie vir alles my vriend", to: "Thanks for everything my friend"))

    // Outcomes built from sample replies.
    let spanish = TranslationOutcome(original: "Hola, ¿cómo estás?", translated: "Hello how are you?", reportedSource: "es")
    check("a translated reply is changed and shown", spanish.isChanged && spanish.isShown(skipping: []))
    check("its marker names the reported language", spanish.markerLanguageName(locale: english) == "Spanish")
    let echoed = TranslationOutcome(original: "Hi Victoria", translated: "Hi Victoria", reportedSource: "ro")
    check("an echoed reply is not changed and not shown", !echoed.isChanged && !echoed.isShown(skipping: []))
    check("the reported language wins over the on-device guess",
          TranslationOutcome(original: "Dankie", translated: "Thank you", reportedSource: "af")
            .markerLanguageName(fallbackCode: "nl", locale: english) == "Afrikaans")
    check("the on-device guess names a reply that reported none",
          TranslationOutcome(original: "Hola", translated: "Hello", reportedSource: nil)
            .markerLanguageName(fallbackCode: "es", locale: english) == "Spanish")
    check("a reported Don't Translate language is not shown",
          !spanish.isShown(skipping: ["fr", "ES"]))
    check("an unlisted language is still shown", spanish.isShown(skipping: ["fr"]))
    check("a reply that names no language is not skipped", TranslationOutcome(original: "Hola", translated: "Hello", reportedSource: nil)
            .isShown(skipping: ["es"]))

    // Session cache keeps unchanged answers.
    let cache = TranslationOutcomeCache()
    check("an unseen text is not cached", cache.outcome(for: "Hi Victoria", target: "en") == nil)
    cache.store(echoed, for: "Hi Victoria", target: "en")
    check("an unchanged answer is cached", cache.outcome(for: "Hi Victoria", target: "en") == echoed)
    check("the cache is per target language", cache.outcome(for: "Hi Victoria", target: "de") == nil)
    check("a cached unchanged answer stays unchanged", cache.outcome(for: "Hi Victoria", target: "EN")?.isChanged == false)
}
