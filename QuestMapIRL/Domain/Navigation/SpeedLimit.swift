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
    /// País del tramo (ISO 3166-1 alfa-2) según el proveedor, solo si toda la ruta está en UN país. Nil = no se sabe.
    var countryCode: String?
    /// false si algún trozo no se pudo consultar (error de red o del servidor): se reintentará más tarde.
    var isComplete = true

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

/// Un tramo (arista dirigida) devuelto por el servicio de límites, ya interpretado. Al ser dirigida, el límite ya es el
/// del sentido de circulación (si OSM lo distingue).
struct SpeedLimitEdge: Equatable {
    var lengthMeters: Double
    var limitKmh: Int?
}

/// Cómo asoció el proveedor cada punto enviado a una vía (map matching).
struct SpeedLimitMatchedPoint: Equatable {
    enum Kind: Equatable { case matched, interpolated, unmatched }
    var kind: Kind
    var edgeIndex: Int?
    /// Fracción (0…1) de la arista en la que cae el punto.
    var distanceAlongEdge: Double?
    /// Metros entre el punto enviado y la vía elegida. Grande = probablemente otra vía (paralela, otro nivel).
    var distanceFromTrace: Double?
}

/// Respuesta completa de una consulta de map matching.
struct SpeedLimitMatch: Equatable {
    var edges: [SpeedLimitEdge]
    var points: [SpeedLimitMatchedPoint]
    var countryCode: String?
}

enum SpeedLimitParser {
    /// Valores razonables para un turismo. 0 (desconocido) y 255 (marca del proveedor para «sin límite explícito»,
    /// p. ej. tramos de autobahn) y cualquier otro valor fuera de rango se descartan: NO se interpretan como un límite
    /// confirmado ni como «sin límite». Un texto (p. ej. «walk», «ES:urban») tampoco se convierte en cifra.
    static let validRange = 5...200

    static func limit(from raw: Any?) -> Int? {
        let value: Int?
        switch raw {
        case let int as Int: value = int
        case let double as Double: value = double.rounded() == double ? Int(double) : nil
        default: value = nil
        }
        guard let value, validRange.contains(value) else { return nil }
        return value
    }

    /// Interpreta la respuesta de `trace_attributes` (solicitada con `units = kilometers`: los límites llegan en km/h).
    static func match(from data: Data) throws -> SpeedLimitMatch {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawEdges = json["edges"] as? [[String: Any]] else { throw SpeedLimitError.decoding }
        guard (json["units"] as? String) ?? "kilometers" == "kilometers" else { throw SpeedLimitError.decoding }
        var edges: [SpeedLimitEdge] = []
        for edge in rawEdges {
            // Una arista sin longitud rompe la correspondencia de índices: mejor descartar la respuesta entera.
            guard let km = edge["length"] as? Double ?? (edge["length"] as? Int).map(Double.init), km >= 0 else {
                throw SpeedLimitError.decoding
            }
            edges.append(SpeedLimitEdge(lengthMeters: km * 1000, limitKmh: limit(from: edge["speed_limit"])))
        }
        let points: [SpeedLimitMatchedPoint] = (json["matched_points"] as? [[String: Any]] ?? []).map { point in
            let kind: SpeedLimitMatchedPoint.Kind
            switch point["type"] as? String {
            case "matched": kind = .matched
            case "interpolated": kind = .interpolated
            default: kind = .unmatched
            }
            return SpeedLimitMatchedPoint(kind: kind,
                                          edgeIndex: point["edge_index"] as? Int,
                                          distanceAlongEdge: number(point["distance_along_edge"]),
                                          distanceFromTrace: number(point["distance_from_trace_point"]))
        }
        let countries = Set((json["admins"] as? [[String: Any]] ?? []).compactMap { $0["country_code"] as? String }
            .filter { $0.count == 2 })
        return SpeedLimitMatch(edges: edges, points: points, countryCode: countries.count == 1 ? countries.first : nil)
    }

    private static func number(_ raw: Any?) -> Double? {
        if let double = raw as? Double { return double }
        if let int = raw as? Int { return Double(int) }
        return nil
    }
}

enum SpeedLimitError: Error, Equatable {
    case decoding
    case noData
}

/// Construye el perfil de la ruta a partir de la asociación PUNTO A PUNTO del proveedor: cada punto enviado (uno cada
/// ~20 m de la ruta) dice en qué arista y en qué fracción de ella cae. Así cada cambio de límite se coloca con un error
/// de unos pocos metros, sin estirar longitudes a lo largo de kilómetros.
///
/// Un tramo entre dos puntos queda SIN DATO si:
/// - alguno de los dos no se pudo asociar o quedó lejos de la vía elegida (`maxSnapMeters`: otra vía paralela, otro nivel);
/// - el camino del proveedor entre ellos no se parece en longitud al de la ruta (`lengthRatio`: el proveedor se fue por
///   otra calle, una salida o un desvío);
/// - el trozo de ruta no se pudo consultar.
enum SpeedLimitProfileBuilder {
    static let maxSnapMeters: Double = 15
    static let lengthRatio: ClosedRange<Double> = 0.6...1.6

