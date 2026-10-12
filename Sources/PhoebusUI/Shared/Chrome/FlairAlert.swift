import SwiftUI
import PhoebusCore

/// Apollo's flair alert (`FlairAlertController`): a tapped flair shown in
/// full under the title "Flair", dismissed with OK. Phoebus adds a line
/// naming the kind of flair and its subreddit.
///
/// Drawn rather than a system alert, which can't show the flair's emoji
/// images, and styled as the system alert of the running OS: iOS 26's
/// glass alert or the classic one. The choice follows the OS
/// (`LiquidGlass.isAvailable`), not the Enable Liquid Glass setting, as the
/// system's own alerts do.
struct FlairAlert: View {
    let info: FlairInfo
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var shown = false

    private let style: Style = LiquidGlass.isAvailable ? .glass : .classic

    /// Metrics read off UIAlertController: iOS 26.5's from its view tree, the
    /// classic ones from iOS 17 and 18.
    private enum Style {
        case glass, classic

        var width: CGFloat { self == .glass ? 320 : 270 }
        var cornerRadius: CGFloat { self == .glass ? 34 : 14 }
        var sideInset: CGFloat { self == .glass ? 30 : 16 }
        var topInset: CGFloat { self == .glass ? 22 : 20 }
        var titleSpacing: CGFloat { self == .glass ? 7 : 2 }
        /// Below the message, above the button area.
        var bottomInset: CGFloat { self == .glass ? 5 : 20 }
        var messageFont: Font { self == .glass ? .subheadline : .footnote }
        var alignment: HorizontalAlignment { self == .glass ? .leading : .center }
        /// The scale the card appears from.
        var appearScale: CGFloat { self == .glass ? 0.9 : 1.2 }
    }

    var body: some View {
        ZStack {
            // UIKit's `_alertControllerDimmingViewColor`, measured on iOS 26.5:
            // black at 48% in dark mode, near-black at 22% in light.
            (colorScheme == .dark ? Color.black.opacity(0.48) : Color(white: 0.1).opacity(0.22))
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
            card
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : style.appearScale)
        }
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(style == .glass ? .spring(duration: 0.35, bounce: 0.2) : .easeOut(duration: 0.3)) {
                shown = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            VStack(alignment: style.alignment, spacing: style.titleSpacing) {
                Text(FlairInfo.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: style.alignment, spacing: 2) {
                    flair
                    Text(info.detail)
                }
                .font(style.messageFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(style == .glass ? .leading : .center)
            }
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: style.alignment, vertical: .center))
            .padding(.horizontal, style.sideInset)
            .padding(.top, style.topInset)
            .padding(.bottom, style.bottomInset)
            button
        }
        .frame(width: style.width)
        .background { background }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The flair in full: text runs split into words so a long flair wraps
    /// between them, emoji as images at the text's size.
    private var flair: some View {
        FlowLayout(horizontalSpacing: 4, verticalSpacing: 2) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .emoji(let url):
                    FlairEmoji(url: url)
                case .text(let word):
                    Text(word)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.spokenText)
    }

    @ViewBuilder
    private var button: some View {
        switch style {
        case .glass:
            // A 48pt capsule inset 16pt, in `tertiarySystemFill`, the label in
            // the app's tint at 17pt medium.
            Button(action: dismiss) {
                Text("OK")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(AlertCapsuleButtonStyle())
            .padding(16)
            .accessibilityIdentifier("flairAlert.ok")
        case .classic:
            // A hairline, then a 44pt full-width row, the label in the app's
            // tint at 17pt regular.
            VStack(spacing: 0) {
                Divider()
                Button(action: dismiss) {
                    Text("OK")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AlertRowButtonStyle())
                .accessibilityIdentifier("flairAlert.ok")
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        if #available(iOS 26.0, *), style == .glass, LiquidGlass.canRenderGlass {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }

    /// Text runs split into words, so a long flair wraps between them.
    private var pieces: [FlairPart.Kind] {
        info.runs.flatMap { run -> [FlairPart.Kind] in
            guard case .text(let value) = run else { return [run] }
            return value.split(separator: " ").map { .text(String($0)) }
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}

/// A flair emoji at the message text's size, following Dynamic Type.
private struct FlairEmoji: View {
    let url: URL
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 17

    var body: some View {
        CachedAsyncImage(url: url)
            .frame(width: size, height: size)
    }
}

private struct AlertCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tint)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)).opacity(configuration.isPressed ? 1 : 0))
            .contentShape(Capsule())
    }
}

private struct AlertRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tint)
            .background(Color(uiColor: .tertiarySystemFill).opacity(configuration.isPressed ? 1 : 0))
    }
}

extension View {
    /// Shows `FlairAlert` for `info` while it's set. Set it with
    /// `FlairAlert.present`, so the cover doesn't slide up under the fade.
    func flairAlert(_ info: Binding<FlairInfo?>) -> some View {
        fullScreenCover(item: info) { shown in
            FlairAlert(info: shown) { FlairAlert.present(nil, in: info) }
        }
    }
}

extension FlairAlert {
    static func present(_ value: FlairInfo?, in binding: Binding<FlairInfo?>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { binding.wrappedValue = value }
    }
}
