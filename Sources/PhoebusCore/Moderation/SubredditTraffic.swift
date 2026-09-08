import Foundation

/// Mod-only subscriber/pageview traffic over time, decoding Reddit's
/// `/r/<sub>/about/traffic` response:
/// `{"day": [[ts, uniques, pageviews], ...], "hour": [[ts, uniques,
/// pageviews], ...], "month": [[ts, uniques, pageviews, subscriptions], ...]}`.
public struct SubredditTraffic: Decodable, Sendable {
    public let day: [TrafficPoint]
    public let hour: [TrafficPoint]
    public let month: [TrafficPoint]

    public struct TrafficPoint: Sendable, Identifiable {
        public let date: Date
        public let uniques: Int
        public let pageviews: Int
        public let subscriptions: Int?

        public var id: TimeInterval { date.timeIntervalSince1970 }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try Self.decodePoints(container, key: .day)
        hour = try Self.decodePoints(container, key: .hour)
        month = try Self.decodePoints(container, key: .month)
    }

    enum CodingKeys: String, CodingKey { case day, hour, month }

    private static func decodePoints(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> [TrafficPoint] {
        let raw = try container.decode([[Double]].self, forKey: key)
        return raw.compactMap { row -> TrafficPoint? in
            guard row.count >= 3 else { return nil }
            return TrafficPoint(
                date: Date(timeIntervalSince1970: row[0]),
                uniques: Int(row[1]),
                pageviews: Int(row[2]),
                subscriptions: row.count > 3 ? Int(row[3]) : nil
            )
        }
    }
}
