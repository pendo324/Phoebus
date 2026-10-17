import SwiftUI
import PhoebusCore

/// The Filters tester: a pinned card on the Filters screen that runs a typed-in
/// post or comment through the same `FilterExplanation` the feed uses, so it
/// names the filter that would hide it, or says a Tag Filter only blurs it.
/// Phoebus-only; Apollo and Reborn have no such tester.
///
/// What the card holds is kept by the screen (`Entry`), never saved: the card is
/// drawn in two places (pinned above the list, or as its first row), so a
/// re-pin makes a new view that must find what was typed. The filter stores are
/// read through `@Setting`, so editing the filters below the card updates the
/// result line.
struct FilterTesterCard: View {
    enum Kind: String, CaseIterable, Identifiable {
        case post
        case comment

        var id: String { rawValue }
        var title: String { self == .post ? "Post" : "Comment" }
    }

    struct Entry: Equatable {
        var kind: Kind = .post
        var input = FilterTesterInput()
        var showingMore = false
    }

    @Binding var entry: Entry

    @Setting(ContentFilterStore.storage) private var contentFilters
    @Setting(PostFilterStore.storage) private var postFilters
    @Setting(PostRuleStore.storage) private var postRules
    @Setting(TagFilterStore.storage) private var tagFilters
    @Setting(CommentFilterStore.storage) private var commentFilters
    @Setting(BlockedUsersStore.storage) private var blockedStore
    @Setting(GeneralSettingsStore.storage) private var general

    @FocusState private var focused: String?

    private var kind: Kind { entry.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Kind", selection: $entry.kind) {
                ForEach(Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("filters.tester.kind")

            switch kind {
            case .post: postFields
            case .comment: commentFields
            }

            resultLine
        }
        .padding(12)
        .accessibilityIdentifier("filters.tester")
        // Number pads have no return key.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    // MARK: - Fields

    @ViewBuilder
    private var postFields: some View {
        inputRow("Title", text: $entry.input.title, identifier: "filters.tester.title")
        inputRow("Subreddit", text: $entry.input.subreddit, identifier: "filters.tester.subreddit")
        inputRow("Author", text: $entry.input.author, identifier: "filters.tester.author")
        inputRow("Link", text: $entry.input.link, identifier: "filters.tester.link")
        inputRow("Flair", text: $entry.input.flair, identifier: "filters.tester.flair")
        moreButton
        if entry.showingMore {
            HStack(alignment: .bottom, spacing: 8) {
                numberField("Score", value: $entry.input.score, allowsNegative: true,
                            identifier: "filters.tester.score")
                numberField("Comments", value: $entry.input.comments, allowsNegative: false,
                            identifier: "filters.tester.comments")
                numberField("Awards", value: $entry.input.awards, allowsNegative: false,
                            identifier: "filters.tester.awards")
            }
            HStack(spacing: 16) {
                toggleRow("NSFW", isOn: $entry.input.nsfw, identifier: "filters.tester.nsfw")
                toggleRow("Spoiler", isOn: $entry.input.spoiler, identifier: "filters.tester.spoiler")
            }
        }
    }

    @ViewBuilder
    private var commentFields: some View {
        inputRow("Text", text: $entry.input.commentText, identifier: "filters.tester.commentText")
        inputRow("Author", text: $entry.input.commentAuthor, identifier: "filters.tester.commentAuthor")
        inputRow("Subreddit", text: $entry.input.commentSubreddit, identifier: "filters.tester.commentSubreddit")
        HStack(spacing: 8) {
            Text("Score")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            NumberInput(title: "Score", value: $entry.input.commentScore, allowsNegative: true,
                        identifier: "filters.tester.commentScore", focused: $focused)
        }
        .fieldBackground()
    }

    /// Only this row opens the extra fields. (A `DisclosureGroup` in a list row
    /// also answered taps on the card's padding.)
    private var moreButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { entry.showingMore.toggle() }
        } label: {
            HStack {
                Text("More")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.apolloAccent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(entry.showingMore ? 90 : 0))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(entry.showingMore ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("filters.tester.more")
    }

    private func inputRow(_ title: String, text: Binding<String>, identifier: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            TextField("", text: text)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.done)
                .focused($focused, equals: identifier)
                .onSubmit { focused = nil }
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .fieldBackground()
    }

