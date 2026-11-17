import Foundation
import CoreLocation

/// Endpoints de los servicios externos. Son servidores PÚBLICOS DE DEMOSTRACIÓN (sin clave,
/// sin garantías, con política de uso razonable): válidos para desarrollo y pruebas, no para una
/// app publicada con muchos usuarios. Para producción hay que apuntar a un servicio propio o
/// contratado: basta con cambiar estos valores, el resto de la app no cambia.
struct ServiceEndpoints {
    var drivingRoute = URL(string: "https://router.project-osrm.org/route/v1/driving/")!
    var walkingRoute = URL(string: "https://routing.openstreetmap.de/routed-foot/route/v1/driving/")!
    var geocoder = URL(string: "https://photon.komoot.io/api/")!

    static let `default` = ServiceEndpoints()
}

/// Rutas con la API de OSRM (datos de OpenStreetMap). Devuelve geometría completa, pasos con
/// tipo y modificador de maniobra, distancia y duración.
struct OSRMRouteService: RouteServiceProtocol {
    var endpoints = ServiceEndpoints.default
    var client = ServiceClient(service: "osrm")

    func routes(from origin: CLLocationCoordinate2D,
                to destination: CLLocationCoordinate2D,
                mode: RouteMode) async throws -> [Route] {
        let base = mode == .driving ? endpoints.drivingRoute : endpoints.walkingRoute
        let coords = String(format: "%.6f,%.6f;%.6f,%.6f",
                            origin.longitude, origin.latitude, destination.longitude, destination.latitude)
        guard var components = URLComponents(string: base.absoluteString + coords) else { throw RoutingError.server }
        components.queryItems = [
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "steps", value: "true"),
            URLQueryItem(name: "alternatives", value: "true")
        ]
        guard let url = components.url else { throw RoutingError.server }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("QuestMapIRL/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        do {
            let data = try await client.data(for: request, operation: "route")
            return try Self.parse(data)
        } catch let error as SearchError {
            throw RoutingError(error)
        }
    }

    // MARK: - Decodificación (separada para poder probarla sin red)

    static func parse(_ data: Data) throws -> [Route] {
        let decoded: OSRMResponse
        do { decoded = try JSONDecoder().decode(OSRMResponse.self, from: data) }
        catch { throw RoutingError.server }

        guard decoded.code == "Ok", let routes = decoded.routes, !routes.isEmpty else {
            throw RoutingError.noRoute
        }
        let parsed: [Route] = routes.compactMap { route in
            let coordinates = route.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
                pair.count >= 2 ? CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) : nil
            }
            guard coordinates.count >= 2 else { return nil }
            let steps = route.legs.flatMap(\.steps).map { step -> RouteStep in
                let built = InstructionBuilder.build(type: step.maneuver.type,
                                                     modifier: step.maneuver.modifier,
                                                     name: step.name,
                                                     exit: step.maneuver.exit,
                                                     exits: step.exits)
                let maneuver = ManeuverInfo(type: step.maneuver.type, modifier: step.maneuver.modifier, exit: step.maneuver.exit,
                                            hasVariableDetail: !(step.exits ?? "").isEmpty)
                return RouteStep(instruction: built.text, distanceMeters: step.distance,
                                 symbol: built.symbol, streetName: step.name ?? "", maneuver: maneuver)
            }
            let summary = route.legs.first?.summary ?? ""
            return Route(name: summary.isEmpty ? "Ruta" : summary,
                         coordinates: coordinates,
                         distanceMeters: route.distance,
                         durationSeconds: route.duration,
                         steps: steps)
        }
        guard !parsed.isEmpty else { throw RoutingError.noRoute }
        return parsed.sorted { $0.durationSeconds < $1.durationSeconds }
    }
}

// MARK: - Modelos de respuesta de OSRM

private struct OSRMResponse: Decodable {
    let code: String
    let routes: [OSRMRoute]?
}

private struct OSRMRoute: Decodable {
    let distance: Double
    let duration: Double
    let geometry: OSRMGeometry
    let legs: [OSRMLeg]
}

private struct OSRMGeometry: Decodable {
    let coordinates: [[Double]]
}

private struct OSRMLeg: Decodable {
    let summary: String?
    let steps: [OSRMStep]
}

private struct OSRMStep: Decodable {
    let distance: Double
    let name: String?
    let exits: String?
    let maneuver: OSRMManeuver
}

private struct OSRMManeuver: Decodable {
    let type: String
    let modifier: String?
    let exit: Int?
}
