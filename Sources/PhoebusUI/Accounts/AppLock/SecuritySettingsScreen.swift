import SwiftUI
import PhoebusCore
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Apollo's Face ID / Touch ID & Passcode screen. Strings are verbatim and vary by
/// the device's biometry: "Require Passcode" / "Require Touch ID" is the row label,
/// "Lock with Passcode" / "Lock with Touch ID & Passcode" / "Lock with Face ID &
/// Passcode" the section header, and each biometry has its own footer sentence.
public struct SecuritySettingsScreen: View {
    @Setting(AppLockStore.storage) private var settings
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        List {
            Section {
                // The switch row is titled "Lock with Passcode" (or the Touch/Face ID variant),
                // not "Require …".
                Toggle(sectionHeader, isOn: Binding(
                    get: { settings.isEnabled },
                    set: { newValue in
                        if newValue {
                            enableLock()
                        } else {
                            $settings.isEnabled.wrappedValue = false
                        }
                    }
                ))
                .apolloSearchRow(sectionHeader)
                .accessibilityIdentifier("security.requireToggle")
                // Two rows, the second a "Require Passcode · Immediately" value row; no section
                // header. "Require Face ID" (by biometry) is enabled whether or not the lock is
                // on, as in Apollo.
                ApolloSettingsPicker(rowTitle, selection: Binding(
                    get: { settings.requireAfterSeconds },
                    set: { $settings.requireAfterSeconds.wrappedValue = $0 }),
                    options: AppLockSettings.requireAfterChoices.map { $0.seconds },
                    display: { v in AppLockSettings.requireAfterChoices.first { $0.seconds == v }?.title ?? "Immediately" })
                    .apolloSearchRow("Require Passcode", lastBeforeFooter: true)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(footerText)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    if let note = biometryEnrollmentNote {
                        Text(note)
                    }
                }
                .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        // The root row's title: "Face ID & Passcode" on a Face ID phone.
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        switch AppLockStore.biometry {
        case .none: return "Passcode"
        case .touchID: return "Touch ID & Passcode"
        case .faceID: return "Face ID & Passcode"
        }
    }

    /// Row title, chosen by available biometry.
    private var rowTitle: String {
        switch AppLockStore.biometry {
        case .none: return "Require Passcode"
        case .touchID: return "Require Touch ID"
        case .faceID: return "Require Face ID"
        }
    }

    /// Section header.
    private var sectionHeader: String {
        switch AppLockStore.biometry {
        case .none: return "Lock with Passcode"
        case .touchID: return "Lock with Touch ID & Passcode"
        case .faceID: return "Lock with Face ID & Passcode"
        }
    }

    /// Footer copy, verbatim per biometry.
    private var footerText: String {
        switch AppLockStore.biometry {
        case .none:
            return "If enabled Phoebus will be locked whenever you close the app, and you'll be prompted your device's passcode when relaunching."
        case .touchID:
            return "If enabled Phoebus will be locked whenever you close the app, and you'll be prompted with Touch ID or your device's passcode when relaunching."
        case .faceID:
            return "If enabled Phoebus will be locked whenever you close the app, and you'll be prompted with Face ID or your device's passcode when relaunching."
        }
    }

    /// "Not enrolled" notes, shown when the device supports a biometry that isn't set
    /// up.
    private var biometryEnrollmentNote: String? {
        guard AppLockStore.biometryNotEnrolled else { return nil }
        switch AppLockStore.hardwareBiometry {
        case .touchID:
            return "Note that Touch ID can be enabled for this feature as well, but you haven't added any fingers for this device. Go to the Settings app to do so."
        case .faceID:
            return "Note that Face ID can be enabled for this feature as well, but you haven't enrolled your face as an authentication method. Go to the Settings app to do so."
        case .none:
            return nil
        }
    }

    private func enableLock() {
        guard AppLockStore.deviceHasPasscode else {
            // Error copy.
            errorMessage = "Unable to enable passcode lock for Phoebus. Your device has no passcode set up, which is required. Go to this device's Settings to add one."
            return
        }
        errorMessage = nil
        $settings.isEnabled.wrappedValue = true
    }
}
