import SwiftUI
import PhoebusCore

/// Apollo's Appearance settings screen, separate from the Theme row. Row
/// titles are Apollo's, backed by Apollo's UserDefaults keys.
///
/// Rows noted inline as WIRED are distinct Apollo settings implemented
/// against their render site. CONSOLIDATED rows read and write an existing
/// `GeneralSettings` field directly, as Apollo surfaces some settings from two
/// entrances (e.g. "Show User Profile Pictures" on General and Interface).
/// "Show GIF Progress" is omitted: there is no GIF progress strip to control.
public struct AppearanceSettingsScreen: View {
    @Setting(AppearanceSettingsStore.storage) private var settings
    @Setting(GeneralSettingsStore.storage) private var generalSettings

    public init() {}

    public var body: some View {
        // Sections: Themes / Text Size / Posts / Large Posts / Compact Posts / Media /
        // Subreddits List / Flair / Other. Each has a small-caps header and no footer.
        List {
            Section {
                SettingsLink {
                    ThemeSettingsScreen()
                } label: {
                    HStack(spacing: 12) {
                        SettingsTile(systemImage: "paintbrush.fill", tint: Color(uiColor: .systemIndigo))
                        Text("Theme Manager")
                    }
                }
                .apolloSettingsRowInsets()
            } header: {
                Text("Themes")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Use System Text Size", isOn: binding(\.useSystemTextSize))
                    .apolloSearchRow("Use System Text Size")
                    .accessibilityIdentifier("appearance.useSystemTextSize")
                // The A ——●—— A slider is always shown (greyed while the
                // switch is on), not hidden.
                HStack(spacing: 7) {
                    Text("A").font(.footnote).foregroundStyle(.secondary)
                    TextSizeSlider(value: binding(\.textSizeScale))
                        .accessibilityIdentifier("appearance.textSize")
                    Text("A").font(.title3).foregroundStyle(.secondary)
                }
                .disabled(settings.useSystemTextSize)
                .apolloCardRowFill()
            } header: {
                Text("Text Size")
                    .apolloSectionHeader()
            }

            Section {
                ApolloSettingsPicker("Post Size", selection: $generalSettings.postDisplayStyle,
                                 options: PostDisplayStyle.allCases.map { $0 },
                                 display: { $0 == .compact ? "Compact" : "Large" })
                    .apolloSearchRow("Post Size")
                Toggle("Post Size Per Subreddit", isOn: binding(\.rememberPostSizePerSubreddit))
                    .apolloSearchRow("Post Size Per Subreddit")
                    .accessibilityIdentifier("appearance.postSizePerSubreddit")
                Toggle("Show Subreddit Icons", isOn: binding(\.showSubredditIconsForPosts))
                    .apolloSearchRow("Show Subreddit Icons")
                    .accessibilityIdentifier("appearance.showSubredditIconsForPosts")
                Toggle("Show Subreddit at Top", isOn: binding(\.showSubredditAtTop))
                    .apolloSearchRow("Show Subreddit at Top")
                    .accessibilityIdentifier("appearance.showSubredditAtTop")
                Toggle("Always Show Usernames", isOn: binding(\.alwaysShowUsernames))
                    .apolloSearchRow("Always Show Usernames")
                    .accessibilityIdentifier("appearance.alwaysShowUsernames")
                Toggle("Show Page Endings", isOn: binding(\.showPageEndings))
                    .apolloSearchRow("Show Page Endings")
                    .accessibilityIdentifier("appearance.showPageEndings")
                Toggle("Bold Post Titles", isOn: binding(\.boldPostTitles))
                    .apolloSearchRow("Bold Post Titles")
                    .accessibilityIdentifier("appearance.boldPostTitles")
            } header: {
                Text("Posts")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Show Voting Buttons", isOn: binding(\.largePostsShowVotingButtons))
                    .apolloSearchRow("Show Voting Buttons")
            } header: {
                Text("Large Posts")
                    .apolloSectionHeader()
            }

            Section {
                ApolloSettingsPicker("Thumbnail Size", selection: $generalSettings.thumbnailSize,
                                 options: Array(ThumbnailSize.allCases),
                                 display: { $0.displayName })
                    .apolloSearchRow("Thumbnail Size")
                    .accessibilityIdentifier("appearance.thumbnailSize")
                ApolloSettingsPicker("Thumbnail Position", selection: thumbnailPositionBinding,
                                 options: AppearanceEdgePosition.allCases.map { $0 },
                                 display: { $0.title })
                    .apolloSearchRow("Thumbnail Position")
                    .accessibilityIdentifier("appearance.thumbnailPosition")
                Toggle("Show Self Post Thumbnails", isOn: binding(\.compactShowSelfPostThumbnails))
                    .apolloSearchRow("Show Self Post Thumbnails")
                    .accessibilityIdentifier("appearance.showSelfPostThumbnails")
                Toggle("Show Voting Buttons", isOn: binding(\.showVotingButtons))
                    // Second "Show Voting Buttons" (Large Posts has the other). Two rows cannot
                    // share one `SettingsSearchRowID`, so this copy is geometry only and search
                    // lands on the Large Posts row.
                    .apolloPlainSettingsRowInsets()
                    .accessibilityIdentifier("appearance.showVotingButtons")
                ApolloSettingsPicker("Voting Buttons Position", selection: binding(\.votingButtonsPosition),
                                 options: Array(AppearanceEdgePosition.allCases),
                                 display: { $0.title })
                    .apolloSearchRow("Voting Buttons Position")
                    .accessibilityIdentifier("appearance.votingButtonsPosition")
            } header: {
                Text("Compact Posts")
                    .apolloSectionHeader()
            }

            Section {
                ApolloSettingsPicker("Show GIF Progress", selection: binding(\.gifProgressLocation),
                                 options: GIFProgressLocation.allCases.map { $0 },
                                 display: { $0.title })
                    .apolloSearchRow("Show GIF Progress")
            } header: {
                Text("Media")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Show Subreddit Icons", isOn: binding(\.showSubredditIconsInSubredditList))
                    // Second "Show Subreddit Icons" (see the Posts
                    // section): geometry only, same reason.
                    .apolloPlainSettingsRowInsets()
                    .accessibilityIdentifier("appearance.showSubredditIconsInList")
            } header: {
                Text("Subreddits List")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Post Flair", isOn: $generalSettings.showPostFlair)
                    .apolloSearchRow("Post Flair")
                Toggle("User Flair", isOn: $generalSettings.showUserFlair)
                    .apolloSearchRow("User Flair")
                Toggle("Color Flairs", isOn: $generalSettings.enableFlairColors)
                    .apolloSearchRow("Color Flairs")
            } header: {
                Text("Flair")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Show Awards", isOn: $generalSettings.showAwards)
                    .apolloSearchRow("Show Awards")
            } header: {
                Text("Other")
                    .apolloSectionHeader()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Appearance")
            }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppearanceSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                $settings[dynamicMember: keyPath].wrappedValue = $0
            }
        )
    }

    private var thumbnailPositionBinding: Binding<AppearanceEdgePosition> {
        Binding(
            get: { generalSettings.thumbnailsOnLeft ? .left : .right },
            set: { side in $generalSettings.update { $0.thumbnailsOnLeft = (side == .left) } }
        )
    }
}

