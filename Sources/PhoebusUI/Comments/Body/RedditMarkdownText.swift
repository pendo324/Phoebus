import SwiftUI
import PhoebusCore

/// One `Text` of a Reddit markdown body whose spoilers hide behind Apollo's
/// "SPOILER" label until tapped. A tap on a revealed spoiler's words hides it
/// again; a link inside the spoiler still opens. A body without a spoiler is
/// the bare `Text`, so its links keep the app's own handler.
///
/// The reveal is per view and not persisted, so scrolling a row away and back
/// hides its spoilers again. A body drawn as several pieces passes one
/// `shared` value and each piece's `spoilerBase` (`SpoilerReveal.bases`).
struct RedditMarkdownText: View {
    let raw: String
    var codeScale: Double = 1
    /// Collapsed previews keep their spoilers shut: the row's own tap runs.
    var isInteractive = true
    var shared: Binding<SpoilerReveal>?
    var spoilerBase = 0
    /// How many spoilers the whole body has, for naming VoiceOver's actions.
    var spoilerTotal: Int?

    @State private var own = SpoilerReveal()
    @Environment(\.bodyTextColor) private var textColor

    var body: some View {
        let count = RedditMarkdown.spoilerCount(in: raw)
        if isInteractive, count > 0 {
            let reveal = shared ?? $own
            let drawn = RedditMarkdown.render(
                raw, codeScale: codeScale,
                revealing: reveal.wrappedValue.revealing(base: spoilerBase, count: count),
                interactive: true
            ).colouringRevealedSpoilers(textColor)
            Text(drawn)
                .opensSpoilers(reveal, base: spoilerBase)
                .spoilerActions(for: drawn, reveal: reveal, base: spoilerBase, total: spoilerTotal ?? count)
        } else {
            Text(RedditMarkdown.render(raw, codeScale: codeScale))
        }
    }
}

/// Routes a tap on a spoiler's label or revealed words to `reveal`; every other
/// link goes on to the handler it would have reached without this. Being a link
/// run, the tap is consumed there and never reaches the row's own tap.
private struct SpoilerTapHandler: ViewModifier {
    @Binding var reveal: SpoilerReveal
    let base: Int
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            if let number = SpoilerMarkup.index(of: url) {
                reveal.toggle(base + number)
            } else {
                openURL(url)
            }
            return .handled
        })
    }
}

/// "Reveal spoiler" / "Hide spoiler" for each spoiler in `text`.
private struct SpoilerActions: ViewModifier {
    @Binding var reveal: SpoilerReveal
    let numbers: [Int]
    let base: Int
    let total: Int

    func body(content: Content) -> some View {
        content.accessibilityActions {
            ForEach(numbers, id: \.self) { number in
                Button(reveal.actionName(for: base + number, total: total)) { reveal.toggle(base + number) }
            }
        }
    }
}

extension View {
    func opensSpoilers(_ reveal: Binding<SpoilerReveal>, base: Int = 0) -> some View {
        modifier(SpoilerTapHandler(reveal: reveal, base: base))
    }

    func spoilerActions(for text: AttributedString, reveal: Binding<SpoilerReveal>, base: Int = 0, total: Int) -> some View {
        modifier(SpoilerActions(reveal: reveal, numbers: SpoilerMarkup.numbers(in: text), base: base, total: total))
    }

    /// The colour of the body's text, drawn in the view's foreground style and
    /// told to `RedditMarkdownText`, whose revealed spoilers are link runs and
    /// would otherwise take the tint.
    func bodyForeground(_ color: Color) -> some View {
        foregroundStyle(color).environment(\.bodyTextColor, color)
    }
}

private struct BodyTextColorKey: EnvironmentKey {
    static let defaultValue = Color.primary
}

extension EnvironmentValues {
    var bodyTextColor: Color {
        get { self[BodyTextColorKey.self] }
        set { self[BodyTextColorKey.self] = newValue }
    }
}

extension AttributedString {
    /// A revealed spoiler's words are a link run, which SwiftUI draws in the
    /// tint; this puts the body's text colour back on them. Links of the body's
    /// own, and runs with a colour of their own (code), are left as they are.
    func colouringRevealedSpoilers(_ color: Color) -> AttributedString {
        var out = self
        let plain = runs.filter { run in
            run.link.flatMap(SpoilerMarkup.index(of:)) != nil
                && run[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] == nil
        }.map(\.range)
        for range in plain { out[range].swiftUI.foregroundColor = color }
        return out
    }
}
