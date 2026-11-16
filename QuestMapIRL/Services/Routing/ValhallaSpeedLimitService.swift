import Foundation
import CoreLocation

protocol SpeedLimitProviding: Sendable {
    /// Perfil de límites a lo largo de una ruta (una sola consulta por ruta, no por lectura GPS).
    func profile(for coordinates: [CLLocationCoordinate2D]) async throws -> SpeedLimitProfile
}

/// Límites de velocidad de OpenStreetMap vía el servidor PÚBLICO DE DEMOSTRACIÓN de Valhalla (FOSSGIS), operación
/// `trace_attributes`. Sin clave ni coste. Solo hay dato donde OSM tiene la etiqueta `maxspeed`; lo demás queda sin dato.
/// Cobertura variable, sin garantías de servicio. Para producción hay que usar un servidor propio o contratado.
///
/// Se envía la geometría de la ruta (coordenadas) a ese servidor: solo cuando el ajuste «Mostrar límite de velocidad»
/// está activado.
struct ValhallaSpeedLimitService: SpeedLimitProviding {
    var endpoint = URL(string: "https://valhalla1.openstreetmap.de/trace_attributes")!
    var client = ServiceClient(service: "valhalla")
    var chunkMeters: Double = 15_000
    var minPointSpacing: Double = 20
    var maxChunks = 20
    private let cache = SpeedLimitCache()

    init(endpoint: URL = URL(string: "https://valhalla1.openstreetmap.de/trace_attributes")!,
         client: ServiceClient = ServiceClient(service: "valhalla")) {
        self.endpoint = endpoint
        self.client = client
    }

    func profile(for coordinates: [CLLocationCoordinate2D]) async throws -> SpeedLimitProfile {
        guard coordinates.count >= 2 else { throw SpeedLimitError.noData }
        let key = Self.signature(coordinates)
        if let cached = cache.value(for: key) { return cached }

        let pieces = Self.chunks(coordinates, chunkMeters: chunkMeters, maxChunks: maxChunks)
        let total = Self.length(coordinates)
        var results: [(startMeters: Double, lengthMeters: Double, edges: [SpeedLimitEdge]?)] = []
        var anySuccess = false
        for piece in pieces {
            try Task.checkCancellation()
            let shape = Self.thinned(piece.points, minSpacing: minPointSpacing)
            do {
                let data = try await client.data(for: Self.request(endpoint: endpoint, shape: shape), operation: "speed-limits")
                let edges = try SpeedLimitParser.edges(from: data)
                results.append((piece.startMeters, piece.lengthMeters, edges))
                anySuccess = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append((piece.startMeters, piece.lengthMeters, nil))   // ese trozo queda sin dato
            }
        }
        // Lo que quede más allá del último trozo consultado también queda sin dato.
        guard anySuccess else { throw SpeedLimitError.noData }
        let profile = SpeedLimitProfileBuilder.build(chunks: results, routeMeters: total)
        cache.store(profile, for: key)
        return profile
    }

    // MARK: - Piezas puras (probadas sin red)

    static func request(endpoint: URL, shape: [CLLocationCoordinate2D]) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("QuestMapIRL/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "shape": shape.map { ["lat": $0.latitude, "lon": $0.longitude] },
            "costing": "auto",
            "shape_match": "map_snap",
            "units": "kilometers",
            "filters": ["attributes": ["edge.speed_limit", "edge.length"], "action": "include"],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func length(_ points: [CLLocationCoordinate2D]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Divide la ruta en trozos contiguos de ~`chunkMeters` (el último punto de uno es el primero del siguiente).
    static func chunks(_ points: [CLLocationCoordinate2D], chunkMeters: Double, maxChunks: Int)
        -> [(startMeters: Double, lengthMeters: Double, points: [CLLocationCoordinate2D])] {
        var result: [(Double, Double, [CLLocationCoordinate2D])] = []
        var current: [CLLocationCoordinate2D] = [points[0]]
        var start = 0.0
        var accumulated = 0.0
        for (previous, point) in zip(points, points.dropFirst()) {
            accumulated += distance(previous, point)
            current.append(point)
            if accumulated >= chunkMeters {
                result.append((start, accumulated, current))
                start += accumulated
                accumulated = 0
                current = [point]
            }
        }
        if current.count >= 2 { result.append((start, accumulated, current)) }
        return Array(result.prefix(maxChunks)).map { (startMeters: $0.0, lengthMeters: $0.1, points: $0.2) }
    }

    /// Reduce puntos casi iguales (la ruta completa de OSRM es muy densa) sin perder el primero ni el último.
    static func thinned(_ points: [CLLocationCoordinate2D], minSpacing: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var kept = [points[0]]
        for point in points.dropFirst().dropLast() where distance(kept[kept.count - 1], point) >= minSpacing { kept.append(point) }
        kept.append(points[points.count - 1])
        return kept
    }

    static func signature(_ points: [CLLocationCoordinate2D]) -> String {
        let a = points[0], b = points[points.count - 1], m = points[points.count / 2]
        return String(format: "%d|%.5f,%.5f|%.5f,%.5f|%.5f,%.5f", points.count, a.latitude, a.longitude, m.latitude, m.longitude, b.latitude, b.longitude)
    }
}

/// Caché en memoria de los perfiles ya calculados (evita repetir la consulta al recalcular a la misma ruta).
final class SpeedLimitCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(key: String, profile: SpeedLimitProfile)] = []

    func value(for key: String) -> SpeedLimitProfile? {
        lock.lock(); defer { lock.unlock() }
        return entries.first { $0.key == key }?.profile
    }

    func store(_ profile: SpeedLimitProfile, for key: String) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.key == key }
        entries.append((key, profile))
        if entries.count > 6 { entries.removeFirst() }
    }
}
