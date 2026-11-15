import CoreLocation
import Observation

/// Implementación real con Core Location.
/// - Pide "When In Use" tras explicarlo en onboarding. No se pide "Always".
/// - Precisión moderada en reposo y máxima solo durante navegación (batería).
/// - Suaviza la posición, usa el rumbo real (course) y detecta pérdida de señal.
@MainActor
@Observable
final class LocationService: NSObject, LocationServiceProtocol {
    private(set) var authState: LocationAuthState = .notDetermined
    private(set) var currentLocation: CLLocation?
    private(set) var smoothedLocation: CLLocation?
    private(set) var displayHeading: Double = 0
    private(set) var quality: GPSQuality = .none
    private(set) var isSignalLost = false

    private let manager = CLLocationManager()
    private var mode: LocationMode = .idle
    private var magneticHeading: Double = 0
    private var staleTimer: Timer?
    private var isRunning = false

    /// Fix más antiguo que esto se considera señal perdida.
    private let staleInterval: TimeInterval = 8

    override init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
        manager.headingFilter = 3
        applyMode(.idle)
        refreshAuthState()
    }

    // MARK: - API

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start(mode: LocationMode) {
        applyMode(mode)
        guard authState.isAuthorized else { return }
        isRunning = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        startStaleTimer()
    }

    func setMode(_ mode: LocationMode) {
        applyMode(mode)
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        staleTimer?.invalidate()
        staleTimer = nil
    }

    // MARK: - Privado

    private func applyMode(_ newMode: LocationMode) {
        mode = newMode
        switch newMode {
        case .idle:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 8
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
        case .navigating:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            // Solo durante una navegación iniciada por el usuario (UIBackgroundModes: location).
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
    }

    private func refreshAuthState() {
        let status = manager.authorizationStatus
        Task.detached { [weak self] in
            // locationServicesEnabled() bloquea si se llama en el hilo principal.
            let enabled = CLLocationManager.locationServicesEnabled()
            await MainActor.run { self?.resolveAuth(status: status, servicesEnabled: enabled) }
        }
    }

    private func resolveAuth(status: CLAuthorizationStatus, servicesEnabled: Bool) {
        guard servicesEnabled else { authState = .servicesDisabled; return }
        switch status {
        case .notDetermined: authState = .notDetermined
        case .denied: authState = .denied
        case .restricted: authState = .restricted
        case .authorizedWhenInUse: authState = .authorizedWhenInUse
        case .authorizedAlways: authState = .authorizedAlways
        @unknown default: authState = .denied
        }
        if authState.isAuthorized, isRunning {
            manager.startUpdatingLocation()
        }
    }

    private func startStaleTimer() {
        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStale() }
        }
    }

    private func checkStale() {
        guard let last = currentLocation else {
            quality = .none
            isSignalLost = true
            return
        }
        let age = Date().timeIntervalSince(last.timestamp)
        if age > staleInterval {
            isSignalLost = true
            quality = .none
        }
    }

    private func ingest(_ location: CLLocation) {
        // Descarta fixes inválidos o muy antiguos (caché al arrancar).
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy < 500,
              Date().timeIntervalSince(location.timestamp) < 10 else { return }

        currentLocation = location
        isSignalLost = false
        quality = Self.quality(for: location.horizontalAccuracy)
        smoothedLocation = smooth(location)
        updateHeading(with: location)
    }

    private static func quality(for accuracy: CLLocationAccuracy) -> GPSQuality {
        switch accuracy {
        case ..<10: return .excellent
        case ..<30: return .good
        case ..<100: return .fair
        default: return .poor
        }
    }

    /// Filtro exponencial: suaviza vibraciones pequeñas y deja pasar movimientos reales.
    private func smooth(_ new: CLLocation) -> CLLocation {
        guard let prev = smoothedLocation else { return new }
        let jump = new.distance(from: prev)
        // Un salto grande o buena señal: fiarse del fix nuevo.
        if jump > 40 || new.horizontalAccuracy < 8 { return new }
        let alpha = mode == .navigating ? 0.65 : 0.5
        let lat = prev.coordinate.latitude + (new.coordinate.latitude - prev.coordinate.latitude) * alpha
        let lon = prev.coordinate.longitude + (new.coordinate.longitude - prev.coordinate.longitude) * alpha
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                          altitude: new.altitude,
                          horizontalAccuracy: new.horizontalAccuracy,
                          verticalAccuracy: new.verticalAccuracy,
                          course: new.course,
                          speed: new.speed,
                          timestamp: new.timestamp)
    }

    /// En movimiento (> 1,5 m/s) manda el course del GPS; parado, la brújula.
    private func updateHeading(with location: CLLocation) {
        if location.speed > 1.5, location.course >= 0 {
            displayHeading = location.course
        } else if magneticHeading >= 0 {
            displayHeading = magneticHeading
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refreshAuthState() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.ingest(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.magneticHeading = value
            if let loc = self.currentLocation, loc.speed <= 1.5 { self.displayHeading = value }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError else { return }
        Task { @MainActor in
            switch clError.code {
            case .denied: self.refreshAuthState()
            case .locationUnknown: self.isSignalLost = true   // túnel, interior: se conserva el último punto
            default: break
            }
        }
    }
}
