import XCTest
@testable import QuestMapIRL

/// Pruebas de decodificación con respuestas de ejemplo (sin red).
final class ServiceParsingTests: XCTestCase {
    private let osrm = """
    {"code":"Ok","routes":[
      {"distance":5157.0,"duration":622.5,
       "geometry":{"type":"LineString","coordinates":[[-3.7038,40.4168],[-3.7036,40.4176],[-3.6883,40.4530]]},
       "legs":[{"summary":"Calle de Alcalá, Paseo de la Castellana","steps":[
          {"distance":120.0,"name":"Calle de Tetuán","maneuver":{"type":"depart","modifier":"right"}},
          {"distance":4900.0,"name":"Paseo de la Castellana","maneuver":{"type":"turn","modifier":"left"}},
          {"distance":0.0,"name":"","maneuver":{"type":"arrive"}}]}]},
      {"distance":5800.0,"duration":500.0,
       "geometry":{"type":"LineString","coordinates":[[-3.7038,40.4168],[-3.6883,40.4530]]},
       "legs":[{"summary":"","steps":[]}]}]}
    """

    func testOSRMRoutesAreSortedAndMapped() throws {
        let routes = try OSRMRouteService.parse(Data(osrm.utf8))
        XCTAssertEqual(routes.count, 2)
        // Ordenadas por duración: la de 500 s primero.
        XCTAssertEqual(routes[0].durationSeconds, 500)
        XCTAssertEqual(routes[0].name, "Ruta")
        XCTAssertEqual(routes[1].name, "Calle de Alcalá, Paseo de la Castellana")
        XCTAssertEqual(routes[1].coordinates.count, 3)
        XCTAssertEqual(routes[1].coordinates[0].latitude, 40.4168, accuracy: 0.00001)   // lat/lon invertidos bien
        XCTAssertEqual(routes[1].coordinates[0].longitude, -3.7038, accuracy: 0.00001)
    }

    func testOSRMStepsCarrySpanishInstructions() throws {
        let route = try OSRMRouteService.parse(Data(osrm.utf8))[1]
        XCTAssertEqual(route.steps.count, 3)
        XCTAssertEqual(route.steps[0].instruction, "Empieza por Calle de Tetuán")
        XCTAssertEqual(route.steps[1].instruction, "Gira a la izquierda en Paseo de la Castellana")
        XCTAssertEqual(route.steps[2].instruction, "Has llegado a tu destino")
        XCTAssertEqual(route.stepInfos.map(\.distanceMeters), [120, 4900, 0])
    }

    func testOSRMNoRouteAndGarbage() {
        XCTAssertThrowsError(try OSRMRouteService.parse(Data(#"{"code":"NoRoute"}"#.utf8))) {
            XCTAssertEqual($0 as? RoutingError, .noRoute)
        }
        XCTAssertThrowsError(try OSRMRouteService.parse(Data("no es json".utf8))) {
            XCTAssertEqual($0 as? RoutingError, .server)
        }
    }

    private let photon = """
    {"type":"FeatureCollection","features":[
     {"geometry":{"type":"Point","coordinates":[-3.7038762,40.416863]},
      "properties":{"osm_type":"R","osm_id":7424032,"name":"Puerta del Sol","district":"Centro","city":"Madrid","state":"Comunidad de Madrid"}},
     {"geometry":{"type":"Point","coordinates":[-3.7038762,40.416863]},
      "properties":{"osm_type":"R","osm_id":7424032,"name":"Puerta del Sol","city":"Madrid"}},
     {"geometry":{"type":"Point","coordinates":[-3.7,40.4]},
      "properties":{"osm_type":"N","osm_id":1,"street":"Calle de Alcalá","housenumber":"50","city":"Madrid"}},
     {"geometry":null,"properties":{"name":"Sin coordenadas"}}]}
    """

    func testPhotonMapsDedupesAndSkipsInvalid() throws {
        let places = try PhotonSearchService.parse(Data(photon.utf8))
        XCTAssertEqual(places.count, 2)   // duplicado y sin coordenadas descartados
        XCTAssertEqual(places[0].name, "Puerta del Sol")
        XCTAssertEqual(places[0].subtitle, "Centro, Madrid")
        XCTAssertEqual(places[0].latitude, 40.416863, accuracy: 0.000001)
        XCTAssertEqual(places[1].name, "Calle de Alcalá 50")
    }

    func testPhotonDoesNotAlterTheChosenCoordinates() throws {
        let place = try PhotonSearchService.parse(Data(photon.utf8))[0]
        XCTAssertEqual(place.coordinate.longitude, -3.7038762, accuracy: 0.0000001)
    }

    func testPhotonGarbageIsAnError() {
        XCTAssertThrowsError(try PhotonSearchService.parse(Data("x".utf8)))
    }
}
