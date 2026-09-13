import SwiftUI
import PhoebusCore

/// Add or remove individual subreddits of a multireddit. Uses Reddit's per-subreddit
/// endpoints (`PUT`/`DELETE /api/multi/<multipath>/r/<srname>`, see
/// `RedditRepository.addSubredditToMultireddit`/`removeSubredditFromMultireddit`)
/// rather than round-tripping the whole list through `updateMultireddit`.
public struct MultiredditSubredditsScreen: View {
    let multireddit: RedditMultireddit
    let repository: RedditRepository
    let onDone: () -> Void

    @State private var subreddits: [RedditMultireddit.SubredditRef]
    @State private var newSubredditName = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(multireddit: RedditMultireddit, repository: RedditRepository, onDone: @escaping () -> Void) {
        self.multireddit = multireddit
        self.repository = repository
        self.onDone = onDone
        _subreddits = State(initialValue: multireddit.subreddits)
    }

    public var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section("Add Subreddit") {
                HStack {
                    TextField("Subreddit name (without r/)", text: $newSubredditName)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                    Button {
                        Task { await add() }
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(isAdding || newSubredditName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Subreddits (\(subreddits.count))") {
                ForEach(subreddits, id: \.name) { subreddit in
                    Text("r/\(subreddit.name)")
                }
                .onDelete { indexSet in
                    Task { await remove(at: indexSet) }
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle(multireddit.displayName)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onDone()
                    dismiss()
                }
            }
        }
    }

    private func add() async {
        let name = newSubredditName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            try await repository.addSubredditToMultireddit(multiPath: multireddit.path, subreddit: name)
            subreddits.append(RedditMultireddit.SubredditRef(name: name))
            newSubredditName = ""
        } catch {
            errorMessage = "Couldn't add r/\(name): \(UserFacingError.text(for: error))"
        }
    }

    private func remove(at indexSet: IndexSet) async {
        for index in indexSet {
            let subreddit = subreddits[index]
            do {
                try await repository.removeSubredditFromMultireddit(multiPath: multireddit.path, subreddit: subreddit.name)
            } catch {
                errorMessage = "Couldn't remove r/\(subreddit.name): \(UserFacingError.text(for: error))"
                return
            }
        }
        subreddits.remove(atOffsets: indexSet)
    }
}
