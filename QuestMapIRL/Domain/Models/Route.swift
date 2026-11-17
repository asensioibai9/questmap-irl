import CoreLocation

/// Modelos neutrales: no dependen de ningún motor de mapas ni de ningún proveedor.

enum RouteMode: String, CaseIterable, Identifiable {
    case driving
    case walking

    var id: String { rawValue }
    var title: String { self == .driving ? "Coche" : "A pie" }
    var symbol: String { self == .driving ? "car.fill" : "figure.walk" }
}

/// Datos ESTRUCTURADOS de la maniobra tal como los da el proveedor de rutas (OSRM): tipo, modificador y salida de
/// rotonda. Sirven para elegir grabaciones de voz sin interpretar el texto.
struct ManeuverInfo: Equatable {
    var type: String
    var modifier: String?
    var exit: Int?
    /// La maniobra lleva un dato variable importante que una grabación genérica no puede decir (p. ej. número de salida).
    var hasVariableDetail = false
}

struct RouteStep: Equatable {
    /// Instrucción en español de la maniobra que ocurre AL INICIO de este paso.
    let instruction: String
    /// Distancia que se recorre en este paso hasta la siguiente maniobra.
    let distanceMeters: Double
    let symbol: String
    let streetName: String
    /// nil en rutas creadas sin datos de maniobra (p. ej. pruebas): las voces grabadas usan entonces el respaldo.
    var maneuver: ManeuverInfo? = nil
}

struct Route: Identifiable {
    let id = UUID()
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let durationSeconds: Double
    let steps: [RouteStep]

    var etaMinutes: Int { max(1, Int((durationSeconds / 60).rounded())) }

    var stepInfos: [RouteStepInfo] {
        steps.map { RouteStepInfo(instruction: $0.instruction, distanceMeters: $0.distanceMeters, symbol: $0.symbol) }
    }
}

/// Lugar resuelto por el servicio de búsqueda o fijado en el mapa.
struct Place: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func pin(at coordinate: CLLocationCoordinate2D, name: String = "Punto del mapa") -> Place {
        Place(id: String(format: "pin-%.5f,%.5f", coordinate.latitude, coordinate.longitude),
              name: name, subtitle: "", latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
