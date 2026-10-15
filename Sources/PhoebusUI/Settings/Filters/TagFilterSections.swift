import SwiftUI
import PhoebusCore

/// Reborn's Tag Filters, as two sections of Filters. "Tag Filters": Enable Tag
/// Filters, then NSFW and Spoiler greyed while the master switch is off;
/// "Per-Subreddit Overrides": one `r/name` row per override with its summary,
/// then "Add Subreddit…". Footers verbatim.
struct TagFilterSections: View {
    @Setting(TagFilterStore.storage) private var settings
    @State private var showingAdd = false
    @State private var newSubreddit = ""

    var body: some View {
        Group {
            Section {
                Toggle("Enable Tag Filters", isOn: $settings.enabled)
                    // search: item "Tag Filters"
                    .apolloSearchRow("Enable Tag Filters")
                Toggle("NSFW", isOn: $settings.nsfw)
                    .disabled(!settings.enabled)
                    .apolloSearchRow("NSFW")
                Toggle("Spoiler", isOn: $settings.spoiler)
                    .disabled(!settings.enabled)
                    .apolloSearchRow("Spoiler", lastBeforeFooter: true)
            } header: {
                Text("Tag Filters")
                    .apolloSectionHeader()
            } footer: {
                Text("Filtered posts are covered with a frosted blur over the post's title and thumbnail. Tap the blur to confirm and reveal the post. Brand Affiliate is unavailable because Phoebus does not store that tag.")
                    .apolloSectionFooter()
            }

            Section {
                ForEach(settings.subredditOverrides.keys.sorted(), id: \.self) { subreddit in
                    SettingsLink {
                        TagFilterSubredditOverrideScreen(subreddit: subreddit)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("r/\(subreddit)")
                            Text(settings.subredditOverrides[subreddit]?.summary ?? "(no overrides)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .apolloPlainSettingsRowInsets()
                }
                .onDelete { offsets in
                    let keys = settings.subredditOverrides.keys.sorted()
                    $settings.update { s in for i in offsets { s.subredditOverrides.removeValue(forKey: keys[i]) } }
                }
                Button("Add Subreddit…") { newSubreddit = ""; showingAdd = true }
                    .apolloSearchRow("Add Subreddit", lastBeforeFooter: true)
                    .alert("Add Subreddit", isPresented: $showingAdd) {
                        TextField("funny", text: $newSubreddit)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Cancel", role: .cancel) {}
                        Button("Add") {
                            var raw = newSubreddit.trimmingCharacters(in: .whitespacesAndNewlines)
                            if raw.lowercased().hasPrefix("r/") { raw.removeFirst(2) }
                            if raw.hasPrefix("/") { raw.removeFirst() }
                            guard !raw.isEmpty else { return }
                            $settings.update { $0.subredditOverrides[raw.lowercased()] = TagFilterSettings.Override() }
                        }
                    } message: {
                        Text("Enter the subreddit name (without r/).")
                    }
            } header: {
                Text("Per-Subreddit Overrides")
                    .apolloSectionHeader()
            } footer: {
                Text("Per-subreddit settings override the global defaults. Add a subreddit to customize behavior for it.")
                    .apolloSectionFooter()
            }
        }
    }
}

/// The pushed per-subreddit page: titled `r/name`, a "Filter" section with NSFW and Spoiler switches
/// showing the effective value, then "Reset to Global Defaults" and
/// "Remove Subreddit Override".
struct TagFilterSubredditOverrideScreen: View {
    let subreddit: String
    @Environment(\.dismiss) private var dismiss
    @Setting(TagFilterStore.storage) private var settings

    private var override: TagFilterSettings.Override {
        settings.subredditOverrides[subreddit] ?? TagFilterSettings.Override()
    }

    var body: some View {
        List {
            Section {
                Toggle("NSFW", isOn: Binding(
                    get: { override.nsfw ?? settings.nsfw },
                    set: { v in var o = override; o.nsfw = v; $settings.update { $0.subredditOverrides[subreddit] = o } }))
                    .apolloSearchRow("NSFW")
                Toggle("Spoiler", isOn: Binding(
                    get: { override.spoiler ?? settings.spoiler },
                    set: { v in var o = override; o.spoiler = v; $settings.update { $0.subredditOverrides[subreddit] = o } }))
                    .apolloSearchRow("Spoiler", lastBeforeFooter: true)
            } header: {
                Text("Filter")
                    .apolloSectionHeader()
            } footer: {
                Text("Per-subreddit settings override the global defaults. Toggles match what you'd set globally.")
                    .apolloSectionFooter()
            }
            Section {
                Button("Reset to Global Defaults") {
                    $settings.update { $0.subredditOverrides[subreddit] = TagFilterSettings.Override() }
                }
                .apolloSearchRow("Reset to Global Defaults")
                Button("Remove Subreddit Override", role: .destructive) {
                    $settings.update { _ = $0.subredditOverrides.removeValue(forKey: subreddit) }
                    dismiss()
                }
                .apolloSearchRow("Remove Subreddit Override", lastBeforeFooter: true)
            } footer: {
                Text("Reset clears overrides for this subreddit (it will follow global settings again).")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("r/\(subreddit)")
    }
}
