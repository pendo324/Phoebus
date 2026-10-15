import SwiftUI
import PhoebusCore

/// A row that opens another category's screen at the row a setting depends
/// on, scrolled to it and flashed as a search result is. It is a link into a
/// category, not a second entrance to a screen, so it is not a drill-down.
struct SettingsCrossLinkRow: View {
    let link: SettingsCrossLink
    /// A grey summary before the disclosure chevron.
    var value: String? = nil
    let accountManager: AccountManager
    /// The last row of a section that has a footer draws no rule.
    var lastBeforeFooter = false

    var body: some View {
        SettingsLink {
            SettingsCategoryScreen(category: link.category, accountManager: accountManager)
                .environment(\.settingsSearchHighlightedRow, link.row)
        } label: {
            ValueRow(title: link.title, value: value ?? "")
        }
        .apolloPlainSettingsRowInsets(rule: !lastBeforeFooter)
        .accessibilityIdentifier("settings.\(link.rawValue)")
    }
}
