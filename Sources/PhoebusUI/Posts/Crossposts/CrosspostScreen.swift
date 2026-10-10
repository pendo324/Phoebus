import SwiftUI
import PhoebusCore

/// Crosspost screen: re-posts an existing link/text post into a chosen
/// subreddit. A flat vertical stack: close button, title editor, options
/// (destination subreddit and flair rows), large full-width submit
/// button. Flair options come from `RedditRepository.fetchFlairOptions`,
/// as in `ComposePostScreen`. While the subreddit field is empty, recently
/// visited and Reddit-suggested destinations list below (Phoebus-only).
public struct CrosspostScreen: View {
    let post: RedditPost
    let repository: RedditRepository
    let onDone: () -> Void

    @State private var targetSubreddit = ""
    @State private var title: String
    @State private var flairOptions: [RedditFlairOption] = []
    @State private var selectedFlair: RedditFlairOption?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var suggestions = CrosspostSuggestions()
    @Setting(SubredditSectionsSettingsStore.storage) private var sectionsSettings
    @Environment(\.dismiss) private var dismiss

    public init(post: RedditPost, repository: RedditRepository, onDone: @escaping () -> Void) {
        self.post = post
        self.repository = repository
        self.onDone = onDone
        _title = State(initialValue: post.title)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    .accessibilityLabel("Close")
                }
                Spacer()
                Text("Crosspost")
                    .font(.headline)
                Spacer()
                // Balances the close button so the title stays centered.
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .opacity(0)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            // Title editor, separated from the options block below.
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            // Options: destination-subreddit row + flair row.
            VStack(spacing: 0) {
                HStack {
                    Text("Subreddit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("Choose a community", text: $targetSubreddit)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("crosspost.subreddit")
                        .onChange(of: targetSubreddit) { _, _ in
                            selectedFlair = nil
                            Task { await loadFlairs() }
                        }
                }
                .padding(.vertical, 10)

                Divider()

                // The flair row is always visible alongside the subreddit row.
                HStack {
                    Text("Flair")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if flairOptions.isEmpty {
                        Text("None available")
                            .foregroundStyle(.tertiary)
                    } else {
                        Picker("Flair", selection: $selectedFlair) {
                            Text("None").tag(RedditFlairOption?.none)
                            ForEach(flairOptions) { option in
                                Text(option.text).tag(RedditFlairOption?.some(option))
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(.vertical, 10)
            }
            .padding(.horizontal, 12)
            .background(Color.secondarySystemBackgroundIfAvailable)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if targetSubreddit.trimmingCharacters(in: .whitespaces).isEmpty, !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        suggestionSection("Recently Visited", names: suggestions.recentlyVisited,
                                          systemImage: "clock", area: "recent")
                        suggestionSection("Suggested", names: suggestions.suggested,
                                          systemImage: "arrow.triangle.branch", area: "suggested")
                    }
                }
                .accessibilityIdentifier("crosspost.suggestions")
            } else {
                Spacer()
            }

            // Large full-width submit button.
            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Crosspost")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(targetSubreddit.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
        }
        .padding(16)
        .task { await loadFlairs() }
        .task { await loadSuggestions() }
    }

    @ViewBuilder
    private func suggestionSection(_ header: String, names: [String], systemImage: String, area: String) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(header)
                    .textCase(.uppercase)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                VStack(spacing: 0) {
                    ForEach(Array(names.enumerated()), id: \.element) { index, name in
                        if index > 0 { Divider() }
                        Button {
                            targetSubreddit = name
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: systemImage)
                                    .foregroundStyle(Color.apolloAccent)
                                    .frame(width: 24)
                                Text("r/\(name)")
                                    .foregroundStyle(Color.primary)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("crosspost.suggestion.\(area).\(name)")
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.secondarySystemBackgroundIfAvailable)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// Recently visited subreddits show at once; Reddit's crosspostable list
    /// joins them when it arrives, and is simply absent if the fetch fails.
    private func loadSuggestions() async {
        let recent = sectionsSettings.showRecentlyVisited ? RecentlyVisitedStore.entries(kind: .subreddit) : []
        suggestions = CrosspostSuggestions.make(recentlyVisited: recent, crosspostable: [], source: post.subreddit)
        let crosspostable = await repository.fetchCrosspostableSubreddits(sourceSubreddit: post.subreddit)
        suggestions = CrosspostSuggestions.make(recentlyVisited: recent, crosspostable: crosspostable,
                                                source: post.subreddit)
    }

    private func loadFlairs() async {
        let sub = targetSubreddit.trimmingCharacters(in: .whitespaces)
        guard !sub.isEmpty else {
            flairOptions = []
            return
        }
        flairOptions = (try? await repository.fetchFlairOptions(subreddit: sub)) ?? []
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await repository.crosspost(
                originalFullname: post.name,
                toSubreddit: targetSubreddit,
                title: title,
                flairID: selectedFlair?.id
            )
            onDone()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
