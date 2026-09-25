import SwiftUI
import PhoebusCore

/// Reddit poll voting: option list with radio-button selection and a
/// Vote button, then percentage bars once voted or ended.
struct PollView: View {
    @Setting(GeneralSettings.self) private var generalSettings
    private var alignsLeft: Bool { generalSettings.pollOptionAlignmentLeft }
    let post: RedditPost
    let poll: RedditPollData
    let repository: RedditRepository
    /// "Polls" off: Reborn falls back to Apollo's own read-only poll,
    /// whose vote opens the poll on Reddit's mobile site.
    var readOnly = false
    @State private var webVoteURL: URL?
    @State private var showingFirstPollAlert = false
    @AppStorage("HasViewedFirstPoll") private var hasViewedFirstPoll = false

    @State private var localSelection: String?
    @State private var isVoting = false
    @State private var errorMessage: String?
    /// The option awaiting a one-time cookie harvest, driving the
    /// sign-in sheet below.
    @State private var pendingHarvestOption: RedditPollOption?
    /// Authoritative poll data refetched after a vote is accepted, since
    /// Reddit withholds per-option counts until you've voted.
    @State private var refreshedPoll: RedditPollData?
    @Environment(\.accountManager) private var accountManager

    /// The authoritative poll once refetched, else the one we were
    /// handed (which has no counts before you vote).
    private var effectivePoll: RedditPollData {
        refreshedPoll ?? poll
    }

    private var effectiveSelection: String? {
        localSelection ?? effectivePoll.userSelection
    }

    /// Results are visible once you've voted OR the poll has ended, to
    /// avoid biasing later voters.
    private var showsResults: Bool {
        effectiveSelection != nil || effectivePoll.hasEnded
    }

    private var totalVotes: Int {
        // Add 1 locally once we've voted so percentages don't look
        // wrong before the server-side count catches up.
        effectivePoll.totalVoteCount
            + (localSelection != nil && effectivePoll.userSelection == nil ? 1 : 0)
    }

    var body: some View {
        content
            .apolloInAppBrowser(url: $webVoteURL)
            // Back from the web vote: show the results it unlocked.
            .onChange(of: webVoteURL) { _, url in
                if url == nil, readOnly { Task { await refreshAuthoritativePoll() } }
            }
            .alert("Voting in Polls", isPresented: $showingFirstPollAlert) {
                Button("OK") { hasViewedFirstPoll = true; openWebVote() }
            } message: {
                Text("Voting in polls (required to see the results) currently requires jumping to the Reddit mobile site, and Phoebus makes it easy. This first time you'll also need to log in.\n\n- Tap the “OK” button\n- Then tap “Log In” at the top\n- (After logging in it may redirect you to the homepage, if so just hit the back button two times)\n- Place your vote!\n\nWhen you hit “Done” and come back, Phoebus will update and show the results.")
            }
            .sheet(item: $pendingHarvestOption) { option in
                NavigationStack {
                    WebSessionLoginScreen(
                        requiredUsername: activeUsername,
                        onSuccess: { credential in
                            Task { await completeHarvest(credential) }
                        },
                        onCancel: {
                            // Cancelling the harvest must also cancel the
                            // optimistic selection.
                            pendingHarvestOption = nil
                            if localSelection == option.id { localSelection = nil }
                        }
                    )
                }
            }
    }

