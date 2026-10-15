import SwiftUI
import PhoebusCore

/// Mark Read / Hiding Posts: whether opening a post marks it read, and whether
/// read posts are hidden from feeds.
struct ReadPostsSections: View {
    @Setting(ReadPostStore.settingsStorage) private var settings
    @Setting(GeneralSettingsStore.storage) private var general
    /// Each guarded control presents its own alert, from its own row.
    @State private var autoHideAlert: HidingAlert?
    @State private var hidePostsAlert: HidingAlert?

    /// Apollo's guards on Auto Hide, verbatim.
    private enum HidingAlert: Identifiable {
        case mustBePermanent, signIn, autoHideEnabled
        var id: Self { self }
    }

    /// Auto Hide needs Permanent hiding and an account.
    private var autoHideBinding: Binding<Bool> {
        Binding(get: { settings.autoHideReadPosts }, set: { on in
            if on, !settings.hideReadPosts { autoHideAlert = .mustBePermanent; return }
            if on, FavoriteSubredditsAccountContext.currentUsernameProvider() == nil { autoHideAlert = .signIn; return }
            $settings.autoHideReadPosts.wrappedValue = on
        })
    }

    /// Temporarily can't be chosen while Auto Hide is on.
    private var hidePostsBinding: Binding<Bool> {
        Binding(get: { settings.hideReadPosts }, set: { permanent in
            if !permanent, settings.autoHideReadPosts { hidePostsAlert = .autoHideEnabled; return }
            $settings.hideReadPosts.wrappedValue = permanent
        })
    }

    var body: some View {
        // Settings → Feed → Read Posts: an untitled first section in Apollo, then
        // "Auto Hide" with its footer. No history-clearing row.
        Group {
            Section {
                Toggle("Disable Marking Posts Read", isOn: Binding(
                    get: { !settings.markReadOnOpen },
                    set: { $settings.markReadOnOpen.wrappedValue = !$0 }))
                    // search: item "Marking Read / Hiding"
                    .apolloSearchRow("Disable Marking Posts Read")
                Toggle("Mark Read on Scroll", isOn: $settings.markReadOnScroll)
                    .apolloSearchRow("Mark Read on Scroll")
                Toggle("Show Hide Read Button", isOn: $settings.showHideReadButton)
                    .apolloSearchRow("Show Hide Read Button")
                ApolloSettingsPicker("Hide Posts…", selection: hidePostsBinding,
                                     options: [true, false],
                                     display: { $0 ? "Permanently" : "Temporarily" })
                    .apolloSearchRow("Hide Posts")
                    .alert(item: $hidePostsAlert) { _ in
                        Alert(title: Text("Auto Hide Read Posts is Enabled"),
                              message: Text("Temporary doesn't work with Auto Hide Read Posts, which is enabled. This is because the read posts are hidden when the feed refreshes (otherwise they'd just be disappearing out from under you as you browse), and posts that are hidden temporarily don't stay hidden past the refresh."),
                              primaryButton: .default(Text("Disable Auto Hide")) {
                                  $settings.update { $0.autoHideReadPosts = false; $0.hideReadPosts = false }
                              },
                              secondaryButton: .cancel())
                    }
                Toggle("3D Touch Marks Read", isOn: $general.threeDTouchMarksRead)
                    .apolloSearchRow("3D Touch Marks Read")
            } header: {
                Text("Read Posts")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Auto Hide Read Posts", isOn: autoHideBinding)
                    .apolloSearchRow("Auto Hide Read Posts")
                    .alert(item: $autoHideAlert) { alert in
                        switch alert {
                        case .signIn:
                            return Alert(title: Text("Sign In to Auto Hide"),
                                         message: Text("In order for Auto Hide to work you need to be signed in as it connects the hiding to your Reddit account to prevent the posts from showing up."))
                        default:
                            return Alert(title: Text("Post Hiding Must be Permanent"),
                                         message: Text("In order to turn Auto Hide on, the “Hide Posts” setting must be set to “Permanently”. This is because the read posts are hidden when the feed refreshes (otherwise they'd just be disappearing out from under you as you browse), and posts that are hidden temporarily don't stay hidden past the refresh."))
                        }
                    }
                Toggle("Disable in Subreddits", isOn: $settings.disableAutoHideInSubreddits)
                    .apolloSearchRow("Disable in Subreddits", lastBeforeFooter: true)
            } header: {
                Text("Auto Hide")
                    .apolloSectionHeader()
            } footer: {
                Text("Auto Hide will automatically hide any read posts upon refresh of the feed so you won't need to do anything manually. Requires “Permanent” Hide setting. “Disable in Subreddits” prevents it from auto-hiding when you’re in a specific subreddit.")
                    .apolloSectionFooter()
            }
        }
    }
}
