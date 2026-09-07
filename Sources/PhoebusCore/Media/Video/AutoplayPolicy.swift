import Foundation
#if canImport(Network)
import Network
#endif

/// Decides whether inline media should start playing by itself, backing
/// Apollo's "Autoplay GIFs/Videos" setting (Always / Wi-Fi Only / Never).
/// The decision is a pure function of the mode and the network so the smoke
/// tests can assert it; only `isOnUnmeteredNetwork` touches the system.
public enum AutoplayPolicy {
    /// Whether autoplay should happen right now.
    public static func shouldAutoplay(
        mode: AutoplayMode = GeneralSettingsStore.load().autoplayMode,
        isUnmetered: Bool = NetworkReachability.isOnUnmeteredNetwork
    ) -> Bool {
        switch mode {
        case .always: return true
        case .never: return false
        case .wifiOnly: return isUnmetered
        }
    }
}

/// "Is this connection unmetered" check for the "Wi-Fi Only" mode.
///
/// `NWPathMonitor.currentPath.isExpensive` is true for cellular or a personal
/// hotspot, the "don't burn my data" distinction the setting is about. Fails
/// open (unmetered) when Network.framework is unavailable, since never
/// autoplaying would look broken.
public enum NetworkReachability {
    #if canImport(Network)
    private static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "com.pendo324.Phoebus.reachability"))
        return monitor
    }()
    #endif

    public static var isOnUnmeteredNetwork: Bool {
        #if canImport(Network)
        // `.requiresConnection` means the path isn't up yet; treat it as
        // unmetered so first-launch behaviour is sane.
        let path = monitor.currentPath
        if path.status == .requiresConnection { return true }
        return !path.isExpensive
        #else
        return true
        #endif
    }
}
