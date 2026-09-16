import SwiftUI
import PhoebusCore

/// Apollo's "Jump Bar": leading "‹ Back", a centered highlighted text
/// field, trailing "Cancel" in the nav bar, with a dropdown results
/// list below it. This type renders only the nav-bar field;
/// `JumpBarResultsList` renders the results as a screen-level overlay,
/// since a results list can't grow past a toolbar item's bounds.
public struct JumpBarField: View {
    let repository: RedditRepository
    @Binding var isActive: Bool
    @Binding var text: String
    let onSubmit: (String) -> Void

    @State private var fieldFocused = false

    public init(repository: RedditRepository, isActive: Binding<Bool>, text: Binding<String>, onSubmit: @escaping (String) -> Void) {
        self.repository = repository
        self._isActive = isActive
        self._text = text
        self.onSubmit = onSubmit
    }

    public var body: some View {
        // Glass back circle (leading, in FeedScreen's toolbar), the text field
        // alone in the principal slot with placeholder "Subreddit…", glass ✕
        // circle trailing.
        //
        // UIKit field (`GlassSearchTextField`): a SwiftUI `TextField` inside a
        // toolbar's principal item does not take focus.
        GlassSearchTextField(
            text: $text,
            placeholder: "Subreddit…",
            isFocused: $fieldFocused,
            onSubmit: { submit(text) },
            textAlignment: .center,
            font: .systemFont(ofSize: 17)
        )
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .accessibilityIdentifier("jumpBar.textField")
            .task {
                try? await Task.sleep(nanoseconds: 80_000_000)
                fieldFocused = true
            }
            .onChange(of: isActive) { _, active in
                if !active { fieldFocused = false }
            }
    }

    private func submit(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed.replacingOccurrences(of: "r/", with: "", options: [.caseInsensitive]))
        isActive = false
    }
}

/// The Jump Bar's live results dropdown, rendered as a screen-level
/// overlay docked below the nav bar rather than inside the toolbar
/// item, since SwiftUI toolbar items can't grow a scrollable list past
/// their own bounds. Multi-row, each bolding the matched prefix.
public struct JumpBarResultsList: View {
    let repository: RedditRepository
    let query: String
    let onSelect: (String) -> Void

    @State private var suggestions: [String] = []
    @State private var lastError: String?

    public init(repository: RedditRepository, query: String, onSelect: @escaping (String) -> Void) {
        self.repository = repository
        self.query = query
        self.onSelect = onSelect
    }

    public var body: some View {
        // A `Group` whose only conditional child is currently `false` does
        // not reliably attach `.task`/`.onAppear`; they sit on an
        // always-present `Color.clear` base layer instead.
        ZStack(alignment: .top) {
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: query) {
                    await loadSuggestions(for: query)
                }
            if let lastError, suggestions.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.background)
                    .accessibilityIdentifier("jumpBar.error")
            }
            if !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { name in
                            Button {
                                onSelect(name)
                            } label: {
                                // Rows use a larger font matching the
                                // jump bar's own field text, with
                                // generous vertical padding.
                                boldedPrefixText(name)
                                    .font(.title3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 16)
                                    // `frame(maxWidth:)` widens the
                                    // layout frame but a `Text` only
                                    // hit-tests where its glyphs draw.
                                    .apolloFullRowTapTarget()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("jumpBar.suggestion.\(name)")
                            Divider()
                        }
                    }
                }
                .background(.background)
                // An opaque table filling the width under the nav bar.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Renders `name` bolding the matched substring (not only a
    /// strict prefix), with the remainder in a lighter secondary weight.
    private func boldedPrefixText(_ name: String) -> Text {
        guard !query.isEmpty,
              let range = name.range(of: query, options: [.caseInsensitive]) else {
            return Text(name)
        }
        let before = String(name[name.startIndex..<range.lowerBound])
        let match = String(name[range])
        let after = String(name[range.upperBound...])
        return Text(before).foregroundStyle(.secondary)
            + Text(match).fontWeight(.semibold)
            + Text(after).foregroundStyle(.secondary)
    }

    /// Minimum query length before hitting the network: a 1-2
    /// character prefix matches an enormous slice of Reddit.
    private static let minimumQueryLength = 3

    /// Keystroke debounce. `.task(id:)` cancels the previous task on
    /// every change, so only the last keystroke in a burst issues a request.
    private static let debounceInterval = Duration.milliseconds(300)

    private func loadSuggestions(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= Self.minimumQueryLength else {
            // Clear stale results AND any stale error, so a too-short
            // query shows nothing rather than the previous failure.
            suggestions = []
            lastError = nil
            return
        }
        // Cancelled by `.task(id:)` when another keystroke arrives.
        do {
            try await Task.sleep(for: Self.debounceInterval)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        do {
            let data = try await repository.autocompleteSubreddits(query: trimmed, limit: 8)
            let listing = try await RedditListing.decodedInBackground(from: data)
            let names = await listing.childrenInBackground(RedditSubreddit.self).map(\.displayName)
            guard !Task.isCancelled else { return }
            // Reddit's autocomplete endpoint already returns
            // name-prefix matches in ranked order, so this preserves it.
            let rules = PostFilterStore.load()
            suggestions = names.filter { !rules.hidesSubredditName($0) }
        } catch {
            // Surface the failure instead of swallowing it, but a
            // cancelled request is the normal debounce path, not a failure.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            lastError = UserFacingError.message(for: error)
            // Best-effort: a failed suggestion fetch shouldn't block
            // typing/submitting a name; the next keystroke retries.
        }
    }
}
