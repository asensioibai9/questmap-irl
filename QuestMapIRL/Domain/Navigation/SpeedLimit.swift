import Foundation
import CoreLocation

/// Límite de velocidad por tramos a lo largo de la RUTA ACTIVA. `limitKmh == nil` significa «el dato no existe»;
/// NUNCA significa «sin límite». Vehículo admitido en esta versión: turismo.
struct SpeedLimitSegment: Equatable {
    var startMeters: Double
    var endMeters: Double
    var limitKmh: Int?
}

struct SpeedLimitProfile: Equatable {
    var segments: [SpeedLimitSegment]
    var routeMeters: Double

    /// Límite en esa distancia recorrida de la ruta, o nil si no hay dato (o está fuera de la ruta).
    func limit(atMeters meters: Double) -> Int? {
        guard meters >= 0, meters <= routeMeters else { return nil }
        return segments.first { meters >= $0.startMeters && meters < $0.endMeters }?.limitKmh
            ?? (meters == routeMeters ? segments.last?.limitKmh : nil)
    }

    /// Fracción de la ruta con dato (para diagnóstico).
    var coverage: Double {
        guard routeMeters > 0 else { return 0 }
        return segments.filter { $0.limitKmh != nil }.reduce(0) { $0 + ($1.endMeters - $1.startMeters) } / routeMeters
    }
}

/// Un tramo (arista) devuelto por el servicio de límites, ya interpretado.
struct SpeedLimitEdge: Equatable {
    var lengthMeters: Double
    var limitKmh: Int?
}

enum SpeedLimitParser {
    /// Valores razonables para un turismo. 255 es la marca de «sin límite explícito» en el servicio y cualquier otro valor
    /// fuera de rango se descarta: no se interpreta como un límite confirmado.
    static let validRange = 5...200

    static func limit(from raw: Any?) -> Int? {
        let value: Int?
        switch raw {
        case let int as Int: value = int
        case let double as Double: value = Int(double.rounded())
        default: value = nil
        }
        guard let value, validRange.contains(value) else { return nil }
        return value
    }

    /// Interpreta la respuesta de `trace_attributes` (solicitada con `units = kilometers`).
    static func edges(from data: Data) throws -> [SpeedLimitEdge] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let edges = json["edges"] as? [[String: Any]] else { throw SpeedLimitError.decoding }
        guard (json["units"] as? String) ?? "kilometers" == "kilometers" else { throw SpeedLimitError.decoding }
        return edges.compactMap { edge in
            guard let km = edge["length"] as? Double ?? (edge["length"] as? Int).map(Double.init), km >= 0 else { return nil }
            return SpeedLimitEdge(lengthMeters: km * 1000, limitKmh: limit(from: edge["speed_limit"]))
        }
    }
}

enum SpeedLimitError: Error, Equatable {
    case decoding
    case noData
}

enum SpeedLimitProfileBuilder {
    /// Une los resultados de varios trozos de la ruta. Si la longitud total de las aristas devueltas no cuadra con la del trozo
    /// (el servicio ajustó el trazado a otra vía), ese trozo se deja SIN DATO en vez de arriesgar un límite equivocado.
    static func build(chunks: [(startMeters: Double, lengthMeters: Double, edges: [SpeedLimitEdge]?)],
                      routeMeters: Double, tolerance: ClosedRange<Double> = 0.8...1.25) -> SpeedLimitProfile {
        var segments: [SpeedLimitSegment] = []
        func append(_ start: Double, _ end: Double, _ limit: Int?) {
            guard end > start else { return }
            if let last = segments.last, last.limitKmh == limit, abs(last.endMeters - start) < 0.5 {
                segments[segments.count - 1].endMeters = end
            } else {
                segments.append(SpeedLimitSegment(startMeters: start, endMeters: end, limitKmh: limit))
            }
        }
        for chunk in chunks {
            let end = min(chunk.startMeters + chunk.lengthMeters, routeMeters)
            let sum = chunk.edges?.reduce(0) { $0 + $1.lengthMeters } ?? 0
            guard let edges = chunk.edges, sum > 0, tolerance.contains(sum / max(chunk.lengthMeters, 1)) else {
                append(chunk.startMeters, end, nil)
                continue
            }
            let scale = chunk.lengthMeters / sum
            var cursor = chunk.startMeters
            for edge in edges {
                let next = min(cursor + edge.lengthMeters * scale, end)
                append(cursor, next, edge.limitKmh)
                cursor = next
            }
            append(cursor, end, nil)
        }
        return SpeedLimitProfile(segments: segments, routeMeters: routeMeters)
    }
}

// MARK: - Qué se muestra

enum SpeedLimitDisplay: Equatable {
    /// Señal oculta (función desactivada, sin ruta, cargando, ubicación dudosa o fuera de ruta).
    case hidden
    /// Función activa y ruta cubierta, pero sin dato fiable en este tramo.
    case unavailable
    case limit(kmh: Int)
}

/// Decide qué mostrar a partir de la posición sobre la ruta. Evita parpadeos: un cambio de límite debe repetirse en
/// lecturas consecutivas antes de aplicarse, y la señal se esconde cuando la posición no es fiable.
struct SpeedLimitTracker {
    var confirmationsNeeded = 2
    var maxAccuracy: Double = 80
    var maxAge: TimeInterval = 10

    private(set) var shown: SpeedLimitDisplay = .hidden
    private var candidate: SpeedLimitDisplay?
    private var candidateCount = 0

    mutating func reset() {
        shown = .hidden
        candidate = nil
        candidateCount = 0
    }

    mutating func update(enabled: Bool, profile: SpeedLimitProfile?, progressMeters: Double, isOffRoute: Bool,
                         accuracy: Double, age: TimeInterval) -> SpeedLimitDisplay {
        guard enabled, let profile, !isOffRoute, accuracy >= 0, accuracy <= maxAccuracy, age <= maxAge else {
            reset()
            return .hidden
        }
        let target: SpeedLimitDisplay = profile.limit(atMeters: progressMeters).map { .limit(kmh: $0) } ?? .unavailable
        if target == shown { candidate = nil; candidateCount = 0; return shown }
        if shown == .hidden {
            // Primera lectura fiable: se muestra al instante.
            shown = target
            return shown
        }
        if candidate == target { candidateCount += 1 } else { candidate = target; candidateCount = 1 }
        if candidateCount >= confirmationsNeeded {
            shown = target
            candidate = nil
            candidateCount = 0
        }
        return shown
    }
}

enum SpeedLimitFormatter {
    /// Número de la señal en las unidades elegidas. En mph se redondea a múltiplos de 5, como las señales.
    static func signNumber(kmh: Int, metric: Bool) -> Int {
        metric ? kmh : Int((Double(kmh) * 0.621371 / 5).rounded()) * 5
    }

    static func spokenLabel(_ display: SpeedLimitDisplay, metric: Bool) -> String {
        switch display {
        case .hidden: return ""
        case .unavailable: return "Límite de velocidad no disponible"
        case .limit(let kmh):
            return "Límite de velocidad: \(signNumber(kmh: kmh, metric: metric)) \(metric ? "kilómetros por hora" : "millas por hora")"
        }
    }
}
