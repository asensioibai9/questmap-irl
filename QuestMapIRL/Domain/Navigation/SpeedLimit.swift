import Foundation
import CoreLocation

/// Límite de velocidad por tramos a lo largo de la RUTA ACTIVA. `limitKmh == nil` significa «el dato no existe»;
/// NUNCA significa «sin límite». Vehículo admitido en esta versión: turismo.
struct SpeedLimitSegment: Equatable {
    var startMeters: Double
    var endMeters: Double
    var limitKmh: Int?
    /// Vía de OpenStreetMap del tramo (identificador del proveedor) y su nombre o referencia, si existen.
    var wayID: Int64? = nil
    var roadName: String? = nil
    /// Valor ORIGINAL recibido («50», «unlimited», «sin dato»): solo para diagnóstico.
    var raw: String? = nil
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

    /// Tramo en esa distancia recorrida de la ruta (con su vía), o nil fuera de la ruta.
    func segment(atMeters meters: Double) -> SpeedLimitSegment? {
        guard meters >= 0, meters <= routeMeters else { return nil }
        return segments.first { meters >= $0.startMeters && meters < $0.endMeters }
            ?? (meters == routeMeters ? segments.last : nil)
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
    /// Vía de OpenStreetMap (`edge.way_id`): identifica de verdad en qué vía se está (no solo «la más cercana»).
    var wayID: Int64? = nil
    var names: [String] = []
    /// Valor original del proveedor para diagnóstico («50», «unlimited» = sin límite general explícito, «sin dato»).
    var raw: String = "sin dato"

    var roadName: String? { names.first }
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
            let rawLimit = edge["speed_limit"]
            edges.append(SpeedLimitEdge(lengthMeters: km * 1000, limitKmh: limit(from: rawLimit),
                                        wayID: (edge["way_id"] as? NSNumber)?.int64Value,
                                        names: edge["names"] as? [String] ?? [],
                                        raw: rawLimit.map { "\($0)" } ?? "sin dato"))
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
        func append(_ start: Double, _ end: Double, _ edge: SpeedLimitEdge?) {
            let end = min(end, routeMeters)
            guard end > start else { return }
            let limit = edge?.limitKmh
            if let last = segments.last, last.limitKmh == limit, last.wayID == edge?.wayID, abs(last.endMeters - start) < 0.5 {
                segments[segments.count - 1].endMeters = end
            } else {
                segments.append(SpeedLimitSegment(startMeters: start, endMeters: end, limitKmh: limit, wayID: edge?.wayID,
                                                  roadName: edge?.roadName, raw: edge?.raw))
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
                    append(start, end, length < 30 ? parts.first?.edge : nil)
                    continue
                }
                guard lengthRatio.contains(total / length) else {
                    append(start, end, nil)
                    continue
                }
                var cursor = start
                for part in parts {
                    let next = cursor + part.meters * length / total
                    append(cursor, next, part.edge)
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
                     edges: [SpeedLimitEdge]) -> [(meters: Double, edge: SpeedLimitEdge)]? {
        guard let ea = usableEdge(a, edges: edges), let eb = usableEdge(b, edges: edges), ea <= eb,
              let fa = a.distanceAlongEdge, let fb = b.distanceAlongEdge else { return nil }
        if ea == eb {
            guard fb >= fa else { return nil }
            return [((fb - fa) * edges[ea].lengthMeters, edges[ea])]
        }
        var parts: [(meters: Double, edge: SpeedLimitEdge)] = [((1 - fa) * edges[ea].lengthMeters, edges[ea])]
        if eb - ea > 1 {
            for index in (ea + 1)..<eb { parts.append((edges[index].lengthMeters, edges[index])) }
        }
        parts.append((fb * edges[eb].lengthMeters, edges[eb]))
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
    /// D · Ubicación no utilizable: imprecisa, antigua o perdida.
    case insufficientLocation
    /// C · Tramo incierto: no se sabe con seguridad por qué vía vas (paralela, salida, desvío, sin coincidencia).
    case uncertainRoad
    /// B · Vía identificada pero SIN límite en los datos (o consulta en curso). No significa «sin límite».
    case unavailable
    /// E · El proveedor falló y no hay otra base fiable.
    case providerError
    /// A · Vía identificada y límite explícito en los datos (km/h).
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

    /// Solo con la ruta (sin comprobación del recorrido real). Se usa el criterio ESTRICTO del resolvedor.
    mutating func update(enabled: Bool, profile: SpeedLimitProfile?, progressMeters: Double, isOffRoute: Bool,
                         distanceFromRoute: Double = 0, accuracy: Double, age: TimeInterval) -> SpeedLimitDisplay {
        guard enabled else {
            reset()
            return .hidden
        }
        let route = RouteSpeedEvidence(segment: profile?.segment(atMeters: progressMeters),
                                       profileState: profile == nil ? .loading : .loaded,
                                       distanceFromRoute: distanceFromRoute, isOffRoute: isOffRoute)
        let decision = SpeedLimitResolver.resolve(route: route, live: nil,
                                                  location: LocationEvidence(accuracy: accuracy, age: age))
        return applyDecision(decision.display)
    }

    /// Aplica una decisión: una cifra se sustituye por otra cosa solo tras lecturas seguidas; lo que no es cifra
    /// (ubicación, tramo incierto) se aplica al momento para no mantener un límite dudoso.
    mutating func applyDecision(_ display: SpeedLimitDisplay) -> SpeedLimitDisplay {
        switch display {
        case .insufficientLocation, .uncertainRoad, .hidden:
            reset(to: display)
            return shown
        default:
            return apply(display)
        }
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
        case .uncertainRoad: return "Límite de velocidad: no se sabe con seguridad por qué vía vas"
        case .providerError: return "Límite de velocidad no disponible: error del servicio"
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

// MARK: - Decisión: ruta + recorrido real

/// Lo que dice la RUTA planificada en la posición actual. La ruta es una ayuda: no garantiza que el usuario siga en ella.
struct RouteSpeedEvidence: Equatable {
    enum ProfileState: Equatable { case loading, loaded, failed }
    var segment: SpeedLimitSegment?
    var profileState: ProfileState
    var distanceFromRoute: Double
    var isOffRoute: Bool
}

/// Lo que dice el MAP MATCHING del recorrido real reciente (proveedor). Identifica la vía por la que se circula
/// teniendo en cuenta continuidad, sentido y conectividad, no solo la línea más cercana.
struct LiveRoadEvidence: Equatable {
    var wayID: Int64?
    var limitKmh: Int?
    var raw: String
    var roadName: String?
    /// El proveedor asoció el último punto a una vía con seguridad (cerca y con coincidencia).
    var confident: Bool
    /// El usuario sigue dentro de la vía identificada (no ha recorrido más de lo que quedaba de ella).
    var stillOnIdentifiedRoad: Bool
    var ageSeconds: TimeInterval
}

struct LocationEvidence: Equatable {
    var accuracy: Double
    var age: TimeInterval
}

/// Resultado con su porqué (para el diagnóstico de desarrollo).
struct SpeedLimitDecision: Equatable {
    enum Source: String { case route = "ruta", liveTrace = "recorrido real", none = "—" }
    var display: SpeedLimitDisplay
    var source: Source
    var reason: String
    var wayID: Int64? = nil
    var roadName: String? = nil
    var raw: String? = nil
}

/// Criterio de fiabilidad (vehículo: turismo). Solo hay cifra con una base suficiente:
/// 1. Ubicación inservible (precisión > 35 m o lectura de más de 6 s) → D.
/// 2. Con el recorrido real identificado (map matching reciente y seguro, y aún dentro de esa vía):
///    - misma vía y mismo límite que la ruta → se usa la ruta; misma vía con otro límite → el del recorrido (sentido real);
///    - vía distinta (paralela, salida, desvío) → manda la vía real; la ruta NO se usa.
/// 3. El recorrido dice que no sabe por qué vía vas → C (aunque la ruta pase cerca).
/// 4. Sin recorrido (aún no hay, sin red o desactivado): solo la ruta y solo si vas pegado a ella (≤ 10 m, precisión
///    ≤ 20 m, sin desvío). Si no → C.
/// Nunca se deduce una cifra por el tipo de vía; «sin dato» (B) no es «sin límite».
enum SpeedLimitResolver {
    static let maxAccuracy: Double = 35
    static let maxAge: TimeInterval = 6
    static let liveMaxAge: TimeInterval = 90
    static let strictRouteDistance: Double = 10
    static let strictRouteAccuracy: Double = 20

    static func resolve(route: RouteSpeedEvidence?, live: LiveRoadEvidence?, location: LocationEvidence) -> SpeedLimitDecision {
        guard location.accuracy >= 0, location.accuracy <= maxAccuracy, location.age <= maxAge else {
            return SpeedLimitDecision(display: .insufficientLocation, source: .none,
                                      reason: location.accuracy < 0 || location.accuracy > maxAccuracy
                                        ? "ubicación imprecisa" : "lectura de ubicación antigua")
        }
        let usableRoute = route.flatMap { $0.isOffRoute ? nil : $0 }
        if let live, live.stillOnIdentifiedRoad, live.ageSeconds <= liveMaxAge {
            guard live.confident else {
                return SpeedLimitDecision(display: .uncertainRoad, source: .liveTrace,
                                          reason: "el recorrido no identifica la vía con seguridad")
            }
            if let segment = usableRoute?.segment, let routeWay = segment.wayID, routeWay == live.wayID {
                if segment.limitKmh == live.limitKmh {
                    return decision(limit: segment.limitKmh, source: .route, reason: "la ruta y el recorrido coinciden",
                                    wayID: segment.wayID, name: segment.roadName, raw: segment.raw)
                }
                // Misma vía y distinto límite: en OSM eso es un límite POR SENTIDO; el recorrido real trae el del sentido
                // en el que se circula de verdad.
                return decision(limit: live.limitKmh, source: .liveTrace, reason: "misma vía, límite del sentido real",
                                wayID: live.wayID, name: live.roadName, raw: live.raw)
            }
            let differs = usableRoute?.segment != nil
            return decision(limit: live.limitKmh, source: .liveTrace,
                            reason: differs ? "vas por una vía distinta de la ruta" : "vía según tu recorrido",
                            wayID: live.wayID, name: live.roadName, raw: live.raw)
        }
        guard let route = usableRoute else {
            return SpeedLimitDecision(display: .uncertainRoad, source: .none,
                                      reason: route?.isOffRoute == true ? "fuera de la ruta" : "vía aún no identificada")
        }
        guard route.distanceFromRoute <= strictRouteDistance, location.accuracy <= strictRouteAccuracy else {
            return SpeedLimitDecision(display: .uncertainRoad, source: .none,
                                      reason: "sin comprobar la vía: lejos de la ruta o GPS impreciso")
        }
        switch route.profileState {
        case .loading:
            return SpeedLimitDecision(display: .unavailable, source: .route, reason: "consultando límites de la ruta")
        case .failed:
            return SpeedLimitDecision(display: .providerError, source: .route, reason: "error del servicio de límites")
        case .loaded:
            guard let segment = route.segment else {
                return SpeedLimitDecision(display: .uncertainRoad, source: .route, reason: "posición fuera del perfil")
            }
            return decision(limit: segment.limitKmh, source: .route, reason: "ruta (pegado a ella, sin comprobar recorrido)",
                            wayID: segment.wayID, name: segment.roadName, raw: segment.raw)
        }
    }

    private static func decision(limit: Int?, source: SpeedLimitDecision.Source, reason: String,
                                 wayID: Int64?, name: String?, raw: String?) -> SpeedLimitDecision {
        let why = limit == nil ? reason + "; sin límite en los datos" + (raw == "unlimited" ? " (sin límite general explícito)" : "") : reason
        return SpeedLimitDecision(display: limit.map { .limit(kmh: $0) } ?? .unavailable, source: source, reason: why,
                                  wayID: wayID, roadName: name, raw: raw)
    }
}

/// Datos del modo diagnóstico (solo desarrollo): nunca coordenadas ni recorridos, y nunca se registran.
struct SpeedLimitDiagnostic: Equatable {
    var source: String
    var wayID: Int64?
    var roadName: String?
    var raw: String?
    var interpreted: String
    var dataAgeSeconds: Int?
    var accuracy: Int?
    var reason: String
    var change: String?

    static func make(_ decision: SpeedLimitDecision, previous: SpeedLimitDiagnostic?, dataAge: TimeInterval?,
                     accuracy: Double, metric: Bool) -> SpeedLimitDiagnostic {
        let interpreted: String
        switch decision.display {
        case .limit(let kmh): interpreted = metric ? "\(kmh) km/h" : "\(SpeedLimitFormatter.signNumber(kmh: kmh, metric: false)) mph (de \(kmh) km/h)"
        case .unavailable: interpreted = "sin dato"
        case .uncertainRoad: interpreted = "tramo incierto"
        case .insufficientLocation: interpreted = "ubicación no utilizable"
        case .providerError: interpreted = "error del proveedor"
        case .hidden: interpreted = "oculta"
        }
        var change: String?
        if let previous {
            if previous.wayID != decision.wayID, decision.wayID != nil {
                change = "cambio de vía \(previous.wayID.map(String.init) ?? "—") → \(decision.wayID.map(String.init) ?? "—")"
            } else if previous.source != decision.source.rawValue {
                change = "fuente \(previous.source) → \(decision.source.rawValue)"
            } else {
                change = previous.change
            }
        }
        return SpeedLimitDiagnostic(source: decision.source.rawValue, wayID: decision.wayID, roadName: decision.roadName,
                                    raw: decision.raw, interpreted: interpreted,
                                    dataAgeSeconds: dataAge.map { Int($0.rounded()) },
                                    accuracy: accuracy >= 0 ? Int(accuracy.rounded()) : nil,
                                    reason: decision.reason, change: change)
    }
}