    struct Piece {
        /// Distancia de la ruta (m) de cada punto enviado, en el mismo orden que `match.points`.
        var pointMeters: [Double]
        /// nil = este trozo falló.
        var match: SpeedLimitMatch?
    }

    static func build(pieces: [Piece], routeMeters: Double) -> SpeedLimitProfile {
        var segments: [SpeedLimitSegment] = []
        func append(_ start: Double, _ end: Double, _ limit: Int?) {
            let end = min(end, routeMeters)
            guard end > start else { return }
            if let last = segments.last, last.limitKmh == limit, abs(last.endMeters - start) < 0.5 {
                segments[segments.count - 1].endMeters = end
            } else {
                segments.append(SpeedLimitSegment(startMeters: start, endMeters: end, limitKmh: limit))
            }
        }

        var complete = true
        var countries = Set<String>()
        var unknownCountry = false
        for piece in pieces {
            let meters = piece.pointMeters
            guard meters.count >= 2 else { continue }
            guard let match = piece.match, match.points.count == meters.count else {
                complete = complete && piece.match != nil
                append(meters[0], meters[meters.count - 1], nil)
                continue
            }
            if let country = match.countryCode { countries.insert(country) } else { unknownCountry = true }
            for i in 0..<(meters.count - 1) {
                let start = meters[i], end = meters[i + 1]
                let length = end - start
                guard length > 0 else { continue }
                guard let parts = path(from: match.points[i], to: match.points[i + 1], edges: match.edges) else {
                    append(start, end, nil)
                    continue
                }
                let total = parts.reduce(0) { $0 + $1.meters }
                if total < 0.5 {
                    // Los dos puntos caen en el mismo sitio de la misma arista (puntos muy juntos).
                    append(start, end, length < 30 ? parts.first?.limit : nil)
                    continue
                }
                guard lengthRatio.contains(total / length) else {
                    append(start, end, nil)
                    continue
                }
                var cursor = start
                for part in parts {
                    let next = cursor + part.meters * length / total
                    append(cursor, next, part.limit)
                    cursor = next
                }
                append(cursor, end, nil)        // resto por redondeo (normalmente nada)
            }
        }
        let country = !unknownCountry && countries.count == 1 ? countries.first : nil
        return SpeedLimitProfile(segments: segments, routeMeters: routeMeters, countryCode: country, isComplete: complete)
    }

    /// Recorrido del proveedor entre dos puntos asociados: lista de (metros, límite) por arista. Nil si no es fiable.
    static func path(from a: SpeedLimitMatchedPoint, to b: SpeedLimitMatchedPoint,
                     edges: [SpeedLimitEdge]) -> [(meters: Double, limit: Int?)]? {
        guard let ea = usableEdge(a, edges: edges), let eb = usableEdge(b, edges: edges), ea <= eb,
              let fa = a.distanceAlongEdge, let fb = b.distanceAlongEdge else { return nil }
        if ea == eb {
            guard fb >= fa else { return nil }
            return [((fb - fa) * edges[ea].lengthMeters, edges[ea].limitKmh)]
        }
        var parts: [(meters: Double, limit: Int?)] = [((1 - fa) * edges[ea].lengthMeters, edges[ea].limitKmh)]
        if eb - ea > 1 {
            for index in (ea + 1)..<eb { parts.append((edges[index].lengthMeters, edges[index].limitKmh)) }
        }
        parts.append((fb * edges[eb].lengthMeters, edges[eb].limitKmh))
        return parts
    }

    private static func usableEdge(_ point: SpeedLimitMatchedPoint, edges: [SpeedLimitEdge]) -> Int? {
        guard point.kind != .unmatched, let index = point.edgeIndex, index >= 0, index < edges.count,
              let fraction = point.distanceAlongEdge, (0...1.0001).contains(fraction) else { return nil }
        if let offset = point.distanceFromTrace, offset > maxSnapMeters { return nil }
        return index
    }
}

// MARK: - Qué se muestra

enum SpeedLimitDisplay: Equatable {
    /// Señal desactivada o sin fuente activa (sin ruta y sin «también sin ruta»).
    case hidden
    /// No se puede identificar la vía con seguridad: ubicación imprecisa, antigua, perdida o fuera de la ruta.
    case insufficientLocation
    /// Vía identificada (o consulta en curso / fallida) pero SIN dato de límite. No significa «sin límite».
    case unavailable
    /// Límite explícito del tramo según el proveedor (km/h).
    case limit(kmh: Int)

