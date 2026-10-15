import SwiftUI
import PhoebusCore

/// Integrations: what Phoebus plugs into. Reborn's Siri & Spotlight (iOS 27
/// and later) and Apollo's home-screen widget are sections; translation,
/// Phoebus AI and the Settings tab's shortcut menu are drill-downs, each a
/// feature of its own with too many settings to sit inline.
public struct IntegrationsSettingsScreen: View {
    public init() {}

    public var body: some View {
        List {
            if #available(iOS 27.0, *) {
                SiriSpotlightSections()
            }
            WidgetSetupSections()
            Section {
                SettingsDrillDownRow(destination: .translation)
                SettingsDrillDownRow(destination: .apolloAI, lastBeforeFooter: true)
            } header: {
                Text("Translation & AI")
                    .apolloSectionHeader()
            }
            Section {
                SettingsDrillDownRow(destination: .settingsShortcuts, lastBeforeFooter: true)
            } header: {
                Text("Settings Tab")
                    .apolloSectionHeader()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.integrations.title)
        .navigationBarTitleDisplayModeIfAvailable()
    }
}
