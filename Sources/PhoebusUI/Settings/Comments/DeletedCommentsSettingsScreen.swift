import SwiftUI
import PhoebusCore

/// Reborn's Deleted Comments sub-screen, pushed from Comments settings.
/// Recovers removed/deleted comment bodies.
public struct DeletedCommentsSettingsScreen: View {
    @Setting(DeletedCommentsSettingsStore.storage) private var settings
    /// One-time warning alert when switching into Always mode, which can
    /// slow comment loading.
    @State private var showsSlowdownWarning = false

    public init() {}

    public var body: some View {
        List {
            Section {
                // A `.navigationLink` `Picker` stands in for the push-to-choose
                // disclosure row ("Always Show ›").
                ApolloSettingsPicker("Show Deleted Comments", selection: $settings.mode,
                                 options: DeletedCommentsMode.allCases.map { $0 },
                                 display: { $0.title },
                                 showsChevron: true)
                    .apolloSearchRow("Show Deleted Comments")
                .accessibilityIdentifier("deletedComments.mode")

                // Only shown in Always mode.
                if settings.mode == .alwaysShow {
                    Toggle("Tap to Show Deleted Comments", isOn: $settings.tapToReveal)
                    .apolloSearchRow("Tap to Show Deleted Comments", lastBeforeFooter: true)
                        .accessibilityIdentifier("deletedComments.tapToReveal")
                }
            } footer: {
                Text("Always Show recovers removed and deleted comments in every thread. Tap to Show hides each recovered comment behind its removal reason until you tap it. This can slow down comment loading.\n\nPassive leaves deleted comments off until you turn them on for a single thread from the ⋯ menu in the comments view; they turn off again when you leave that thread. The ⋯ menu always includes a Show/Hide Deleted Comments shortcut.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Deleted Comments")
        .onChange(of: settings.mode) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if newValue == .alwaysShow {
                showsSlowdownWarning = true
            }
        }
        .onChange(of: settings.tapToReveal) { _, _ in
        }
        .alert("⚠️ WARNING", isPresented: $showsSlowdownWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This feature can slow down comment loading. If you notice comments loading slowly, turn this feature off.")
        }
    }
}
