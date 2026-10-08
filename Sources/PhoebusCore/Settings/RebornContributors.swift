import Foundation

/// Apollo Reborn's contributors, grouped as Reborn credits them, from its
/// `contributors.json` (the same list behind Reborn's README). GitHub's own
/// contributors API only knows commit authors, so it misses the icon and
/// design contributors and includes bots.
public enum RebornContributors {
    public static let sourceURL = URL(string: "https://raw.githubusercontent.com/Apollo-Reborn/Apollo-Reborn/main/contributors.json")!

    public struct Group: Equatable, Sendable {
        public let title: String
        public let names: [String]
    }

    /// The groups in Reborn's order, empty ones dropped. Entries name a
    /// GitHub account (`github`) or carry a `displayName`; bot accounts are
    /// left out.
    public static func parse(_ data: Data) -> [Group]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["contributors"] as? [[String: Any]] else { return nil }
        let roles: [(role: String, title: String)] = [
            ("maintainer", "Maintainers"), ("code", "Code"), ("design", "Icons & Design"),
        ]
        var names: [String: [String]] = [:]
        for entry in entries {
            guard let role = entry["role"] as? String,
                  let name = (entry["github"] as? String) ?? (entry["displayName"] as? String),
                  !name.isEmpty, !name.hasSuffix("[bot]") else { continue }
            names[role, default: []].append(name)
        }
        let groups = roles.compactMap { role, title in
            names[role].map { Group(title: title, names: $0) }
        }
        return groups.isEmpty ? nil : groups
    }
}