    /// The signed-in account the harvest must match, so a second Reddit
    /// login in the web view cannot be stored for the wrong user.
    private var activeUsername: String? {
        guard let accountManager, let index = accountManager.activeIndex,
              accountManager.accounts.indices.contains(index) else { return nil }
        return accountManager.accounts[index].username
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(effectivePoll.options) { option in
                optionRow(option)
            }

            HStack {
                if effectivePoll.hasEnded {
                    Text("Voting has ended")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let selection = effectiveSelection {
                    Text("You voted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(votingEndCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let _ = selection
                } else {
                    Text(votingEndCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("poll.error")
            }
        }
        .padding()
        .background(Color.secondarySystemBackgroundIfAvailable)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var votingEndCaption: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Ends " + formatter.localizedString(for: effectivePoll.votingEndDate, relativeTo: Date())
    }

    @ViewBuilder
    private func optionRow(_ option: RedditPollOption) -> some View {
        let isSelected = effectiveSelection == option.id
        let canVote = effectiveSelection == nil && !effectivePoll.hasEnded

        Button {
            guard canVote, !isVoting else { return }
            if readOnly {
                if hasViewedFirstPoll { openWebVote() } else { showingFirstPollAlert = true }
                return
            }
            Task { await vote(for: option) }
        } label: {
            ZStack(alignment: .leading) {
                if showsResults {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.apolloAccent.opacity(0.25) : Color.secondary.opacity(0.15))
                            .frame(width: geo.size.width * percentage(for: option))
                    }
                }
                HStack {
                    if canVote {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isSelected ? Color.apolloAccent : .secondary)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.apolloAccent)
                    }
                    // Center by default, Left as an option
                    // (`pollOptionAlignmentLeft`).
                    if !alignsLeft { Spacer(minLength: 0) }
                    Text(option.text)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(alignsLeft ? .leading : .center)
                    Spacer(minLength: 0)
                    if showsResults {
                        Text(percentageLabel(for: option))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .disabled(!canVote || isVoting)
        .accessibilityIdentifier("poll.option.\(option.id)")
    }

    /// Stock Apollo's `https://www.reddit.com/poll/<id>`.
    private func openWebVote() {
        webVoteURL = URL(string: "https://www.reddit.com/poll/\(post.id)")
    }

    private func percentage(for option: RedditPollOption) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(voteCount(for: option)) / Double(totalVotes)
    }

    /// Per-option count, preferring the authoritative refetch (the
    /// initial listing withholds `vote_count` until you've voted).
    private func voteCount(for option: RedditPollOption) -> Int {
        if let refreshed = refreshedPoll?.options.first(where: { $0.id == option.id }),
           let count = refreshed.voteCount {
            return count
        }
        return option.voteCount ?? (effectiveSelection == option.id ? 1 : 0)
    }

    /// Refetches the post so the poll carries real per-option counts:
    /// the vote mutation itself only returns { ok, errors }. Retries
    /// since the listing read is eventually consistent right after voting.
    private func refreshAuthoritativePoll() async {
        let postID = post.id
        let subreddit = post.subreddit
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(700))
            }
            guard let updated = try? await repository.fetchPost(subreddit: subreddit, postID: postID),
                  let pollData = updated.pollData else { continue }
            // Only accept a payload that actually carries counts.
            if pollData.options.contains(where: { $0.voteCount != nil }) {
                refreshedPoll = pollData
                return
            }
        }
    }

    private func percentageLabel(for option: RedditPollOption) -> String {
        "\(Int((percentage(for: option) * 100).rounded()))%"
    }

    private func vote(for option: RedditPollOption) async {
        isVoting = true
        errorMessage = nil
        defer { isVoting = false }
        do {
            try await repository.votePoll(postFullname: post.name, optionID: option.id)
            localSelection = option.id
            // Fetch the real result bars, since the mutation itself
            // returns only { ok, errors }.
            await refreshAuthoritativePoll()
        } catch PollVoteService.VoteError.requiresWebSession {
            // First vote on an OAuth account needs a one-time cookie
            // session harvest, since Reddit's poll mutation is a
            // Shreddit GraphQL call that only accepts cookie auth.
            pendingHarvestOption = option
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Retries the vote after a successful harvest, so sign-in is a
    /// one-time interruption.
    private func completeHarvest(_ credential: WebSessionCredential) async {
        guard let option = pendingHarvestOption else { return }
        pendingHarvestOption = nil
        accountManager?.addWebSessionAccount(credential)
        await vote(for: option)
    }
}
