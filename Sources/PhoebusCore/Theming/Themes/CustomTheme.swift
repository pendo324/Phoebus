import Foundation

/// The four fonts a custom theme can set (Reborn's theme font option).
public enum ThemeFont: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case mono

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "SF Pro"
        case .rounded: return "SF Pro Rounded"
        case .serif: return "New York"
        case .mono: return "SF Mono"
        }
    }

    public var detailName: String {
        switch self {
        case .system: return "Default"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        }
    }
}

extension ThemeInputKey {
    /// The editor's Colours section.
    public static let defaultKeys: [ThemeInputKey] = [.accent, .background, .card, .raised, .bars]
    /// Shown with Advanced options.
    public static let advancedKeys: [ThemeInputKey] = [.text, .mutedText, .separator]

    public var displayName: String {
        switch self {
        case .accent: return "Accent"
        case .background: return "Background"
        case .card: return "Card"
        case .raised: return "Raised"
        case .bars: return "Bars & Chrome"
        case .text: return "Text"
        case .mutedText: return "Muted Text"
        case .separator: return "Separators"
        }
    }

    /// What the colour paints, as the editor explains it.
    public var editorDescription: String {
        switch self {
        case .accent: return "Selected tabs, links, switches, buttons, and active controls."
        case .background: return "Main page background behind cards and grouped sections."
        case .card: return "List rows, setting cells, post cards, and grouped panels."
        case .raised: return "Raised surfaces such as inset controls and elevated panels."
        case .bars: return "Navigation bars, tab bar backing, and other app chrome."
        case .text: return "Primary text. Auto keeps contrast readable against the background."
        case .mutedText: return "Secondary labels, metadata, placeholders, and disabled text."
        case .separator: return "Thin divider lines between rows, cells, and grouped sections."
        }
    }
}

/// A user-made theme (Reborn's custom theme dictionary, schema v3): eight
/// input colours per mode compiled into the app's tokens, plus a font and
/// the vote-arrow option.
public struct CustomTheme: Codable, Sendable, Equatable, Identifiable {
    public enum Origin: String, Codable, Sendable {
        case created, generated, imported
    }

