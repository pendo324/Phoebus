import SwiftUI
import PhoebusCore

/// Reborn's theme editor in SwiftUI: name, Light/Dark, the five colours, Advanced
/// overrides, font, generating the other mode, a live preview, Share, Apply and
/// Delete. Changes save as they are made, and the app repaints while the theme is active.
public struct ThemeEditorScreen: View {
    let themeID: String
    @State private var theme: CustomTheme?
    @State private var mode: ThemeMode
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var shareFile: URL?
    @State private var showingShareChoices = false
    @State private var sharingCard: Theme?
    @Environment(\.dismiss) private var dismiss

    public init(themeID: String, mode: ThemeMode? = nil) {
        self.themeID = themeID
        _theme = State(initialValue: CustomThemeStore.theme(id: themeID))
        _mode = State(initialValue: mode ?? (ThemeStore.load().isDark ? .dark : .light))
    }

    public var body: some View {
        Group {
            if let theme {
                editor(theme)
            } else {
                ContentUnavailableView("Theme Deleted", systemImage: "paintpalette")
            }
        }
        .navigationTitle(theme?.name ?? "Theme")
    }

    private func editor(_ theme: CustomTheme) -> some View {
        let compiled = theme.compiled()
        return List {
            Section {
                Button {
                    newName = theme.name
                    renaming = true
                } label: {
                    HStack {
                        Text("Name").foregroundStyle(Color.primary)
                        Spacer()
                        Text(theme.name).foregroundStyle(.secondary)
                        ApolloSettingsChevron()
                    }
                }
                .apolloPlainSettingsRowInsets(rule: false)
            }

            Section {
                // Appearance only: Reborn's subtle/balanced/bold variant is an
                // AI-generation setting, not edited here.
                HStack {
                    Text("Appearance")
                    Spacer()
                    Picker("Appearance", selection: $mode) {
                        Text("Light").tag(ThemeMode.light)
                        Text("Dark").tag(ThemeMode.dark)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }
                .apolloPlainSettingsRowInsets(rule: false)
            }

            Section {
                ForEach(ThemeInputKey.defaultKeys, id: \.self) { key in
                    colorRow(key, theme: theme, compiled: compiled)
                }
            } header: {
                Text("Colours").apolloSectionHeader()
            }

            Section {
                Toggle(isOn: binding(\.advancedOptionsEnabled)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced options")
                        Text("Text and separator overrides").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .apolloPlainSettingsRowInsets()
                if theme.advancedOptionsEnabled {
                    ForEach(ThemeInputKey.advancedKeys, id: \.self) { key in
                        colorRow(key, theme: theme, compiled: compiled)
                    }
                }
                Toggle(isOn: binding(\.voteArrowsAccent)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Colourize Vote Arrows")
                        Text("Idle arrows use the accent colour. A cast vote still shows Phoebus's green/blue.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .apolloPlainSettingsRowInsets(rule: false)
            } header: {
                Text("Advanced (optional)").apolloSectionHeader()
            } footer: {
                Text("Turn on advanced options to override text and separator colours.").apolloSectionFooter()
            }

            Section {
                ThemeFontGrid(selection: binding(\.font), compiled: compiled, mode: mode)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } header: {
                Text("Font").apolloSectionHeader()
            } footer: {
                Text("Used across the app while this theme is active. Applies immediately.").apolloSectionFooter()
            }

            Section {
                let other: ThemeMode = mode == .light ? .dark : .light
                Button {
                    update { $0.generate(other, from: mode) }
                    Haptics.medium()
                } label: {
                    Label("Generate \(other.rawValue) from \(mode.rawValue)", systemImage: "wand.and.stars")
                        .foregroundStyle(Color.apolloAccent)
                }
                .apolloPlainSettingsRowInsets(rule: false)
            }

            Section {
                ThemePreviewRows(compiled: compiled, mode: mode)
            } header: {
                Text("Preview").apolloSectionHeader()
            }

            Section {
                Button { showingShareChoices = true } label: {
                    Label("Share…", systemImage: "square.and.arrow.up").foregroundStyle(Color.apolloAccent)
                }
                .apolloPlainSettingsRowInsets(rule: false)
            } footer: {
                Text("Share as an image (a picture of this theme with a QR code anyone can import) or as a theme file.")
                    .apolloSectionFooter()
            }

            Section {
                Button {
                    ThemeStore.save(theme.asTheme(mode: mode))
                    dismiss()
                } label: {
                    Text("Apply Theme").frame(maxWidth: .infinity).foregroundStyle(Color.apolloAccent)
                }
                .apolloPlainSettingsRowInsets(rule: false)
            } footer: {
                Text("Applying selects this theme and enables custom theming.").apolloSectionFooter()
            }

            Section {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete Theme").frame(maxWidth: .infinity).foregroundStyle(.red)
                }
                .apolloPlainSettingsRowInsets(rule: false)
            }
        }
        .apolloSettingsListAppearance()
        .alert("Rename Theme", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { update { $0.name = CustomTheme(name: newName).name } }
        }
        .alert("Delete \"\(theme.name)\"?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("This can't be undone.")
        }
        .apolloActionSheet(isPresented: $showingShareChoices, title: "Share Theme", rows: [
            ApolloActionSheetRow("Share as Image…") { sharingCard = theme.asTheme(mode: mode) },
            ApolloActionSheetRow("Share Theme File…") { shareFile = writeExport(theme) },
        ])
        #if canImport(UIKit)
        .sheet(isPresented: $shareFile.isPresent()) {
            if let shareFile { ActivityShareSheet(items: [shareFile]) }
        }
        #endif
        .sheet(item: $sharingCard) { card in
            NavigationStack {
                ThemeQRCodeView(theme: card)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { sharingCard = nil } }
                    }
            }
        }
    }

    // MARK: Colour rows

    /// One input colour: its swatch opens the system colour picker. An
    /// advanced override can go back to Auto (derived by the compiler).
    @ViewBuilder
    private func colorRow(_ key: ThemeInputKey, theme: CustomTheme, compiled: CompiledTheme) -> some View {
        let stored = theme.hex(key, mode: mode)
        let shown = stored ?? compiled.hex(key.derivedToken, mode: mode)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(stored == nil ? Color.clear : Color(hex: shown))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(stored == nil ? 0.6 : 0.3),
                                  style: StrokeStyle(lineWidth: 1, dash: stored == nil ? [3] : [])))
                .frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.displayName)
                Text("\(stored.map { "#\($0)" } ?? "Auto") · \(key.editorDescription)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // The system colour picker, opened from its own well.
            ColorPicker(key.displayName, selection: Binding(
                get: { Color(hex: shown) },
                set: { color in
                    guard let hex = color.hexRGB, hex != stored else { return }
                    update { $0.setHex(hex, for: key, mode: mode) }
                }), supportsOpacity: false)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .apolloSettingsRowInsets()
        .contextMenu {
            if stored != nil, ThemeInputKey.advancedKeys.contains(key) {
                Button("Reset to Auto", systemImage: "arrow.uturn.backward") {
                    update { $0.setHex(nil, for: key, mode: mode) }
                }
            }
        }
        .swipeActions {
            if stored != nil, ThemeInputKey.advancedKeys.contains(key) {
                Button("Auto") { update { $0.setHex(nil, for: key, mode: mode) } }
            }
        }
    }

    // MARK: Saving

    private func binding<Value>(_ keyPath: WritableKeyPath<CustomTheme, Value>) -> Binding<Value> {
        Binding(
            get: { theme![keyPath: keyPath] },
            set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func update(_ change: (inout CustomTheme) -> Void) {
        guard var edited = theme else { return }
        change(&edited)
        let snapshot = edited
        CustomThemeStore.update(themeID) { $0 = snapshot }
        theme = CustomThemeStore.theme(id: themeID)
    }

    private func delete() {
        let active = ThemeStore.load()
        CustomThemeStore.delete(themeID)
        // The active theme gone: back to the default rather than a ghost.
        if CustomTheme.parse(themeID: active.id)?.id == themeID {
            ThemeStore.save(active.isDark ? .defaultDark : .defaultLight)
        }
        theme = nil
        dismiss()
    }

    private func writeExport(_ theme: CustomTheme) -> URL? {
        guard let data = theme.exportData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(theme.exportFilename)
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }
}

extension ThemeInputKey {
    /// The token an unset input falls back to, for showing "Auto".
    var derivedToken: ThemeToken {
        switch self {
        case .accent: return .accent
        case .background: return .background
        case .card: return .secondaryBackground
        case .raised: return .tertiaryBackground
        case .bars: return .barBackground
        case .text: return .label
        case .mutedText: return .secondaryLabel
        case .separator: return .separator
        }
    }
}

#if canImport(UIKit)
extension Color {
    /// "RRGGBB" for an opaque colour picked in the colour picker.
    var hexRGB: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
#endif

/// The font tiles: "Aa" in each font, its name and kind; the current one
/// outlined in the theme's accent.
private struct ThemeFontGrid: View {
    @Binding var selection: ThemeFont
    let compiled: CompiledTheme
    let mode: ThemeMode

    var body: some View {
        let accent = Color(hex: compiled.hex(.accent, mode: mode))
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(ThemeFont.allCases) { font in
                Button {
                    selection = font
                    Haptics.selection()
                } label: {
                    VStack(spacing: 4) {
                        Text("Aa").font(.system(size: 28, weight: .semibold))
                        Text(font.displayName).font(.system(size: 13, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(font.detailName).font(.caption2).foregroundStyle(.secondary)
                    }
                    // Each tile in its own font, whatever the app's is.
                    .fontDesign(font.design ?? .default)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: compiled.hex(.tertiaryBackground, mode: mode)).opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selection == font ? accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == font ? .isSelected : [])
            }
        }
    }
}

/// Reborn's four preview rows, painted with the theme being edited.
private struct ThemePreviewRows: View {
    let compiled: CompiledTheme
    let mode: ThemeMode

    private func color(_ token: ThemeToken) -> Color { Color(hex: compiled.hex(token, mode: mode)) }

    var body: some View {
        row(icon: "arrow.up", iconColor: color(.accent), title: "Post title goes here",
            detail: "r/phoebus · 3h · 142 points", background: color(.secondaryBackground))
        row(icon: "bubble.left", iconColor: color(.secondaryLabel), title: "A comment with body text",
            detail: "username · reply", background: color(.secondaryBackground))
        row(icon: "link", iconColor: color(.accent), title: "Tinted link / button", titleColor: color(.accent),
            detail: nil, background: color(.secondaryBackground))
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5).fill(color(.separator)).frame(width: 22, height: 22)
            Text("Selected / tapped row").foregroundStyle(color(.label))
            Spacer()
        }
        .listRowBackground(color(.rowHighlight))
    }

    private func row(icon: String, iconColor: Color, title: String, titleColor: Color? = nil,
                     detail: String?, background: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(iconColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(titleColor ?? color(.label))
                if let detail { Text(detail).font(.footnote).foregroundStyle(color(.secondaryLabel)) }
            }
            Spacer()
        }
        .listRowBackground(background)
        .listRowSeparatorTint(color(.separator))
    }
}

/// A custom theme's swatch: its light and dark backgrounds with the accent.
struct CustomThemeSwatch: View {
    let theme: CustomTheme

    var body: some View {
        let compiled = theme.compiled()
        ZStack {
            HStack(spacing: 0) {
                Rectangle().fill(Color(hex: compiled.hex(.background, mode: .light)))
                Rectangle().fill(Color(hex: compiled.hex(.background, mode: .dark)))
            }
            Circle().fill(Color(hex: compiled.hex(.accent, mode: .light))).frame(width: 12, height: 12)
        }
        .frame(width: 29, height: 29)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }
}
