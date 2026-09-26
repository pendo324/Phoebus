import SwiftUI
import PhoebusCore

/// Reborn's Picture-in-Picture screen. Sections: In-App PiP, In-App PiP Controls,
/// System PiP (one footer), Global Options. Rows whose master switch is off stay
/// visible but grey out. "Hidden by Default" disappears when the position is Last
/// Position, and "Skip Amount" only appears while skip buttons are on.
public struct PictureInPictureSettingsScreen: View {
    @Setting(PictureInPictureSettingsStore.storage) private var settings
    @State private var showingPosition = false
    @State private var showingSkip = false
    @State private var showingActivation = false

    public init() {}

    private var anyEnabled: Bool { settings.inAppEnabled || settings.systemEnabled }

    public var body: some View {
        List {
            Section {
                switchRow("Enable In-App PiP",
                          description: "Video playback continues in miniplayer as you scroll through comments.",
                          isOn: $settings.inAppEnabled)
                valueRow("Default Position", value: settings.startPosition.title, enabled: settings.inAppEnabled) {
                    showingPosition = true
                }
                if settings.startPosition != .lastPosition {
                    switchRow("Hidden by Default",
                              description: "Miniplayer starts in hidden state against edge of screen.",
                              isOn: $settings.startHidden, enabled: settings.inAppEnabled)
                }
            } header: {
                Text("In-App PiP")
                    .apolloSectionHeader()
            }

            Section {
                switchRow("Show Skip Buttons", description: nil, isOn: $settings.skipButtons, enabled: settings.inAppEnabled)
                if settings.skipButtons {
                    valueRow("Skip Amount", value: "\(settings.skipSeconds) Seconds", enabled: settings.inAppEnabled) {
                        showingSkip = true
                    }
                }
                switchRow("Show Progress Bar", description: nil, isOn: $settings.progressBar, enabled: settings.inAppEnabled)
            } header: {
                Text("In-App PiP Controls")
                    .apolloSectionHeader()
            }

            Section {
                switchRow("Enable PiP When Leaving App",
                          description: "Video playback continues in system PiP window when leaving Phoebus.",
                          isOn: $settings.systemEnabled)
            } header: {
                Text("System PiP")
                    .apolloSectionHeader()
            } footer: {
                Text("This doesn't apply to fullscreen videos, which Phoebus already supports. In feeds, only unmuted videos can trigger it.")
                    .apolloSectionFooter()
            }

            Section {
                valueRow("Activate For", value: settings.activation.title, enabled: anyEnabled) {
                    showingActivation = true
                }
                switchRow("Loop Videos", description: nil, isOn: $settings.loopVideos, enabled: anyEnabled)
            } header: {
                Text("Global Options")
                    .apolloSectionHeader()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Picture-in-Picture")
        // Kept in step for backups.
        .onChange(of: settings) { _, newValue in
            GeneralSettingsStore.storage.update { $0.pipEnabled = newValue.systemEnabled || newValue.inAppEnabled }
        }
        // Five positions, "(Current)" suffix.
        .confirmationDialog("Default Position", isPresented: $showingPosition, titleVisibility: .visible) {
            ForEach(PictureInPictureSettings.StartPosition.allCases) { position in
                Button(position == settings.startPosition ? "\(position.title) (Current)" : position.title) {
                    $settings.startPosition.wrappedValue = position
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Skip Amount", isPresented: $showingSkip, titleVisibility: .visible) {
            ForEach(PictureInPictureSettings.skipChoices, id: \.self) { seconds in
                Button(seconds == settings.skipSeconds ? "\(seconds) Seconds (Current)" : "\(seconds) Seconds") {
                    $settings.skipSeconds.wrappedValue = seconds
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Activate For", isPresented: $showingActivation, titleVisibility: .visible) {
            ForEach(PictureInPictureSettings.Activation.allCases) { mode in
                Button(mode == settings.activation ? "\(mode.title) (Current)" : mode.title) {
                    $settings.activation.wrappedValue = mode
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func switchRow(_ title: String, description: String?, isOn: Binding<Bool>, enabled: Bool = true) -> some View {
        Group {
            if let description {
                SettingsDetailToggle(title, detail: description, isOn: isOn)
            } else {
                Toggle(title, isOn: isOn)
            }
        }
        .disabled(!enabled)
        .apolloSearchRow(title)
    }

    private func valueRow(_ title: String, value: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(enabled ? .primary : .secondary)
                Spacer()
                Text(value).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .disabled(!enabled)
        .apolloSearchRow(title)
    }
}
