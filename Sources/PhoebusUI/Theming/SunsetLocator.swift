import SwiftUI
import PhoebusCore
#if canImport(CoreLocation)
import CoreLocation

/// Apollo's one-time approximate location for "Use Location Sunset &
/// Sunrise": reduced accuracy, a single reading, stored in `SunsetCoordinates`,
/// never sent anywhere. States match Apollo's own rows: "Finding
/// Location…" and "Locating failed. Tap to retry."
@MainActor
final class SunsetLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, locating, failed, found(SolarTimes.Coordinates) }

    @Published private(set) var state: State = SunsetCoordinatesStore.load().map { .found($0) } ?? .idle
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func locate() {
        state = .locating
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: state = .failed
        default: manager.requestLocation()
        }
    }

    func clear() {
        SunsetCoordinatesStore.save(nil)
        state = .idle
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.state == .locating else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.state = .failed
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Rounded to ~1 km: sunrise/sunset need nothing finer.
        let c = SolarTimes.Coordinates(latitude: (loc.coordinate.latitude * 100).rounded() / 100,
                                       longitude: (loc.coordinate.longitude * 100).rounded() / 100)
        Task { @MainActor in
            SunsetCoordinatesStore.save(c)
            self.state = .found(c)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.state = .failed }
    }
}
#endif
