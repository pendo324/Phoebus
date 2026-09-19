import SwiftUI
import PhoebusCore
import PhotosUI
import UniformTypeIdentifiers

/// Themes settings: a picker among Apollo's 18 named accent themes
/// (`Theme.allThemes`), each shown once with a Light/Dark toggle, plus
/// AI-generated or QR-imported themes and entry points to generate or share
/// one. See `Theme`'s doc comment for scope limits vs. Apollo's full theme system.
public struct ThemeSettingsScreen: View {
    @State private var selected = ThemeStore.load()
    @State private var generatedThemes = ThemeStore.loadGeneratedThemes()
    @State private var showingGenerate = false
    @State private var showingScan = false
    /// Reborn's three import routes (`importTapped`).
    @State private var showingImportChoices = false
    @State private var showingFileImport = false
    @State private var showingPhotoImport = false
    @State private var photoImportItem: PhotosPickerItem?
    @State private var pendingImport: Theme?
    @State private var importError: String?
    @State private var sharingTheme: Theme?
    @Setting(PureBlackSettingsStore.storage) private var pureBlack
    @Setting(ThemeAutoSwitchSettingsStore.storage) private var autoSwitch
    @State private var showingApolloThemes = false
    @State private var customThemes = CustomThemeStore.all()
    /// The custom theme the editor opens on.
    @State private var editingThemeID: String?
    @State private var showingEditor = false
    @State private var pendingCustomImport: CustomTheme?

    public init() {}

    private var groupedBuiltInThemes: [(name: String, light: Theme, dark: Theme)] {
        var seen = Set<String>()
        var groups: [(String, Theme, Theme)] = []
        for theme in Theme.allThemes where !seen.contains(theme.name) {
            seen.insert(theme.name)
            let light = Theme.allThemes.first { $0.name == theme.name && !$0.isDark } ?? theme
            let dark = Theme.allThemes.first { $0.name == theme.name && $0.isDark } ?? theme
            groups.append((theme.name, light, dark))
        }
        return groups
    }

    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The palette name shown on the Comments Theme row. Held in `@State` and
    /// refreshed in `.onAppear`: SwiftUI evaluates an inline store read once and
    /// caches it, so the row would show a stale palette.
    @State private var commentsThemeDetail: String = ThemeSettingsScreen.currentCommentsThemeName()

    static func currentCommentsThemeName() -> String {
        CommentsThemeStore.overridePaletteName
            ?? (ThemeStore.load().commentPaletteName ?? "Theme's Own")
    }

    public var body: some View {
        // Reborn's Theme Manager: Current / Create / Browse / My Themes /
        // (Imported) / Options.
        List {
            // "Current": a swatch, the active theme's title, its
            // origin detail, and a tinted "Change"/"Edit"/"Copy & Edit"
            // action with a 14pt chevron on the trailing edge.
            Section {
                Button { currentThemeActionTapped() } label: {
                    HStack(spacing: 12) {
                        // A stock theme shows the palette glyph, as the
                        // Browse row does; a custom one its swatch.
                        if let custom = CustomThemeStore.theme(forThemeID: selected.id) {
                            CustomThemeSwatch(theme: custom)
                        } else if selected.isGenerated {
                            ThemeSwatch(theme: selected)
                        } else {
                            Image(systemName: "paintpalette")
                                .foregroundStyle(Color.apolloAccent)
                                .frame(width: 29)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.isGenerated ? selected.name : "Phoebus Theme")
                                .foregroundStyle(Color.primary)
                            Text(currentOriginDetail)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Text(currentActionTitle)
                                .font(.system(size: 17))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 10)
                        }
                        .foregroundStyle(Color.apolloAccent)
                    }
                }
                // The icon row's rule sits past the swatch, matching
                // `apolloSettingsRowInsets`; it is the section's only row, so no
                // trailing rule.
                .apolloSettingsRowInsets(rule: false)
            } header: {
                Text("Current")
                    .apolloSectionHeader()
            }

