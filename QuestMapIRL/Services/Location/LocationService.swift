import CoreLocation
import Observation

/// Lo mínimo de `CLLocationManager` que usa el servicio (permite sustituirlo en pruebas).
protocol LocationManaging: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var activityType: CLActivityType { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var showsBackgroundLocationIndicator: Bool { get set }
    var headingFilter: CLLocationDegrees { get set }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startUpdatingHeading()
    func stopUpdatingHeading()
    func requestLocation()
    func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String, completion: ((Error?) -> Void)?)
}

extension CLLocationManager: LocationManaging {}

/// Implementación real con Core Location.
/// - Pide "When In Use" tras explicarlo en onboarding. No se pide "Always".
/// - Precisión moderada en reposo y máxima solo durante navegación (batería).
/// - Acepta toda lectura válida (también las imprecisas o aproximadas) y deja que `status` diga qué
///   calidad tiene: descartarlas dejaba la app sin posición alguna.
/// - Estar quieto NO es perder la señal: con `distanceFilter` iOS no entrega lecturas sin movimiento,
///   así que se pide una lectura puntual para confirmar la vigencia antes de dar nada por perdido.
@MainActor
@Observable
final class LocationService: NSObject, LocationServiceProtocol {
    private(set) var authState: LocationAuthState = .notDetermined
    private(set) var accuracyMode: LocationAccuracyMode = .full
    private(set) var currentLocation: CLLocation?
    private(set) var smoothedLocation: CLLocation?
    private(set) var displayHeading: Double = 0
    private(set) var quality: GPSQuality = .none
    private(set) var status: LocationStatus = .requestingPermission

    var isSignalLost: Bool {
        if case .lastKnown = status { return true }
        return false
    }

    @ObservationIgnored private let manager: LocationManaging
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let servicesEnabledProvider: (() -> Bool)?
    @ObservationIgnored private var mode: LocationMode = .idle
    @ObservationIgnored private var headingSelector = HeadingSourceSelector()
    @ObservationIgnored private var timer: Timer?
    /// Alguien pidió actualizaciones (puede que aún falte el permiso).
    @ObservationIgnored private var wantsUpdates = false
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var startedAt: Date
    @ObservationIgnored private var freshSinceStart = false
    @ObservationIgnored private var lastTemporaryErrorAt: Date?
    @ObservationIgnored private var lastRefreshRequestAt: Date?
    @ObservationIgnored private var lastReadingLogAt: Date?
    @ObservationIgnored private var lastDiscardLogAt: Date?

    init(manager: LocationManaging = CLLocationManager(),
         diagnostics: DiagnosticsLog = .shared,
         clock: @escaping () -> Date = Date.init,
         servicesEnabledProvider: (() -> Bool)? = nil,
         startTimer: Bool = true) {
        self.manager = manager
        self.diagnostics = diagnostics
        self.clock = clock
        self.servicesEnabledProvider = servicesEnabledProvider
        self.startedAt = clock()
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = false
        manager.headingFilter = 3
        applyMode(.idle)
        refreshAuthState()
        if startTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    // MARK: - API

    func requestWhenInUseAuthorization() {
        log("permission", note: "solicitud When In Use")
        manager.requestWhenInUseAuthorization()
    }

    func start(mode: LocationMode) {
        applyMode(mode)
        wantsUpdates = true
        if isRunning { return }                       // idempotente: no reinicia la espera ni duplica actualizaciones
        startedAt = clock()
        freshSinceStart = false
        if authState.isAuthorized { beginUpdates() }
        reevaluate()
    }

    func setMode(_ mode: LocationMode) {
        applyMode(mode)
        reevaluate()
    }

    func stop() {
        wantsUpdates = false
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        log("stop")
    }

    func refreshNow() {
        switch authState {
        case .notDetermined:
            requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if !isRunning { start(mode: mode) }
            requestOneShot()
        case .denied, .restricted, .servicesDisabled:
            refreshAuthState()
        }
        reevaluate()
    }

    func requestTemporaryFullAccuracy() {
        log("fullAccuracy", note: "solicitud de precisión temporal")
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Navigation") { [weak self] error in
            Task { @MainActor in
                if let error { self?.log("fullAccuracy", outcome: "error", kind: "request", note: "\(error.localizedDescription)") }
                self?.refreshAuthState()
            }
        }
    }

