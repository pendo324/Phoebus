import SwiftUI
import PhoebusCore

/// Reborn's "Subreddit Layout" screen: customizes a subreddit's own page (as
/// opposed to `SubredditSectionsSettingsScreen`, which customizes the
/// Subreddits-root list). See `SubredditLayoutSettings.swift`.
public struct SubredditLayoutSettingsScreen: View {
    @Setting(SubredditLayoutSettingsStore.storage) private var settings

    public init() {}

    public var body: some View {
        // The live header preview card leads the screen, so every switch below is
        // changed with its effect in view.
        SettingsPreviewScreenLayout(screen: .subredditLayout) {
            SubredditLayoutPreviewMock(settings: settings)
        } content: {
            Section {
                // "Header Style" row (Immersive / Compact / Native) with a chevron, opening a
                // picker with those three options.
                ApolloSettingsPicker("Header Style", selection: densityBinding,
                                 options: [Density.immersive, Density.classic, Density.native],
                                 display: { value in
                                     switch value {
                                     case Density.immersive: return "Immersive"
                                     case Density.classic: return "Compact"
                                     case Density.native: return "Native"
                                     default: return "\(value)"
                                     }
                                 },
                                 showsChevron: true) { Text("Header Style") }
                    .apolloSearchRow("Header Style")
                .accessibilityIdentifier("subredditLayout.density")

                if settings.showSubredditHeaders {
                    // Reborn's order.
                    Toggle("Banner", isOn: binding(\.subredditShowBanner))
                    .apolloSearchRow("Banner")
                        .accessibilityIdentifier("subredditLayout.showBanner")
                    Toggle("Join Button", isOn: binding(\.subredditShowJoinButton))
                    .apolloSearchRow("Join Button")
                        .accessibilityIdentifier("subredditLayout.showJoinButton")
                    Toggle("User Flair Button", isOn: binding(\.subredditShowUserFlairButton))
                    .apolloSearchRow("User Flair Button")
                        .accessibilityIdentifier("subredditLayout.showUserFlairButton")
                    Toggle("Sidebar Button", isOn: binding(\.subredditShowSidebarButton))
                    .apolloSearchRow("Sidebar Button")
                        .accessibilityIdentifier("subredditLayout.showSidebarButton")
                    Toggle("Subreddit Name", isOn: binding(\.subredditShowDisplayName))
                    .apolloSearchRow("Subreddit Name")
                        .accessibilityIdentifier("subredditLayout.showDisplayName")
                    Toggle("Subtitle", isOn: binding(\.subredditShowSubtitle))
                    .apolloSearchRow("Subtitle")
                        .accessibilityIdentifier("subredditLayout.showSubtitle")
                    Toggle("Description", isOn: binding(\.subredditShowDescription))
                    .apolloSearchRow("Description", lastBeforeFooter: true)
                        .accessibilityIdentifier("subredditLayout.showDescription")
                }
            } header: {
                Text("Layout")
                    .apolloPreviewScreenSectionHeader()
            } footer: {
                // Verbatim.
                Text("Immersive and Compact use Apollo Reborn’s customizable header. Native keeps Apollo’s original layout.")
                    .apolloPreviewScreenSectionFooter()
            }

            // Section "Community Highlights", row "Display" with Off / Partial / Full and a
            // chevron, no footer.
            Section {
                ApolloSettingsPicker("Display", selection: binding(\.communityHighlights),
                                 options: Array(SubredditLayoutSettings.CommunityHighlightsMode.allCases),
                                 display: { $0.displayName },
                                 showsChevron: true) { Text("Display") }
                    .apolloSearchRow("Community Highlights")
                .accessibilityIdentifier("subredditLayout.communityHighlights")
                // Reborn's highlights preview row: the carousel with sample posts.
                CommunityHighlightsPreview(mode: settings.communityHighlights)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 0))
                    .accessibilityIdentifier("subredditLayout.highlightsPreview")
            } header: {
                Text("Community Highlights")
                    .apolloPreviewScreenSectionHeader()
            }
        }
        .apolloSettingsSearchScroll()
        .navigationTitle("Subreddit Layout")
    }

    private enum Density: Hashable {
        case immersive, classic, native
    }

    private var densityBinding: Binding<Density> {
        Binding(
            get: {
                guard settings.showSubredditHeaders else { return .native }
                return settings.subredditHeaderImmersive ? .immersive : .classic
            },
            set: { newValue in
                switch newValue {
                case .immersive:
                    $settings.showSubredditHeaders.wrappedValue = true
                    $settings.subredditHeaderImmersive.wrappedValue = true
                case .classic:
                    $settings.showSubredditHeaders.wrappedValue = true
                    $settings.subredditHeaderImmersive.wrappedValue = false
                case .native:
                    $settings.showSubredditHeaders.wrappedValue = false
                }
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SubredditLayoutSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                $settings[dynamicMember: keyPath].wrappedValue = $0
            }
        )
    }
}