            // "Create".
            Section {
                Button { showingGenerate = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles").foregroundStyle(Color.apolloAccent).frame(width: 29)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Generate with AI…").foregroundStyle(Color.apolloAccent)
                            Text("Describe a theme and let Phoebus build it.")
                                .font(.system(size: 15)).foregroundStyle(Color.secondary)
                        }
                    }
                }
                .apolloSettingsRowInsets()
                Button { newBlankTheme() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle").foregroundStyle(Color.apolloAccent).frame(width: 29)
                        Text("New Blank Theme…").foregroundStyle(Color.apolloAccent)
                    }
                }
                .apolloSettingsRowInsets()
                Button { showingImportChoices = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down").foregroundStyle(Color.apolloAccent).frame(width: 29)
                        Text("Import Theme…").foregroundStyle(Color.apolloAccent)
                    }
                }
                .apolloSettingsRowInsets(rule: false)
            } header: {
                Text("Create")
                    .apolloSectionHeader()
            }

            // "Browse": Theme Gallery, then Apollo Themes with
            // "Default"/"Not Active" as its detail.
            Section {
                SettingsLink {
                    ThemeGalleryScreen { galleryTheme in
                        let mode: ThemeMode = selected.isDark ? .dark : .light
                        select(galleryTheme.asTheme(mode: mode))
                        generatedThemes = ThemeStore.loadGeneratedThemes()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2").foregroundStyle(Color.apolloAccent).frame(width: 29)
                        Text("Theme Gallery")
                    }
                }
                .apolloSearchRow("Theme Gallery")
                .accessibilityIdentifier("theme.gallery")
                SettingsLink {
                    ApolloThemesPickerScreen(selected: $selected, groups: groupedBuiltInThemes, onSelect: select)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "paintpalette").foregroundStyle(Color.apolloAccent).frame(width: 29)
                        Text("Phoebus Themes")
                        Spacer()
                        Text(selected.isGenerated ? "Not Active" : selected.name)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .apolloSearchRow("Phoebus Themes")
            } header: {
                Text("Browse")
                    .apolloSectionHeader()
            }

            // "My Themes", with the empty state.
            Section {
                ForEach(customThemes) { custom in
                    customThemeRow(custom)
                }
                if generatedThemes.isEmpty && customThemes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No custom themes yet").foregroundStyle(Color.secondary)
                        Text("Create one, generate one, import one, or start from the gallery.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    // Default inset rather than the icon-row inset; the section's only
                    // row, so no rule.
                    .apolloSettingsRowInsets(rule: false)
                } else {
                    themeRows(for: generatedThemes)
                }
            } header: {
                Text("My Themes")
                    .apolloSectionHeader()
            }

            // "Options": Light/Dark Mode and Comments Theme, both
            // pushes into Apollo's own screens.
            Section {
                SettingsLink {
                    LightDarkModeSettingsScreen()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(Color.apolloAccent).frame(width: 29)
                        Text("Light/Dark Mode")
                    }
                }
                .apolloSearchRow("Light/Dark Mode")
                SettingsLink {
                    CommentsThemeSettingsScreen()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "text.bubble").foregroundStyle(Color.apolloAccent).frame(width: 29)
                        Text("Comments Theme")
                        Spacer()
                        Text(commentsThemeDetail).foregroundStyle(Color.secondary)
                    }
                }
                .apolloSearchRow("Comments Theme")
                .accessibilityIdentifier("theme.commentsTheme")
            } header: {
                Text("Options")
                    .apolloSectionHeader()
            } footer: {
                Text("Light/dark switching applies to all themes. Pure black affects Phoebus themes only — custom themes control their own dark background.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Theme Manager")
        .onAppear {
            commentsThemeDetail = Self.currentCommentsThemeName()
            customThemes = CustomThemeStore.all()
            selected = ThemeStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: CustomThemeStore.didChangeNotification)) { _ in
            customThemes = CustomThemeStore.all()
        }
        .settingsDestination(isPresented: $showingEditor) {
            if let editingThemeID { ThemeEditorScreen(themeID: editingThemeID) }
        }
        .alert("Import Theme", isPresented: $pendingCustomImport.isPresent(), presenting: pendingCustomImport) { custom in
            Button("Cancel", role: .cancel) {}
            Button("Import") {
                let added = CustomThemeStore.add(custom)
                select(added.asTheme(mode: selected.isDark ? .dark : .light))
            }
        } message: { custom in
            Text("Import \"\(custom.name)\" as a new theme?")
        }
        .settingsDestination(isPresented: $showingApolloThemes) {
            ApolloThemesPickerScreen(selected: $selected, groups: groupedBuiltInThemes, onSelect: select)
        }
        .sheet(isPresented: $showingGenerate) {
            ThemeGenerateScreen { theme in
                select(theme)
                generatedThemes = ThemeStore.loadGeneratedThemes()
            }
        }
        .apolloActionSheet(isPresented: $showingImportChoices, title: "Import Theme", rows: [
            ApolloActionSheetRow("From File…") { showingFileImport = true },
            ApolloActionSheetRow("From Photo…") { showingPhotoImport = true },
            ApolloActionSheetRow("Scan with Camera…") { showingScan = true },
        ])
        .fileImporter(isPresented: $showingFileImport,
                      allowedContentTypes: [.json, .image, .plainText, .data, .item]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                importError = "Couldn't read that file."
                return
            }
            guard data.count <= 40 * 1024 * 1024 else {
                importError = "That file is too large to be a theme."
                return
            }
            importThemeData(data)
        }
        .photosPicker(isPresented: $showingPhotoImport, selection: $photoImportItem, matching: .images)
        .onChange(of: photoImportItem) { _, item in
            guard let item else { return }
            photoImportItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    importError = "Couldn't read that image."
                    return
                }
                importThemeData(data)
            }
        }
        .alert("Import Theme", isPresented: $pendingImport.isPresent(), presenting: pendingImport) { theme in
            Button("Cancel", role: .cancel) {}
            Button("Import") {
                select(theme)
                generatedThemes = ThemeStore.loadGeneratedThemes()
            }
        } message: { theme in
            Text("Import \"\(theme.name)\" (\(theme.isDark ? "Dark" : "Light")) as a new theme?")
        }
        .alert("Import Theme", isPresented: $importError.isPresent()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showingScan) {
            ThemeQRScanScreen { theme in
                select(theme)
                generatedThemes = ThemeStore.loadGeneratedThemes()
            }
        }
        .sheet(item: $sharingTheme) { theme in
            NavigationStack {
                ThemeQRCodeView(theme: theme)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { sharingTheme = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func themeRows(for themes: [Theme]) -> some View {
        ForEach(themes) { theme in
            Button {
                select(theme)
            } label: {
                HStack {
                    Circle()
                        .fill(Color(hex: theme.accentColorHex))
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading) {
                        Text(theme.name)
                            .foregroundStyle(Color.primary)
                        Text(theme.isDark ? "Dark" : "Light")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(theme.commentDepthColorHexes, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 8, height: 8)
                        }
                    }
                    if selected.id == theme.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.apolloAccent)
                    }
                }
            }
            // Theme rows lead with a colour swatch column, so they
            // take the icon-row geometry (rule inset past the swatch).
            .apolloSettingsRowInsets()
            .swipeActions(edge: .trailing) {
                Button {
                    sharingTheme = theme
                } label: {
                    Label("Share", systemImage: "qrcode")
                }
                .tint(.blue)
                if theme.isGenerated {
                    Button(role: .destructive) {
                        ThemeStore.removeGeneratedTheme(id: theme.id)
                        generatedThemes = ThemeStore.loadGeneratedThemes()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Switches to this theme family's light or dark variant.
    private func selectLightDark(isDark: Bool) {
        let variants = ThemeStore.allAvailableThemes().filter { $0.name == selected.name }
        if let match = variants.first(where: { $0.isDark == isDark }) {
            select(match)
        } else if let fallback = ThemeStore.allAvailableThemes().first(where: { $0.isDark == isDark }) {
            select(fallback)
        }
    }

    /// A theme file's text, or a shared theme image's QR code; sniffed by
    /// content, as Reborn does.
    private func importThemeData(_ data: Data) {
        if let image = UIImage(data: data) {
            guard let payload = ThemeImageQRReader.payload(in: image),
                  let theme = try? ThemeQRCodePayload.decode(payload) else {
                importError = "This image doesn't contain a Phoebus theme code. Import the original shared theme image (screenshots of it work too, as long as the QR code is visible)."
                return
            }
            pendingImport = theme
            return
        }
        // A theme file (Reborn's schema, so Reborn exports import too).
        if let custom = try? CustomTheme.parse(fileData: data) {
            pendingCustomImport = custom
            return
        }
        guard let text = String(data: data, encoding: .utf8),
              let theme = try? ThemeQRCodePayload.decode(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            importError = "Couldn't read that theme."
            return
        }
        pendingImport = theme
    }

    private func select(_ theme: Theme) {
        selected = theme
        ThemeStore.save(theme)
    }

    // MARK: Custom themes

    private var activeGallerySlug: String? {
        guard selected.id.hasPrefix("gallery_") else { return nil }
        var slug = String(selected.id.dropFirst("gallery_".count))
        for suffix in ["_light", "_dark"] where slug.hasSuffix(suffix) { slug = String(slug.dropLast(suffix.count)) }
        return slug
    }

    /// Reborn's Current row action: Edit a custom theme, Copy & Edit a
    /// gallery one, Change otherwise.
    private var currentActionTitle: String {
        if CustomThemeStore.theme(forThemeID: selected.id) != nil { return "Edit" }
        if activeGallerySlug != nil { return "Copy & Edit" }
        return "Change"
    }

    private var currentOriginDetail: String {
        if let custom = CustomThemeStore.theme(forThemeID: selected.id) {
            switch custom.origin {
            case .created: return "Created"
            case .generated: return "Generated"
            case .imported: return "Imported"
            }
        }
        if activeGallerySlug != nil { return "Gallery" }
        return selected.isGenerated ? "Created" : selected.name.capitalized
    }

    private func currentThemeActionTapped() {
        if let custom = CustomThemeStore.theme(forThemeID: selected.id) {
            openEditor(custom.id)
        } else if let slug = activeGallerySlug, let gallery = ThemeGallery.theme(slug: slug) {
            // Reborn's customizeActiveTheme: a gallery theme becomes the
            // user's own copy, applied, then opened for editing.
            let copy = CustomThemeStore.add(CustomTheme(name: gallery.name, input: gallery.input,
                                                        variant: gallery.variant, advancedOptionsEnabled: true))
            select(copy.asTheme(mode: selected.isDark ? .dark : .light))
            Haptics.medium()
            openEditor(copy.id)
        } else {
            showingApolloThemes = true
        }
    }

    private func newBlankTheme() {
        let created = CustomThemeStore.add(CustomTheme(name: "My Theme"))
        openEditor(created.id)
    }

    private func openEditor(_ id: String) {
        editingThemeID = id
        showingEditor = true
    }

    private func deleteCustom(_ custom: CustomTheme) {
        let wasActive = CustomTheme.parse(themeID: selected.id)?.id == custom.id
        CustomThemeStore.delete(custom.id)
        if wasActive { select(selected.isDark ? .defaultDark : .defaultLight) }
    }

    @ViewBuilder
    private func customThemeRow(_ custom: CustomTheme) -> some View {
        let isActive = CustomTheme.parse(themeID: selected.id)?.id == custom.id
        Button {
            select(custom.asTheme(mode: selected.isDark ? .dark : .light))
        } label: {
            HStack(spacing: 12) {
                CustomThemeSwatch(theme: custom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(custom.name).foregroundStyle(Color.primary)
                    Text(custom.origin == .imported ? "Imported" : custom.origin == .generated ? "Generated" : "Created")
                        .font(.system(size: 15)).foregroundStyle(Color.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark").foregroundStyle(Color.apolloAccent)
                }
            }
        }
        .apolloSettingsRowInsets()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleteCustom(custom) } label: { Label("Delete", systemImage: "trash") }
            Button { openEditor(custom.id) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                .tint(.blue)
        }
        .contextMenu {
            Button("Edit", systemImage: "slider.horizontal.3") { openEditor(custom.id) }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                var copy = custom
                copy.id = UUID().uuidString
                copy.origin = .created
                CustomThemeStore.add(copy)
            }
            Button("Delete", systemImage: "trash", role: .destructive) { deleteCustom(custom) }
        }
    }

}

/// One row per theme name, with a Light/Dark segmented control instead of two flat rows.
private struct ThemeGroupRow: View {
    let name: String
    let light: Theme
    let dark: Theme
    let selected: Theme
    let onSelect: (Theme) -> Void

    private var isCurrentlyDark: Bool { selected.id == dark.id }
    private var activeTheme: Theme { isCurrentlyDark ? dark : light }

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: activeTheme.accentColorHex))
                .frame(width: 24, height: 24)
            Text(name)
                .foregroundStyle(Color.primary)
            Spacer()
            HStack(spacing: 2) {
                ForEach(activeTheme.commentDepthColorHexes, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 8, height: 8)
                }
            }
            Picker("Mode", selection: Binding(
                get: { isCurrentlyDark },
                set: { onSelect($0 ? dark : light) }
            )) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
                    .apolloSearchRow("Mode")
            .pickerStyle(.segmented)
            .frame(width: 120)
            if selected.id == light.id || selected.id == dark.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.apolloAccent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(activeTheme)
        }
    }
}


