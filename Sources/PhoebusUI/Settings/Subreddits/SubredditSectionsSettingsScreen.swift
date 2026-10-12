import SwiftUI
import PhoebusCore

/// Reborn's "Subreddit List Sections" screen: drag-to-reorder for the Subreddits-root
/// list's special sections, a "Following" section toggle for followed users, and
/// multireddit-description visibility. See `SubredditSectionsSettings.swift`.
///
/// Also hosts "Per-Account Favorites", which Reborn groups into the same
/// Subreddits hub, rather than adding a standalone screen for a single toggle.
public struct SubredditSectionsSettingsScreen: View {
    @Setting(SubredditSectionsSettingsStore.storage) private var settings
    @Setting(AppearanceSettingsStore.storage) private var appearance

    public init() {}

    public var body: some View {
        // Built around a live preview card, a miniature of the Subreddits list that stays
        // on screen while the toggles and drag-to-reorder rows scroll beneath it.
        SettingsPreviewScreenLayout(screen: .subredditSections) {
            SubredditSectionsPreviewMock(settings: settings, showIcons: appearance.showSubredditIconsInSubredditList)
        } content: {
            Section {
                // Moved here from Appearance (Reborn "Polish Subreddit Section
                // Previews and Settings", #1351); same `ShowSubredditIconsInSubredditList` key.
                Toggle("Show Subreddit Icons", isOn: $appearance.showSubredditIconsInSubredditList)
                    .apolloSearchRow("Show Subreddit Icons")
                    .accessibilityIdentifier("subredditSections.showIcons")
                Toggle("Separate Followed Users", isOn: separateFollowingBinding)
                    .apolloSearchRow("Separate Followed Users")
                    .accessibilityIdentifier("subredditSections.separateFollowing")
                Toggle("Hide Multireddit Descriptions", isOn: hideMultiredditDescriptionsBinding)
                    .apolloSearchRow("Hide Multireddit Descriptions")
                    .accessibilityIdentifier("subredditSections.hideMultiredditDescriptions")
                // Phoebus-only: also hides the Search tab's list.
                Toggle("Show Recently Visited", isOn: $settings.showRecentlyVisited)
                    .apolloSearchRow("Show Recently Visited")
                    .accessibilityIdentifier("subredditSections.showRecentlyVisited")
                // Rows 3 and 4 both default on, as in Apollo's Subreddits list. Enhancements
                // drives the preview's accent band headers and letter avatars; Modern Dividers
                // picks the rule style, and its row is hidden while Enhancements is off.
                Toggle("Subreddit List Enhancements", isOn: listEnhancementsBinding)
                    .apolloSearchRow("Subreddit List Enhancements")
                    .accessibilityIdentifier("subredditSections.listEnhancements")
                if settings.subredditListEnhancements {
                    Toggle("Modern Subreddit Dividers", isOn: modernDividersBinding)
                        .apolloSearchRow("Modern Subreddit Dividers", lastBeforeFooter: true)
                        .accessibilityIdentifier("subredditSections.modernDividers")
                }
            } header: {
                Text("Options")
                    .apolloPreviewScreenSectionHeader()
            } footer: {
                // Verbatim footer.
                Text("Subreddit List Enhancements make the alphabet index and favorite stars easier to tap, and improve spacing around icons and the index.")
                    .apolloPreviewScreenSectionFooter()
            }

            // The "Section Order" drag-to-reorder list; `.onMove` is SwiftUI's equivalent of
            // a `UITableView` drag-and-drop delegate pair.
            Section {
                ForEach(visibleOrderForEditing, id: \.self) { token in
                    HStack {
                        Text(token.displayName)
                        Spacer()
                        Image(systemName: "line.horizontal.3")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityIdentifier("subredditSections.order.\(token.rawValue)")
                }
                .onMove(perform: moveSections)
            } header: {
                Text("Section Order")
                    .apolloPreviewScreenSectionHeader()
            }
            .environment(\.editMode, .constant(.active))

        }
        .apolloSettingsSearchScroll()
        .navigationTitle("Subreddit List Sections")
    }

    /// The Following row only appears in the reorder list while Separate Followed
    /// Users is on, matching `SubredditSectionsSettings.visibleOrder`.
    private var visibleOrderForEditing: [SubredditSectionsSettings.SectionToken] {
        settings.visibleOrder
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        // Reorders only the currently-visible tokens, then splices any hidden `following`
        // token back at its last resolved position so toggling Separate Followed Users
        // back on does not lose its place.
        var visible = settings.visibleOrder
        visible.move(fromOffsets: source, toOffset: destination)
        if !settings.separateFollowedUsers, settings.resolvedOrder.contains(.following) {
            let followingIndex = settings.resolvedOrder.firstIndex(of: .following) ?? visible.count
            visible.insert(.following, at: min(followingIndex, visible.count))
        }
        $settings.order.wrappedValue = visible
    }

    private var separateFollowingBinding: Binding<Bool> {
        Binding(
            get: { settings.separateFollowedUsers },
            set: {
                $settings.separateFollowedUsers.wrappedValue = $0
            }
        )
    }

    private var hideMultiredditDescriptionsBinding: Binding<Bool> {
        Binding(
            get: { settings.hideMultiredditDescriptions },
            set: {
                $settings.hideMultiredditDescriptions.wrappedValue = $0
            }
        )
    }

    private var listEnhancementsBinding: Binding<Bool> {
        Binding(
            get: { settings.subredditListEnhancements },
            set: {
                $settings.subredditListEnhancements.wrappedValue = $0
            }
        )
    }

    private var modernDividersBinding: Binding<Bool> {
        Binding(
            get: { settings.modernSubredditDividers },
            set: {
                $settings.modernSubredditDividers.wrappedValue = $0
            }
        )
    }
}
