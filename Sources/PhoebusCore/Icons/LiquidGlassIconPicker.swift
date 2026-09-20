import Foundation

/// The three icon appearances Reborn's Liquid Glass picker offers.
///
/// Titles are "Light"/"Dark"/"System", glyphs are `sun.max`, `moon`,
/// `circle.lefthalf.filled`, and Light/Dark append an alternate-icon
/// name suffix. Dynamic uses the bare icon ID with no suffix.
public enum LiquidGlassIconAppearance: Int, Sendable, CaseIterable {
    case light = 0
    case dark = 1
    case system = 2

    public var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    public var systemImageName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    /// Light and Dark append a suffix, Dynamic ("System") uses the
    /// bare ID.
    public func alternateIconName(for iconID: String) -> String {
        switch self {
        case .light: return "\(iconID)__apollo_light"
        case .dark: return "\(iconID)__apollo_dark"
        case .system: return iconID
        }
    }

    /// The preview variant this mode shows: Light shows "default",
    /// Dark shows "dark", and System follows the phone.
    public func previewVariant(systemIsDark: Bool) -> String {
        switch self {
        case .light: return "default"
        case .dark: return "dark"
        case .system: return systemIsDark ? "dark" : "default"
        }
    }
}

/// Persists the chosen appearance so the value survives the same way
/// Reborn's does.
public enum LiquidGlassIconAppearanceStore {
    public static let defaultsKey = "ApolloLGPreferredIconAppearance"

    public static func load(
        _ defaults: UserDefaults = .standard
    ) -> LiquidGlassIconAppearance {
        // Validates the stored integer is in range and falls back to
        // Dynamic otherwise.
        guard let stored = defaults.object(forKey: defaultsKey) as? Int,
              let mode = LiquidGlassIconAppearance(rawValue: stored) else {
            return .system
        }
        return mode
    }

    public static func save(
        _ mode: LiquidGlassIconAppearance,
        to defaults: UserDefaults = .standard
    ) {
        storage.save(mode, to: defaults)
    }

    public static let storage = CustomSettingsSource<LiquidGlassIconAppearance>(
        key: defaultsKey, load: { load($0) }, save: { mode, defaults in defaults.set(mode.rawValue, forKey: defaultsKey) })
}

/// Reborn's "Daily Spotlight" row: five Liquid Glass icons that change
/// once per calendar day and stay put for the rest of it.
///
/// This is a direct port of Reborn's own generator: the same xorshift
/// generator, seed, three shuffles in the same order, and "deliberately
/// span at least 3 packs" rule. Any PRNG divergence would make the lineup
/// jump around within a single day.
public enum LiquidGlassDailySpotlight {
    public static let count = 5

    public static let dayDefaultsKey = "ApolloLGDailyFeaturedDay"
    public static let idsDefaultsKey = "ApolloLGDailyFeaturedIDs"