/// Stock Apollo's theme picker, reached from Theme Manager > Browse >
/// "Apollo Themes".
struct ApolloThemesPickerScreen: View {
    @Binding var selected: Theme
    let groups: [(name: String, light: Theme, dark: Theme)]
    let onSelect: (Theme) -> Void

    var body: some View {
        // Stock Apollo's picker is a plain list of its named themes,
        // no header or footer prose.
        List {
            let names = groups.map(\.name)
            ForEach(groups, id: \.name) { group in
                ThemeGroupRow(name: group.name, light: group.light, dark: group.dark, selected: selected, onSelect: onSelect)
                    // Leading accent swatch column: icon-row geometry.
                    .apolloSettingsRowInsets(rule: group.name != names.last)
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Phoebus Themes")
    }
}

/// Stock Apollo's Light/Dark Mode screen, reached from Theme Manager > Options.
struct LightDarkModeSettingsScreen: View {
    /// One-time locate on; "Turn switch off to clear."
    private func sunsetLocationToggled(_ on: Bool) {
        #if canImport(CoreLocation)
        if on { sunsetLocator.locate() } else { sunsetLocator.clear() }
        #endif
    }

    #if canImport(CoreLocation)
    @StateObject private var sunsetLocator = SunsetLocator()

    /// Apollo's status row under the toggle: "Finding Location…",
    /// "Locating failed. Tap to retry.", or today's times with a way to
    /// "Reset location if you've traveled".
    @ViewBuilder private var sunsetStatusRow: some View {
        switch sunsetLocator.state {
        case .locating:
            Text("Finding Location…").foregroundStyle(Color.secondary)
                .apolloPlainSettingsRowInsets(rule: false)
        case .failed:
            Button("Locating failed. Tap to retry.") { sunsetLocator.locate() }
                .apolloPlainSettingsRowInsets(rule: false)
        case .idle:
            Button("Find Location") { sunsetLocator.locate() }
                .apolloPlainSettingsRowInsets(rule: false)
        case .found(let c):
            let times = SolarTimes.sunriseSunset(on: Date(), at: c)
            Button {
                sunsetLocator.locate()
            } label: {
                HStack {
                    Text("Reset Location")
                    Spacer()
                    if let times {
                        Text("\(times.sunrise.formatted(date: .omitted, time: .shortened)) – \(times.sunset.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .apolloPlainSettingsRowInsets(rule: false)
        }
    }
    #endif
    @State private var selected = ThemeStore.load()
    @Setting(PureBlackSettingsStore.storage) private var pureBlack
    @Setting(ThemeAutoSwitchSettingsStore.storage) private var autoSwitch

    var body: some View {
        List {
            // "THEME" section, shown first: a plain Light/Dark choice with a
            // trailing checkmark on the active one.
            Section {
                ForEach([false, true], id: \.self) { wantsDark in
                    Button {
                        selectLightDark(isDark: wantsDark)
                    } label: {
                        HStack {
                            Text(wantsDark ? "Dark" : "Light")
                            Spacer()
                            if selected.isDark == wantsDark {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.apolloAccent)
                            }
                        }
                        .foregroundStyle(Color.primary)
                        // Whole row tappable, not just the label text.
                        .apolloFullRowTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("theme.mode.\(wantsDark ? "dark" : "light")")
                    // No footer on this section, so both rows rule.
                    .apolloPlainSettingsRowInsets()
                }
            } header: {
                Text("Theme")
                    .apolloSectionHeader()
            }

            // "Use System Light/Dark Mode" (`UseSystemLightDarkMode`).
            Section {
                Toggle("Use System Light/Dark Mode", isOn: Binding(
                    get: { autoSwitch.useSystemLightDarkMode },
                    set: { newValue in
                        $autoSwitch.useSystemLightDarkMode.wrappedValue = newValue
                    }
                ))
                    .apolloSearchRow("Use System Light/Dark Mode", lastBeforeFooter: true)
            } footer: {
                Text("Follows the system's own Light/Dark Mode setting instead of Phoebus's manual or scheduled theme switching.")
                    .apolloSectionFooter()
            }
            Section {
                Toggle("Pure Black Dark Mode", isOn: Binding(
                    get: { pureBlack.isEnabled },
                    set: { newValue in
                        $pureBlack.isEnabled.wrappedValue = newValue
                        if !newValue { $pureBlack.isPurerEnabled.wrappedValue = false }
                    }
                ))
                    .apolloSearchRow("Pure Black Dark Mode")
                if pureBlack.isEnabled {
                    Toggle("PURER Black Dark Mode", isOn: Binding(
                        get: { pureBlack.isPurerEnabled },
                        set: { newValue in
                            $pureBlack.isPurerEnabled.wrappedValue = newValue
                        }
                    ))
                    .apolloSearchRow("PURER Black Dark Mode")
                    // Row title is "Reduce Smearing"; "OLED" appears only in the footer.
                    Toggle("Reduce Smearing", isOn: Binding(
                        get: { pureBlack.reduceSmearing },
                        set: { newValue in
                            $pureBlack.reduceSmearing.wrappedValue = newValue
                        }
                    ))
                    .apolloSearchRow("Reduce Smearing", lastBeforeFooter: true)
                }
            } header: {
                Text("Dark Mode")
                    .apolloSectionHeader()
            } footer: {
                Text("Overrides dark-mode backgrounds to true black for OLED screens, independent of the accent theme below.")
                    .apolloSectionFooter()
            }
            // "SWITCH MODE": three exclusive rows (title over verbatim subtitle)
            // with a trailing checkmark on the active mode.
            Section {
                ForEach(ThemeSwitchMode.allCases, id: \.self) { mode in
                    Button {
                        $autoSwitch.switchMode.wrappedValue = mode
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                Text(mode.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            // Standard label colours, not the default button tint.
                            .foregroundStyle(Color.primary)
                            Spacer()
                            if autoSwitch.switchMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.apolloAccent)
                            }
                        }
                        .apolloFullRowTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("theme.switchMode.\(mode.rawValue)")
                    .apolloPlainSettingsRowInsets()
                }
            } header: {
                Text("Switch Mode")
                    .apolloSectionHeader()
            }

            // Each mode's controls sit in a separate section titled after it.
            if autoSwitch.switchMode == .brightness {
                Section {
                    BrightnessThresholdRow(value: Binding(
                        get: { autoSwitch.brightnessThreshold },
                        set: { $autoSwitch.brightnessThreshold.wrappedValue = $0 }))
                    .apolloPlainSettingsRowInsets(rule: false)
                } header: {
                    Text("Automatic Switch Threshold")
                        .apolloSectionHeader()
                } footer: {
                    // Verbatim copy.
                    Text("Will switch to dark mode when \(Int(autoSwitch.brightnessThreshold * 100))% brightness or less. Auto-brightness recommended. The pin is your current screen brightness, and the notch is the recommended setting.")
                        .apolloSectionFooter()
                }
            }

            if autoSwitch.switchMode == .schedule {
                Section {
                    Toggle("Use Location Sunset & Sunrise", isOn: Binding(
                        get: { autoSwitch.useLocationSunsetSunrise },
                        set: {
                            $autoSwitch.useLocationSunsetSunrise.wrappedValue = $0
                            sunsetLocationToggled($0)
                        }
                    ))
                    // Followed by the DatePickers (off) or the location
                    // status row (on), so never the last row.
                    .apolloSearchRow("Use Location Sunset & Sunrise")
                    .accessibilityIdentifier("theme.useLocationSunsetSunrise")
                    #if canImport(CoreLocation)
                    if autoSwitch.useLocationSunsetSunrise {
                        sunsetStatusRow
                    }
                    #endif
                    if !autoSwitch.useLocationSunsetSunrise {
                        DatePicker("Dark Mode Starts", selection: Binding(
                            get: { ThemeSettingsScreen.date(fromMinutes: autoSwitch.darkModeStartMinutes) },
                            set: {
                                $autoSwitch.darkModeStartMinutes.wrappedValue = ThemeSettingsScreen.minutes(from: $0)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .apolloPlainSettingsRowInsets()
                        DatePicker("Light Mode Starts", selection: Binding(
                            get: { ThemeSettingsScreen.date(fromMinutes: autoSwitch.lightModeStartMinutes) },
                            set: {
                                $autoSwitch.lightModeStartMinutes.wrappedValue = ThemeSettingsScreen.minutes(from: $0)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .apolloPlainSettingsRowInsets(rule: false)
                    }
                } header: {
                    Text("Scheduled")
                        .apolloSectionHeader()
                } footer: {
                    if autoSwitch.useLocationSunsetSunrise {
                        Text("Calculating sunset/sunrise times require a one-time check of your approximate location and is not shared or sent. Turn switch off to clear. Reset location if you've traveled.")
                            .apolloSectionFooter()
                    }
                }
            }

            // "Enable Quick Switch" (`ThemeToggleGestureEnabled`) with its verbatim footer.
            Section {
                Toggle("Enable Quick Switch", isOn: Binding(
                    get: { autoSwitch.quickSwitchEnabled },
                    set: { newValue in
                        $autoSwitch.quickSwitchEnabled.wrappedValue = newValue
                    }
                ))
                    .apolloSearchRow("Enable Quick Switch", lastBeforeFooter: true)
            } header: {
                Text("Manually")
                    .apolloSectionHeader()
            } footer: {
                Text("If enabled, at any time long-press the top navigation bar to quickly toggle themes.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Light/Dark Mode")
        // The theme also changes underneath this screen (Use System
        // Light/Dark Mode, Quick Switch), so the checkmark follows the store.
        .onReceive(NotificationCenter.default.publisher(for: ThemeStore.didChangeNotification)) { _ in
            selected = ThemeStore.load()
        }
    }

    private func selectLightDark(isDark: Bool) {
        // A hand-picked mode is a manual choice: Use System Light/Dark Mode
        // would otherwise switch straight back to the system's.
        if autoSwitch.useSystemLightDarkMode {
            $autoSwitch.useSystemLightDarkMode.wrappedValue = false
        }
        let variants = ThemeStore.allAvailableThemes().filter { $0.name == selected.name }
        if let match = variants.first(where: { $0.isDark == isDark }) {
            select(match)
        } else if let fallback = ThemeStore.allAvailableThemes().first(where: { $0.isDark == isDark }) {
            select(fallback)
        }
    }

    private func select(_ theme: Theme) {
        selected = theme
        ThemeStore.save(theme)
    }
}

/// `ThemeSwatchImage`: light background / dark background halves with
/// the accent dot.
struct ThemeSwatch: View {
    let theme: Theme
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Rectangle().fill(Color.white)
                Rectangle().fill(Color.black)
            }
            Circle().fill(Color(hex: theme.accentColorHex)).frame(width: 12, height: 12)
        }
        .frame(width: 29, height: 29)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }
}

/// The brightness-threshold row: low/high glyphs either side of the slider,
/// a pin at the current screen brightness, and notches at both ends and at
/// the recommended 25%.
struct BrightnessThresholdRow: View {
    @Binding var value: Double
    @State private var screenBrightness: Double = BrightnessThresholdRow.currentBrightness()

    /// UISlider's track runs between the thumb's centre at each end.
    private let thumbInset: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            StockPNG.image("low-brightness")
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let track = geo.size.width - thumbInset * 2
                ZStack(alignment: .topLeading) {
                    StockPNG.image("brightness-pin")
                        .foregroundStyle(Color.apolloAccent)
                        .offset(x: thumbInset + track * screenBrightness - 6, y: 0)
                        .accessibilityHidden(true)
                    ForEach([0.0, AutomaticThemeThreshold.recommended, 1.0], id: \.self) { mark in
                        Capsule()
                            .fill(Color.secondary.opacity(mark == AutomaticThemeThreshold.recommended ? 0.9 : 0.5))
                            .frame(width: 2, height: 6)
                            .offset(x: thumbInset + track * mark - 1, y: 46)
                    }
                    Slider(value: $value, in: 0...1)
                        .tint(Color(red: 103 / 255, green: 206 / 255, blue: 103 / 255))
                        .offset(y: 17)
                        .accessibilityIdentifier("theme.brightnessThreshold")
                }
            }
            .frame(height: 54)
            StockPNG.image("high-brightness")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
            screenBrightness = Self.currentBrightness()
        }
        #endif
    }

    static func currentBrightness() -> Double {
        #if canImport(UIKit)
        return Double(UIScreen.main.brightness)
        #else
        return 0.5
        #endif
    }
}

enum AutomaticThemeThreshold {
    /// Apollo's default threshold, shown as the notch.
    static let recommended = 0.25
}

/// Reads the theme code from a shared theme card's QR.
enum ThemeImageQRReader {
    static func payload(in image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) ?? image.cgImage.map({ CIImage(cgImage: $0) }),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detector.features(in: ciImage)
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .first
    }
}
