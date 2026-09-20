import SwiftUI
import PhoebusCore

/// One subreddit's keyword and flair rules, laid out as Reborn's detail screen:
/// Keywords, Flairs, then "Remove This Subreddit", with Reborn's footers and add
/// prompts.
struct SubredditFilterDetailScreen: View {
    let subreddit: String
    @Binding var rules: PostFilterRules
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var adding: Kind?
    @State private var newValue = ""

    private enum Kind: Identifiable {
        case keyword, flair
        var id: Self { self }
    }

    var body: some View {
        List {
            Section {
                ForEach(current.keywords, id: \.self) {
                    Text($0).apolloPlainSettingsRowInsets()
                }
                .onDelete { offsets in
                    var r = current
                    r.keywords.remove(atOffsets: offsets)
                    write(r)
                }
                Button("Add Keyword...") { adding = .keyword }
                    .foregroundStyle(Color.apolloAccent)
                    .apolloPlainSettingsRowInsets(rule: false)
            } header: {
                Text("Keywords")
                    .apolloSectionHeader()
            } footer: {
                Text("Hide posts in r/\(subreddit) whose title or link contains any of these words (case-insensitive).")
                    .apolloSectionFooter()
            }

            Section {
                ForEach(current.flairs, id: \.self) {
                    Text($0).apolloPlainSettingsRowInsets()
                }
                .onDelete { offsets in
                    var r = current
                    r.flairs.remove(atOffsets: offsets)
                    write(r)
                }
                Button("Add Flair...") { adding = .flair }
                    .foregroundStyle(Color.apolloAccent)
                    .apolloPlainSettingsRowInsets(rule: false)
            } header: {
                Text("Flairs")
                    .apolloSectionHeader()
            } footer: {
                Text("Hide posts in r/\(subreddit) with any of these post flairs. Type the flair label exactly as it appears on posts (case-insensitive).")
                    .apolloSectionFooter()
            }

            Section {
                Button(role: .destructive) {
                    rules.subreddits[subreddit] = nil
                    onChange()
                    dismiss()
                } label: {
                    Text("Remove This Subreddit").frame(maxWidth: .infinity)
                }
                .foregroundStyle(.red)
                .apolloPlainSettingsRowInsets(rule: false)
            } footer: {
                Text("Stops filtering this subreddit and clears its keywords and flairs.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("r/\(subreddit)")
        .toolbar {
            if !(current.keywords.isEmpty && current.flairs.isEmpty) {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .alert(adding == .flair ? "Add Flair" : "Add Keyword", isPresented: $adding.isPresent()) {
            TextField(adding == .flair ? "Fanart" : "giveaway", text: $newValue)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { newValue = "" }
            Button("Add") { add() }
        } message: {
            Text(adding == .flair
                 ? "Posts in this subreddit with this flair label are hidden."
                 : "Posts in this subreddit whose title or link contains this word are hidden.")
        }
    }

    private var current: PostFilterRules.SubredditRules {
        rules.subreddits[subreddit] ?? PostFilterRules.SubredditRules()
    }

    private func write(_ value: PostFilterRules.SubredditRules) {
        rules.subreddits[subreddit] = value
        onChange()
    }

    /// Keywords are trimmed and lowercased; flairs are normalised as their chips are
    /// (`:emoji:` tokens dropped, whitespace collapsed), as Reborn does at entry.
    private func add() {
        let kind = adding
        let raw = newValue
        newValue = ""
        var r = current
        switch kind {
        case .keyword:
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty, !r.keywords.contains(value) else { return }
            r.keywords.append(value)
        case .flair:
            let value = PostFilterRules.normalizedFlair(raw)
            guard !value.isEmpty, !r.flairs.contains(value) else { return }
            r.flairs.append(value)
        case nil:
            return
        }
        write(r)
    }
}
