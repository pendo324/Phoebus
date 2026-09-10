import SwiftUI
import PhoebusCore

/// The active "Find in Comments" field, pinned under the nav bar.
///
/// Modelled on Reborn's Liquid Glass find, a `UISearchController` in the
/// navigation bar's palette:
///
/// - The field stays pinned under the title while a search is live, so
///   it never scrolls with the thread.
/// - The "n/m" count sits inside the field at its trailing end, before
///   the native clear button, in 15pt monospaced digits, secondary label
///   colour.
/// - The native clear (x) empties the query; with the field unfocused
///   that ends the search.
/// - The round-glass cancel beside the field ends the search.
/// - Return drops the keyboard and keeps the search up for stepping.
/// - The prev/next chevrons are not in the field: they replace the nav
///   bar's trailing action pill for the length of the search
///   (`FindInCommentsNavigator`, in `PostDetailScreen`'s toolbar).
public struct FindInCommentsBar: View {
    @Binding var query: String
    let matchCount: Int
    let currentIndex: Int
    let onClose: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme

    public init(query: Binding<String>, matchCount: Int, currentIndex: Int, onClose: @escaping () -> Void) {
        self._query = query
        self.matchCount = matchCount
        self.currentIndex = currentIndex
        self.onClose = onClose
    }

    /// Apollo's label format: "n/m", "0/0" for a query with no hits.
    /// Nothing shows for a query under two characters.
    private var countText: String? {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return nil }
        return matchCount == 0 ? "0/0" : "\(currentIndex + 1)/\(matchCount)"
    }

    private var fieldFill: Color {
        Color.apolloSearchFieldFill(colorScheme: colorScheme)
    }

    public var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find in Comments", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFocused)
                    // Return: keyboard down, search stays.
                    .onSubmit { isFocused = false }
                    .accessibilityIdentifier("findInComments.field")
                if let countText {
                    Text(countText)
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("findInComments.counter")
                }
                if !query.isEmpty {
                    Button {
                        query = ""
                        // Clear on an unfocused field ends the search;
                        // while typing it only empties the field.
                        if !isFocused { onClose() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear text")
                    .accessibilityIdentifier("findInComments.clear")
                }
            }
            .font(.system(size: 17))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Capsule().fill(fieldFill))

            // UIKit's iOS 26 search cancel: a round glass (x) beside
            // the field, not the word "Cancel".
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .apolloGlassBackground(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Find in Comments")
            .accessibilityIdentifier("findInComments.cancel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Palette band: the nav bar's own colour, so field and title
        // read as one bar (same token as SubredditsRootScreen's pinned
        // filter band).
        .background {
            if let bar = apolloTheme.color(.barBackground) {
                bar.ignoresSafeArea(edges: .horizontal)
            } else {
                Rectangle().fill(.bar)
            }
        }
        .onAppear { DispatchQueue.main.async { isFocused = true } }
    }
}

/// The ^ v match navigator that stands in for the nav bar's trailing
/// action pill while a search is live: two 34pt slots, 15pt semibold
/// `chevron.up` / `chevron.down`, accent tint, enabled only when there
/// is something to step through.
public struct FindInCommentsNavigator: View {
    let enabled: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    public init(enabled: Bool, onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.enabled = enabled
        self.onPrevious = onPrevious
        self.onNext = onNext
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 36)
            }
            .accessibilityLabel("Previous match")
            .accessibilityIdentifier("findInComments.previous")
            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 36)
            }
            .accessibilityLabel("Next match")
            .accessibilityIdentifier("findInComments.next")
        }
        .disabled(!enabled)
    }
}