/// Apollo's stepped text-size slider: a 1pt track between the first and last
/// of seven sizes, a 1pt tick hanging below it at each size, no coloured fill,
/// and a white capsule thumb (#DADADA track and #B5B5B5 ticks on light, thumb
/// 37x24).
private struct TextSizeSlider: View {
    @Binding var value: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    private static let sizes = AppearanceTextSizeStep.sizes
    private static let thumb = CGSize(width: 37, height: 24)

    private var index: Int {
        Self.sizes.enumerated().min { abs($0.element - value) < abs($1.element - value) }?.offset ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let inset = Self.thumb.width / 2
            let span = max(1, geometry.size.width - inset * 2)
            let step = span / CGFloat(Self.sizes.count - 1)
            let midY = geometry.size.height / 2
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(trackColor)
                    .frame(width: span, height: 1)
                    .offset(x: inset, y: midY - 0.5)
                ForEach(Self.sizes.indices, id: \.self) { tick in
                    Rectangle()
                        .fill(tickColor)
                        .frame(width: 1, height: 6.5)
                        .offset(x: inset + CGFloat(tick) * step - 0.5, y: midY - 0.5)
                }
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 1)
                    .frame(width: Self.thumb.width, height: Self.thumb.height)
                    .offset(x: CGFloat(index) * step, y: midY - Self.thumb.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let raw = ((drag.location.x - inset) / step).rounded()
                        let next = Self.sizes[min(max(Int(raw), 0), Self.sizes.count - 1)]
                        if next != value { value = next }
                    }
            )
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel("Text Size")
        .accessibilityValue("\(index + 1) of \(Self.sizes.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = Self.sizes[min(index + 1, Self.sizes.count - 1)]
            case .decrement: value = Self.sizes[max(index - 1, 0)]
            @unknown default: break
            }
        }
    }

    private var trackColor: Color {
        Color(hex: colorScheme == .dark ? ApolloSettingsRowMetrics.separatorColorHex : "DADADA")
    }

    private var tickColor: Color {
        Color(hex: colorScheme == .dark ? ApolloSettingsRowMetrics.detailColorHex : "B5B5B5")
    }
}
