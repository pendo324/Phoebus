import Foundation

/// Reborn's "Liquid Glass" app icon category: a community-contributed icon
/// pack structure of icon sets grouped under Apollo, Classics, Helios and
/// Concepts, each credited to its designer ("Canon by iGerman00", "OG by
/// jryng", ...). `AppIconOption`'s catalog mirrors this category and
/// attribution structure rather than a flat grid.
///
/// Excludes the registry's `standardPack: "ultra"` entries (Ultra-tier
/// icons), which never appear in Liquid Glass pack grids; only entries
/// with a `group` are Liquid Glass icons.
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

    /// The Liquid Glass catalog, excluding Ultra-tier `standardPack` entries.
    public static let all: [LiquidGlassIconOption] = [
        LiquidGlassIconOption(id: "apollo", displayName: "Apollo", designer: "IllIIllIllIllII", groupID: "original"),
        LiquidGlassIconOption(id: "AppIcon", displayName: "Apollo Glass", designer: "IllIIllIllIllII", groupID: "original"),
        LiquidGlassIconOption(id: "halo", displayName: "Halo", designer: "IllIIllIllIllII", groupID: "original"),
        LiquidGlassIconOption(id: "halo-glass", displayName: "Halo Glass", designer: "IllIIllIllIllII", groupID: "original"),
        LiquidGlassIconOption(id: "apollo-classic", displayName: "Apollo Classic", designer: "IllIIllIllIllII", groupID: "original"),
        LiquidGlassIconOption(id: "aloppo-v2", displayName: "Aloppo", designer: "IllIIllIllIllII", groupID: "original"),
        LiquidGlassIconOption(id: "igerman00", displayName: "Canon", designer: "iGerman00", groupID: "original"),
        LiquidGlassIconOption(id: "jryng", displayName: "OG", designer: "jryng", groupID: "original"),
        LiquidGlassIconOption(id: "metalnakls", displayName: "metalnakls", designer: "metalnakls", groupID: "original"),
        LiquidGlassIconOption(id: "harunatsu", displayName: "harunatsu", designer: "harunatsu91202024", groupID: "original"),
        LiquidGlassIconOption(id: "LG-morty", displayName: "Wubalubadubdub", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-duck", displayName: "Wilson", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-antenna", displayName: "Irradiate", designer: "jryng", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-spaceship", displayName: "Stanley", designer: "jryng", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-burnt-orange", displayName: "Nuclear Sunset", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-green", displayName: "Danger Noodle", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-dark", displayName: "Lumos", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-orange", displayName: "Hugo", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-purple", displayName: "Great Googly Moogly", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-white", displayName: "Dark Link", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-pink", displayName: "Jibbles", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-gold", displayName: "I Love Goooold", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-crimson", displayName: "Ruby", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-blueberry", displayName: "Blueberry Breath", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-calico", displayName: "Calico", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-castro", displayName: "Beware the Turtles", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-teal", displayName: "Under the Sea", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-brown", displayName: "Tremors", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-sunset", displayName: "Crimson", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-gravel-juice", displayName: "Gravel Juice", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-gray", displayName: "Deep Space", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-chosen-one", displayName: "Chosen One", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-enter-the-state", displayName: "Enter the State", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-rule-of-two", displayName: "Rule of Two", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-galactic-zoomer", displayName: "Galactic Zoomer", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-six-colors", displayName: "Six Colors", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-stonewall", displayName: "Stonewall", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-trans", displayName: "Helms", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-pride", displayName: "Pride", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-clearly-combustion", displayName: "Clearly Combustion", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-dino-spoon", displayName: "Dino Spoon", designer: "jryng", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-apollos6", displayName: "ApollOS 6", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-atp", displayName: "ATP", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-canada", displayName: "Canada D'Eh", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-ernest", displayName: "Ernest", designer: "jryng", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-slothkun", displayName: "Sloth-Kun", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-dave2d", displayName: "Teal All the Things", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-red-black-white", displayName: "Apollo: First App in 8K?", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-camera-pool", displayName: "Wrapping Paper", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-peachy", displayName: "Peachy", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-sandals", displayName: "Sandals 'n Socks", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-andru", displayName: "Pro Wrestler", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-rene", displayName: "A+ Intontaion", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-tld", displayName: "Yo. Jonathan Here.", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-snazzy", displayName: "Margaret", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "LG-eap", displayName: "Icons Drop Test", designer: "IllIIllIllIllII", groupID: "classics"),
        LiquidGlassIconOption(id: "bajader-aperture-science", displayName: "Aperture Science", designer: "bajader", groupID: "concepts"),
        LiquidGlassIconOption(id: "bajader-apollos", displayName: "ApollOS", designer: "bajader", groupID: "concepts"),
        LiquidGlassIconOption(id: "bajader-glitched", displayName: "Glitched", designer: "bajader", groupID: "concepts"),
        LiquidGlassIconOption(id: "bajader-rtr", displayName: "Right to Repair", designer: "bajader", groupID: "concepts"),
        LiquidGlassIconOption(id: "bajader-sunset", displayName: "Sunset", designer: "bajader", groupID: "concepts"),
        LiquidGlassIconOption(id: "paulo1manso-modern", displayName: "Modern", designer: "paulo1manso", groupID: "concepts"),
        LiquidGlassIconOption(id: "paulo1manso-modern-alt", displayName: "Modern Alt", designer: "paulo1manso", groupID: "concepts"),
        LiquidGlassIconOption(id: "synthwave", displayName: "Synthwave", designer: "IllIIllIllIllII", groupID: "concepts"),
        LiquidGlassIconOption(id: "toon-bot", displayName: "Toon Bot", designer: "IllIIllIllIllII", groupID: "concepts"),
        LiquidGlassIconOption(id: "toon-bot-2", displayName: "Happy Toon Bot", designer: "IllIIllIllIllII", groupID: "concepts"),
        LiquidGlassIconOption(id: "jryng-red", displayName: "Red", designer: "jryng", groupID: "concepts"),
        LiquidGlassIconOption(id: "helios", displayName: "Helios", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-halo", displayName: "Helios Halo", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-legacy", displayName: "Legacy", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-tribute", displayName: "Tribute", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-cryo", displayName: "Cryo", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-cryo-halo", displayName: "Cryo Halo", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-parallax", displayName: "Parallax", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-parallax-halo", displayName: "Parallax Halo", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-ultra", displayName: "Ultra", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-ultra-halo", displayName: "Ultra Halo", designer: "IllIIllIllIllII", groupID: "helios"),
        LiquidGlassIconOption(id: "helios-pixel", displayName: "Pixels", designer: "IllIIllIllIllII", groupID: "helios"),
    ]

    /// Icons grouped by their group, in the registry's group order.
    public static var groupedByGroup: [(group: LiquidGlassIconGroup, icons: [LiquidGlassIconOption])] {
        LiquidGlassIconGroup.all.map { group in
            (group, all.filter { $0.groupID == group.id })
        }
    }
}

/// One of the four Liquid Glass groups.
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
        LiquidGlassIconGroup(id: "original", title: "Apollo", iconDescription: "The original Apollo icon in Liquid Glass, crafted by the community.", coverIconIDs: ["apollo-classic", "halo-glass", "AppIcon"]),
        LiquidGlassIconGroup(id: "classics", title: "Classics", iconDescription: "Dozens of colorful variants and one-off designs from the original Apollo app, recreated in Liquid Glass.", coverIconIDs: ["LG-white", "LG-crimson", "LG-galactic-zoomer"]),
        LiquidGlassIconGroup(id: "helios", title: "Helios", iconDescription: "Icons inspired by the Hyper Suit 4000 icon from Apollo, and the Modern icons by paulo1manso.", coverIconIDs: ["helios-legacy", "helios-cryo", "helios"]),
        LiquidGlassIconGroup(id: "concepts", title: "Concepts", iconDescription: "A mix of standalone icon concepts, including small thematic sets too short for their own pack.", coverIconIDs: ["paulo1manso-modern", "bajader-rtr", "toon-bot-2"]),
    ]
}
