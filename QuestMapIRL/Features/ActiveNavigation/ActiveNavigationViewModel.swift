import CoreLocation
import Observation

/// Estado de una navegación en curso. Recibe lecturas REALES de ubicación y delega la geometría
/// en `NavigationEngine` (dominio puro). No extrapola: si no llegan lecturas (túnel, sin señal), las
/// instrucciones se pausan en vez de basarse en una estimación.
@MainActor
@Observable
final class ActiveNavigationViewModel {
    private(set) var route: Route
    private(set) var snapshot = NavigationSnapshot()
    private(set) var isRecalculating = false
    private(set) var recalculationFailed = false
    private(set) var speedKmh: Double = 0
    private(set) var visitedKeys: Set<String> = []
    /// Qué muestra la señal de límite (oculta, sin dato o la cifra de la ruta activa).
    private(set) var speedLimit: SpeedLimitDisplay = .hidden
    var finished = false

    let destinationName: String
    let destination: CLLocationCoordinate2D
    let mode: RouteMode
    let startedAt = Date()
    let useMetric: Bool

    private var engine: NavigationEngine
    private var offRouteCount = 0
    private var announced: (index: Int, band: Int)?
    private var lastLocation: CLLocation?
    private var traveledMeters: Double = 0
    private var lastRecalculation = Date.distantPast
    private var hasStarted = false

    private let routeService: RouteServiceProtocol
    private let speech: SpeechService
    private let speedLimitService: SpeedLimitProviding?
    private var showsSpeedLimit: Bool
    private var speedProfile: SpeedLimitProfile?
    private var speedTracker = SpeedLimitTracker()
    private var speedLimitTask: Task<Void, Never>?

    init(route: Route, destinationName: String, destination: CLLocationCoordinate2D,
         mode: RouteMode, routeService: RouteServiceProtocol, speech: SpeechService, useMetric: Bool,
         speedLimitService: SpeedLimitProviding? = nil, showsSpeedLimit: Bool = false) {
        self.route = route
        self.destinationName = destinationName
        self.destination = destination
        self.mode = mode
        self.routeService = routeService
        self.speech = speech
        self.useMetric = useMetric
        self.speedLimitService = speedLimitService
        self.showsSpeedLimit = showsSpeedLimit
        self.engine = Self.makeEngine(route)
    }

    // MARK: - Datos para el HUD

    private var upcomingStep: RouteStep? {
        guard !route.steps.isEmpty else { return nil }
        return route.steps[min(snapshot.upcomingIndex, route.steps.count - 1)]
    }

    var currentInstruction: String { upcomingStep?.instruction ?? "Continúa por la ruta" }
    var maneuverSymbol: String { upcomingStep?.symbol ?? "arrow.up" }
    var upcomingStreet: String { upcomingStep?.streetName ?? "" }

    var nextInstruction: String? {
        let next = snapshot.upcomingIndex + 1
        guard next < route.steps.count else { return nil }
        let text = route.steps[next].instruction
        return text.isEmpty ? nil : text
    }

    var nextSymbol: String {
        let next = snapshot.upcomingIndex + 1
        return next < route.steps.count ? route.steps[next].symbol : "arrow.up"
    }

    var eta: Date { Date().addingTimeInterval(snapshot.remainingSeconds) }
    var hasArrived: Bool { snapshot.hasArrived }

    // MARK: - Ciclo

    func start() {
        // Si se inicia dos veces, el aviso de inicio suena solo una.
        guard !hasStarted else { return }
        hasStarted = true
        refreshSpeedProfile()
        speech.announce("Empezamos la ruta hacia \(destinationName).")
    }

    func update(with location: CLLocation) {
        // Lecturas inválidas: no se usan para guiar.
        guard location.horizontalAccuracy >= 0 else { return }

        if let last = lastLocation {
            let delta = location.distance(from: last)
            if delta < 200 { traveledMeters += delta }   // ignora saltos por mala señal
        }
        lastLocation = location
        speedKmh = max(0, location.speed) * 3.6
        visitedKeys.insert(FogGrid.key(for: location.coordinate))

        snapshot = engine.update(with: location.coordinate)
        updateSpeedLimit(with: location)
        announceIfNeeded()

        if snapshot.hasArrived {
            speech.announce("Has llegado a tu destino.", interrupt: true)
            finished = true
            return
        }

        // Recálculo: exige varias lecturas seguidas fuera de ruta, tolerancia según la precisión
        // del GPS, descarta lecturas muy imprecisas y respeta una pausa entre peticiones.
        let tolerance = max(engine.offRouteThreshold, location.horizontalAccuracy * 1.5)
        let isOffRoute = snapshot.distanceFromRoute > tolerance && location.horizontalAccuracy <= 65
        offRouteCount = isOffRoute ? offRouteCount + 1 : 0
        if offRouteCount >= 3, !isRecalculating, Date().timeIntervalSince(lastRecalculation) > 8 {
            Task { await recalculate(from: location.coordinate) }
        }
    }

