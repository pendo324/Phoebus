import SwiftUI
import PhoebusCore

/// Apollo's "Open Links In" browser preference. See `ExternalBrowser` for
/// the scheme-translation templates.
public struct ExternalBrowserSettingsScreen: View {
    @Setting(ExternalBrowserSettingsStore.storage) private var settings

    public init() {}

    public var body: some View {
        List {
            Section {
                // Installed browsers only, plus the current choice so a
                // restored one stays visible.
                let browsers = ExternalBrowser.allCases.filter { $0.isAvailable || $0 == settings.preferredBrowser }
                ForEach(browsers) { browser in
                    Button {
                        $settings.preferredBrowser.wrappedValue = browser
                    } label: {
                        HStack {
                            Text(browser.displayName).foregroundStyle(.primary)
                            Spacer()
                            if settings.preferredBrowser == browser {
                                Image(systemName: "checkmark").foregroundStyle(Color.apolloAccent)
                            }
                        }
                    }
                    // Section has a footer, so the last row has no rule.
                    .apolloPlainSettingsRowInsets(rule: browser != browsers.last)
                }
            } footer: {
                Text("Links open in the chosen browser, falling back to In-App Safari if it's been uninstalled.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Open Links In")
    }
}
