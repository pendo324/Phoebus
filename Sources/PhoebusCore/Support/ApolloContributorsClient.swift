import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Reborn contributor entry with an optional Buy Me a Coffee link,
/// fetched from the same live JSON URL Reborn uses:
/// `https://raw.githubusercontent.com/Apollo-Reborn/Apollo-Reborn/refs/heads/main/contributors.json`.
public struct ApolloContributor: Sendable, Equatable, Identifiable {
    public let github: String?
    public let displayName: String?
    public let role: String?
    public let buyMeACoffeeURL: String?

    public var id: String { github ?? displayName ?? UUID().uuidString }

    /// Special case for one contributor whose GitHub login casing differs
    /// from their preferred display name.
    public var resolvedDisplayName: String {
        if github == "icpryde" { return "iCpryde" }
        if let displayName, !displayName.isEmpty { return displayName }
        if let github, !github.isEmpty { return github }
        return ""
    }
}

/// Reborn's fetch + parse pipeline for both the "Buy Us a Coffee" screen
/// (contributors with a coffee link) and the About screen's "Thanks To…"
/// role-grouped listing.
public enum ApolloContributorsClient {
    private static let jsonURL = URL(string: "https://raw.githubusercontent.com/Apollo-Reborn/Apollo-Reborn/refs/heads/main/contributors.json")!

    public enum ClientError: Error, Sendable {
        case invalidResponse
    }

    public static func fetchContributors(session: URLSession = .shared) async throws -> [ApolloContributor] {
        let (data, response) = try await session.data(from: jsonURL)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidResponse
        }
        return try parse(data: data)
    }

    /// Parses the JSON shape: `{"contributors": [{"role":...,
    /// "github":...,"displayName":...,"buyMeACoffeeUrl":...}, ...]}`.
    public static func parse(data: Data) throws -> [ApolloContributor] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawContributors = json["contributors"] as? [[String: Any]] else {
            throw ClientError.invalidResponse
        }
        return rawContributors.map { raw in
            ApolloContributor(
                github: raw["github"] as? String,
                displayName: raw["displayName"] as? String,
                role: raw["role"] as? String,
                buyMeACoffeeURL: raw["buyMeACoffeeUrl"] as? String
            )
        }
    }

    /// Only contributors with a non-empty coffee link.
    public static func buyCoffeeEntries(from contributors: [ApolloContributor]) -> [ApolloContributor] {
        contributors.filter { ($0.buyMeACoffeeURL?.isEmpty == false) }
    }

    /// Role-grouped sections (Maintainers, Code, Icon & Design, ...) for the
    /// About screen's "Thanks To…" listing.
    public static func groupedByRole(_ contributors: [ApolloContributor]) -> [(title: String, contributors: [ApolloContributor])] {
        let roleOrder: [(key: String, title: String)] = [
            ("maintainer", "Maintainers"),
            ("code", "Code"),
            ("design", "Icon & Design"),
        ]
        var sections: [(title: String, contributors: [ApolloContributor])] = []
        for (key, title) in roleOrder {
            let matched = contributors.filter { ($0.role ?? "").caseInsensitiveCompare(key) == .orderedSame }
            if !matched.isEmpty {
                sections.append((title, matched))
            }
        }
        return sections
    }
}
