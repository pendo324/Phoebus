import SwiftUI
import PhoebusCore

/// Reborn's Rich Link Previews sub-screen: controls how `LinkPreviewCard`
/// renders. See `LinkPreviewSettings`.
public struct LinkPreviewSettingsScreen: View {
    @Setting(LinkPreviewSettings.self) private var settings
    /// `ColorPicker` needs a concrete `Color`; a nil model value (Default color) maps
    /// to the accent as the picker's starting point. "Use Default Color" is what
    /// clears `cardColorHex`.
    @State private var pickerColor: Color
    @State private var modeSheetForBody: Bool?
    @State private var showingColorPicker = false
    @State private var showingTwitterFallback = false

    /// `ApolloLPQuickSwatchHexes()`.
    static let quickSwatchHexes = ["FF3B30", "FF9500", "FFCC00", "34C759", "30B0C7", "007AFF", "5856D6", "AF52DE", "FF2D55"]

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    public init() {
        let loaded = LinkPreviewSettingsStore.load()
        _pickerColor = State(initialValue: loaded.cardColorHex.map(Color.init(hex:)) ?? .accentColor)
    }

    public var body: some View {
        // Live preview card showing both areas, so a custom card colour can be judged
        // before committing.
        SettingsPreviewScreenLayout(screen: .linkPreview) {
            LinkPreviewSettingsMock(settings: settings)
        } content: {
            #if DEBUG
            // Debug only: set APOLLO_TWEET_PREVIEW to a status URL to preview the tweet card.
            if let raw = ProcessInfo.processInfo.environment["APOLLO_TWEET_PREVIEW"],
               let url = URL(string: raw), let id = TweetURL.statusID(from: url) {
                Section { LinkPreviewCard(url: url) }
            }
            #endif
            // Body / Comments value rows open an action sheet with the current mode marked
            // "(Current)".
            Section {
                Button { modeSheetForBody = true } label: { valueRow("Body", settings.bodyDisplayMode.title) }
                    .apolloSearchRow("Body")
                    .accessibilityIdentifier("linkPreviews.bodyMode")
                Button { modeSheetForBody = false } label: { valueRow("Comments", settings.commentsDisplayMode.title) }
                    .apolloSearchRow("Comments", lastBeforeFooter: true)
                    .accessibilityIdentifier("linkPreviews.commentsMode")
            } header: {
                Text("Previews")
                    .apolloSectionHeader()
            } footer: {
                Text("Off keeps Phoebus's classic link button, Compact shows a small thumbnail row, Full shows a large hero image card. The preview above follows each setting. Comments with more than one link always use compact cards, even when Full is selected, so long comments don't stack up hero images.")
                    .apolloSectionFooter()
            }

            // Fallback provider for tweets X will not serve.
            Section {
                Button { showingTwitterFallback = true } label: {
                    valueRow("Fallback Provider", settings.twitterFallback.title)
                }
                .apolloSearchRow("Fallback Provider", lastBeforeFooter: true)
                .accessibilityIdentifier("linkPreviews.twitterFallback")
            } header: {
                Text("Twitter / X")
                    .apolloSectionHeader()
            } footer: {
                Text("X sometimes withholds a post from apps on purpose. When it does, Phoebus asks this service for it instead, sending it the post's link. None leaves those posts as a plain link.")
                    .apolloSectionFooter()
            }

            // Card Color: swatch row, nine quick swatches, and "Use Default (No Color)" only
            // while a custom colour is set.
            Section {
                Button { showingColorPicker = true } label: {
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(settings.cardColorHex.map(Color.init(hex:)) ?? Color(.secondarySystemFill))
                            .frame(width: 24, height: 24)
                        Text("Color").foregroundStyle(.primary)
                        Spacer()
                        Text(settings.cardColorHex.map { "#\($0.uppercased())" } ?? "Default")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .modifier(SettingsSearchRowModifier(title: "Color"))
                // The row separator starts at the title, past the swatch.
                .modifier(ApolloSettingsRowChrome(rule: true, ruleLeading: 40, breathing: false))
                .accessibilityIdentifier("linkPreviews.cardColor")
                HStack {
                    ForEach(Self.quickSwatchHexes, id: \.self) { hex in
                        let selected = settings.cardColorHex?.uppercased() == hex
                        Button {
                            $settings.cardColorHex.wrappedValue = hex
                            pickerColor = Color(hex: hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: selected ? 2.5 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Card color #\(hex)")
                        if hex != Self.quickSwatchHexes.last { Spacer(minLength: 0) }
                    }
                }
                .padding(.vertical, 11)
                .apolloPlainSettingsRowInsets(rule: settings.cardColorHex != nil)
                if settings.cardColorHex != nil {
                    Button("Use Default (No Color)") {
                        $settings.cardColorHex.wrappedValue = nil
                        pickerColor = .accentColor
                    }
                    .foregroundStyle(Color.apolloAccent)
                    .apolloPlainSettingsRowInsets(rule: false)
                }
            } header: {
                Text("Card Color")
                    .apolloSectionHeader()
            } footer: {
                Text("The card is painted the exact color you pick, the same in light and dark mode, with title and description text automatically set to black or white for contrast. Default keeps the standard neutral card.")
                    .apolloSectionFooter()
            }
        }
        .confirmationDialog(modeSheetForBody == true ? "Body Link Previews" : "Comment Link Previews",
                            isPresented: $modeSheetForBody.isPresent(),
                            titleVisibility: .visible) {
            let isBody = modeSheetForBody == true
            let current = isBody ? settings.bodyDisplayMode : settings.commentsDisplayMode
            // Full, Compact, Off in that order.
            ForEach([LinkPreviewDisplayMode.full, .compact, .off]) { mode in
                Button(mode == current ? "\(mode.title) (Current)" : mode.title) {
                    if isBody { $settings.bodyDisplayMode.wrappedValue = mode } else { $settings.commentsDisplayMode.wrappedValue = mode }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(modeSheetForBody == true
                 ? "Choose how rich link preview cards appear in feeds and post bodies."
                 : "Choose how rich link preview cards appear in comments.")
        }
        .confirmationDialog("Twitter Fallback Provider", isPresented: $showingTwitterFallback, titleVisibility: .visible) {
            ForEach(TwitterFallbackProvider.allCases) { provider in
                Button(provider == settings.twitterFallback ? "\(provider.title) (Current)" : provider.title) {
                    $settings.twitterFallback.wrappedValue = provider
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Used for tweets X won't show to apps.")
        }
        // `UIColorPickerViewController` titled "Preview Card Color", no alpha.
        .sheet(isPresented: $showingColorPicker) {
            NavigationStack {
                ColorPicker("Preview Card Color", selection: $pickerColor, supportsOpacity: false)
                    .padding()
                    .navigationTitle("Preview Card Color")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingColorPicker = false } } }
                    .onChange(of: pickerColor) { _, newValue in $settings.cardColorHex.wrappedValue = newValue.hexString }
            }
            .presentationDetents([.medium])
        }
        .apolloSettingsSearchScroll()
        .navigationTitle("Rich Link Previews")
    }
}
