import Foundation

/// The size of the HTTP cache `URLSession.shared` stores downloaded pictures
/// and previews in (`URLCache.shared`, set at launch). Reddit's image hosts
/// send long `Cache-Control`/`Expires` headers and its API answers are
/// `no-store`, so only pictures and previews end up in it. The iOS default is
/// 512 KB in memory and 10 MB on disk, which a single thread of avatars and
/// previews fills.
public enum HTTPCacheLimits {
    public static let memoryCapacity = 32 * 1024 * 1024
    public static let diskCapacity = 256 * 1024 * 1024

    /// Apollo's Storage footer ("Maximum of around 200 MB.") with the size
    /// Phoebus keeps.
    public static var storageFooter: String { "Maximum of around \(diskCapacity / (1024 * 1024)) MB." }

    /// Shown under the "What Phoebus Keeps on Disk" listing: where the
    /// pictures are and what clears them.
    public static var explainerNote: String {
        "Pictures and previews Phoebus has downloaded are kept in Library, up to \(diskCapacity / (1024 * 1024)) MB, and Clear Cache empties them."
    }
}
