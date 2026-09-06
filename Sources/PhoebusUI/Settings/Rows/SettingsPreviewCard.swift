import SwiftUI
import PhoebusCore

/// A settings screen with a live preview card above its controls (Reborn's
/// pinned settings preview). A container rather than a `ViewModifier` because
/// pinning is a two-position problem: pinned, the card sits outside the
/// scrolling content via `safeAreaInset`; unpinned, it is the first row. A
/// modifier cannot inject a row into the `Form` it wraps, so this owns the
/// `List` instead.
public struct SettingsPreviewScreenLayout<Preview: View, Content: View>: View {
    let screen: SettingsPreviewScreen
    let title: String
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let content: () -> Content

    @State private var isPinned: Bool
    @State private var captionToken = 0
    @State private var captionVisible = false
    @State private var glyphScale: CGFloat = 1
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Profile Layout's card spans the table's readable width, with the
    /// pin control near the card's trailing edge, not over its top
    /// corner.
    private var edgeToEdge: Bool { screen == .profileLayout }

    @State private var cardHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = .greatestFiniteMagnitude

    public init(
        screen: SettingsPreviewScreen,
        title: String = "Preview",
        @ViewBuilder preview: @escaping () -> Preview,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.screen = screen
        self.title = title
        self.preview = preview
        self.content = content
        _isPinned = State(initialValue: SettingsPreviewPinStore.isPinned(screen))
    }

    /// The list room (viewport minus card height plus backdrop pad)
    /// must be at least 200pt or pinning is unavailable outright,
    /// otherwise a tall preview card would fill the `safeAreaInset`
    /// entirely and leave the `List` beneath it unable to scroll.
    private var pinningAvailable: Bool {
        containerHeight - (cardHeight + 8) >= 200
    }
    private var shouldPin: Bool {
        isPinned && pinningAvailable && verticalSizeClass != .compact
    }

    public var body: some View {
        GeometryReader { proxy in
            listBody
                .onAppear { containerHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, h in containerHeight = h }
        }
    }

    private var listBody: some View {
        List {
            if !shouldPin {
                Section {
                    card
                        .listRowInsets(edgeToEdge
                                       ? EdgeInsets(top: 0, leading: 16, bottom: 15, trailing: 16)
                                       : EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(edgeToEdge ? .hidden : .automatic)
                } header: {
                    // "Preview", bold (not the uppercase footnote),
                    // sitting under the bar, with the card below it.
                    HStack(alignment: .center) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.apolloSettingsSecondary)
                            .textCase(nil)
                            .modifier(ApolloSectionTextInset(flatLeading: 36 - 16, flatTrailing: 0))
                        if edgeToEdge {
                            Spacer()
                            pinControl.padding(.trailing, 5)
                        }
                    }
                    .padding(.top, 15 - 8)
                    .padding(.bottom, edgeToEdge ? 5 : -1)
                }
            }
            content()
        }
        // The preview screens are plain grouped tables like every other settings
        // screen: no rounded inset cards (`Form` alone draws them).
        .apolloSettingsListAppearance()
        .onChange(of: pinningAvailable) { _, available in
            // Availability flipping re-shows the caption on its own,
            // not just on tap, so shrinking the window below 200pt of
            // list room says "Needs room" without the user touching
            // the pin.
            guard !available else { return }
            captionToken += 1
            withAnimation(.easeOut(duration: 0.15)) { captionVisible = true }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if shouldPin {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.apolloSettingsSecondary)
                            .padding(.leading, edgeToEdge ? 18 : 20)
                        Spacer()
                        if edgeToEdge { pinControl.padding(.trailing, 5) }
                    }
                    card
                }
                .padding(.horizontal, 16)
                // Rich Link Previews' pinned title sits 31pt under the bar, as Apollo's
                // does.
                .padding(.top, screen == .linkPreview ? 28 : 0)
                .padding(.bottom, 8)
                // The card sits on an opaque backdrop, so the rows
                // scrolling under it are hidden.
                .background(Color(.systemBackground))
            }
        }
    }

    private var card: some View {
        ZStack(alignment: .topTrailing) {
            if edgeToEdge {
                // The preview is the card (22pt clip inside), no inner
                // padding.
                preview()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Rich Link Previews' cards run under the pin to the full
                // width; their captions keep clear of it themselves.
                preview()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .padding(.trailing, screen == .linkPreview ? 0 : 22)

                pinControl
                    .padding(.trailing, 12)
                    .padding(.top, 7)
            }
        }
        .background(
            // Corner radius 22, matching the shared container for
            // every settings preview card. No fill: the card is a
            // clear, clipped container, since the preview content
            // paints itself.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, edgeToEdge || screen == .linkPreview ? 0 : 4)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { cardHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, h in cardHeight = h }
        })
        .accessibilityIdentifier("settings.preview.\(screen.rawValue)")
    }

    /// Caption + pin glyph. Reborn's pin target is a real `UIButton`,
    /// not a tap recogniser on the card, so this is a `Button` too.
    private var pinControl: some View {
        HStack(spacing: 6) {
            if captionVisible {
                Text(SettingsPreviewPinStore.caption(pinned: isPinned, pinningAvailable: pinningAvailable))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button(action: togglePin) {
                Image(systemName: SettingsPreviewPinStore.symbolName(pinned: isPinned, pinningAvailable: pinningAvailable))
                    .font(.system(size: 13, weight: .semibold))
                    // Colour rule: accent only while actively pinned
                    // (pinned and room); otherwise secondary if the
                    // preference is pinned or there is no room at all,
                    // tertiary only for a genuinely unpinned,
                    // available state.
                    .foregroundStyle(
                        isPinned && pinningAvailable ? Color.apolloAccent
                        : (isPinned || !pinningAvailable) ? Color(.secondaryLabel)
                        : Color(.tertiaryLabel)
                    )
                    .scaleEffect(glyphScale)
                    // Glyph box is 22pt, inset 12pt from the card's
                    // right edge and 7pt from its top.
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SettingsPreviewPinStore.accessibilityLabel(pinned: isPinned))
            .accessibilityIdentifier("settings.preview.pin.\(screen.rawValue)")
        }
    }

    private func togglePin() {
        isPinned.toggle()
        SettingsPreviewPinStore.setPinned(isPinned, for: screen)
        Haptics.selection()

        // Spring bounce: 1.3x, 0.45s, damping 0.5.
        glyphScale = 1.3
        withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { glyphScale = 1 }

        // The token is what makes a quick re-tap replace the caption
        // instead of stacking another fade; without it a double tap
        // can leave a caption showing the opposite of the current
        // state.
        captionToken += 1
        let token = captionToken
        withAnimation(.easeOut(duration: 0.15)) { captionVisible = true }
        // No fade timer at all while there's no room, so "Needs room"
        // stays up rather than disappearing on a control the tap did
        // not actually change.
        guard pinningAvailable else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard token == captionToken else { return }
            withAnimation(.easeOut(duration: 0.3)) { captionVisible = false }
        }
    }
}
