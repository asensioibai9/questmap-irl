import CoreLocation
import Observation

/// Implementación real con Core Location.
/// Pide permiso "When In Use" y solo tras una explicación previa en onboarding.
@MainActor
@Observable
final class LocationService: NSObject, LocationServiceProtocol {
    private(set) var authState: LocationAuthState = .notDetermined
    private(set) var currentLocation: CLLocation?
    private(set) var heading: CLHeading?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        refreshAuthState(manager.authorizationStatus)
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func refreshAuthState(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: authState = .notDetermined
        case .restricted, .denied: authState = .denied
        case .authorizedWhenInUse: authState = .authorizedWhenInUse
        case .authorizedAlways: authState = .authorizedAlways
        @unknown default: authState = .denied
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.refreshAuthState(status)
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.startUpdating()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.heading = newHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Errores transitorios (túneles, sin señal) se ignoran; el último punto válido se conserva.
    }
}
