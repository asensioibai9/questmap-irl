import Foundation
import CoreLocation

/// Textos y cálculos de la interfaz de CarPlay, sin depender de CarPlay para poder probarlos.
enum CarPlayPresentation {
    /// Variantes de la instrucción de una maniobra (de más larga a más corta, como pide CarPlay).
    static func maneuverVariants(_ step: RouteStep) -> [String] {
        var variants: [String] = []
        if !step.streetName.isEmpty { variants.append("\(step.instruction) · \(step.streetName)") }
        variants.append(step.instruction)
        return variants
    }

    /// Resumen de una ruta para la vista previa: «12 min · 5,4 km».
    static func routeSummary(_ route: Route, metric: Bool) -> [String] {
        let distance = Formatters.distance(route.distanceMeters, metric: metric)
        return ["\(route.etaMinutes) min · \(distance)", "\(route.etaMinutes) min"]
    }

    static func routeInformation(_ route: Route, index: Int, count: Int) -> [String] {
        let via = route.name == "Ruta" ? "" : "Por \(route.name)"
        let position = count > 1 ? "Ruta \(index + 1) de \(count)" : ""
        return [[position, via].filter { !$0.isEmpty }.joined(separator: " · ")].filter { !$0.isEmpty }
    }

    /// Segundos estimados hasta una distancia de la ruta (velocidad media de la propia ruta).
    static func seconds(forMeters meters: Double, route: Route) -> TimeInterval {
        guard route.distanceMeters > 0, route.durationSeconds > 0 else { return 0 }
        return meters / (route.distanceMeters / route.durationSeconds)
    }

    /// Índices de las maniobras que se muestran: la próxima y, si existe, la siguiente.
    static func upcomingIndices(snapshot: NavigationSnapshot, stepCount: Int) -> [Int] {
        guard stepCount > 0 else { return [] }
        let first = min(snapshot.upcomingIndex, stepCount - 1)
        return first + 1 < stepCount ? [first, first + 1] : [first]
    }

    /// Texto de un lugar guardado para una lista.
    static func detail(for place: Place, distanceMeters: Double?, metric: Bool) -> String {
        var parts: [String] = []
        if !place.subtitle.isEmpty { parts.append(place.subtitle) }
        if let distanceMeters { parts.append(Formatters.distance(distanceMeters, metric: metric)) }
        return parts.joined(separator: " · ")
    }

    /// Las listas de CarPlay tienen un máximo de elementos; se recorta sin romper nada.
    static func limited<T>(_ items: [T], max limit: Int) -> [T] {
        Array(items.prefix(Swift.max(0, limit)))
    }
}