    public var id: String
    public var name: String
    /// Hex strings (no `#`) by mode, then input key. Absent advanced keys
    /// are derived by the compiler.
    public var input: [String: [String: String]]
    public var variant: String
    public var advancedOptionsEnabled: Bool
    public var font: ThemeFont
    public var voteArrowsAccent: Bool
    public var origin: Origin
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String,
                input: [ThemeMode: [ThemeInputKey: String]]? = nil,
                variant: ThemeVariant = .balanced, advancedOptionsEnabled: Bool = false,
                font: ThemeFont = .system, voteArrowsAccent: Bool = false,
                origin: Origin = .created, createdAt: Date = Date()) {
        self.id = id
        self.name = CustomTheme.clampName(name)
        self.input = CustomTheme.normalized(input ?? CustomTheme.starterInput)
        self.variant = variant.rawValue
        self.advancedOptionsEnabled = advancedOptionsEnabled
        self.font = font
        self.voteArrowsAccent = voteArrowsAccent
        self.origin = origin
        self.createdAt = createdAt
    }

    // MARK: Input access

    public func hex(_ key: ThemeInputKey, mode: ThemeMode) -> String? {
        input[mode.rawValue]?[key.rawValue]
    }

    public mutating func setHex(_ hex: String?, for key: ThemeInputKey, mode: ThemeMode) {
        var modeInput = input[mode.rawValue] ?? [:]
        if let hex, let rgb = ThemeColorMath.parseHex(hex) {
            modeInput[key.rawValue] = ThemeColorMath.hexString(rgb)
        } else if ThemeInputKey.defaultKeys.contains(key) {
            // A required surface goes back to the starter colour, not blank.
            modeInput[key.rawValue] = CustomTheme.starterInput[mode]?[key]
        } else {
            modeInput.removeValue(forKey: key.rawValue)
        }
        input[mode.rawValue] = modeInput
    }

    /// Derives the other mode from this one (Reborn's mode generation).
    public mutating func generate(_ destination: ThemeMode, from source: ThemeMode) {
        let src = typedInput[source] ?? [:]
        let generated = ThemeCompiler.generateOppositeModeInput(from: src, sourceMode: source)
        var dest: [String: String] = [:]
        for key in ThemeInputKey.defaultKeys {
            dest[key.rawValue] = generated[key] ?? CustomTheme.starterInput[destination]?[key]
        }
        for key in ThemeInputKey.advancedKeys {
            if let value = generated[key] { dest[key.rawValue] = value }
        }
        input[destination.rawValue] = dest
    }

    public var typedInput: [ThemeMode: [ThemeInputKey: String]] {
        var out: [ThemeMode: [ThemeInputKey: String]] = [:]
        for mode in ThemeMode.allCases {
            var keys: [ThemeInputKey: String] = [:]
            for (raw, hex) in input[mode.rawValue] ?? [:] {
                if let key = ThemeInputKey(rawValue: raw) { keys[key] = hex }
            }
            out[mode] = keys
        }
        return out
    }

    public var themeVariant: ThemeVariant { ThemeVariant(rawValue: variant) ?? .balanced }

    public func compiled() -> CompiledTheme {
        ThemeCompiler.compile(input: typedInput, variant: themeVariant, advancedEnabled: advancedOptionsEnabled)
    }

    // MARK: Bridge to the app's selection

    public static let bridgePrefix = "custom_"

    /// The id the app selects this theme by in one mode.
    public func themeID(mode: ThemeMode) -> String { "\(Self.bridgePrefix)\(id)_\(mode.rawValue)" }

    /// The custom theme id and mode behind a bridged `Theme` id.
    public static func parse(themeID: String) -> (id: String, mode: ThemeMode)? {
        guard themeID.hasPrefix(bridgePrefix) else { return nil }
        let rest = themeID.dropFirst(bridgePrefix.count)
        for mode in ThemeMode.allCases where rest.hasSuffix("_\(mode.rawValue)") {
            return (String(rest.dropLast(mode.rawValue.count + 1)), mode)
        }
        return nil
    }

    public func asTheme(mode: ThemeMode) -> Theme {
        let accent = compiled().rgb(.accent, mode: mode)
        return Theme(id: themeID(mode: mode), name: name,
                     accentColorHex: ThemeColorMath.hexString(accent),
                     commentDepthColorHexes: GalleryTheme.commentDepthHexes(fromAccent: accent),
                     isDark: mode == .dark, isGenerated: true, commentPaletteName: nil,
                     voteArrowsAccent: voteArrowsAccent)
    }

    // MARK: Portable file (Reborn's schema v3 export, so files move both ways)

    public static let schemaVersion = 3

    public func exportData() -> Data? {
        var portable: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "name": name,
            "variant": themeVariant.rawValue,
            "advancedOptionsEnabled": advancedOptionsEnabled,
        ]
        var exported = input
        if !advancedOptionsEnabled {
            for mode in exported.keys {
                for key in ThemeInputKey.advancedKeys { exported[mode]?.removeValue(forKey: key.rawValue) }
            }
        }
        portable["input"] = exported
        if font != .system { portable["font"] = font.rawValue }
        return try? JSONSerialization.data(withJSONObject: portable, options: [.prettyPrinted, .sortedKeys])
    }

    public enum ImportError: Error, Equatable {
        case notATheme, missingColours, unsupportedVersion(Int)

        public var message: String {
            switch self {
            case .notATheme: return "Not a valid theme file."
            case .missingColours: return "Theme file is missing colours."
            case .unsupportedVersion(let v): return "Unsupported theme version (\(v))."
            }
        }
    }

    /// Reads a theme file (Reborn's import); always a new theme.
    public static func parse(fileData data: Data) throws -> CustomTheme {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.notATheme
        }
        let schema = (object["schemaVersion"] as? NSNumber)?.intValue ?? 0
        guard let raw = object["input"] as? [String: Any] else { throw ImportError.missingColours }
        if schema > schemaVersion { throw ImportError.unsupportedVersion(schema) }
        var typed: [ThemeMode: [ThemeInputKey: String]] = [:]
        for mode in ThemeMode.allCases {
            var keys: [ThemeInputKey: String] = [:]
            for (k, v) in raw[mode.rawValue] as? [String: Any] ?? [:] {
                if let key = ThemeInputKey(rawValue: k), let hex = v as? String { keys[key] = hex }
            }
            typed[mode] = keys
        }
        let hasAdvanced = typed.values.contains { $0.keys.contains { ThemeInputKey.advancedKeys.contains($0) } }
        return CustomTheme(name: object["name"] as? String ?? "Imported Theme", input: typed,
                           variant: ThemeVariant(rawValue: object["variant"] as? String ?? "") ?? .balanced,
                           advancedOptionsEnabled: object["advancedOptionsEnabled"] as? Bool ?? hasAdvanced,
                           font: ThemeFont(rawValue: object["font"] as? String ?? "") ?? .system,
                           origin: .imported)
    }

    public var exportFilename: String {
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        return (safe.isEmpty ? "theme" : safe) + ".json"
    }

    // MARK: Normalising

    /// Reborn's starter input: the five surfaces per mode, advanced unset.
    public static let starterInput: [ThemeMode: [ThemeInputKey: String]] = [
        .light: [.accent: "FF5A5F", .background: "F2F2F7", .card: "FFFFFF", .raised: "E5E5EA", .bars: "F7F7F7"],
        .dark: [.accent: "FF6B70", .background: "000000", .card: "1C1C1E", .raised: "2C2C2E", .bars: "0A0A0A"],
    ]

    static func normalized(_ input: [ThemeMode: [ThemeInputKey: String]]) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for mode in ThemeMode.allCases {
            var keys: [String: String] = [:]
            for (key, hex) in input[mode] ?? [:] {
                if let rgb = ThemeColorMath.parseHex(hex) { keys[key.rawValue] = ThemeColorMath.hexString(rgb) }
            }
            for key in ThemeInputKey.defaultKeys where keys[key.rawValue] == nil {
                keys[key.rawValue] = starterInput[mode]?[key]
            }
            out[mode.rawValue] = keys
        }
        return out
    }

    static func clampName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "Untitled Theme" : trimmed).prefix(60))
    }
}

