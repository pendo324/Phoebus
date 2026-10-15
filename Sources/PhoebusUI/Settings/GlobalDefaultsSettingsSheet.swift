import SwiftUI
import PhoebusCore

/// "Edit Global Defaults" for "Separate Settings per Account": the whole
/// Settings tree on the global layer, under a banner saying so. Settings
/// are shared app-wide, so while this is open the app reads the globals.
struct GlobalDefaultsSettingsSheet: View {
    let accountManager: AccountManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Editing Global Defaults", systemImage: "globe")
                        .font(.subheadline.weight(.semibold))
                    Text("Used by every account that hasn't changed a setting itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.globalDefaults.banner")
                Spacer(minLength: 0)
                // In the banner rather than the toolbar, so it is there on every pushed screen.
                Button("Done") { isPresented = false }
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("settings.globalDefaults.done")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.apolloAccent.opacity(0.15))
            NavigationStack {
                SettingsScreen(repository: accountManager.repository, accountManager: accountManager)
            }
            // A sheet inherits the Settings tab's path model, which would push
            // these rows onto the tab behind the sheet; plain links push here.
            .environment(\.settingsNavigation, nil)
            // Editing the shared layer is not the place to end the session.
            .environment(\.settingsSignOut, nil)
        }
        .accessibilityIdentifier("settings.globalDefaults")
        .onAppear { AccountSettingsScope.setEditingGlobalDefaults(true) }
        .onDisappear { AccountSettingsScope.setEditingGlobalDefaults(false) }
    }
}
