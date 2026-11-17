import SwiftData
import XCTest
@testable import QuestMapIRL

final class MapLayersTests: XCTestCase {
    // MARK: Preferencias

    func testDefaultsKeepWhatTheMapAlreadyShowedAndNewLayersStartOff() {
        let defaults = MapLayerPreferences.defaults
        for id: MapLayerID in [.food, .shops, .fuel, .health, .parking, .otherPlaces, .transitStations] {
            XCTAssertTrue(defaults.isEnabled(id), id.rawValue)
        }
        for id: MapLayerID in [.busStops, .transitLines, .cycleways, .bikeParking, .bikeRental, .trafficSignals, .liveTraffic] {
            XCTAssertFalse(defaults.isEnabled(id), id.rawValue)
        }
    }

    func testRawRoundTripAndUnknownOrMissingEntriesUseDefaults() {
        var preferences = MapLayerPreferences.defaults
        preferences.set(.food, false)
        preferences.set(.cycleways, true)
        let restored = MapLayerPreferences(raw: preferences.raw)
        XCTAssertEqual(restored, preferences)
        // Una capa que no estaba guardada (añadida en una versión nueva) toma su valor por defecto.
        let old = MapLayerPreferences(raw: "food=0,inventada=1")
        XCTAssertFalse(old.isEnabled(.food))
        XCTAssertTrue(old.isEnabled(.fuel), "no guardada: por defecto activada")
        XCTAssertFalse(old.isEnabled(.cycleways), "no guardada: por defecto apagada")
        XCTAssertEqual(MapLayerPreferences(raw: ""), .defaults)
    }

    func testLayersWithoutARealSourceCanNeverBeEnabled() {
        var preferences = MapLayerPreferences.defaults
        preferences.set(.liveTraffic, true)
        preferences.set(.trafficSignals, true)
        XCTAssertFalse(preferences.isEnabled(.liveTraffic))
        XCTAssertFalse(preferences.isEnabled(.trafficSignals))
        XCTAssertFalse(MapLayerPreferences(raw: "liveTraffic=1,trafficSignals=1").isEnabled(.liveTraffic))
        XCTAssertNotNil(MapLayerID.liveTraffic.availability.unavailableReason, "explica por qué")
        XCTAssertNotNil(MapLayerID.trafficSignals.detail)
    }

    func testRapidTogglesKeepTheLastState() {
        var preferences = MapLayerPreferences.defaults
        for on in [true, false, true, true, false, true] { preferences.set(.cycleways, on) }
        XCTAssertTrue(preferences.isEnabled(.cycleways))
        XCTAssertEqual(preferences.styleLayerVisibility["layer-cycleways"], true)
        XCTAssertEqual(preferences.styleLayerVisibility["poi-icon-bus-stop"], false)
    }

    // MARK: Estilos: cada capa existe en TODOS los estilos (no hay interruptores que no hagan nada)

    private func styleLayers(_ resource: String) throws -> [[String: Any]] {
        let url = try XCTUnwrap(Bundle(for: AppEnvironment.self).url(forResource: resource, withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return json["layers"] as? [[String: Any]] ?? []
    }

    func testEveryAvailableLayerExistsInEveryStyleAndOptionalOnesStartHidden() throws {
        for theme in ThemeCatalog.all {
            guard let cartography = theme.cartography else { continue }
            let layers = try styleLayers(cartography.resourceName)
            let ids = Set(layers.compactMap { $0["id"] as? String })
            for layer in MapLayerID.allCases {
                for styleID in layer.styleLayerIDs {
                    XCTAssertTrue(ids.contains(styleID), "\(cartography.resourceName) no tiene \(styleID)")
                }
            }
            for optional in ["layer-cycleways", "layer-transit-lines", "layer-traffic-signals"] {
                let layout = layers.first { $0["id"] as? String == optional }?["layout"] as? [String: Any]
                XCTAssertEqual(layout?["visibility"] as? String, "none", "\(cartography.resourceName): \(optional)")
            }
            // Las líneas opcionales quedan BAJO la ruta (la ruta siempre se lee por encima).
            let order = layers.compactMap { $0["id"] as? String }
            let route = try XCTUnwrap(order.firstIndex(of: "route-glow"))
            XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: "layer-cycleways")), route)
            XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: "layer-transit-lines")), route)
        }
    }

    func testPlaceNamesAreShortOneLineAndKeepTheOriginalData() throws {
        let layers = try styleLayers("style-ciudad-nocturna")
        let food = try XCTUnwrap(layers.first { $0["id"] as? String == "poi-icon-food" })
        let layout = try XCTUnwrap(food["layout"] as? [String: Any])
        let text = String(decoding: try JSONSerialization.data(withJSONObject: layout["text-field"] as Any), as: UTF8.self)
        XCTAssertTrue(text.contains("\"slice\"") && text.contains("\"length\""), "recorte solo de presentación")
        XCTAssertTrue(text.contains("…") || text.contains("\\u2026"), "puntos suspensivos")
        XCTAssertTrue(text.contains("name:es") && text.contains("\"name\""), "nombre real, no inventado")
        XCTAssertFalse(text.contains("address") || text.contains("housenumber"), "nunca la dirección")
        XCTAssertEqual(layout["text-anchor"] as? String, "top", "debajo del icono")
        XCTAssertEqual(layout["text-optional"] as? Bool, true, "el icono no desaparece por falta de sitio para el nombre")
        XCTAssertEqual(layout["icon-allow-overlap"] as? Bool, false, "con colisiones: sin solapes")
    }

    // MARK: Persistencia y restablecer

    @MainActor
    func testPreferencesPersistAndResetOnlyTouchesLayers() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("layers-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        var keep: [ModelContainer] = []
        func open() throws -> ModelContext {
            let container = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(schema: AppSchema.schema, url: url))
            keep.append(container)
            return ModelContext(container)
        }
        do {
            let context = try open()
            let settings = UserSettings()
            XCTAssertEqual(settings.mapLayers, .defaults)
            XCTAssertTrue(settings.showPlaceNames)
            var layers = settings.mapLayers
            layers.set(.cycleways, true)
            layers.set(.food, false)
            settings.mapLayers = layers
            settings.showPlaceNames = false
            settings.themeRawValue = MapThemeID.islaRoyale.rawValue
            context.insert(settings)
            context.insert(SavedPlace(name: "Casa", kind: .home, latitude: 40.4, longitude: -3.7))
            try PersistenceCommit.save(context)
        }
        do {
            let context = try open()                                 // como cerrar y abrir la app
            let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
            XCTAssertTrue(settings.mapLayers.isEnabled(.cycleways))
            XCTAssertFalse(settings.mapLayers.isEnabled(.food))
            XCTAssertFalse(settings.showPlaceNames)
            settings.resetMapLayers()
            try PersistenceCommit.save(context)
            XCTAssertEqual(settings.mapLayers, .defaults)
            XCTAssertTrue(settings.showPlaceNames)
            XCTAssertEqual(settings.themeID, .islaRoyale, "restablecer capas no cambia el estilo")
            XCTAssertEqual(try context.fetch(FetchDescriptor<SavedPlace>()).count, 1, "ni borra Casa")
        }
    }
}
