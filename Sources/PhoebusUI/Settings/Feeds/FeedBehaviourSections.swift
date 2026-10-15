import SwiftUI
import PhoebusCore

/// Feed's Sorting and Loading sections: Apollo's General Posts rows that
/// shape the feed (default sort, infinite scrolling, Default Reddit to
/// Load) and Reborn's Feed rows (video scrubber, forward-swipe memory),
/// with Phoebus's Resume Where I Left Off.
struct FeedBehaviourSections: View {
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(ResumeSettings.self) private var resume
    @Setting(FeedVideoScrubberStore.storage) private var scrubber
    /// Top or Controversial just picked: Apollo follows up with "Sort by
    /// Top for…" / "Sort by Controversial for…".
    @State private var timeRangeSort: DefaultPostSort?
    @State private var showingDefaultRedditSheet = false
    @State private var choosingSubreddit = false
    @State private var subredditName = ""
    @State private var multireddits: [RedditMultireddit] = []
    @State private var showingMultiredditSheet = false
    @State private var defaultRedditMessage: String?

    private func setDefaultReddit(_ choice: DefaultRedditToLoadChoice?) {
        $settings.update {
            $0.rememberSubredditToLoad = choice == nil
            if let choice { $0.defaultRedditToLoad = choice.stored }
        }
    }

    private func chooseMultireddit() async {
        guard let repository = ActiveRedditRepository.provider(),
              let multis = try? await repository.fetchMultireddits() else {
            defaultRedditMessage = "You need to be signed in to set a specific multireddit from your account."
            return
        }
        guard !multis.isEmpty else {
            defaultRedditMessage = "You haven’t created any multireddits! Why not create one then come back and set it?"
            return
        }
        multireddits = multis
        showingMultiredditSheet = true
    }

    var body: some View {
        Group {
            sortingSection
            loadingSection
        }
    }

    private var sortingSection: some View {
        Section {
            ApolloSettingsPicker("Default Sort", selection: Binding(
                                     get: { settings.defaultPostsSort },
                                     set: { sort in
                                         if sort.supportsTimeRange { timeRangeSort = sort }
                                         else { $settings.defaultPostsSort.wrappedValue = sort }
                                     }),
                                 options: DefaultPostSort.allCases.map { $0 },
                                 display: { sort in
                                     guard sort.supportsTimeRange, sort == settings.defaultPostsSort,
                                           let range = FeedScreen.timeframes.first(where: { $0.value == settings.defaultPostsTimeSort })
                                     else { return sort.displayName }
                                     return "\(sort.displayName) (\(range.label))"
                                 })
                .apolloSearchRow("Default Sort")
                .apolloActionSheet(isPresented: $timeRangeSort.isPresent(),
                                   title: "Sort by \(timeRangeSort?.displayName ?? "Top") for…",
                                   rows: FeedScreen.timeframes.map { option in
                                       ApolloActionSheetRow(option.label) {
                                           let sort = timeRangeSort ?? .top
                                           $settings.update {
                                               $0.defaultPostsSort = sort
                                               $0.defaultPostsTimeSort = option.value
                                           }
                                       }
                                   })
            Toggle("Remember Subreddit Sort", isOn: $settings.rememberPostsSortPerSubreddit)
                .apolloSearchRow("Remember Subreddit Sort", lastBeforeFooter: true)
        } header: {
            Text("Sorting")
                .apolloSectionHeader()
        }
    }

    private var loadingSection: some View {
        Section {
            Toggle("Infinite Scrolling", isOn: $settings.infiniteScrollingEnabled)
                .apolloSearchRow("Infinite Scrolling")
            // Stock "Default Reddit to Load…": a picker of the feeds, the
            // Subreddits list, Remember Subreddit, a subreddit or one of
            // your multireddits.
            Button { showingDefaultRedditSheet = true } label: {
                HStack {
                    Text("Default Reddit to Load")
                    Spacer()
                    Text(settings.rememberSubredditToLoad ? "Remember Subreddit"
                         : DefaultRedditToLoadChoice(stored: settings.defaultRedditToLoad).displayName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .apolloSearchRow("Default Reddit to Load")
            .apolloActionSheet(isPresented: $showingDefaultRedditSheet, title: "Default Reddit to Load…", rows: [
                ApolloActionSheetRow("Home") { setDefaultReddit(.home) },
                ApolloActionSheetRow("Popular Posts") { setDefaultReddit(.popular) },
                ApolloActionSheetRow("All Posts") { setDefaultReddit(.all) },
                ApolloActionSheetRow("Subreddits List") { setDefaultReddit(.redditsList) },
                ApolloActionSheetRow("Remember Subreddit") { setDefaultReddit(nil) },
                ApolloActionSheetRow("Subreddit…") { subredditName = ""; choosingSubreddit = true },
                ApolloActionSheetRow("Multireddit…") { Task { await chooseMultireddit() } },
            ])
            .apolloActionSheet(isPresented: $showingMultiredditSheet, title: "Multireddit", rows: multireddits.map { multi in
                ApolloActionSheetRow(multi.displayName) { setDefaultReddit(.multireddit(path: multi.path, name: multi.displayName)) }
            })
            .alert("Subreddit", isPresented: $choosingSubreddit) {
                TextField("Subreddit name", text: $subredditName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Set") {
                    let name = subredditName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { setDefaultReddit(.subreddit(name.hasPrefix("r/") ? String(name.dropFirst(2)) : name)) }
                }
            }
            .alert("Default Reddit to Load", isPresented: $defaultRedditMessage.isPresent()) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(defaultRedditMessage ?? "")
            }
            // Phoebus-only: a cold launch reopens the tab, feed and post you left.
            Toggle("Resume Where I Left Off", isOn: $resume.resumeWhereLeftOff)
                .accessibilityIdentifier("settings.general.resumeWhereLeftOff")
                .apolloSearchRow("Resume Where I Left Off")
                // Turning it off forgets the saved place.
                .onChange(of: resume.resumeWhereLeftOff) { _, on in
                    if !on { ResumeStore.clear() }
                }
            Toggle("No Subscribed in All/Popular", isOn: $settings.excludeSubscribedFromAllPopular)
                .apolloSearchRow("No Subscribed in All/Popular")
            Toggle("Feed Video Scrubber", isOn: $scrubber.isEnabled)
                .apolloSearchRow("Feed Video Scrubber")
            Toggle("Forget Forward Swipe After Scrolling", isOn: $settings.forwardSwipeForgetAfterScrolling)
                .apolloSearchRow("Forget Forward Swipe After Scrolling", lastBeforeFooter: true)
        } header: {
            Text("Loading")
                .apolloSectionHeader()
        } footer: {
            Text("Feed Video Scrubber: drag the bar under a feed video to scrub it.\n\nForget Forward Swipe After Scrolling: once you've scrolled a few posts on, a forward swipe won't reopen the post you came back from.")
                .apolloSectionFooter()
        }
    }
}
