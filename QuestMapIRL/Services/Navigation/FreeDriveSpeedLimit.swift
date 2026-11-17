import CoreLocation
import Observation

/// Límite de velocidad SIN ruta activa (opcional, desactivado por defecto). Envía al proveedor el recorrido REAL reciente
/// (los últimos ~400 m) para que haga map matching: así la vía se elige teniendo en cuenta la continuidad del recorrido y
/// el sentido de circulación, no solo la calle más cercana.
///
/// - Solo consulta en movimiento (> ~14 km/h), con buena precisión, como mucho cada 12 s y cada 200 m.
/// - Nunca envía puntos a menos de 300 m de Casa o Trabajo: al acercarse se vacía el recorrido guardado.
/// - El resultado vale para lo que queda de la vía identificada más un margen; después, «ubicación insuficiente»
///   hasta la siguiente respuesta. No se mantiene la última cifra indefinidamente.
/// - Las respuestas llevan número de orden: una antigua que llega tarde se descarta.
/// - Usa las lecturas REALES del GPS, nunca la posición animada de la flecha.
@MainActor
@Observable
final class FreeDriveSpeedLimit {
    struct Config {
        var minSpeed: Double = 4                 // m/s
        var maxAccuracy: Double = 30
        var maxAge: TimeInterval = 6
        var minQueryInterval: TimeInterval = 12
        var minQueryDistance: Double = 200
        var traceSpan: Double = 400
        var minTraceSpan: Double = 120
        var minPointSpacing: Double = 15
        var maxPoints = 16
        var privacyRadius: Double = 300
        var maxSnapMeters: Double = 20
        var resultMaxAge: TimeInterval = 180
        var extraValidMeters: Double = 200
    }

    private(set) var display: SpeedLimitDisplay = .hidden
    private(set) var countryCode: String?
    private(set) var currentSpeedKmh: Double?
    /// Estado para el diagnóstico (sin coordenadas).
    private(set) var status = "desactivado"

    @ObservationIgnored var config = Config()
    /// Lugares personales (Casa/Trabajo) cerca de los cuales NO se envía nada. nil = no se pudieron leer: no se envía nada.
    @ObservationIgnored var excludedAreas: () -> [CLLocationCoordinate2D]? = { [] }
    @ObservationIgnored private let matcher: SpeedLimitTraceMatching
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private(set) var isEnabled = false
    @ObservationIgnored private var buffer: [CLLocation] = []
    @ObservationIgnored private var lastQuery: (at: Date, location: CLLocation)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var appliedSequence = 0
    @ObservationIgnored private var result: (limit: Int?, location: CLLocation, validMeters: Double, at: Date)?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var retryAt: Date?
    @ObservationIgnored private(set) var requestCount = 0

    init(matcher: SpeedLimitTraceMatching, clock: @escaping () -> Date = Date.init) {
        self.matcher = matcher
        self.clock = clock
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        reset()
        display = enabled ? .insufficientLocation : .hidden
        status = enabled ? "esperando movimiento" : "desactivado"
    }

    /// Suelta todo (al empezar una navegación, que tiene su propia fuente, o al desactivar).
    func reset() {
        task?.cancel()
        task = nil
        sequence += 1
        appliedSequence = sequence
        buffer.removeAll()
        lastQuery = nil
        result = nil
        failures = 0
        retryAt = nil
        countryCode = nil
        currentSpeedKmh = nil
        display = isEnabled ? .insufficientLocation : .hidden
    }

    /// Lectura REAL nueva.
    func ingest(_ location: CLLocation) {
        guard isEnabled else { return }
        let now = clock()
        currentSpeedKmh = SpeedLimitFormatter.currentSpeedKmh(location)
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= config.maxAccuracy,
              now.timeIntervalSince(location.timestamp) <= config.maxAge else {
            display = .insufficientLocation
            return
        }
        if isNearExcludedArea(location.coordinate) {
            // Cerca de Casa/Trabajo: no se guarda ni se envía nada.
            buffer.removeAll()
            result = nil
            display = .insufficientLocation
            status = "en pausa cerca de un lugar personal"
            return
        }
        if let last = buffer.last {
            if location.distance(from: last) >= config.minPointSpacing { buffer.append(location) }
        } else {
            buffer.append(location)
        }
        trimBuffer()
        display = currentDisplay(at: location, now: now)
        queryIfNeeded(at: location, now: now)
    }

