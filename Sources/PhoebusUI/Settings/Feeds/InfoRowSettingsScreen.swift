import SwiftUI
import PhoebusCore

/// Reborn's Info Row sub-screen. See `InfoRowSettings` for the keys.
public struct InfoRowSettingsScreen: View {
    @Setting(InfoRowSettingsStore.storage) private var settings
    /// Whether the translation marker is available, as Reborn derives it
    /// from the other translation settings. `TranslationSettings` has no
    /// separate title/details toggles (only `enableBulkTranslation` +
    /// `mode`), so the marker is available when bulk translation is on.
    private var translationMarkerAvailable: Bool {
        // Single shared definition so the row's availability and the
        // feed marker's availability can never drift apart.
        InfoRowSettings.translationAvailable
    }

    public init() {}

    public var body: some View {
        List {
            Section {
                Toggle("Magnify Info Row on Hold", isOn: $settings.magnifierOnHold)
                    .apolloSearchRow("Magnify Info Row on Hold", lastBeforeFooter: true)
                    .accessibilityIdentifier("infoRow.magnifier")
            } header: {
                Text("Magnifier")
                    .apolloSectionHeader()
            } footer: {
                Text("Press and hold a post's info row to zoom its icons in a glass card, then slide and release to activate one.")
                    .apolloSectionFooter()
            }

            Section {
                Toggle("Upvote", isOn: $settings.tapToUpvote)
                    .apolloSearchRow("Upvote")
                    .accessibilityIdentifier("infoRow.upvote")
                Toggle("Comments", isOn: $settings.tapToComments)
                    .apolloSearchRow("Comments")
                    .accessibilityIdentifier("infoRow.comments")

                Toggle("Popup", isOn: Binding(
                    get: { settings.popupMode && !settings.overlayMode },
                    set: { newValue in
                        $settings.update { $0.popupMode = newValue }
                        if newValue { $settings.update { $0.overlayMode = false } }
                    }
                ))
                    .apolloSearchRow("Popup")
                .disabled(settings.overlayMode)
                .accessibilityIdentifier("infoRow.popup")

                Toggle("Overlay", isOn: Binding(
                    get: { settings.overlayMode && !settings.popupMode },
                    set: { newValue in
                        $settings.update { $0.overlayMode = newValue }
                        if newValue { $settings.update { $0.popupMode = false } }
                    }
                ))
                    .apolloSearchRow("Overlay")
                .disabled(settings.popupMode)
                .accessibilityIdentifier("infoRow.overlay")

                // Shown off while there's no marker, as Reborn's.
                Toggle("Translation", isOn: Binding(
                    get: { translationMarkerAvailable && settings.tapToTranslation },
                    set: { $settings.tapToTranslation.wrappedValue = $0 }))
                    .apolloSearchRow("Translation", lastBeforeFooter: true)
                    .disabled(!translationMarkerAvailable)
                    .accessibilityIdentifier("infoRow.translation")
            } header: {
                Text("Tap Actions")
                    .apolloSectionHeader()
            } footer: {
                // Footer with a conditional trailing paragraph.
                Text(actionsFooter)
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Info Row")
    }

    private var actionsFooter: String {
        var footer = "Choose what the info-row icons do when tapped. Comments still opens the post when off; it just no longer jumps straight to the comments.\n\nPopup and Overlay control how % upvoted, timestamp and edited reveal their full details. Pick one style or neither.\n\nHold the score on one of your own comments for Reddit's author-only Comment Insights. Phoebus shows Reddit-reported upvotes and ratio, and calculates downvotes only when the ratio is reliable. This uses the Reddit web session shared by Chat and Polls."
        if translationMarkerAvailable {
            footer += "\n\nTranslation controls the 🌐 marker beside a post's stats. The Translate line under comment text remains controlled from Translation settings."
        } else {
            footer += "\n\nTranslation becomes available after enabling Tap to Translate or a Details toggle in Translation settings."
        }
        return footer
    }
}
