import SwiftUI
import PhoebusCore

/// Chooses which communities' posts and comments show on your profile
/// ("Show content and activity from..."). Hands the chosen set back; Edit
/// Profile stages it until Save.
struct ProfileVisibilityCommunitiesSheet: View {
    let communities: [ProfileActiveCommunity]
    let onDone: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var visible: Set<String>
    @State private var query = ""

    init(communities: [ProfileActiveCommunity], visible: Set<String>, onDone: @escaping (Set<String>) -> Void) {
        self.communities = communities
        self.onDone = onDone
        _visible = State(initialValue: visible)
    }

    private var matches: [ProfileActiveCommunity] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return communities }
        return communities.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var allVisible: Bool { visible.count == communities.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(matches) { community in
                        Button {
                            if visible.contains(community.id) {
                                visible.remove(community.id)
                            } else {
                                visible.insert(community.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                icon(community)
                                    .accessibilityHidden(true)
                                Text(community.title)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Image(systemName: visible.contains(community.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(visible.contains(community.id) ? Color.accentColor : Color.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .apolloPlainSettingsRowInsets()
                        .accessibilityAddTraits(visible.contains(community.id) ? .isSelected : [])
                        .accessibilityIdentifier("profileVisibility.community.\(community.id)")
                    }
                } header: {
                    HStack {
                        Text("\(visible.count) visible, \(communities.count - visible.count) hidden")
                        Spacer()
                        Button(allVisible ? "Deselect All" : "Select All") {
                            visible = allVisible ? [] : Set(communities.map(\.id))
                        }
                        .textCase(nil)
                        .accessibilityIdentifier("profileVisibility.selectAll")
                    }
                    .apolloSectionHeader()
                }
            }
            .apolloSettingsListAppearance()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationTitle("Show Activity From")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("profileVisibility.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(visible)
                        dismiss()
                    }
                    .accessibilityIdentifier("profileVisibility.done")
                }
            }
        }
    }

    private func icon(_ community: ProfileActiveCommunity) -> some View {
        Group {
            if let url = community.iconURL.flatMap({ URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) }) {
                CachedAsyncImage(url: url, contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }
}
