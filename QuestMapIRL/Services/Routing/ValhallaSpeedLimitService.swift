import Foundation
import CoreLocation

protocol SpeedLimitProviding: Sendable {
    /// Perfil de límites a lo largo de una ruta (una sola consulta por ruta, no por lectura GPS).
    func profile(for coordinates: [CLLocationCoordinate2D]) async throws -> SpeedLimitProfile
}

/// Punto de un recorrido reciente real (modo «también sin ruta»).
struct SpeedLimitTracePoint: Equatable, Sendable {
    var coordinate: CLLocationCoordinate2D
    var accuracy: Double

    static func == (a: Self, b: Self) -> Bool {
        a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude && a.accuracy == b.accuracy
    }
}

protocol SpeedLimitTraceMatching: Sendable {
    /// Asocia un recorrido reciente a la red viaria (map matching del proveedor) y devuelve las aristas y la asociación de
    /// cada punto. El último punto indica la vía actual.
    func match(trace: [SpeedLimitTracePoint]) async throws -> SpeedLimitMatch
}

/// Límites de velocidad de OpenStreetMap vía el servidor PÚBLICO DE DEMOSTRACIÓN de Valhalla (FOSSGIS), operación
/// `trace_attributes` (map matching). Sin clave ni coste. Solo hay dato donde OSM tiene la etiqueta `maxspeed`; lo demás
/// queda sin dato. Cobertura variable, sin garantías de servicio ni de disponibilidad.
///
/// Qué se envía a ese servidor (solo con el ajuste «Mostrar señal» activado):
/// - Navegando: la geometría de la ruta.
/// - «También sin ruta» (desactivado por defecto): los últimos ~400 m recorridos, sin puntos cerca de Casa/Trabajo.
struct ValhallaSpeedLimitService: SpeedLimitProviding, SpeedLimitTraceMatching {
    static let defaultEndpoint = URL(string: "https://valhalla1.openstreetmap.de/trace_attributes")!

    var endpoint: URL
    var client: ServiceClient
    var chunkMeters: Double = 15_000
    var minPointSpacing: Double = 20
    var maxChunks = 20
    private let cache = SpeedLimitCache()

    init(endpoint: URL = ValhallaSpeedLimitService.defaultEndpoint,
         client: ServiceClient = ServiceClient(service: "valhalla")) {
        self.endpoint = endpoint
        self.client = client
    }

    func profile(for coordinates: [CLLocationCoordinate2D]) async throws -> SpeedLimitProfile {
        guard coordinates.count >= 2 else { throw SpeedLimitError.noData }
        let key = Self.signature(coordinates)
        if let cached = cache.value(for: key) { return cached }

        let (points, meters) = Self.thinnedWithMeters(coordinates, minSpacing: minPointSpacing)
        let total = Self.length(coordinates)
        var pieces: [SpeedLimitProfileBuilder.Piece] = []
        var anySuccess = false
        for range in Self.chunkRanges(meters: meters, chunkMeters: chunkMeters, maxChunks: maxChunks) {
            try Task.checkCancellation()
            let shape = Array(points[range])
            let pointMeters = Array(meters[range])
            do {
                let data = try await client.data(for: Self.request(endpoint: endpoint, shape: shape), operation: "speed-limits")
                let match = try SpeedLimitParser.match(from: data)
                // Si no devuelve un resultado por cada punto enviado, no se puede ubicar nada con seguridad.
                guard match.points.count == shape.count else { throw SpeedLimitError.decoding }
                pieces.append(.init(pointMeters: pointMeters, match: match))
                anySuccess = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                pieces.append(.init(pointMeters: pointMeters, match: nil))   // ese trozo queda sin dato (se reintentará)
            }
        }
        guard anySuccess else { throw SpeedLimitError.noData }
        let profile = SpeedLimitProfileBuilder.build(pieces: pieces, routeMeters: total)
        // Lo que quede más allá del último trozo consultado (rutas de más de 300 km) también queda sin dato; no cuenta
        // como fallo, así que no se reintenta.
        if profile.isComplete { cache.store(profile, for: key) }
        return profile
    }

    func match(trace: [SpeedLimitTracePoint]) async throws -> SpeedLimitMatch {
        guard trace.count >= 2 else { throw SpeedLimitError.noData }
        let accuracy = min(50, max(5, trace.map(\.accuracy).max() ?? 10))
        let request = Self.request(endpoint: endpoint, shape: trace.map(\.coordinate),
                                   traceOptions: ["search_radius": min(40, accuracy * 2), "gps_accuracy": accuracy])
        let data = try await client.data(for: request, operation: "speed-limit-live")
        let match = try SpeedLimitParser.match(from: data)
        guard match.points.count == trace.count else { throw SpeedLimitError.decoding }
        return match
    }

