import Foundation

/// Reddit Chat's fixed reaction set.
///
/// Reddit does not accept unicode reactions: a key is an IMAGE FILENAME
/// served from Reddit's CDN (e.g. `foyijyyga7081.gif`), and anything else
/// returns `M_INVALID_ARGUMENT_VALUE: "reaction key is not supported"`.
/// The 48 keys below are the ones the homeserver accepts; each resolves
/// to an image at `https://i.redd.it/<key>`.
public enum RedditChatReactions {
    /// The 48 keys the server accepts, in Reddit's own picker order.
    public static let keys: [String] = [
        "mi2jolzfa7081.gif",
        "2o3aooqfa7081.gif",
        "k7ry7t1ga7081.gif",
        "jvuspmbga7081.gif",
        "g6akcitga7081.gif",
        "3i2arwzga7081.gif",
        "cdnhvqfga7081.gif",
        "t5bqwxdyt7081.gif",
        "tspuf53ga7081.gif",
        "ax7wu47ga7081.gif",
        "t2r5xc9ga7081.gif",
        "0ku6twega7081.gif",
        "b5s6cohga7081.gif",
        "pleyoikga7081.gif",
        "zn7iubvfa7081.gif",
        "19b5q4vga7081.gif",
        "8r21ukpfa7081.gif",
        "m7uy86lga7081.gif",
        "wbrgz1nga7081.gif",
        "vq7naqwfa7081.gif",
        "qzl5vyxfa7081.gif",
        "sjs1a2fyt7081.gif",
        "9ut7iedga7081.gif",
        "3s0glewga7081.gif",
        "00brcfjga7081.gif",
        "dfxygs4ga7081.gif",
        "1p1jgpgga7081.gif",
        "t1djdguga7081.gif",
        "79opsq0ha7081.gif",
        "foyijyyga7081.gif",
        "uy83aa8ga7081.gif",
        "mag7v6tfa7081.gif",
        "xjls1pqga7081.gif",
        "ksz4fmaga7081.gif",
        "evwks24ga7081.gif",
        "d45pfmsga7081.gif",
        "iuqmp7ufa7081.gif",
        "8zx5ixoga7081.gif",
        "ytv3x0sfa7081.png",
        "4zhlw4iyt7081.gif",
        "av9z8iiga7081.gif",
        "7rc03trga7081.gif",
        "mp9zclcga7081.gif",
        "fsg2a1oga7081.gif",
        "7url39xga7081.gif",
        "d2kn6yxga7081.gif",
        "8kw138jyt7081.gif",
        "ul2w17ega7081.gif"
    ]

    /// The CDN image for a reaction key.
    ///
    /// Keys carry their own extension (`.gif`, and one `.png`), so the
    /// key is appended verbatim rather than having an extension added.
    public static func imageURL(forKey key: String) -> URL? {
        // Reject anything that could escape the path; keys are opaque
        // filenames and should never contain a slash.
        guard !key.isEmpty, !key.contains("/"), !key.contains("..") else { return nil }
        return URL(string: "https://i.redd.it/" + key)
    }

    /// Whether the server will accept this key.
    public static func isSupported(_ key: String) -> Bool {
        keys.contains(key)
    }
}
