import Foundation

/// The disk-space guard Apollo-Reborn applies before a bulk "Save All" from a
/// multi-image album. Saving downloads every original first, so a large album
/// on a nearly-full device could fail halfway and leave a partial save; the
/// available capacity is checked against a worst-case estimate before starting
/// and the save is refused with "Not enough free space".
public enum AlbumSaveCapacity {
    /// Per-image ceiling: 50 MB.
    public static let maximumItemBytes: UInt64 = 50 * 1024 * 1024
    /// Whole-viewer ceiling: 150 MB.
    public static let maximumViewerBytes: UInt64 = 150 * 1024 * 1024
    /// Headroom kept free on top of the estimate: 50 MB.
    public static let saveSafetyBytes: UInt64 = 50 * 1024 * 1024

    /// Whether `remainingCount` not-yet-downloaded images can be saved.
    /// `storedBytes` is what is already on disk for this viewer and is deducted
    /// from the viewer allowance; only what is still to be fetched is charged.
    ///
    /// Returns true when nothing remains to download, since the bytes
    /// are already accounted for.
    public static func hasCapacity(
        availableBytes: UInt64,
        storedBytes: UInt64,
        remainingCount: Int
    ) -> Bool {
        guard remainingCount > 0 else { return true }
        return availableBytes >= requiredBytes(
            storedBytes: storedBytes, remainingCount: remainingCount)
    }

    /// The worst-case free space a save needs.
    /// Takes the minimum of the remaining viewer allowance and the per-item
    /// estimate, then adds the safety margin. Without the min, a 100-image album
    /// would demand 5 GB though the viewer never holds more than 150 MB.
    public static func requiredBytes(storedBytes: UInt64, remainingCount: Int) -> UInt64 {
        guard remainingCount > 0 else { return 0 }
        let remainingAllowance = storedBytes >= maximumViewerBytes
            ? 0 : maximumViewerBytes - storedBytes
        // Saturating, so overflow cannot wrap.
        let requested = UInt64(remainingCount).multipliedReportingOverflow(by: maximumItemBytes)
        let requestedAllowance = requested.overflow ? UInt64.max : requested.partialValue
        let worstCase = min(remainingAllowance, requestedAllowance)
        let total = worstCase.addingReportingOverflow(saveSafetyBytes)
        return total.overflow ? UInt64.max : total.partialValue
    }

    /// Menu title; shown only for a real album, a single image says "Save Image".
    public static func saveAllTitle(count: Int) -> String {
        "Save All \(count) Images"
    }

    /// Completion toast.
    public static func savedToast(count: Int) -> String {
        count == 1 ? "Saved" : "Saved \(count) images"
    }

    /// Progress toast.
    public static func downloadingToast(count: Int) -> String {
        count > 1 ? "Downloading originals…" : "Downloading original…"
    }
}
