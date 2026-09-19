import SwiftUI
import PhoebusCore

/// Apollo's "Comments Theme" picker (Theme Manager > Options): one
/// section listing Rainbow, Combustion, Ocean, Forest, Nuit and Blep,
/// each with its seven colours as dots and a checkmark on the chosen
/// one. The palette is independent of the app theme; Rainbow is the
/// default.
///
/// A generated or imported theme carries its own colours, so while one
/// is active a "Theme's Own Colours" row leads the list (a Phoebus
/// addition; built-in themes have no palette of their own).
public struct CommentsThemeSettingsScreen: View {
    @State private var selection: String?
    private let theme: Theme

    public init() {
        _selection = State(initialValue: CommentsThemeStore.overridePaletteName)
        theme = ThemeStore.load()
    }

    private var themeHasOwnColours: Bool {
        theme.commentPaletteName == nil && !theme.commentDepthColorHexes.isEmpty
    }

    /// The row showing a checkmark: the override, else what the theme
    /// resolves to.
    private var checked: String? {
        if let selection { return selection }
        return themeHasOwnColours ? nil : CommentsThemeStore.effectivePaletteName(theme: theme)
    }

    public var body: some View {
        List {
            Section {
                if themeHasOwnColours {
                    row(title: "Theme's Own Colours", paletteName: nil, isChecked: checked == nil)
                        .apolloPlainSettingsRowInsets()
                }
                let names = CommentColorPalette.names
                ForEach(names, id: \.self) { name in
                    row(title: name, paletteName: name, isChecked: checked == name)
                        .apolloPlainSettingsRowInsets(rule: name != names.last)
                }
            } header: {
                Text("Comments Theme")
                    .apolloSectionHeader()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Comments Theme")
        .navigationBarTitleDisplayModeIfAvailable()
    }

    private func row(title: String, paletteName: String?, isChecked: Bool) -> some View {
        Button {
            selection = paletteName
            CommentsThemeStore.overridePaletteName = paletteName
        } label: {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 8)
                dots(for: paletteName)
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.apolloAccent)
                    .opacity(isChecked ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("commentsTheme.\(paletteName ?? "themeOwn")")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private func dots(for paletteName: String?) -> some View {
        let hexes = paletteName.map { CommentColorPalette.hexes(named: $0, isDark: theme.isDark) }
            ?? theme.commentDepthColorHexes
        return HStack(spacing: 5) {
            ForEach(Array(hexes.prefix(7).enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 11, height: 11)
            }
        }
        .accessibilityHidden(true)
    }
}