    /// year*10000 + month*100 + day.
    public static func dayIdentifier(
        for date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// An xorshift64 star. Written with `&*` / `&<<` so Swift's
    /// overflow traps do not reject the wrapping arithmetic C does
    /// implicitly here.
    static func randomNext(_ state: inout UInt64) -> UInt64 {
        var value = state
        value ^= value >> 12
        value ^= value << 25
        value ^= value >> 27
        state = value
        return value &* 2_685_821_657_736_338_717
    }

    /// The five icon IDs for a given day.
    ///
    /// - Parameter excluded: the previous day's lineup plus the active
    ///   icon, so a fresh day does not repeat yesterday or show the
    ///   icon already in use.
    public static func icons(
        forDay dayIdentifier: Int,
        excluding excluded: Set<String> = [],
        catalog: [LiquidGlassIconOption] = LiquidGlassIconOption.all,
        groups: [LiquidGlassIconGroup] = LiquidGlassIconGroup.all
    ) -> [String] {
        // Candidates are walked group by group, in registry order, so
        // the pre-shuffle ordering matches Reborn's nested loop.
        var candidates: [(id: String, groupIndex: Int)] = []
        for (groupIndex, group) in groups.enumerated() {
            for icon in catalog where icon.groupID == group.id {
                guard !excluded.contains(icon.id) else { continue }
                candidates.append((icon.id, groupIndex))
            }
        }
        guard !candidates.isEmpty else { return [] }

        var state = (UInt64(bitPattern: Int64(dayIdentifier)) << 32) ^ 0xA901_10DA_17F3_4D6B

        // Fisher-Yates over the candidates.
        if candidates.count > 1 {
            for i in stride(from: candidates.count - 1, to: 0, by: -1) {
                let j = Int(randomNext(&state) % UInt64(i + 1))
                candidates.swapAt(i, j)
            }
        }

        // Then over the group order, so which packs get first pick
        // also rotates daily.
        var groupOrder = Array(groups.indices)
        if groupOrder.count > 1 {
            for i in stride(from: groupOrder.count - 1, to: 0, by: -1) {
                let j = Int(randomNext(&state) % UInt64(i + 1))
                groupOrder.swapAt(i, j)
            }
        }

        var used = Array(repeating: false, count: candidates.count)
        var selected: [String] = []

        // "the selection deliberately spans at least 3 packs"
        let requiredGroups = min(3, groups.count)
        for wantedGroup in groupOrder where selected.count < requiredGroups {
            for index in candidates.indices
            where !used[index] && candidates[index].groupIndex == wantedGroup {
                used[index] = true
                selected.append(candidates[index].id)
                break
            }
        }
        // Fill the rest from whatever is left, in shuffled order.
        for index in candidates.indices where selected.count < count {
            guard !used[index] else { continue }
            used[index] = true
            selected.append(candidates[index].id)
        }

        // A final shuffle so the group-spanning picks are not always
        // the leftmost cards.
        if selected.count > 1 {
            for i in stride(from: selected.count - 1, to: 0, by: -1) {
                let j = Int(randomNext(&state) % UInt64(i + 1))
                selected.swapAt(i, j)
            }
        }
        return selected
    }
}

/// Apollo's own (non-Liquid-Glass) icons, which Reborn presents as four
/// packs rather than one flat list.
///
/// Names, counts, and cover icon IDs are verbatim from Reborn. The counts
/// are Reborn's hardcoded numbers, since the flat `AppIconOption.all` has
/// no section information to derive them from.
public struct StandardIconPack: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// The pushed list's title and its section header (Apollo's "Community
    /// Pack" / "Community Icons").
    public let screenTitle: String
    public let sectionTitle: String
    /// Apollo's own picker order, with Reborn's Ultra additions where Reborn
    /// places them.
    public let iconIDs: [String]
    public let coverIconIDs: [String]

    public var iconCount: Int { iconIDs.count }

    public var icons: [AppIconOption] {
        iconIDs.compactMap { id in AppIconOption.all.first { $0.id == id } }
    }

    public init(id: String, title: String, screenTitle: String, sectionTitle: String,
                iconIDs: [String], coverIconIDs: [String]) {
        self.id = id
        self.title = title
        self.screenTitle = screenTitle
        self.sectionTitle = sectionTitle
        self.iconIDs = iconIDs
        self.coverIconIDs = coverIconIDs
    }

