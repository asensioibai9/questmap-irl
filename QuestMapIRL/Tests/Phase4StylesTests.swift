import XCTest
@testable import QuestMapIRL

/// Estilos de la Fase 4: deben diferenciarse en la cartografía (no solo en el color) y no presentarse como
/// oficiales de ningún juego.
@MainActor
final class Phase4StylesTests: XCTestCase {
    private let resources = ["style-salvaje-oeste", "style-ciudad-ciber", "style-mapa-fantasia", "style-red-urbana", "style-rutas-rally"]

    private func style(_ name: String) throws -> [String: Any] {
        let bundle = Bundle(for: AppEnvironment.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func layers(_ name: String) throws -> [[String: Any]] {
        try XCTUnwrap(style(name)["layers"] as? [[String: Any]])
    }

    private func ids(_ name: String) throws -> Set<String> {
        Set(try layers(name).compactMap { $0["id"] as? String })
    }

    private func paint(_ name: String, _ layer: String, _ key: String) throws -> Any? {
        (try layers(name).first { $0["id"] as? String == layer }?["paint"] as? [String: Any])?[key]
    }

    func testEveryNewStyleIsReadyAndHasItsOwnRouteColor() throws {
        var routes = Set<String>()
        for name in resources {
            let route = try XCTUnwrap(try paint(name, "route-core", "line-color") as? String, name)
            routes.insert(route)
        }
        XCTAssertEqual(routes.count, resources.count, "cada estilo tiene su propia ruta")
        for theme in [ThemeCatalog.salvajeOeste, ThemeCatalog.ciudadCiber, ThemeCatalog.mapaFantasia, ThemeCatalog.redUrbana, ThemeCatalog.rutasRally] {
            XCTAssertTrue(theme.isCartographyReady, theme.name)
        }
    }

    func testInkStylesHaveNoRoadCasingsButNeonStyleDoes() throws {
        for name in ["style-salvaje-oeste", "style-mapa-fantasia"] {
            XCTAssertFalse(try ids(name).contains("road-casing-primary"), "\(name): trazo de tinta sin contorno")
        }
        for name in ["style-ciudad-ciber", "style-red-urbana", "style-rutas-rally"] {
            XCTAssertTrue(try ids(name).contains("road-casing-primary"), name)
        }
    }

    func testMinorRoadsAreDashedInTheInkStyles() throws {
        XCTAssertNotNil(try paint("style-salvaje-oeste", "road-service", "line-dasharray"))
        XCTAssertNotNil(try paint("style-mapa-fantasia", "road-minor", "line-dasharray"))
        XCTAssertNil(try paint("style-red-urbana", "road-minor", "line-dasharray"))
    }

    func testRallyDistinguishesUnpavedRoadsFromRealSurfaceData() throws {
        let layer = try XCTUnwrap(try layers("style-rutas-rally").first { $0["id"] as? String == "road-unpaved" })
        XCTAssertTrue(String(describing: layer["filter"] as Any).contains("surface"))
        XCTAssertNotNil((layer["paint"] as? [String: Any])?["line-dasharray"])
        XCTAssertFalse(try ids("style-red-urbana").contains("road-unpaved"))
    }

    func testRoadHierarchyIsVisibleInTheRallyAndCyberStyles() throws {
        for name in ["style-rutas-rally", "style-ciudad-ciber"] {
            let motorway = String(describing: try paint(name, "road-motorway", "line-color") as Any)
            let service = String(describing: try paint(name, "road-service", "line-color") as Any)
            XCTAssertNotEqual(motorway, service, "\(name): el rango de la vía cambia su color")
        }
    }

    func testOnlyCyberAndUrbanNetworkOfferBuildings3D() throws {
        XCTAssertTrue(try ids("style-ciudad-ciber").contains("building-3d"))
        XCTAssertTrue(try ids("style-red-urbana").contains("building-3d"))
        for name in ["style-salvaje-oeste", "style-mapa-fantasia", "style-rutas-rally"] {
            XCTAssertFalse(try ids(name).contains("building-3d"), "\(name): interpretación plana")
        }
    }

    func testFantasyStyleIsAFlatInterpretationAndSaysSo() throws {
        let reference = try XCTUnwrap((try style("style-mapa-fantasia")["metadata"] as? [String: Any])?["questmap:reference"] as? String)
        XCTAssertTrue(reference.contains("PLANA"))
        XCTAssertTrue(reference.contains("NO se promete relieve"))
    }

    func testReferencesAreHonestAboutWhatWasAndWasNotCompared() throws {
        for name in resources {
            let reference = try XCTUnwrap((try style(name)["metadata"] as? [String: Any])?["questmap:reference"] as? String)
            XCTAssertTrue(reference.contains("NO realizada"), "\(name): no se afirma una comparación que no existe")
        }
    }

}