    var limitKmh: Int? {
        if case .limit(let kmh) = self { return kmh }
        return nil
    }
}

/// Decide qué mostrar a partir de la posición REAL sobre la ruta (nunca la posición animada de la flecha). Evita
/// parpadeos: cambiar de una cifra a otra cosa exige lecturas consecutivas; y deja de mostrar la cifra en cuanto la
/// posición no es fiable.
struct SpeedLimitTracker {
    var confirmationsNeeded = 2
    /// Con más error que esto no se distingue una vía de su paralela.
    var maxAccuracy: Double = 35
    var maxAge: TimeInterval = 6
    /// Más lejos de la ruta que esto: puede ir por una vía paralela o una salida.
    var maxDistanceFromRoute: Double = 25

    private(set) var shown: SpeedLimitDisplay = .hidden
    private var candidate: SpeedLimitDisplay?
    private var candidateCount = 0

    mutating func reset(to display: SpeedLimitDisplay = .hidden) {
        shown = display
        candidate = nil
        candidateCount = 0
    }

    mutating func update(enabled: Bool, profile: SpeedLimitProfile?, progressMeters: Double, isOffRoute: Bool,
                         distanceFromRoute: Double = 0, accuracy: Double, age: TimeInterval) -> SpeedLimitDisplay {
        guard enabled else {
            reset()
            return .hidden
        }
        guard !isOffRoute, accuracy >= 0, accuracy <= maxAccuracy, age <= maxAge,
              distanceFromRoute <= max(maxDistanceFromRoute, 0) else {
            reset(to: .insufficientLocation)
            return shown
        }
        let target: SpeedLimitDisplay
        if let profile {
            target = profile.limit(atMeters: progressMeters).map { .limit(kmh: $0) } ?? .unavailable
        } else {
            target = .unavailable          // consulta en curso o fallida: nunca una cifra supuesta
        }
        return apply(target)
    }

    /// Pérdida de señal (no llegan lecturas): no se mantiene la última cifra.
    mutating func locationLost(enabled: Bool) -> SpeedLimitDisplay {
        reset(to: enabled ? .insufficientLocation : .hidden)
        return shown
    }

    /// Aplica un objetivo ya calculado con la misma regla anti-parpadeo (la usa también el modo sin ruta).
    mutating func apply(_ target: SpeedLimitDisplay) -> SpeedLimitDisplay {
        if target == shown { candidate = nil; candidateCount = 0; return shown }
        // Sin cifra en pantalla, la primera lectura fiable se muestra al instante. Con una cifra, cualquier cambio se
        // confirma con lecturas seguidas (evita saltar entre dos tramos por el ruido del GPS en el límite entre ambos).
        guard shown.limitKmh != nil else {
            reset(to: target)
            return shown
        }
        if candidate == target { candidateCount += 1 } else { candidate = target; candidateCount = 1 }
        if candidateCount >= confirmationsNeeded { reset(to: target) }
        return shown
    }
}

enum SpeedLimitFormatter {
    /// Los límites llegan del proveedor en km/h. En km/h se muestran tal cual; en mph se CONVIERTEN y se redondean al
    /// entero (no a múltiplos de 5, que inventaría cifras de señal). La unidad se muestra siempre junto a la señal.
    static func signNumber(kmh: Int, metric: Bool) -> Int {
        metric ? kmh : Int((Double(kmh) * 0.621371).rounded())
    }

    /// Texto de la unidad que acompaña a la señal. En mph lleva «≈» porque es una conversión.
    static func unitCaption(metric: Bool) -> String { metric ? "km/h" : "≈ mph" }

    static func spokenLabel(_ display: SpeedLimitDisplay, metric: Bool) -> String {
        switch display {
        case .hidden: return ""
        case .insufficientLocation: return "Límite de velocidad: ubicación insuficiente para identificar la vía"
        case .unavailable: return "Límite de velocidad no disponible"
        case .limit(let kmh):
            if metric { return "Límite de velocidad: \(kmh) kilómetros por hora" }
            return "Límite de velocidad: unas \(signNumber(kmh: kmh, metric: false)) millas por hora, convertido desde \(kmh) kilómetros por hora"
        }
    }

    /// Velocidad actual válida en km/h, o nil si la lectura no la da (velocidad o precisión negativas).
    static func currentSpeedKmh(_ location: CLLocation?) -> Double? {
        guard let location, location.speed >= 0, location.speedAccuracy >= 0 else { return nil }
        return location.speed * 3.6
    }
}
