import Foundation
#if canImport(Network)
import Network
#endif

/// Whether a video should start playing by itself.
///
/// Apollo's feed autoplays: `GeneralSettings.autoplayMode` (default
/// `AutoplayGIFs = always`) describes how feed videos behave when they
/// autoplay while scrolling.
public enum VideoAutoplayPolicy {
    /// Whether to autoplay, given the user's mode and the current
    /// connection.
    ///
    /// `wifiOnly` maps to Apollo's own `AutoplayGifsOverCellular`
    /// (default false), i.e. "not on cellular".
    public static func shouldAutoplay(mode: AutoplayMode, isExpensive: Bool) -> Bool {
        switch mode {
        case .always: return true
        case .never: return false
        case .wifiOnly: return !isExpensive
        }
    }

    /// The live answer for this device.
    @MainActor
    public static func shouldAutoplay(mode: AutoplayMode) -> Bool {
        shouldAutoplay(mode: mode, isExpensive: NetworkCostMonitor.shared.isExpensive)
    }
}

/// Tracks whether the current connection is "expensive" (cellular or a
/// personal hotspot), for `wifiOnly` autoplay.
///
/// `NWPathMonitor` rather than a reachability guess: `isExpensive` is
/// the system's own answer and already accounts for hotspots, which a
/// plain "is the interface cellular" check does not.
@MainActor
public final class NetworkCostMonitor {
    public static let shared = NetworkCostMonitor()

    /// Defaults to FALSE - i.e. assume unmetered until told otherwise.
    ///
    /// The monitor delivers its first path asynchronously, so a video
    /// appearing in the first moments after launch would otherwise be
    /// judged against "expensive" and silently not autoplay. Guessing
    /// "cheap" fails toward playing, which matches `.always` being the
    /// default mode.
    public private(set) var isExpensive = false

    #if canImport(Network)
    private let monitor = NWPathMonitor()
    #endif

    private init() {
        #if canImport(Network)
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive
            Task { @MainActor in self?.isExpensive = expensive }
        }
        monitor.start(queue: DispatchQueue(label: "apollo.network.cost"))
        #endif
    }
}