/// The user's custom themes.
public enum CustomThemeStore {
    private static let key = "com.pendo324.Phoebus.customThemes"
    public static let didChangeNotification = Notification.Name("com.pendo324.Phoebus.customThemesDidChange")

    public static func all() -> [CustomTheme] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let themes = try? JSONDecoder().decode(LossyArray<CustomTheme>.self, from: data) else { return [] }
        return themes.elements
    }

    public static func theme(id: String) -> CustomTheme? {
        all().first { $0.id == id }
    }

    /// A bridged `Theme` id back to its custom theme.
    public static func theme(forThemeID themeID: String) -> CustomTheme? {
        CustomTheme.parse(themeID: themeID).flatMap { theme(id: $0.id) }
    }

    /// Both modes of every custom theme, for the app's theme lookup.
    public static func bridgedThemes() -> [Theme] {
        all().flatMap { [$0.asTheme(mode: .light), $0.asTheme(mode: .dark)] }
    }

    @discardableResult
    public static func add(_ theme: CustomTheme) -> CustomTheme {
        var theme = theme
        var themes = all()
        theme.name = uniqueName(theme.name, among: themes)
        themes.append(theme)
        save(themes)
        return theme
    }

    public static func update(_ id: String, _ mutate: (inout CustomTheme) -> Void) {
        var themes = all()
        guard let index = themes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&themes[index])
        themes[index].name = uniqueName(themes[index].name, among: themes, excluding: id)
        save(themes)
    }

    public static func delete(_ id: String) {
        save(all().filter { $0.id != id })
    }

    /// "My Theme", then "My Theme 2", …
    public static func uniqueName(_ name: String, among themes: [CustomTheme], excluding id: String? = nil) -> String {
        let taken = Set(themes.filter { $0.id != id }.map(\.name))
        guard taken.contains(name) else { return name }
        for i in 2..<1000 where !taken.contains("\(name) \(i)") { return "\(name) \(i)" }
        return name + " " + UUID().uuidString.prefix(4)
    }

    private static func save(_ themes: [CustomTheme]) {
        guard let data = try? JSONEncoder().encode(themes) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
