import SwiftUI
import PhoebusCore
// MARK: - Row highlighting

private struct SettingsSearchHighlightedRowKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Title of the row a search result asked to be highlighted, if any.
    var settingsSearchHighlightedRow: String? {
        get { self[SettingsSearchHighlightedRowKey.self] }
        set { self[SettingsSearchHighlightedRowKey.self] = newValue }
    }
}
