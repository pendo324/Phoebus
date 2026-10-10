import Foundation

/// Where a piece of text sits, for the per-role sizes and font families of
/// Settings > Appearance > Text Sizes & Fonts. Not an Apollo or Reborn
/// setting: Apollo has only the one app-wide text size.
public enum TextRole: String, CaseIterable, Sendable {
    case postTitle
    case postMeta
    case openedPostTitle
    case postBody
    case commentHeader
    case commentBody
    case linkCard
    /// Everything not assigned a role; follows the app-wide size and the
    /// system font (or a custom theme's) only.
    case other

    /// The roles with their own size control, in settings order.
    public static let scalable: [TextRole] = allCases.filter { $0 != .other }

    public var title: String {
        switch self {
        case .postTitle: return "Post Titles"
        case .postMeta: return "Post Details"
        case .openedPostTitle: return "Opened Post Title"
        case .postBody: return "Post Text"
        case .commentHeader: return "Comment Headers"
        case .commentBody: return "Comment Text"
        case .linkCard: return "Link Previews"
        case .other: return "Everything Else"
        }
    }

    /// The font picker the role follows; nil for `.other`.
    public var fontGroup: TextFontGroup? {
        switch self {
        case .postTitle, .openedPostTitle: return .titles
        case .postBody, .commentBody: return .content
        case .postMeta, .commentHeader, .linkCard: return .interface
        case .other: return nil
        }
    }
}

/// Which font picker a role follows.
public enum TextFontGroup: String, CaseIterable, Sendable {
    case titles
    case content
    case interface

    public var title: String {
        switch self {
        case .titles: return "Titles"
        case .content: return "Content"
        case .interface: return "Interface"
        }
    }
}

/// The built-in families, each a system font design so Dynamic Type and
/// weights keep working.
public enum TextFontFamily: String, Codable, CaseIterable, Sendable {
    case system
    case rounded
    /// New York.
    case serif
    case monospaced

    public var title: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        }
    }
}

public struct TextScaleSettings: Codable, Equatable, Sendable {
    public var postTitleScale: Double
    public var postMetaScale: Double
    public var openedPostTitleScale: Double
    public var postBodyScale: Double
    public var commentHeaderScale: Double
    public var commentBodyScale: Double
    public var linkCardScale: Double
    public var titleFont: TextFontFamily
    public var contentFont: TextFontFamily
    public var interfaceFont: TextFontFamily

    /// 80%...150% in 5% steps, on top of the app-wide text size.
    public static let scaleRange: ClosedRange<Double> = 0.8...1.5
    public static let scaleStep: Double = 0.05

    public static let `default` = TextScaleSettings()

    public init(
        postTitleScale: Double = 1,
        postMetaScale: Double = 1,
        openedPostTitleScale: Double = 1,
        postBodyScale: Double = 1,
        commentHeaderScale: Double = 1,
        commentBodyScale: Double = 1,
        linkCardScale: Double = 1,
        titleFont: TextFontFamily = .system,
        contentFont: TextFontFamily = .system,
        interfaceFont: TextFontFamily = .system
    ) {
        self.postTitleScale = postTitleScale
        self.postMetaScale = postMetaScale
        self.openedPostTitleScale = openedPostTitleScale
        self.postBodyScale = postBodyScale
        self.commentHeaderScale = commentHeaderScale
        self.commentBodyScale = commentBodyScale
        self.linkCardScale = linkCardScale
        self.titleFont = titleFont
        self.contentFont = contentFont
        self.interfaceFont = interfaceFont
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func scale(_ key: CodingKeys) -> Double {
            (try? container.decodeIfPresent(Double.self, forKey: key)) ?? 1
        }
        func family(_ key: CodingKeys) -> TextFontFamily {
            (try? container.decodeIfPresent(TextFontFamily.self, forKey: key)) ?? .system
        }
        postTitleScale = scale(.postTitleScale)
        postMetaScale = scale(.postMetaScale)
        openedPostTitleScale = scale(.openedPostTitleScale)
        postBodyScale = scale(.postBodyScale)
        commentHeaderScale = scale(.commentHeaderScale)
        commentBodyScale = scale(.commentBodyScale)
        linkCardScale = scale(.linkCardScale)
        titleFont = family(.titleFont)
        contentFont = family(.contentFont)
        interfaceFont = family(.interfaceFont)
    }

    private static func keyPath(for role: TextRole) -> WritableKeyPath<TextScaleSettings, Double>? {
        switch role {
        case .postTitle: return \.postTitleScale
        case .postMeta: return \.postMetaScale
        case .openedPostTitle: return \.openedPostTitleScale
        case .postBody: return \.postBodyScale
        case .commentHeader: return \.commentHeaderScale
        case .commentBody: return \.commentBodyScale
        case .linkCard: return \.linkCardScale
        case .other: return nil
        }
    }

    /// Snaps to a 5% step inside `scaleRange`.
    public static func snapped(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1 }
        // Divided rather than multiplied by the step so 130% stores as 1.3.
        let stepped = (scale / scaleStep).rounded() / (1 / scaleStep)
        return min(max(stepped, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// The role's multiplier, clamped; `.other` is always 1.
    public func scale(for role: TextRole) -> Double {
        guard let keyPath = Self.keyPath(for: role) else { return 1 }
        let value = self[keyPath: keyPath]
        guard value.isFinite else { return 1 }
        return min(max(value, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    public mutating func setScale(_ scale: Double, for role: TextRole) {
        guard let keyPath = Self.keyPath(for: role) else { return }
        self[keyPath: keyPath] = Self.snapped(scale)
    }

    public func family(for group: TextFontGroup) -> TextFontFamily {
        switch group {
        case .titles: return titleFont
        case .content: return contentFont
        case .interface: return interfaceFont
        }
    }

    public mutating func setFamily(_ family: TextFontFamily, for group: TextFontGroup) {
        switch group {
        case .titles: titleFont = family
        case .content: contentFont = family
        case .interface: interfaceFont = family
        }
    }

    /// The family a role draws in, or nil for the surrounding font design
    /// (System, or a custom theme's font), which System always leaves alone.
    public func resolvedFamily(for role: TextRole) -> TextFontFamily? {
        guard let group = role.fontGroup else { return nil }
        let family = family(for: group)
        return family == .system ? nil : family
    }

    /// The point size for `base` (already scaled for Dynamic Type) in `role`.
    public func pointSize(_ base: Double, role: TextRole) -> Double {
        base * scale(for: role)
    }
}

public enum TextScaleSettingsStore {
    public static let storage = SettingsStore<TextScaleSettings>(
        key: "com.pendo324.Phoebus.textScaleSettings") { TextScaleSettings.default }

    public static func load() -> TextScaleSettings { storage.load() }
}

extension TextScaleSettings: StoredSettingsModel {
    public static var store: SettingsStore<TextScaleSettings> { TextScaleSettingsStore.storage }
}
