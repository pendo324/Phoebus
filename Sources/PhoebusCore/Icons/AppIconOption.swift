import Foundation

/// Apollo's App Icon picker / Community Icon Pack: 155 named alternate icons,
/// with Reborn's additions. The artwork is Apollo's own, extracted from its
/// IPA at build time (`scripts/generate-icons.sh`).
public struct AppIconOption: Sendable, Equatable, Identifiable {
    /// The short identifier, used to build the `CFBundleAlternateIcons` key
    /// (`AppIcon-<id>`) and asset filename.
    public var id: String
    public var displayName: String
    /// The designer Apollo credits under the name, where it does.
    public var artist: String?

    public init(id: String, displayName: String, artist: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.artist = artist
    }

    /// `nil` alternateIconName means the primary icon.
    public var alternateIconName: String? {
        id == "original" ? nil : "AppIcon-\(id)"
    }

    /// "Default": the settings root row reads "App Icon · Default".
    public static let original = AppIconOption(id: "original", displayName: "Default")

    /// The complete 155-icon catalog (plus the implicit "Original" primary icon).
    public static let all: [AppIconOption] = [.original] + [
        AppIconOption(id: "obsidian", displayName: "Obsidian", artist: "Ilya Miskov"),
        AppIconOption(id: "detective", displayName: "Man of Mystery", artist: "Matthew Skiles"),
        AppIconOption(id: "magma", displayName: "Magma", artist: "joeyeatsfridays"),
        AppIconOption(id: "upvote-eater", displayName: "Upvote Eater", artist: "Matthew Skiles"),
        AppIconOption(id: "gorilla-gus", displayName: "Gorilla Gus", artist: "Alfrey Davilla"),
        AppIconOption(id: "in-the-jungle", displayName: "Safari", artist: "Matthew Skiles"),
        // Reborn's own Ultra additions.
        AppIconOption(id: "the-little-prince-ii", displayName: "The Little Prince II", artist: "Anh Nguyen"),
        AppIconOption(id: "wish-maker-ii", displayName: "Wish Maker II", artist: "Michael Myers"),
        AppIconOption(id: "explorer-of-smiles-ii", displayName: "Explorer of Smiles II", artist: "Raphael Lopes"),
        AppIconOption(id: "gorilla-gus-ii", displayName: "Gorilla Gus II", artist: "Alfrey Davilla"),
        AppIconOption(id: "under-the-tree-ii", displayName: "Under the Tree II", artist: "Qi Sandor"),
        AppIconOption(id: "under-the-tree-iii", displayName: "Under the Tree III", artist: "Qi Sandor"),
        AppIconOption(id: "space-paws", displayName: "Space Paws", artist: "Raphael Lopes"),
        AppIconOption(id: "grumpy-space-paws", displayName: "Grumpy Space Paws", artist: "Raphael Lopes"),
        AppIconOption(id: "sea-are-tea", displayName: "Sea Are Tea", artist: "Ilya Miskov"),
        AppIconOption(id: "glitch", displayName: "Glitch", artist: "heckingcomputernerd"),
        AppIconOption(id: "spca", displayName: "SPCA", artist: "David Lanham"),
        AppIconOption(id: "beans", displayName: "Beans", artist: "Matthew Skiles"),
        AppIconOption(id: "mr-banks", displayName: "Mr. Banks", artist: "Brad Ellis"),
        AppIconOption(id: "ye-snow-guardian", displayName: "Ye Snow Guardian", artist: "Qi Sandor"),
        AppIconOption(id: "throckmorton", displayName: "Throckmorton", artist: "Adam Whitcroft"),
        AppIconOption(id: "george", displayName: "Gingerbread George", artist: "Qi Sandor"),
        AppIconOption(id: "camera-pool", displayName: "Wrapping Paper"),
        AppIconOption(id: "frankenpollo", displayName: "Frankenpollo", artist: "Matthew Skiles"),
        AppIconOption(id: "mechapollo2", displayName: "Mechapollo Part II", artist: "Jorge Velez"),
        AppIconOption(id: "ernest", displayName: "Ernest"),
        AppIconOption(id: "royalty", displayName: "Royalty", artist: "Yannick Lung"),
        AppIconOption(id: "crimson", displayName: "Ruby"),
        AppIconOption(id: "poe-the-space-ghost", displayName: "Poe the Space Ghost", artist: "hinkeroniarts"),
        AppIconOption(id: "sasageyo", displayName: "Sasageyo", artist: "Gleptech"),
        AppIconOption(id: "hyper-suit-4000", displayName: "Hyper Suit 4000", artist: "Piraino, Maheux (The Iconfactory)"),
        AppIconOption(id: "gray", displayName: "Deep Space"),
        AppIconOption(id: "surprised", displayName: "Surprised", artist: "berrymetal"),
        AppIconOption(id: "year-of-the-tiger", displayName: "Year of the Tiger", artist: "Matthew Skiles & Barry Hershman"),
        AppIconOption(id: "burnt-orange", displayName: "Nuclear Sunset"),
        AppIconOption(id: "white", displayName: "Dark Link"),
        AppIconOption(id: "starry-eyed", displayName: "Starry Eyed", artist: "Raphael Lopes"),
        AppIconOption(id: "food-bank", displayName: "Food Bank", artist: "David Lanham"),
        AppIconOption(id: "mechapollo", displayName: "Mechapollo", artist: "Jorge Velez"),
        AppIconOption(id: "roary", displayName: "Roary the Dragon", artist: "Matthew Skiles"),
        AppIconOption(id: "gravel-juice", displayName: "Gravel Juice"),
        AppIconOption(id: "chippie", displayName: "Chippie", artist: "Michael Flarup"),
        AppIconOption(id: "apollobook-pro", displayName: "ApolloBook Pro"),
        AppIconOption(id: "pink", displayName: "Jibbles"),
        AppIconOption(id: "peachy", displayName: "Peachy"),
        AppIconOption(id: "apollo-san", displayName: "Apollo-san", artist: "Helunky"),
        AppIconOption(id: "planetary-pod", displayName: "Planetary Pod", artist: "Matthew Skiles"),
        AppIconOption(id: "trans", displayName: "Helms"),
        AppIconOption(id: "diving-for-upvotes", displayName: "Diving for Upvotes", artist: "Yannick Lung"),
        AppIconOption(id: "purple", displayName: "Great Googly Moogly"),
        AppIconOption(id: "cheese-rock", displayName: "Cheese Rock", artist: "Matthew Skiles"),
        AppIconOption(id: "dave2d", displayName: "Teal All the Things"),
        AppIconOption(id: "squingus", displayName: "Squingus", artist: "Adam Whitcroft"),
        AppIconOption(id: "mr-eyes", displayName: "Mr. Eyes", artist: "Brad Ellis"),
        AppIconOption(id: "santapollo", displayName: "Santapollo", artist: "Matthew Skiles"),
        AppIconOption(id: "snazzy", displayName: "Margaret"),
        AppIconOption(id: "morty", displayName: "Wubalubadubdub"),
        AppIconOption(id: "clearly-combustion", displayName: "Clearly Combustion"),
        AppIconOption(id: "nelson", displayName: "N.E.L.S.O.N.", artist: "Gavin Nelson"),
        AppIconOption(id: "rene", displayName: "A+ Intontation"),
        AppIconOption(id: "ones-and-zeroes", displayName: "1s and 0s", artist: "flashboy131"),
        AppIconOption(id: "green", displayName: "Danger Noodle"),
        AppIconOption(id: "ukraine", displayName: "Ukraine"),
        AppIconOption(id: "blueberry", displayName: "Blueberry Breath"),
        AppIconOption(id: "space-shanty", displayName: "Space Shanty", artist: "Matthew Skiles"),
        AppIconOption(id: "orange", displayName: "Hugo"),
        AppIconOption(id: "void-emperor", displayName: "Void Emperor", artist: "Jhona Burame"),
        AppIconOption(id: "stuart-from-saturn", displayName: "Stuart from Saturn", artist: "Matthew Skiles"),
        AppIconOption(id: "canvas-painting", displayName: "Canvas Painting", artist: "johnnysilverpaw"),
        AppIconOption(id: "apolloween", displayName: "Apollowe'en", artist: "Anthony Piraino (The Iconfactory)"),
        AppIconOption(id: "atp", displayName: "ATP"),
        AppIconOption(id: "dino-spoon", displayName: "Dino Spoon"),
        AppIconOption(id: "spaceship", displayName: "Stanley"),
        AppIconOption(id: "coconut-head", displayName: "Coconut Head", artist: "Matthew Skiles"),
        AppIconOption(id: "blast-off", displayName: "Blast Off!", artist: "Helunky"),
        AppIconOption(id: "apollo-a1", displayName: "Apollo A1", artist: "Michael Flarup"),
        AppIconOption(id: "neon-glow", displayName: "Neon Glow", artist: "CandbotYT"),
        AppIconOption(id: "apollos6", displayName: "ApollOS 6", artist: "Basic Apple Guy"),
        AppIconOption(id: "floaty-boy", displayName: "Floaty Boy", artist: "01davi"),
        AppIconOption(id: "slothkun", displayName: "Sloth-kun"),
        AppIconOption(id: "tapioca", displayName: "Deregulation of Tapioca", artist: "Alfrey Davilla"),
        AppIconOption(id: "macrodata-refinement", displayName: "Macrodata Refinement", artist: "Jeroen Schaper"),
        AppIconOption(id: "the-adventurer", displayName: "The Adventurer", artist: "David Lanham"),
        AppIconOption(id: "smiles", displayName: "Explorer of Smiles", artist: "Raphael Lopes"),
        AppIconOption(id: "calico", displayName: "Calico"),
        AppIconOption(id: "eap", displayName: "Icons Drop Test"),
        AppIconOption(id: "eggius-cuniculus", displayName: "Eggius Cuniculus", artist: "Matthew Skiles"),
        AppIconOption(id: "duck", displayName: "Wilson"),
        AppIconOption(id: "midasbot", displayName: "Midasbot", artist: "Michael Flarup"),
        AppIconOption(id: "gordon-ramesses", displayName: "Gordon Ramesses", artist: "Matthew Skiles"),
        AppIconOption(id: "red-black-white", displayName: "Apollo: First App in 8K?"),
        AppIconOption(id: "uk", displayName: "UK, Hugh Laurie"),
        AppIconOption(id: "macaroni-and-apollo", displayName: "Macaroni and Apollo", artist: "Matthew Skiles"),
        AppIconOption(id: "enter-the-state", displayName: "Enter the State"),
        AppIconOption(id: "pie-in-the-sky", displayName: "Pie in the Sky", artist: "flashboy131"),
        AppIconOption(id: "the-orbit-of-gargantua", displayName: "The Orbit of Gargantua", artist: "Victor F. Leão"),
        AppIconOption(id: "chosen-one", displayName: "Chosen One"),
        AppIconOption(id: "stonewall", displayName: "Stonewall"),
        AppIconOption(id: "mr-moustache", displayName: "Mr. Moustache", artist: "Brad Ellis"),
        AppIconOption(id: "low-battery", displayName: "Low Battery", artist: "Adam Whitcroft"),
        AppIconOption(id: "the-little-prince", displayName: "The Little Prince", artist: "Anh Nguyen"),
        AppIconOption(id: "usa2", displayName: "Super America"),
        AppIconOption(id: "sunset", displayName: "Crimson"),
        AppIconOption(id: "apollopy", displayName: "Apolloppy", artist: "Matthew Skiles & Josh Holtz"),
        AppIconOption(id: "decade-of-frosting", displayName: "Decade of Frosting", artist: "Luka Grafera (Parakeet)"),
        AppIconOption(id: "stringfish", displayName: "Stringfish", artist: "Huang Zitao"),
        AppIconOption(id: "under-the-tree", displayName: "Under the Tree", artist: "Qi Sandor"),
        AppIconOption(id: "demogorgon", displayName: "Demogorgon", artist: "Matthew Skiles"),
        AppIconOption(id: "mighty-apollo", displayName: "Mighty Apollo", artist: "Nao Enomoto"),
        AppIconOption(id: "shakey-shakey", displayName: "Shakey Shakey", artist: "Matthew Skiles"),
        AppIconOption(id: "sandals", displayName: "Sandals 'n Socks"),
        AppIconOption(id: "jackopollo", displayName: "Jack-o'-pollo", artist: "Anthony Piraino (The Iconfactory)"),
        AppIconOption(id: "antenna", displayName: "Irradiate"),
        AppIconOption(id: "year-of-the-rabbit", displayName: "Year of the Rabbit", artist: "Matthew Skiles & Barry Hershman"),
        AppIconOption(id: "rimuru", displayName: "Rimuru", artist: "StevSarm"),
        AppIconOption(id: "ice-bot", displayName: "Ice•bot (Hero Mode)", artist: "Mike of Creative Mints"),
        AppIconOption(id: "apollobot", displayName: "Apollobot", artist: "Mark Jardine (Tapbots)"),
        AppIconOption(id: "wish-maker", displayName: "Wish Maker", artist: "Michael Myers"),
        AppIconOption(id: "metal-cap", displayName: "Metal Cap", artist: "Matthew Skiles"),
        AppIconOption(id: "rule-of-two", displayName: "Rule of Two"),
        AppIconOption(id: "red", displayName: "Red"),
        AppIconOption(id: "canada", displayName: "Canada D'Eh"),
        AppIconOption(id: "launched", displayName: "Launched", artist: "chuckyc17"),
        AppIconOption(id: "scan-lines", displayName: "Scan Lines", artist: "Ilya Miskov"),
        AppIconOption(id: "six-colors", displayName: "Six Colors"),
        AppIconOption(id: "blorbo", displayName: "Blorbo", artist: "Adam Whitcroft"),
        AppIconOption(id: "castiel", displayName: "Castiel", artist: "Matthew Skiles"),
        AppIconOption(id: "shadowbot", displayName: "Shadowbot", artist: "Michael Flarup"),
        AppIconOption(id: "knight", displayName: "Night Knight", artist: "ben5292001"),
        AppIconOption(id: "mr-neep-neep", displayName: "Brocolibot", artist: "Michael Flarup"),
        AppIconOption(id: "tld", displayName: "Yo. Jonathan Here."),
        AppIconOption(id: "teal", displayName: "Under the Sea"),
        AppIconOption(id: "dark", displayName: "Lumos"),
        AppIconOption(id: "palette", displayName: "Palette", artist: "Marcelo Curiel"),
        AppIconOption(id: "broby", displayName: "Broby", artist: "burkybang's son (5 y/o)"),
        AppIconOption(id: "phil", displayName: "Phil"),
        AppIconOption(id: "no-space", displayName: "No Space", artist: "s4pete"),
        AppIconOption(id: "cuddleb0t", displayName: "Cuddleb0t", artist: "Louie Mantia (Parakeet)"),
        AppIconOption(id: "pride", displayName: "Pride"),
        AppIconOption(id: "galactic-zoomer", displayName: "Galactic Zoomer"),
        AppIconOption(id: "waving-yolkstronaut", displayName: "Waving Yolkstronaut", artist: "Yannick Lung"),
        AppIconOption(id: "dr-spaceman", displayName: "Dr. Spaceman", artist: "Jeff Broderick"),
        AppIconOption(id: "icarusbot", displayName: "Icarusbot", artist: "Michael Flarup"),
        AppIconOption(id: "andru", displayName: "Pro Wrestler"),
        AppIconOption(id: "notebook", displayName: "Notebook", artist: "Nick Takayama"),
        AppIconOption(id: "the-copper-giant", displayName: "The Copper Giant", artist: "Thomas Noppers"),
        AppIconOption(id: "felt-and-feels", displayName: "Felt and Feels", artist: "Yannick Lung"),
        AppIconOption(id: "murica", displayName: "America!"),
        AppIconOption(id: "apollomoji", displayName: "Apollomoji", artist: "Louie Mantia (Parakeet)"),
        AppIconOption(id: "castro", displayName: "Beware the Turtles"),
        AppIconOption(id: "ducky-buddy", displayName: "My Ducky Buddy", artist: "Lux (@thisislux)"),
        AppIconOption(id: "floating", displayName: "Floating", artist: "Lalit"),
        AppIconOption(id: "forest-spirit", displayName: "Forest Spirit", artist: "Ilya Shapko"),
        AppIconOption(id: "gold", displayName: "I Love Goooold"),
        AppIconOption(id: "rosso", displayName: "Rosso", artist: "Matthew Skiles"),
        AppIconOption(id: "rainbow-visor", displayName: "Rainbow Visor", artist: "Matthew Skiles"),
        AppIconOption(id: "brown", displayName: "Tremors"),
        AppIconOption(id: "bluesteroid", displayName: "Blueboi", artist: "the_philter"),
        AppIconOption(id: "retrowave", displayName: "Retrowave", artist: "cwlsmith"),
        AppIconOption(id: "neptunebot", displayName: "Neptunebot", artist: "Michael Flarup"),
        AppIconOption(id: "sir-yule-treemas", displayName: "Sir Yule Treemas", artist: "Anthony Piraino (The Iconfactory)"),
        AppIconOption(id: "sus", displayName: "sus", artist: "Karol Tylke"),
        AppIconOption(id: "jonybot", displayName: "Jonybot", artist: "Michael Flarup"),
    ]
}

public enum AppIconStore {
    private static let key = "com.pendo324.Phoebus.selectedAppIcon"

    public static let storage = CustomSettingsSource<AppIconOption>(
        key: key,
        load: { defaults in defaults.string(forKey: key).flatMap { raw in AppIconOption.all.first { $0.id == raw } } ?? .original },
        save: { option, defaults in defaults.set(option.id, forKey: key) })

    public static func load() -> AppIconOption { storage.load() }

    public static func save(_ option: AppIconOption) { storage.save(option) }
}