    // MARK: - Piezas puras (probadas sin red)

    static let requestedAttributes = [
        "edge.speed_limit", "edge.length", "edge.way_id", "edge.names", "node.admin_index", "admin.country_code",
        "matched.type", "matched.edge_index", "matched.distance_along_edge", "matched.distance_from_trace_point",
    ]

    static func request(endpoint: URL, shape: [CLLocationCoordinate2D], traceOptions: [String: Double]? = nil) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("QuestMapIRL/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        var body: [String: Any] = [
            "shape": shape.map { ["lat": $0.latitude, "lon": $0.longitude] },
            "costing": "auto",
            "shape_match": "map_snap",
            "units": "kilometers",
            "filters": ["attributes": requestedAttributes, "action": "include"],
        ]
        if let traceOptions { body["trace_options"] = traceOptions }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            // Solo números y textos: no puede fallar. Si fallara, la petición sale sin cuerpo y el servidor la rechaza.
            assertionFailure("Cuerpo de trace_attributes no serializable: \(error)")
        }
        return request
    }

    static func length(_ points: [CLLocationCoordinate2D]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Reduce puntos casi iguales (la ruta de OSRM es muy densa) sin perder el primero ni el último, y devuelve la
    /// distancia de la ruta ORIGINAL a la que está cada punto conservado.
    static func thinnedWithMeters(_ points: [CLLocationCoordinate2D], minSpacing: Double)
        -> (points: [CLLocationCoordinate2D], meters: [Double]) {
        guard let first = points.first else { return ([], []) }
        var kept = [first]
        var keptMeters = [0.0]
        var along = 0.0
        for index in 1..<points.count {
            along += distance(points[index - 1], points[index])
            let isLast = index == points.count - 1
            if isLast || distance(kept[kept.count - 1], points[index]) >= minSpacing {
                kept.append(points[index])
                keptMeters.append(along)
            }
        }
        return (kept, keptMeters)
    }

    /// Compatibilidad: solo los puntos.
    static func thinned(_ points: [CLLocationCoordinate2D], minSpacing: Double) -> [CLLocationCoordinate2D] {
        thinnedWithMeters(points, minSpacing: minSpacing).points
    }

    /// Trozos contiguos de ~`chunkMeters` sobre los puntos ya reducidos; el último punto de un trozo es el primero del
    /// siguiente (no quedan huecos).
    static func chunkRanges(meters: [Double], chunkMeters: Double, maxChunks: Int) -> [ClosedRange<Int>] {
        guard meters.count >= 2 else { return [] }
        var ranges: [ClosedRange<Int>] = []
        var start = 0
        for index in 1..<meters.count where meters[index] - meters[start] >= chunkMeters || index == meters.count - 1 {
            ranges.append(start...index)
            start = index
            if ranges.count == maxChunks { break }
        }
        return ranges
    }

    static func signature(_ points: [CLLocationCoordinate2D]) -> String {
        let a = points[0], b = points[points.count - 1], m = points[points.count / 2]
        return String(format: "%d|%.5f,%.5f|%.5f,%.5f|%.5f,%.5f", points.count, a.latitude, a.longitude, m.latitude, m.longitude, b.latitude, b.longitude)
    }
}

/// Caché en memoria de los perfiles COMPLETOS ya calculados: evita repetir la consulta al recalcular a la misma ruta.
/// Caduca a los 30 minutos (los datos de OSM cambian poco, pero no se guardan para siempre) y guarda como mucho 6 rutas.
/// No se escribe en disco.
final class SpeedLimitCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(key: String, profile: SpeedLimitProfile, storedAt: Date)] = []
    private let lifetime: TimeInterval
    private let clock: () -> Date

    init(lifetime: TimeInterval = 30 * 60, clock: @escaping () -> Date = Date.init) {
        self.lifetime = lifetime
        self.clock = clock
    }

    func value(for key: String) -> SpeedLimitProfile? {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        entries.removeAll { now.timeIntervalSince($0.storedAt) > lifetime }
        return entries.first { $0.key == key }?.profile
    }

    func store(_ profile: SpeedLimitProfile, for key: String) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.key == key }
        entries.append((key, profile, clock()))
        if entries.count > 6 { entries.removeFirst() }
    }
}
