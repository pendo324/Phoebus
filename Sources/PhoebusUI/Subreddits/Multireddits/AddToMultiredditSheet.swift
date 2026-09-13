import SwiftUI
import PhoebusCore

/// Picks a multireddit to add r/<sub> to.
///
/// Reached from the subreddit "•••" menu's "Add to Multireddit" row, using
/// `addSubredditToMultireddit` (`PUT /api/multi/<multipath>/r/<srname>`).
public struct AddToMultiredditSheet: View {
    let subredditName: String
    let repository: RedditRepository
    let onDone: () -> Void

    @State private var multireddits: [RedditMultireddit] = []
    @State private var isLoading = true
    @State private var busyPath: String?
    @State private var errorMessage: String?
    /// Paths this sheet has successfully added to, so a second tap
    /// doesn't silently repeat the request.
    @State private var addedPaths: Set<String> = []

    public init(subredditName: String,
                repository: RedditRepository,
                onDone: @escaping () -> Void) {
        self.subredditName = subredditName
        self.repository = repository
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ApolloLoadingCell()
                } else if multireddits.isEmpty {
                    Text("You don't have any multireddits yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(multireddits) { multi in
                        Button {
                            Task { await add(to: multi) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(multi.displayName)
                                    Text("\(multi.subreddits.count) subreddits")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if busyPath == multi.path {
                                    ProgressView()
                                } else if addedPaths.contains(multi.path)
                                            || multi.subreddits.contains(where: {
                                                $0.name.caseInsensitiveCompare(subredditName) == .orderedSame
                                            }) {
                                    // Already a member: shown as state,
                                    // not hidden, so the user can see
                                    // WHY tapping does nothing.
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("addToMultireddit.row.\(multi.name)")
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Add to Multireddit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDone() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            multireddits = try await repository.fetchMultireddits()
        } catch {
            errorMessage = "Couldn't load your multireddits. \(error.localizedDescription)"
        }
    }

    private func add(to multi: RedditMultireddit) async {
        guard busyPath == nil, !addedPaths.contains(multi.path) else { return }
        busyPath = multi.path
        defer { busyPath = nil }
        do {
            try await repository.addSubredditToMultireddit(multiPath: multi.path,
                                                           subreddit: subredditName)
            addedPaths.insert(multi.path)
        } catch {
            errorMessage = "Couldn't add r/\(subredditName). \(error.localizedDescription)"
        }
    }
}
