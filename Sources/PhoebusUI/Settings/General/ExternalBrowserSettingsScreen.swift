import SwiftUI
import PhoebusCore

/// Apollo's "Open Links In" browser preference as a screen, for Open in
/// App's link to it. Settings draws the same section inside Links &
/// Sharing. See `ExternalBrowser` for the scheme-translation templates.
public struct ExternalBrowserSettingsScreen: View {
    public init() {}

    public var body: some View {
        List {
            ExternalBrowserSections()
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Open Links In")
    }
}

/// The installed browsers, one tap to choose, with a checkmark on the
/// current one.
struct ExternalBrowserSections: View {
    @Setting(ExternalBrowserSettingsStore.storage) private var settings

    var body: some View {
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
                .modifier(OpenLinksInSearchTarget(isFirst: browser == browsers.first))
            }
        } header: {
            Text("Open Links In")
                .apolloSectionHeader()
        } footer: {
            Text("Links open in the chosen browser, falling back to In-App Safari if it's been uninstalled.")
                .apolloSectionFooter()
        }
    }
}

/// The section's search target: its first row, so "Open Links In" scrolls
/// to and flashes the browser list.
private struct OpenLinksInSearchTarget: ViewModifier {
    let isFirst: Bool

    func body(content: Content) -> some View {
        if isFirst {
            content.modifier(SettingsSearchRowModifier(title: "Open Links In"))
        } else {
            content
        }
    }
}