    public static let all: [StandardIconPack] = [
        StandardIconPack(id: "originals", title: "Originals", screenTitle: "Originals", sectionTitle: "Original Icons", iconIDs: [
            "original", "morty", "duck", "antenna", "spaceship", "burnt-orange", "green", "dark", "orange",
            "purple", "white", "pink", "gold", "crimson", "blueberry", "calico", "castro", "teal", "brown",
            "sunset", "gravel-juice", "gray", "chosen-one", "enter-the-state", "rule-of-two",
            "galactic-zoomer", "six-colors", "stonewall", "trans", "pride", "clearly-combustion",
            "dino-spoon"
        ], coverIconIDs: ["gold", "calico", "teal"]),
        StandardIconPack(id: "community", title: "Community", screenTitle: "Community Pack", sectionTitle: "Community Icons", iconIDs: [
            "neon-glow", "bluesteroid", "poe-the-space-ghost", "ones-and-zeroes", "blast-off", "retrowave",
            "glitch", "pie-in-the-sky", "knight", "launched", "magma", "apollo-san", "rimuru", "surprised",
            "canvas-painting", "floaty-boy", "nelson", "broby", "no-space"
        ], coverIconIDs: ["apollo-san", "rimuru", "surprised"]),
        StandardIconPack(id: "ultra", title: "Ultra", screenTitle: "Ultra", sectionTitle: "Ultra Icons", iconIDs: [
            "hyper-suit-4000", "the-adventurer", "ye-snow-guardian", "the-orbit-of-gargantua", "ice-bot",
            "cuddleb0t", "the-little-prince", "the-little-prince-ii", "wish-maker", "wish-maker-ii",
            "ducky-buddy", "mechapollo", "the-copper-giant", "jackopollo", "void-emperor",
            "sir-yule-treemas", "decade-of-frosting", "apollobot", "stringfish", "floating", "forest-spirit",
            "mechapollo2", "castiel", "demogorgon", "rosso", "apolloween", "smiles", "explorer-of-smiles-ii",
            "george", "space-shanty", "roary", "sasageyo", "detective", "tapioca", "coconut-head",
            "gorilla-gus", "gorilla-gus-ii", "apollo-a1", "chippie", "gordon-ramesses", "dr-spaceman",
            "santapollo", "diving-for-upvotes", "icarusbot", "midasbot", "mr-neep-neep", "neptunebot",
            "shadowbot", "jonybot", "year-of-the-tiger", "macrodata-refinement", "waving-yolkstronaut",
            "starry-eyed", "stuart-from-saturn", "scan-lines", "sea-are-tea", "obsidian", "shakey-shakey",
            "frankenpollo", "apollopy", "under-the-tree", "under-the-tree-ii", "under-the-tree-iii",
            "apollomoji", "notebook", "year-of-the-rabbit", "throckmorton", "squingus", "blorbo",
            "low-battery", "eggius-cuniculus", "apollos6", "felt-and-feels", "mr-banks", "mr-eyes",
            "mr-moustache", "palette", "mighty-apollo", "royalty", "food-bank", "planetary-pod",
            "macaroni-and-apollo", "metal-cap", "cheese-rock", "upvote-eater", "rainbow-visor",
            "in-the-jungle", "space-paws", "grumpy-space-paws", "spca"
        ], coverIconIDs: ["wish-maker", "in-the-jungle", "the-little-prince"]),
        StandardIconPack(id: "sekrit", title: "Sekrit", screenTitle: "Sekrit", sectionTitle: "Sekrit Icons", iconIDs: [
            "atp", "phil", "canada", "ukraine", "murica", "usa2", "uk", "ernest", "slothkun", "sus",
            "dave2d", "red-black-white", "camera-pool", "peachy", "sandals", "andru", "rene", "tld",
            "snazzy", "apollobook-pro", "beans", "eap"
        ], coverIconIDs: ["beans", "sus", "apollobook-pro"]),
    ]
}

/// The Liquid Glass icon last applied (Reborn tracks it separately):
/// iOS's `alternateIconName` can't be trusted for it on sideloaded
/// installs, so the picker keeps its own record. Nil while a standard
/// icon is chosen.
public enum LiquidGlassActiveIconStore {
    public static let defaultsKey = "ApolloLGActiveIconID"

    public static func load(_ defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: defaultsKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func save(_ iconID: String?, _ defaults: UserDefaults = .standard) {
        if let iconID { defaults.set(iconID, forKey: defaultsKey) } else { defaults.removeObject(forKey: defaultsKey) }
    }
}
