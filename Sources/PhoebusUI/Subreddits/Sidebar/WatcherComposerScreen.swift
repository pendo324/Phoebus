import SwiftUI
import PhoebusCore

/// Stock Apollo's subreddit watcher composer: a subreddit, a
/// "Notification Name", and optional filters ("Narrow down matches by
/// adding filters"): Title Contains, Flair Contains, Link Contains,
/// Author Matches, and a minimum upvote count. Saved to the
/// self-hosted backend's watcher API, which matches each filter
/// exactly as the stock server did.
struct WatcherComposerScreen: View {
    @Setting(NotificationBackendSettings.self) private var notificationBackendSettings
    let redditID: String
    var initialSubreddit = ""
    var trending = false
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var subreddit = ""
    @State private var name = ""
    @State private var keyword = ""
    @State private var flair = ""
    @State private var domain = ""
    @State private var author = ""
    @State private var upvotes = ""
    @State private var saving = false
    @State private var alert: (title: String, message: String)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Subreddit", text: $subreddit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("watcher.subreddit")
                        .apolloPlainSettingsRowInsets()
                    if !trending {
                        TextField("Notification Name", text: $name)
                            .accessibilityIdentifier("watcher.name")
                            .apolloPlainSettingsRowInsets(rule: false)
                    }
                } footer: {
                    Text(trending
                         ? "Get a notification when a post in this subreddit is trending."
                         : "Be the first to know about a new post.")
                        .apolloSectionFooter()
                }
                if !trending {
                    Section {
                        TextField("Title Contains…", text: $keyword)
                            .accessibilityIdentifier("watcher.keyword")
                            .apolloPlainSettingsRowInsets()
                        TextField("Flair Contains…", text: $flair)
                            .apolloPlainSettingsRowInsets()
                        TextField("Link Contains…", text: $domain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .apolloPlainSettingsRowInsets()
                        TextField("Author Matches…", text: $author)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .apolloPlainSettingsRowInsets()
                        TextField("Upvotes at Least…", text: $upvotes)
                            .keyboardType(.numberPad)
                            .apolloPlainSettingsRowInsets(rule: false)
                    } header: {
                        Text("Filters").apolloSectionHeader()
                    } footer: {
                        // Verbatim stock copy.
                        Text("Narrow down matches by adding filters. Comma or spaces to separate words, will match if all are in title. Order of words and capitalization doesn’t matter.")
                            .apolloSectionFooter()
                    }
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle(trending ? "Watch Trending" : "Add Subreddit Watcher")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || subreddit.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("watcher.save")
                }
            }
            .alert(alert?.title ?? "", isPresented: $alert.isPresent()) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alert?.message ?? "")
            }
        }
        .onAppear { if subreddit.isEmpty { subreddit = initialSubreddit } }
    }

    /// Validation copy is stock Apollo's.
    private func save() async {
        let sub = subreddit.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "r/", with: "").replacingOccurrences(of: "/", with: "")
        guard !sub.isEmpty, sub.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            alert = ("Invalid Subreddit", "Unfortunately someone somewhere decided \(sub) isn’t a valid subreddit. Please try again with different entry.")
            return
        }
        var minUpvotes: Int64?
        let up = upvotes.trimmingCharacters(in: .whitespaces)
        if !up.isEmpty {
            guard let value = Int64(up) else { alert = ("Are you sure that’s a number?", ""); return }
            guard value > 0 else {
                alert = ("Must Greather Than Zero", "Fun fact: posts can’t go below 0 upvotes, only comments can, so every post has at least 0 upvotes! Try an amount above 0 if you want to match based on upvotes.")
                return
            }
            minUpvotes = value
        }
        saving = true
        defer { saving = false }
        let label = name.trimmingCharacters(in: .whitespaces).isEmpty ? sub : name
        let body = PushNotificationClient.watcherBody(
            type: trending ? "trending" : "subreddit", subreddit: sub, user: nil, label: label,
            keyword: keyword, upvotes: minUpvotes, flair: flair, domain: domain, author: author)
        do {
            try await PushNotificationClient.createWatcher(settings: notificationBackendSettings, redditID: redditID, body: body)
            onSaved()
            dismiss()
        } catch {
            alert = (trending ? "Error Adding Subreddit" : "Error Adding Watcher", error.localizedDescription)
        }
    }
}
