import XCTest
import SwiftData
@testable import QuestMapIRL

/// Edificios 3D: la capa extruida debe estar bien colocada y solo en los estilos que la admiten.
final class Buildings3DTests: XCTestCase {
    private func layers(_ resource: String) throws -> [[String: Any]] {
        let bundle = Bundle(for: AppEnvironment.self)
        let url = try XCTUnwrap(bundle.url(forResource: resource, withExtension: "json"))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["layers"] as? [[String: Any]])
    }

    private func index(_ layers: [[String: Any]], _ id: String) -> Int? {
        layers.firstIndex { $0["id"] as? String == id }
    }

    func testGTAStyleHasHiddenExtrusionLayerBuiltFromBuildingFootprints() throws {
        let all = try layers("style-ciudad-nocturna")
        let layer = try XCTUnwrap(all.first { $0["id"] as? String == "building-3d" })
        XCTAssertEqual(layer["type"] as? String, "fill-extrusion")
        XCTAssertEqual(layer["source-layer"] as? String, "building", "se extruye la capa de edificios, nunca las carreteras")
        XCTAssertEqual((layer["layout"] as? [String: Any])?["visibility"] as? String, "none", "empieza en 2D")
        XCTAssertGreaterThanOrEqual(layer["minzoom"] as? Double ?? Double(layer["minzoom"] as? Int ?? 0), 15)
        let paint = try XCTUnwrap(layer["paint"] as? [String: Any])
        let text = String(describing: paint)
        XCTAssertTrue(text.contains("render_height"))
        XCTAssertTrue(text.contains("render_min_height"))
        XCTAssertTrue(String(describing: layer["filter"] as Any).contains("hide_3d"), "evita duplicar volúmenes de edificios con partes")
    }

    func testNothingElseIsExtruded() throws {
        for resource in ["style-ciudad-nocturna", "style-minimalista-pro", "style-isla", "style-bloques"] {
            let extruded = try layers(resource).filter { $0["type"] as? String == "fill-extrusion" }
            for layer in extruded {
                XCTAssertEqual(layer["source-layer"] as? String, "building", "\(resource): solo edificios")
            }
        }
    }

    func testExtrusionSitsAboveRoadsAndBelowRouteLabelsAndMarkers() throws {
        let all = try layers("style-ciudad-nocturna")
        let building = try XCTUnwrap(index(all, "building-3d"))
        XCTAssertGreaterThan(building, try XCTUnwrap(index(all, "road-motorway")))
        XCTAssertGreaterThan(building, try XCTUnwrap(index(all, "bridge-motorway")))
        for above in ["route-core", "label-water", "poi-icon-a", "destination-core", "user-arrow", "selection-arrows"] {
            XCTAssertLessThan(building, try XCTUnwrap(index(all, above)), "\(above) debe dibujarse por encima de los edificios")
        }
    }

    func testOnlyStylesWithTheLayerOfferTheControl() throws {
        for theme in ThemeCatalog.all {
            guard let cartography = theme.cartography else { continue }
            let all = try layers(cartography.resourceName)
            XCTAssertEqual(cartography.supportsBuildings3D, index(all, "building-3d") != nil,
                           "\(cartography.resourceName): el indicador y el JSON deben coincidir")
        }
    }

    func testPreferenceDefaultsTo2D() {
        XCTAssertFalse(UserSettings().view3D)
    }

    // MARK: Fase 3: Isla y Mundo de bloques

    func testIslaUsesSimplifiedSteppedVolumesWithWarmColors() throws {
        let layer = try XCTUnwrap(try layers("style-isla").first { $0["id"] as? String == "building-3d" })
        let paint = String(describing: layer["paint"] as Any)
        XCTAssertTrue(paint.contains("round"), "alturas escalonadas (volúmenes simplificados)")
        XCTAssertTrue(paint.contains("fill-extrusion-color"))
    }

    func testBlockWorldUsesBlockHeightsAndPlankTextureButIsNotVoxelized() throws {
        let layer = try XCTUnwrap(try layers("style-bloques").first { $0["id"] as? String == "building-3d" })
        let paint = try XCTUnwrap(layer["paint"] as? [String: Any])
        XCTAssertEqual(paint["fill-extrusion-pattern"] as? String, "tex-block-planks")
        XCTAssertTrue(String(describing: paint["fill-extrusion-height"] as Any).contains("round"), "alturas en múltiplos de bloque")
        XCTAssertEqual(layer["source-layer"] as? String, "building", "una huella extruida por edificio: no hay voxels")
        let bundle = Bundle(for: AppEnvironment.self)
        let url = try XCTUnwrap(bundle.url(forResource: "style-bloques", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let images = (json["metadata"] as? [String: Any])?["questmap:images"] as? [String]
        XCTAssertTrue(images?.contains("tex-block-planks") ?? false, "la textura se registra en el estilo")
        XCTAssertTrue(ThemeCatalog.mundoBloques.cartography?.textures.contains("tex-block-planks") ?? false)
    }

    func testAllThreeGameStylesOfferTheControlAndMinimalistDoesNot() {
        XCTAssertTrue(ThemeCatalog.ciudadNocturna.activeCartography.supportsBuildings3D)
        XCTAssertTrue(ThemeCatalog.islaRoyale.activeCartography.supportsBuildings3D)
        XCTAssertTrue(ThemeCatalog.mundoBloques.activeCartography.supportsBuildings3D)
        XCTAssertFalse(ThemeCatalog.minimalistaPro.activeCartography.supportsBuildings3D)
    }
}
