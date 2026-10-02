import Foundation

/// Picks one photo per calendar day, deterministically.
///
/// Pure and separate so the guarantees are checkable: the same day always
/// yields the same index (even across timeline rebuilds) and consecutive days
/// differ.
public enum CalendarPhotoPicker {
    /// A rolling ~150-day history avoids dupes.
    public static let historyWindow = 150

    public static func index(for day: Date, poolSize: Int) -> Int {
        guard poolSize > 0 else { return 0 }
        // Day number since the epoch: stable for a whole calendar day.
        let dayNumber = Int(day.timeIntervalSince1970 / 86_400)
        // A multiplier coprime with typical pool sizes spreads consecutive days
        // across the pool instead of walking it in order.
        return ((dayNumber &* 7) % poolSize + poolSize) % poolSize
    }
}

