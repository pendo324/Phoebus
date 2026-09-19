import Foundation

/// Sunrise/sunset for Apollo's "Use Location Sunset & Sunrise"
/// (`AutomaticThemeToggleUseSunset`, coordinates in `SunsetCoordinates`).
///
/// NOAA's general solar-position algorithm (zenith 90.833 degrees for
/// official sunrise/sunset), accurate to about a minute, computed fully
/// on-device. Returns nil during polar day/night.
public enum SolarTimes {
    public struct Coordinates: Codable, Sendable, Equatable {
        public var latitude: Double
        public var longitude: Double
        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// (sunrise, sunset) for the calendar day containing `date`, in
    /// absolute time.
    public static func sunriseSunset(on date: Date, at c: Coordinates,
                                     calendar: Calendar = .current) -> (sunrise: Date, sunset: Date)? {
        let day = calendar.startOfDay(for: date)
        guard let rise = event(day: day, c: c, rising: true, calendar: calendar),
              let set = event(day: day, c: c, rising: false, calendar: calendar) else { return nil }
        return (rise, set)
    }

    /// Minutes after local midnight, the form the schedule uses.
    public static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private static func event(day: Date, c: Coordinates, rising: Bool, calendar: Calendar) -> Date? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        guard let utcNoon = utc.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)),
              let n = utc.ordinality(of: .day, in: .year, for: utcNoon) else { return nil }
        let rad = Double.pi / 180
        let lngHour = c.longitude / 15
        let t = Double(n) + ((rising ? 6 : 18) - lngHour) / 24
        let m = 0.9856 * t - 3.289
        var l = m + 1.916 * sin(m * rad) + 0.020 * sin(2 * m * rad) + 282.634
        l = l.truncatingRemainder(dividingBy: 360); if l < 0 { l += 360 }
        var ra = atan(0.91764 * tan(l * rad)) / rad
        ra = ra.truncatingRemainder(dividingBy: 360); if ra < 0 { ra += 360 }
        ra += floor(l / 90) * 90 - floor(ra / 90) * 90
        ra /= 15
        let sinDec = 0.39782 * sin(l * rad)
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(90.833 * rad) - sinDec * sin(c.latitude * rad)) / (cosDec * cos(c.latitude * rad))
        guard cosH >= -1, cosH <= 1 else { return nil }
        var h = rising ? 360 - acos(cosH) / rad : acos(cosH) / rad
        h /= 15
        let localMean = h + ra - 0.06571 * t - 6.622
        var ut = (localMean - lngHour).truncatingRemainder(dividingBy: 24); if ut < 0 { ut += 24 }
        guard let midnightUTC = utc.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day)) else { return nil }
        return midnightUTC.addingTimeInterval(ut * 3600)
    }
}

/// `SunsetCoordinates`: the one-time approximate location. "Turn switch
/// off to clear."
public enum SunsetCoordinatesStore {
    public static let key = "SunsetCoordinates"

    public static func load() -> SolarTimes.Coordinates? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SolarTimes.Coordinates.self, from: data)
    }

    public static func save(_ c: SolarTimes.Coordinates?) {
        if let c, let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
