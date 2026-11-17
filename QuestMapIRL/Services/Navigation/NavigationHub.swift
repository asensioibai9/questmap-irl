import CoreLocation
import Observation

/// Fuente de verdad ÚNICA de la navegación activa. La comparten la pantalla del iPhone y CarPlay: no hay sesiones
/// independientes, ni recálculos o indicaciones de voz duplicados. Vive fuera de cualquier vista, así que la navegación
/// sigue con el iPhone bloqueado, sin la pantalla del teléfono creada y al conectar o desconectar CarPlay.
@MainActor
@Observable
final class NavigationHub {
    private(set) var session: ActiveNavigationViewModel?
    private(set) var destination: Place?
    /// Cambia cada vez que empieza una navegación (las pantallas reaccionan a esto).
    private(set) var startToken = 0
    /// Cambia cada vez que termina (llegada, cancelación o cambio de destino).
    private(set) var endToken = 0
    private(set) var lastEndWasArrival = false

    @ObservationIgnored let location: LocationServiceProtocol
    @ObservationIgnored let routeService: RouteServiceProtocol
    @ObservationIgnored let speech: SpeechService
    @ObservationIgnored let speedLimits: SpeedLimitProviding?
    /// Límite sin ruta (opcional). Nil si no hay proveedor de map matching (pruebas).
    let freeDrive: FreeDriveSpeedLimit?
    /// Ajustes relevantes (unidades y límite de velocidad). Se leen al empezar y no tocan el almacén desde aquí.
    @ObservationIgnored var settings: () -> (useMetric: Bool, showSpeedLimit: Bool)
    /// Guarda el viaje terminado (SwiftData). Lo conecta la app; en tests puede quedarse en nil.
    @ObservationIgnored var tripStore: ((TripSummary) -> Void)?
    @ObservationIgnored private var trackingToken = 0
    @ObservationIgnored private var freeDriveToken = 0
    @ObservationIgnored private var wantsFreeDrive = false
    @ObservationIgnored private var lastFedTimestamp: Date?

    init(location: LocationServiceProtocol, routeService: RouteServiceProtocol, speech: SpeechService,
         speedLimits: SpeedLimitProviding?,
         freeDrive: FreeDriveSpeedLimit? = nil,
         settings: @escaping () -> (useMetric: Bool, showSpeedLimit: Bool) = { (true, true) },
         tripStore: ((TripSummary) -> Void)? = nil) {
        self.location = location
        self.routeService = routeService
        self.speech = speech
        self.speedLimits = speedLimits
        self.freeDrive = freeDrive
        self.settings = settings
        self.tripStore = tripStore
    }

    var isNavigating: Bool { session != nil }

    // MARK: - Señal de límite: UNA sola fuente para iPhone y CarPlay

    /// Navegando: el límite del tramo de la ruta. Sin ruta: el del modo «también sin ruta», si está activado.
    var speedLimit: SpeedLimitDisplay { session?.speedLimit ?? freeDrive?.display ?? .hidden }
    var speedLimitCountry: String? { session != nil ? session?.speedLimitCountry : freeDrive?.countryCode }
    var currentSpeedKmh: Double? { session != nil ? session?.currentSpeedKmh : freeDrive?.currentSpeedKmh }

    /// Activa o desactiva el límite sin ruta (ajustes «Mostrar señal» + «También sin ruta»). Aplicación inmediata.
    func setFreeDriveSpeedLimit(_ enabled: Bool) {
        wantsFreeDrive = enabled
        updateFreeDrive()
    }

    private func updateFreeDrive() {
        guard let freeDrive else { return }
        let active = wantsFreeDrive && session == nil
        freeDrive.setEnabled(active)
        freeDriveToken += 1
        if active { trackFreeDrive(token: freeDriveToken) }
    }

    private func trackFreeDrive(token: Int) {
        guard token == freeDriveToken, let freeDrive, freeDrive.isEnabled else { return }
        withObservationTracking {
            _ = location.currentLocation
            _ = location.status
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, token == self.freeDriveToken, let freeDrive = self.freeDrive else { return }
                if let reading = self.location.currentLocation, reading.timestamp != self.lastFedTimestamp {
                    self.lastFedTimestamp = reading.timestamp
                    freeDrive.ingest(reading)
                }
                freeDrive.checkFreshness()
                self.trackFreeDrive(token: token)
            }
        }
    }

    // MARK: - Rutas para vista previa

    /// Rutas desde la ubicación real hasta el destino. Sin ubicación no se inventa un origen.
    func previewRoutes(to place: Place, mode: RouteMode = .driving) async throws -> [Route] {
        guard let origin = location.currentLocation?.coordinate else { throw RoutingError.noRoute }
        return try await routeService.routes(from: origin, to: place.coordinate, mode: mode)
    }

    // MARK: - Ciclo de vida

    /// Empieza una navegación. Si ya había una (cambio de destino) se cierra primero: nunca hay dos a la vez.
    func start(route: Route, destination place: Place, mode: RouteMode) {
        if session != nil { end() }
        let config = settings()
        let new = ActiveNavigationViewModel(
            route: route, destinationName: place.name, destination: place.coordinate, mode: mode,
            routeService: routeService, speech: speech, useMetric: config.useMetric,
            speedLimitService: speedLimits, showsSpeedLimit: config.showSpeedLimit)
        session = new
        destination = place
        updateFreeDrive()                       // la navegación tiene su propia fuente: el modo sin ruta se para
        location.start(mode: .navigating)
        new.start()
        if let reading = location.currentLocation { new.update(with: reading) }
        startToken += 1
        trackingToken += 1
        trackLocation(token: trackingToken)
        watchFinish(of: new)
    }

    /// Cancela la navegación activa (la termina el mismo camino que una llegada).
    func stop() {
        session?.stop()          // marca `finished`; `watchFinish` cierra la sesión
        if session?.finished == true { end() }
    }

    /// Cierra la sesión: guarda el viaje, suelta la voz y baja la precisión del GPS. Es idempotente.
    func end() {
        guard let finishing = session else { return }
        let summary = finishing.summary()
        if summary.distanceMeters >= 100 || finishing.hasArrived { tripStore?(summary) }
        lastEndWasArrival = finishing.hasArrived
        session = nil
        destination = nil
        trackingToken += 1
        updateFreeDrive()
        location.setMode(.idle)
        if finishing.hasArrived {
            speech.releaseAfterSpeaking()      // deja terminar «Has llegado a tu destino»
        } else {
            speech.stopImmediately()
        }
        endToken += 1
    }

    // MARK: - Observación (sin vistas)

    /// Cada lectura real de ubicación alimenta la sesión. Es el ÚNICO sitio que lo hace.
    private func trackLocation(token: Int) {
        guard token == trackingToken, session != nil else { return }
        withObservationTracking {
            _ = location.currentLocation
            _ = location.status            // también cambia sin lecturas nuevas: detecta la pérdida de señal
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, token == self.trackingToken, let session = self.session else { return }
                if let reading = self.location.currentLocation, reading.timestamp != self.lastFedTimestamp {
                    self.lastFedTimestamp = reading.timestamp
                    session.update(with: reading)
                }
                session.checkLocationFreshness()
                self.trackLocation(token: token)
            }
        }
    }

    private func watchFinish(of watched: ActiveNavigationViewModel) {
        withObservationTracking {
            _ = watched.finished
        } onChange: { [weak self, weak watched] in
            Task { @MainActor in
                guard let self, let watched, self.session === watched else { return }
                if watched.finished { self.end() } else { self.watchFinish(of: watched) }
            }
        }
    }
}
