import Foundation

/// Reborn's "Liquid Glass" app icon category: icon packs shown as cards,
/// each icon credited to its designer. Phoebus fills it with its own two
/// packs, Phoebus and Always Dark (`Icons/LiquidGlass`), in place of
/// Reborn's community packs.
public struct LiquidGlassIconOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let designer: String
    public let groupID: String

    public init(id: String, displayName: String, designer: String, groupID: String) {
        self.id = id
        self.displayName = displayName
        self.designer = designer
        self.groupID = groupID
    }

    /// Follows the `CFBundleAlternateIcons` key convention of the base
    /// `AppIconOption` catalog (`AppIcon-<id>`), namespaced separately
    /// (`LGIcon-<id>`) since a Liquid Glass icon's ID can collide with a base
    /// one (`AppIcon` is both).
    public var alternateIconName: String {
        "LGIcon-\(id)"
    }

    /// Phoebus's own icons, in `Icons/source/set.json`'s order. Phoebus is
    /// also the primary icon.
    public static let all: [LiquidGlassIconOption] = [
        LiquidGlassIconOption(id: "phoebus", displayName: "Phoebus", designer: "pendo324", groupID: "phoebus"),
        LiquidGlassIconOption(id: "dusk", displayName: "Dusk", designer: "pendo324", groupID: "phoebus"),
        LiquidGlassIconOption(id: "classic", displayName: "Classic", designer: "pendo324", groupID: "phoebus"),
        LiquidGlassIconOption(id: "sky", displayName: "Sky", designer: "pendo324", groupID: "phoebus"),
        LiquidGlassIconOption(id: "lagoon", displayName: "Lagoon", designer: "pendo324", groupID: "phoebus"),
        LiquidGlassIconOption(id: "nebula", displayName: "Nebula", designer: "pendo324", groupID: "phoebus"),
        LiquidGlassIconOption(id: "cloud", displayName: "Cloud", designer: "pendo324", groupID: "phoebus"),
        LiquidGlassIconOption(id: "midnight", displayName: "Midnight", designer: "pendo324", groupID: "always-dark"),
        LiquidGlassIconOption(id: "twilight", displayName: "Twilight", designer: "pendo324", groupID: "always-dark"),
        LiquidGlassIconOption(id: "graphite", displayName: "Graphite", designer: "pendo324", groupID: "always-dark"),
    ]

    /// Icons grouped by their group, in the registry's group order.
    public static var groupedByGroup: [(group: LiquidGlassIconGroup, icons: [LiquidGlassIconOption])] {
        LiquidGlassIconGroup.all.map { group in
            (group, all.filter { $0.groupID == group.id })
        }
    }
}

/// One of the Liquid Glass packs.
public struct LiquidGlassIconGroup: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let iconDescription: String
    /// The three icons fanned across the group's card, from the registry's
    /// `coverIconIDs`. An editorial pick, not the group's first three members,
    /// so it is carried rather than derived.
    public let coverIconIDs: [String]

    public init(id: String, title: String, iconDescription: String,
                coverIconIDs: [String] = []) {
        self.id = id
        self.title = title
        self.iconDescription = iconDescription
        self.coverIconIDs = coverIconIDs
    }

    public static let all: [LiquidGlassIconGroup] = [
        LiquidGlassIconGroup(id: "phoebus", title: "Phoebus", iconDescription: "Phoebus's own icon by day, and its night look in dark mode.", coverIconIDs: ["nebula", "sky", "phoebus"]),
        LiquidGlassIconGroup(id: "always-dark", title: "Always Dark", iconDescription: "Phoebus on a night sky all day, a step deeper in dark mode.", coverIconIDs: ["graphite", "twilight", "midnight"]),
    ]
}
