import SwiftUI
import PhoebusCore

/// The list of Post Rules: a switch per rule, tap to edit, swipe to delete.
struct PostRulesScreen: View {
    @Setting(PostRuleStore.storage) private var rules
    @State private var showingAdd = false

    var body: some View {
        List {
            Section {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    HStack {
                        SettingsLink {
                            PostRuleEditorScreen(ruleID: rule.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name.isEmpty ? "Rule \(index + 1)" : rule.name)
                                Text("\(rule.summary) · \(scopeSummary(rule))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("postRules.rule.\(index)")
                        Toggle("Enabled", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { on in $rules.update { list in
                                if let i = list.firstIndex(where: { $0.id == rule.id }) { list[i].isEnabled = on }
                            } }))
                            .labelsHidden()
                            .accessibilityIdentifier("postRules.rule.\(index).enabled")
                    }
                    .apolloPlainSettingsRowInsets()
                }
                .onDelete { offsets in $rules.update { $0.remove(atOffsets: offsets) } }
                Button("Add Rule…") { showingAdd = true }
                    .foregroundStyle(Color.apolloAccent)
                    .accessibilityIdentifier("postRules.add")
                    .apolloPlainSettingsRowInsets(rule: false)
            } footer: {
                Text("A post is hidden when it fails any condition of any rule that applies to the feed. Pinned posts and your own posts are never hidden. Applies on this device.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Post Rules")
        .accessibilityIdentifier("postRules.screen")
        .toolbar {
            if !rules.isEmpty {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                PostRuleEditorScreen(ruleID: nil, onFinish: { added in
                    if let added { $rules.update { $0.append(added) } }
                    showingAdd = false
                })
            }
        }
    }

    private func scopeSummary(_ rule: PostRule) -> String {
        rule.feeds.isEmpty ? "All feeds"
            : rule.feeds.compactMap { PostRuleFeed(token: $0)?.displayName }.joined(separator: ", ")
    }
}

/// Edits one Post Rule in place, or a new one as a draft until "Add".
struct PostRuleEditorScreen: View {
    /// Nil for a new rule.
    let ruleID: UUID?
    /// New rules only: the rule to add, or nil when cancelled.
    var onFinish: ((PostRule?) -> Void)?

    @Setting(PostRuleStore.storage) private var rules
    @State private var draft = PostRule()
    @State private var addingFeed: FeedKind?
    @State private var newFeedName = ""

    private enum FeedKind: Identifiable {
        case subreddit, multireddit
        var id: Self { self }
    }

    private var rule: Binding<PostRule> {
        guard let ruleID else { return $draft }
        return Binding(
            get: { rules.first { $0.id == ruleID } ?? PostRule(id: ruleID) },
            set: { new in $rules.update { list in
                if let i = list.firstIndex(where: { $0.id == ruleID }) { list[i] = new }
            } })
    }

    var body: some View {
        List {
            Section {
                TextField("Name (optional)", text: rule.name)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("postRuleEditor.name")
                    .apolloPlainSettingsRowInsets()
                Toggle("Enabled", isOn: rule.isEnabled)
                    .accessibilityIdentifier("postRuleEditor.enabled")
                    .apolloPlainSettingsRowInsets(rule: false)
            }

            Section {
                PostRuleBoundRow(title: "Minimum Score", id: "postRuleEditor.minScore",
                                 value: rule.minScore, allowsNegative: true)
                PostRuleBoundRow(title: "Maximum Score", id: "postRuleEditor.maxScore",
                                 value: rule.maxScore, allowsNegative: true)
                PostRuleBoundRow(title: "Minimum Comments", id: "postRuleEditor.minComments",
                                 value: rule.minComments)
                PostRuleBoundRow(title: "Maximum Comments", id: "postRuleEditor.maxComments",
                                 value: rule.maxComments)
                PostRuleBoundRow(title: "Minimum Awards", id: "postRuleEditor.minAwards",
                                 value: rule.minAwards)
                PostRuleBoundRow(title: "Maximum Awards", id: "postRuleEditor.maxAwards",
                                 value: rule.maxAwards, last: true)
            } header: {
                Text("Ranges")
                    .apolloSectionHeader()
            } footer: {
                Text(rule.wrappedValue.hasInvertedRange
                     ? "A minimum is above its maximum, so this rule hides every post."
                     : "Posts outside a range are hidden; both ends are included. Leave a field empty for no limit. Most posts report no awards now.")
                    .apolloSectionFooter()
            }

            Section {
                Toggle("NSFW Only", isOn: rule.onlyNSFW)
                    .accessibilityIdentifier("postRuleEditor.onlyNSFW")
                    .apolloPlainSettingsRowInsets()
                Toggle("Spoiler Only", isOn: rule.onlySpoiler)
                    .accessibilityIdentifier("postRuleEditor.onlySpoiler")
                    .apolloPlainSettingsRowInsets(rule: false)
            } header: {
                Text("Tags")
                    .apolloSectionHeader()
            } footer: {
                Text("Show only posts with these tags. With both on, a post with either is shown.")
                    .apolloSectionFooter()
            }

            titleSection

            scopeSection

            if ruleID != nil {
                Section {
                    PostRuleDeleteButton {
                        guard let ruleID else { return }
                        $rules.update { $0.removeAll { $0.id == ruleID } }
                    }
                }
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle(ruleID == nil ? "New Rule" : "Edit Rule")
        .accessibilityIdentifier("postRuleEditor.screen")
        .toolbar {
            if let onFinish {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(nil) }
                        .accessibilityIdentifier("postRuleEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onFinish(draft) }
                        .accessibilityIdentifier("postRuleEditor.save")
                }
            }
        }
        .alert(addingFeed == .multireddit ? "Add Multireddit" : "Add Subreddit",
               isPresented: $addingFeed.isPresent()) {
            TextField(addingFeed == .multireddit ? "multireddit name" : "subreddit", text: $newFeedName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("postRuleEditor.newFeedName")
            Button("Cancel", role: .cancel) { newFeedName = "" }
            Button("Add") { addFeed() }
        }
    }

    private var titleSection: some View {
        Section {
            regexField("Hide Titles Matching", text: rule.titleExcludesRegex, id: "postRuleEditor.titleExcludesRegex")
            regexField("Only Titles Matching", text: rule.titleRequiresRegex, id: "postRuleEditor.titleRequiresRegex")
        } header: {
            Text("Title")
                .apolloSectionHeader()
        } footer: {
            Text("Regular expressions, case-insensitive. An invalid pattern is ignored.")
                .apolloSectionFooter()
        }
    }

    private func regexField(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .accessibilityIdentifier(id)
            if !PostRule.isValidTitleRegex(text.wrappedValue) {
                Text("Invalid regular expression")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("\(id).invalid")
            }
        }
        .apolloPlainSettingsRowInsets()
    }

    private var scopeSection: some View {
        let feeds = rule.wrappedValue.feeds
        return Section {
            Toggle("All Feeds", isOn: Binding(
                get: { feeds.isEmpty },
                // Choosing feeds starts from Home; clearing the list returns to all.
                set: { all in rule.wrappedValue.feeds = all ? [] : [PostRuleFeed.home.token] }))
                .accessibilityIdentifier("postRuleEditor.allFeeds")
                .apolloPlainSettingsRowInsets()
            if !feeds.isEmpty {
                ForEach([PostRuleFeed.home, .popular, .all], id: \.self) { feed in
                    Toggle(feed.displayName, isOn: feedBinding(feed))
                        .accessibilityIdentifier("postRuleEditor.feed.\(feed.token)")
                        .apolloPlainSettingsRowInsets()
                }
                ForEach(feeds.filter { !["home", "popular", "all"].contains($0) }, id: \.self) { token in
                    Text(PostRuleFeed(token: token)?.displayName ?? token)
                        .accessibilityIdentifier("postRuleEditor.feed.\(token)")
                        .apolloPlainSettingsRowInsets()
                }
                .onDelete { offsets in
                    let custom = feeds.filter { !["home", "popular", "all"].contains($0) }
                    let removed = Set(offsets.map { custom[$0] })
                    rule.wrappedValue.feeds.removeAll { removed.contains($0) }
                }
                Button("Add Subreddit…") { addingFeed = .subreddit }
                    .foregroundStyle(Color.apolloAccent)
                    .accessibilityIdentifier("postRuleEditor.addSubreddit")
                    .apolloPlainSettingsRowInsets()
                Button("Add Multireddit…") { addingFeed = .multireddit }
                    .foregroundStyle(Color.apolloAccent)
                    .accessibilityIdentifier("postRuleEditor.addMultireddit")
                    .apolloPlainSettingsRowInsets(rule: false)
            }
        } header: {
            Text("Applies To")
                .apolloSectionHeader()
        } footer: {
            Text("A subreddit or multireddit rule applies while viewing that feed. With no feeds chosen, the rule applies everywhere.")
                .apolloSectionFooter()
        }
    }

    private func feedBinding(_ feed: PostRuleFeed) -> Binding<Bool> {
        Binding(
            get: { rule.wrappedValue.feeds.contains(feed.token) },
            set: { on in
                if on { if !rule.wrappedValue.feeds.contains(feed.token) { rule.wrappedValue.feeds.append(feed.token) } }
                else { rule.wrappedValue.feeds.removeAll { $0 == feed.token } }
            })
    }

    private func addFeed() {
        var name = newFeedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        newFeedName = ""
        let prefix = addingFeed == .multireddit ? "m/" : "r/"
        if name.hasPrefix(prefix) { name.removeFirst(2) }
        guard !name.isEmpty, let feed = PostRuleFeed(token: prefix + name),
              !rule.wrappedValue.feeds.contains(feed.token) else { return }
        rule.wrappedValue.feeds.append(feed.token)
    }
}

/// One optional bound: empty is no limit.
private struct PostRuleBoundRow: View {
    let title: String
    let id: String
    @Binding var value: Int?
    var allowsNegative = false
    var last = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Any", text: Binding(
                get: { value.map(String.init) ?? "" },
                set: { value = PostRule.parseBound($0, allowsNegative: allowsNegative) }))
                .keyboardType(allowsNegative ? .numbersAndPunctuation : .numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 120)
                .accessibilityIdentifier(id)
        }
        .apolloPlainSettingsRowInsets(rule: !last)
    }
}

/// "Delete Rule", a leaf so the editor doesn't read `dismiss` itself.
private struct PostRuleDeleteButton: View {
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(role: .destructive) {
            action()
            dismiss()
        } label: {
            Text("Delete Rule").frame(maxWidth: .infinity)
        }
        .foregroundStyle(.red)
        .accessibilityIdentifier("postRuleEditor.delete")
        .apolloPlainSettingsRowInsets(rule: false)
    }
}
