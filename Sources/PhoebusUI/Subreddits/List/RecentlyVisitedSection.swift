import SwiftUI
import PhoebusCore

/// The Recently Visited list section, shared by the Subreddits list and the
/// Search tab's landing page. Phoebus-only (inspired by Continuum's history):
/// collapsed to the five newest with Show All, swipe to remove, and Clear.
struct RecentlyVisitedSection<Header: View, Row: View>: View {
    let entries: [RecentlyVisitedEntry]
    /// Prefix for accessibility identifiers ("subreddits" / "search").
    let area: String
    let onOpen: (RecentlyVisitedEntry) -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (RecentlyVisitedEntry) -> Row

    @State private var showsAll = false
    @State private var confirmingClear = false

    static var collapsedCount: Int { 5 }

    private var visible: [RecentlyVisitedEntry] {
        showsAll ? entries : Array(entries.prefix(Self.collapsedCount))
    }

    var body: some View {
        if !entries.isEmpty {
            Section {
                ForEach(visible) { entry in
                    Button { onOpen(entry) } label: { row(entry) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { RecentlyVisitedStore.remove(entry) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .accessibilityIdentifier("\(area).recentlyVisited.remove")
                        }
                        .accessibilityIdentifier("\(area).recentlyVisited.row.\(entry.title)")
                }
                HStack {
                    if entries.count > Self.collapsedCount {
                        Button(showsAll ? "Show Less" : "Show All (\(entries.count))") {
                            withAnimation { showsAll.toggle() }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("\(area).recentlyVisited.showAll")
                    }
                    Spacer(minLength: 0)
                    Button("Clear", role: .destructive) { confirmingClear = true }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("\(area).recentlyVisited.clear")
                }
                .font(.subheadline)
                .confirmationDialog("Clear Recently Visited?", isPresented: $confirmingClear, titleVisibility: .visible) {
                    Button("Clear", role: .destructive) {
                        withAnimation { RecentlyVisitedStore.clear() }
                    }
                    .accessibilityIdentifier("\(area).recentlyVisited.clearConfirm")
                    Button("Cancel", role: .cancel) {}
                }
            } header: {
                header()
            }
            .accessibilityIdentifier("\(area).recentlyVisited")
        }
    }
}

extension RecentlyVisitedEntry {
    /// "r/name", "u/name", or the multireddit's own name.
    var title: String {
        switch kind {
        case .subreddit: return "r/\(SubredditCapitalization.display(name))"
        case .user: return "u/\(name)"
        case .multireddit: return name
        }
    }

    var systemImage: String {
        switch kind {
        case .subreddit: return "number"
        case .user: return "person.crop.circle"
        case .multireddit: return "square.stack"
        }
    }

    /// Opens a profile entry the way a tapped u/ link does, on the current tab.
    func openProfile() {
        RedditLinkNavigator.open(.user(name))
    }
}
