import SwiftUI
import PhoebusCore

/// Smart Rotation Lock: a single toggle that keeps the app in portrait regardless
/// of the device's rotation setting.
public struct PortraitLockSettingsScreen: View {
    @Setting(PortraitLockStore.storage) private var settings

    public init() {}

    public var body: some View {
        List {
            Section {
                Toggle("Smart Rotation Lock", isOn: Binding(
                    get: { settings.isEnabled },
                    set: {
                        $settings.isEnabled.wrappedValue = $0
                    }
                ))
                    .apolloSearchRow("Smart Rotation Lock", lastBeforeFooter: true)
                .accessibilityIdentifier("portraitLock.toggle")
            } footer: {
                // Verbatim from Apollo's Settings → General → Smart Rotation Lock.
                Text("Locks Phoebus to portrait (vertical) orientation except for Media Viewer.")
                    .apolloSectionFooter()
            }
            Section {
                Toggle("Portrait Lock Buddy", isOn: Binding(
                    get: { settings.portraitLockBuddy },
                    set: {
                        $settings.portraitLockBuddy.wrappedValue = $0
                    }
                ))
                    .apolloSearchRow("Portrait Lock Buddy", lastBeforeFooter: true)
                .accessibilityIdentifier("portraitLock.buddyToggle")
            } footer: {
                Text("If using the iOS Portrait Orientation Lock feature, Phoebus will attempt to detect device rotations in Media Viewer and offer to let you rotate media.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Portrait Lock")
    }
}