    /// A small numeric field with its label above it, so three fit in a row.
    private func numberField(_ title: String, value: Binding<Int?>, allowsNegative: Bool,
                             identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            NumberInput(title: title, value: value, allowsNegative: allowsNegative, identifier: identifier,
                        focused: $focused)
                .fieldBackground()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, identifier: String) -> some View {
        Toggle(title, isOn: isOn)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(identifier)
    }

    // MARK: - Result

    private enum Line {
        case prompt
        case post(PostFilterOutcome)
        case comment(CommentFilterOutcome)

        var description: String {
            switch self {
            case .prompt: return "Type something to test it against your filters."
            case .post(let outcome): return outcome.description
            case .comment(let outcome): return outcome.description
            }
        }

        var symbolName: String {
            switch self {
            case .prompt: return "info.circle"
            case .post(let outcome):
                switch outcome {
                case .shown, .shownUntested: return "eye"
                case .hidden: return "eye.slash"
                case .exempt: return "checkmark.shield"
                case .blurred: return "eye.trianglebadge.exclamationmark"
                }
            case .comment(let outcome):
                switch outcome {
                case .shown, .shownScoreUntested: return "eye"
                case .hidden: return "eye.slash"
                case .collapsed: return "rectangle.compress.vertical"
                }
            }
        }

        var tint: Color {
            switch self {
            case .prompt: return .secondary
            case .post(.shown), .post(.shownUntested), .post(.exempt),
                 .comment(.shown), .comment(.shownScoreUntested): return .green
            case .post(.blurred), .comment(.collapsed): return .orange
            case .post(.hidden), .comment(.hidden): return .red
            }
        }

        var isPlaceholder: Bool {
            if case .prompt = self { return true }
            return false
        }
    }

    private var line: Line {
        switch kind {
        case .post:
            guard entry.input.hasPostInput else { return .prompt }
            // Post Rules are scoped per feed; the tester stands in for the home
            // feed, which an unscoped rule applies to as well.
            return .post(FilterExplanation.explain(
                post: entry.input.post(), filters: contentFilters, postFilters: postFilters,
                postRules: postRules, tagFilters: tagFilters, feed: .home, username: username,
                untested: entry.input.untestedPostFields))
        case .comment:
            guard entry.input.hasCommentInput else { return .prompt }
            return .comment(FilterExplanation.explain(
                comment: entry.input.comment(), subreddit: entry.input.commentSubreddit, ownUsername: username,
                filters: commentFilters, blockedUsers: blockedNames,
                blockedUsersHide: general.hideBlockedUserComments,
                scoreTested: entry.input.commentScoreEntered))
        }
    }

    /// The active account, read through the same Core provider the blocked-users
    /// store uses, so the tester's exemptions match the feed's.
    private var username: String? {
        FavoriteSubredditsAccountContext.currentUsernameProvider()
    }

    private var blockedNames: Set<String> {
        _ = blockedStore
        return BlockedUsersStore.lowercasedNames()
    }

    private var resultLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: line.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(line.tint)
            Text(line.description)
                .font(.system(size: 13))
                .foregroundStyle(line.isPlaceholder ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.quaternarySystemFill)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.description)
        .accessibilityIdentifier("filters.tester.result")
    }
}

/// A number field that keeps what was typed ("-" on its way to "-5") and hands
/// the parsed value on; nothing parses as no bound, so a half-typed number
/// never tests the wrong range.
private struct NumberInput: View {
    let title: String
    @Binding var value: Int?
    let allowsNegative: Bool
    let identifier: String
    var focused: FocusState<String?>.Binding
    @State private var text: String

    init(title: String, value: Binding<Int?>, allowsNegative: Bool, identifier: String,
         focused: FocusState<String?>.Binding) {
        self.title = title
        _value = value
        self.allowsNegative = allowsNegative
        self.identifier = identifier
        self.focused = focused
        _text = State(initialValue: value.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        TextField("", text: $text)
            .font(.system(size: 15))
            #if canImport(UIKit)
            .keyboardType(allowsNegative ? .numbersAndPunctuation : .numberPad)
            #endif
            .focused(focused, equals: identifier)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
            .onChange(of: text) { _, new in
                value = PostRule.parseBound(new, allowsNegative: allowsNegative)
            }
            // The entry was cleared from outside.
            .onChange(of: value) { _, new in
                if PostRule.parseBound(text, allowsNegative: allowsNegative) != new { text = new.map(String.init) ?? "" }
            }
    }
}

private extension View {
    func fieldBackground() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
    }
}
