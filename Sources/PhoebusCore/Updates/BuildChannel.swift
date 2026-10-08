import Foundation

/// The release channel a build came from. CI stamps it into the app's
/// Info.plist (`PhoebusBuildChannel`) when packaging; local and dev builds
/// carry no key, so they have no channel. Phoebus-only: Apollo has no
/// release channels.
public enum BuildChannel: String, Sendable, CaseIterable {
    case stable
    case nightly

    public static let infoKey = "PhoebusBuildChannel"

    public init?(infoDictionary: [String: Any]?) {
        guard let raw = infoDictionary?[Self.infoKey] as? String else { return nil }
        self.init(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    public static var current: BuildChannel? { BuildChannel(infoDictionary: Bundle.main.infoDictionary) }
}