    /// Cancelar la navegación: se corta cualquier voz pendiente.
    func stop() {
        speech.stopImmediately()
        speedLimitTask?.cancel()
        finished = true
    }

    // MARK: - Límite de velocidad

    /// Activa o desactiva la señal al instante. Desactivada: no se hace ninguna consulta a ese servicio.
    func setShowsSpeedLimit(_ enabled: Bool) {
        showsSpeedLimit = enabled
        if enabled {
            refreshSpeedProfile()
        } else {
            speedLimitTask?.cancel()
            speedTracker.reset()
            speedLimit = .hidden
        }
    }

    /// Una consulta por ruta (no por lectura GPS). Si falla, la señal queda oculta: nunca se inventa una cifra.
    private func refreshSpeedProfile() {
        guard showsSpeedLimit, let service = speedLimitService, speedProfile == nil, speedLimitTask == nil else { return }
        let coordinates = route.coordinates
        speedLimitTask = Task { [weak self] in
            let profile = try? await service.profile(for: coordinates)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.speedProfile = profile
                self.speedLimitTask = nil
            }
        }
    }

    private func updateSpeedLimit(with location: CLLocation) {
        let progress = engine.totalMeters - snapshot.remainingMeters
        speedLimit = speedTracker.update(enabled: showsSpeedLimit, profile: speedProfile, progressMeters: progress,
                                         isOffRoute: offRouteCount > 0 || snapshot.isOffRoute,
                                         accuracy: location.horizontalAccuracy,
                                         age: -location.timestamp.timeIntervalSinceNow)
    }

    func summary() -> TripSummary {
        TripSummary(
            startedAt: startedAt,
            distanceMeters: traveledMeters,
            durationSeconds: Date().timeIntervalSince(startedAt),
            destinationName: destinationName,
            destinationKey: FogGrid.key(for: destination),
            modeRawValue: mode.rawValue,
            visitedKeys: visitedKeys.union(FogGrid.keys(along: route.coordinates))
        )
    }

    // MARK: - Privado

    /// Anuncia a ~500 m, ~150 m y en el punto; una vez por banda y paso. La primera maniobra
    /// lejana se anuncia nada más empezar.
    private func announceIfNeeded() {
        let distance = snapshot.distanceToManeuver
        let band: Int
        switch distance {
        case ..<40: band = 0
        case ..<180: band = 1
        case ..<550: band = 2
        default: band = 3
        }
        if let last = announced, last.index == snapshot.upcomingIndex, last.band <= band { return }
        let isFirstAnnouncement = announced == nil
        announced = (snapshot.upcomingIndex, band)
        // Una maniobra lejana solo se anuncia al empezar (después, al acercarse).
        if band == 3 && !isFirstAnnouncement { return }
        // La primera indicación se encola tras "Empezamos la ruta"; las demás cancelan la anterior.
        speech.announce(ManeuverFormatter.spoken(instruction: currentInstruction, distance: distance, metric: useMetric),
                        interrupt: !isFirstAnnouncement)
    }

    private func recalculate(from origin: CLLocationCoordinate2D) async {
        isRecalculating = true
        recalculationFailed = false
        lastRecalculation = Date()
        defer { isRecalculating = false }
        speech.announce("Recalculando la ruta.", interrupt: true)
        do {
            if let newRoute = try await routeService.routes(from: origin, to: destination, mode: mode).first {
                route = newRoute
                engine = Self.makeEngine(newRoute)
                speedLimitTask?.cancel()
                speedLimitTask = nil
                speedProfile = nil
                speedTracker.reset()
                speedLimit = .hidden
                refreshSpeedProfile()
                announced = nil
                offRouteCount = 0
            }
        } catch {
            recalculationFailed = true
            speech.announce("No he podido recalcular. Vuelve a la ruta marcada.")
        }
    }

    private static func makeEngine(_ route: Route) -> NavigationEngine {
        NavigationEngine(points: route.coordinates, steps: route.stepInfos, expectedSeconds: route.durationSeconds)
    }
}