    /// Llamada periódica (cambios de estado de la ubicación): caduca el resultado si no llegan lecturas.
    func checkFreshness() {
        guard isEnabled, let last = buffer.last else { return }
        if clock().timeIntervalSince(last.timestamp) > config.maxAge { display = .insufficientLocation }
    }

    // MARK: - Privado

    private func isNearExcludedArea(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let areas = excludedAreas() else { return true }
        return areas.contains {
            here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < config.privacyRadius
        }
    }

    private func trimBuffer() {
        guard let last = buffer.last else { return }
        while buffer.count > config.maxPoints || (buffer.count > 2 && buffer[0].distance(from: last) > config.traceSpan) {
            buffer.removeFirst()
        }
    }

    private var traceSpan: Double {
        guard buffer.count >= 2 else { return 0 }
        return zip(buffer, buffer.dropFirst()).reduce(0) { $0 + $1.1.distance(from: $1.0) }
    }

    private func currentDisplay(at location: CLLocation, now: Date) -> SpeedLimitDisplay {
        guard let result else { return .insufficientLocation }
        let moved = location.distance(from: result.location)
        guard moved <= result.validMeters, now.timeIntervalSince(result.at) <= config.resultMaxAge else {
            return .insufficientLocation
        }
        return result.limit.map { .limit(kmh: $0) } ?? .unavailable
    }

    private func queryIfNeeded(at location: CLLocation, now: Date) {
        guard task == nil, location.speed >= config.minSpeed, buffer.count >= 4, traceSpan >= config.minTraceSpan else { return }
        if let retryAt, now < retryAt { return }
        if let lastQuery {
            let soon = now.timeIntervalSince(lastQuery.at) < config.minQueryInterval
            let near = location.distance(from: lastQuery.location) < config.minQueryDistance
            let expiring = result.map { location.distance(from: $0.location) > $0.validMeters - 60 } ?? true
            if soon || (near && !expiring) { return }
        }
        sequence += 1
        let order = sequence
        let trace = buffer.map { SpeedLimitTracePoint(coordinate: $0.coordinate, accuracy: $0.horizontalAccuracy) }
        let anchor = location
        lastQuery = (now, location)
        requestCount += 1
        status = "consultando"
        let matcher = matcher
        task = Task { [weak self] in
            let outcome: Result<SpeedLimitMatch, Error>
            do {
                outcome = .success(try await matcher.match(trace: trace))
            } catch {
                outcome = .failure(error)
            }
            self?.apply(outcome, order: order, anchor: anchor)
        }
    }

    /// Aplica una respuesta. Público para las pruebas de respuestas fuera de orden.
    func apply(_ outcome: Result<SpeedLimitMatch, Error>, order: Int, anchor: CLLocation) {
        if order == sequence { task = nil }
        guard isEnabled, order > appliedSequence else { return }          // respuesta antigua o tras desactivar
        let now = clock()
        switch outcome {
        case .failure(let error):
            if error is CancellationError { return }
            failures += 1
            retryAt = now.addingTimeInterval(ActiveNavigationViewModel.retryDelay(attempt: failures))
            status = "error del proveedor o sin red; reintento en \(Int(ActiveNavigationViewModel.retryDelay(attempt: failures))) s"
        case .success(let match):
            appliedSequence = order
            failures = 0
            retryAt = nil
            countryCode = match.countryCode
            if let identified = Self.currentEdge(of: match, maxSnapMeters: config.maxSnapMeters) {
                let speed = max(0, anchor.speed)
                result = (identified.limit, anchor, identified.remainingMeters + max(config.extraValidMeters, speed * 15), now)
                status = identified.limit == nil ? "vía identificada, sin dato" : "vía identificada"
            } else {
                result = nil
                status = "no se pudo identificar la vía con seguridad"
            }
        }
        if let last = buffer.last { display = currentDisplay(at: last, now: now) }
    }

    /// Vía del ÚLTIMO punto enviado, si el proveedor la asoció con seguridad.
    static func currentEdge(of match: SpeedLimitMatch, maxSnapMeters: Double) -> (limit: Int?, remainingMeters: Double)? {
        guard let point = match.points.last, point.kind != .unmatched, let index = point.edgeIndex,
              index >= 0, index < match.edges.count else { return nil }
        if let offset = point.distanceFromTrace, offset > maxSnapMeters { return nil }
        let edge = match.edges[index]
        let remaining = (1 - min(1, max(0, point.distanceAlongEdge ?? 1))) * edge.lengthMeters
        return (edge.limitKmh, remaining)
    }
}