    var diagnosticSummary: String {
        let now = clock()
        var parts = ["estado=\(status.logName)", "permiso=\(authState)", "precisión concedida=\(accuracyMode == .full ? "completa" : "aproximada")",
                     "actualizaciones=\(isRunning ? "activas" : "paradas")", "modo=\(mode == .navigating ? "navegación" : "reposo")"]
        if let fix = currentLocation {
            parts.append("última lectura hace \(Int(now.timeIntervalSince(fix.timestamp))) s, ±\(Int(fix.horizontalAccuracy)) m, velocidad \(String(format: "%.1f", max(0, fix.speed))) m/s")
        } else {
            parts.append("sin lecturas desde \(Int(now.timeIntervalSince(startedAt))) s")
        }
        return parts.joined(separator: "; ")
    }

    // MARK: - Privado

    private func applyMode(_ newMode: LocationMode) {
        mode = newMode
        switch newMode {
        case .idle:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 8
            manager.activityType = .other
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
        case .navigating:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            manager.activityType = .automotiveNavigation
            // Solo durante una navegación iniciada por el usuario (UIBackgroundModes: location).
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
    }

    private func beginUpdates() {
        guard !isRunning else { return }
        isRunning = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        requestOneShot()                              // lectura rápida sin esperar a moverse
        log("start", note: "modo=\(mode == .navigating ? "navegación" : "reposo")")
    }

    private func requestOneShot() {
        lastRefreshRequestAt = clock()
        manager.requestLocation()
    }

    private func refreshAuthState() {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        if let servicesEnabledProvider {
            resolveAuth(status: status, accuracy: accuracy, servicesEnabled: servicesEnabledProvider())
        } else {
            Task.detached { [weak self] in
                // locationServicesEnabled() bloquea si se llama en el hilo principal.
                let enabled = CLLocationManager.locationServicesEnabled()
                await MainActor.run { self?.resolveAuth(status: status, accuracy: accuracy, servicesEnabled: enabled) }
            }
        }
    }

    func resolveAuth(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization, servicesEnabled: Bool) {
        let previous = authState
        if !servicesEnabled {
            authState = .servicesDisabled
        } else {
            switch status {
            case .notDetermined: authState = .notDetermined
            case .denied: authState = .denied
            case .restricted: authState = .restricted
            case .authorizedWhenInUse: authState = .authorizedWhenInUse
            case .authorizedAlways: authState = .authorizedAlways
            @unknown default: authState = .denied
            }
        }
        accuracyMode = accuracy == .reducedAccuracy ? .reduced : .full
        if previous != authState {
            log("auth", note: "permiso=\(authState) precisión=\(accuracyMode == .full ? "completa" : "aproximada")")
        }
        // El permiso llegó después de pedir actualizaciones: se arrancan solas, sin depender de la interfaz.
        if authState.isAuthorized, wantsUpdates, !isRunning {
            startedAt = clock()
            freshSinceStart = false
            beginUpdates()
        }
        if !authState.isAuthorized, isRunning {
            isRunning = false
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
        }
        reevaluate()
    }

    /// Cada 2 s: reevalúa el estado y, si la última lectura envejece sin haber movimiento, pide una puntual.
    func tick() {
        guard isRunning else { return }
        let now = clock()
        if let fix = currentLocation {
            let moving = fix.speed > 1.5
            let age = now.timeIntervalSince(fix.timestamp)
            let sinceRefresh = lastRefreshRequestAt.map { now.timeIntervalSince($0) } ?? .infinity
            if age > LocationStatusEvaluator.refreshAge(mode: mode, moving: moving), sinceRefresh > 12 {
                requestOneShot()
            }
        } else if (lastRefreshRequestAt.map { clock().timeIntervalSince($0) } ?? .infinity) > 15 {
            requestOneShot()
        }
        reevaluate()
    }

    func reevaluate() {
        let now = clock()
        var snapshot = LocationSnapshot(auth: authState)
        snapshot.accuracyMode = accuracyMode
        snapshot.mode = mode
        snapshot.sinceStart = now.timeIntervalSince(startedAt)
        snapshot.freshSinceStart = freshSinceStart
        snapshot.recentTemporaryError = lastTemporaryErrorAt.map { now.timeIntervalSince($0) < 60 } ?? false
        if let fix = currentLocation {
            snapshot.hasFix = true
            snapshot.fixAccuracy = fix.horizontalAccuracy
            snapshot.fixAge = now.timeIntervalSince(fix.timestamp)
            snapshot.moving = fix.speed > 1.5
        }
        setStatus(LocationStatusEvaluator.evaluate(snapshot))
    }

    private func setStatus(_ new: LocationStatus) {
        // Los segundos de "sin confirmar" cambian cada vez: solo importa el tipo de estado para publicar y registrar.
        let changedKind = new.logName != status.logName
        if new != status { status = new }
        if changedKind { log("status", note: "→ \(new.logName)") }
    }

    /// Acepta toda lectura válida y publica su calidad; las inválidas se descartan con motivo registrado.
    func ingest(_ location: CLLocation) {
        let now = clock()
        if let reason = LocationStatusEvaluator.discardReason(
            horizontalAccuracy: location.horizontalAccuracy, latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude, timestamp: location.timestamp,
            newestAccepted: currentLocation?.timestamp) {
            if lastDiscardLogAt.map({ now.timeIntervalSince($0) > 5 }) ?? true {
                lastDiscardLogAt = now
                log("reading", outcome: "error", kind: "discarded", note: reason)
            }
            return
        }

        currentLocation = location
        lastTemporaryErrorAt = nil
        quality = Self.quality(for: location.horizontalAccuracy)
        smoothedLocation = smooth(location)
        updateHeading(with: location)
        // Una lectura con más de 15 s de antigüedad (caché del arranque) no cuenta como "fresca".
        if now.timeIntervalSince(location.timestamp) <= 15 { freshSinceStart = true }

        if lastReadingLogAt.map({ now.timeIntervalSince($0) >= 10 }) ?? true {
            lastReadingLogAt = now
            log("reading", note: "±\(Int(location.horizontalAccuracy)) m, edad \(Int(now.timeIntervalSince(location.timestamp))) s, v=\(String(format: "%.1f", max(0, location.speed))) m/s")
        }
        reevaluate()
    }

    /// Valoración por la precisión de la lectura recibida (no mide "señal" del satélite).
    static func quality(for accuracy: CLLocationAccuracy) -> GPSQuality {
        switch accuracy {
        case ..<10: return .excellent
        case ..<30: return .good
        case ..<100: return .fair
        default: return .poor
        }
    }

    /// Filtro exponencial: suaviza vibraciones pequeñas y deja pasar movimientos reales.
    private func smooth(_ new: CLLocation) -> CLLocation {
        guard let prev = smoothedLocation, new.horizontalAccuracy < 100 else { return new }
        let jump = new.distance(from: prev)
        // Un salto grande, buena señal o desplazamiento claro: fiarse del fix nuevo. En marcha la suavidad la pone la
        // animación de la flecha (MarkerMotion); filtrar aquí también solo añadiría retraso.
        if jump > 40 || new.horizontalAccuracy < 8 || (new.speed > 2 && new.course >= 0) { return new }
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

    /// En marcha manda el course del GPS; parado, la brújula (con histéresis: `HeadingSourceSelector`).
    private func updateHeading(with location: CLLocation) {
        if let heading = headingSelector.ingestFix(speed: location.speed, course: location.course,
                                                   courseAccuracy: location.courseAccuracy),
           heading != displayHeading {
            displayHeading = heading
        }
    }

    /// Lectura de la brújula (grados verdaderos si los hay). Solo se muestra si la fuente activa es la brújula.
    func ingestCompass(_ value: Double, accuracy: Double) {
        if let heading = headingSelector.ingestCompass(value, accuracy: accuracy), heading != displayHeading {
            displayHeading = heading
        }
    }

    func didFail(_ error: CLError) {
        switch error.code {
        case .denied:
            log("error", outcome: "error", kind: "denied", code: error.errorCode)
            refreshAuthState()
        case .locationUnknown:
            // Temporal: iOS sigue intentándolo. NO es una pérdida; se conserva la última posición.
            lastTemporaryErrorAt = clock()
            log("error", outcome: "error", kind: "locationUnknown", code: error.errorCode)
            reevaluate()
        default:
            log("error", outcome: "error", kind: "other", code: error.errorCode)
        }
    }

    /// Registro sin coordenadas (solo estados, códigos y precisiones).
    private func log(_ operation: String, outcome: String = "ok", kind: String? = nil, code: Int? = nil, note: String? = nil) {
        diagnostics.record(DiagnosticEvent(date: clock(), service: "location", operation: operation, outcome: outcome,
                                           errorKind: kind, code: code, httpStatus: nil, durationMs: 0, attempt: 1, note: note))
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
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in self.ingestCompass(value, accuracy: accuracy) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError else { return }
        Task { @MainActor in self.didFail(clError) }
    }
}
