import XCTest
import UIKit
@testable import QuestMapIRL

/// Estilo «GTA VI» (id interno `costaTropical`): valida el JSON que se publica en la app contra la ficha visual de
/// docs/30-estilo-gta-vi.md y comprueba que no altera GTA V ni el resto de estilos.
@MainActor
final class GTA6StyleTests: XCTestCase {
    private var style: [String: Any] = [:]
    private var layers: [[String: Any]] = []
    private var json = ""

    override func setUpWithError() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        let url = try XCTUnwrap(bundle.url(forResource: "style-costa-tropical", withExtension: "json"))
        let data = try Data(contentsOf: url)
        json = String(decoding: data, as: UTF8.self)
        style = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        layers = try XCTUnwrap(style["layers"] as? [[String: Any]])
    }

    private var ids: [String] { layers.compactMap { $0["id"] as? String } }
    private func layer(_ id: String) -> [String: Any]? { layers.first { $0["id"] as? String == id } }
    private func paint(_ id: String, _ key: String) -> Any? { (layer(id)?["paint"] as? [String: Any])?[key] }
    private func color(_ id: String, _ key: String) -> String { ((paint(id, key) as? String) ?? "").lowercased() }

    private func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    private func luminance(_ hex: String) -> Double {
        let c = rgb(hex)
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    /// `line-width` (interpolate exponencial base 1,4) a un zoom dado.
    private func width(_ id: String, atZoom zoom: Double, in source: [[String: Any]]? = nil) -> Double? {
        let all = source ?? layers
        guard let expression = ((all.first { $0["id"] as? String == id })?["paint"] as? [String: Any])?["line-width"] as? [Any],
              expression.count >= 5 else { return nil }
        func number(_ value: Any) -> Double? { value as? Double ?? (value as? Int).map(Double.init) }
        var stops: [(Double, Double)] = []
        var index = 3
        while index + 1 < expression.count {
            if let z = number(expression[index]), let v = number(expression[index + 1]) { stops.append((z, v)) }
            index += 2
        }
        guard let first = stops.first, let last = stops.last else { return nil }
        if zoom <= first.0 { return first.1 }
        if zoom >= last.0 { return last.1 }
        for pair in zip(stops, stops.dropFirst()) where zoom >= pair.0.0 && zoom <= pair.1.0 {
            let t = (pow(1.4, zoom - pair.0.0) - 1) / (pow(1.4, pair.1.0 - pair.0.0) - 1)
            return pair.0.1 + (pair.1.1 - pair.0.1) * t
        }
        return nil
    }

    // MARK: Identidad

    func testIsAnIndependentStyleNamedGTAVIAndGTAVIsUntouched() {
        XCTAssertEqual(MapThemeID.costaTropical.rawValue, "costaTropical", "identificador interno estable")
        XCTAssertEqual(ThemeCatalog.costaTropical.name, "GTA VI")
        XCTAssertTrue(ThemeCatalog.costaTropical.isCartographyReady)
        XCTAssertEqual(ThemeCatalog.costaTropical.activeCartography.resourceName, "style-costa-tropical")
        // GTA V sigue igual: mismo nombre, mismo JSON, misma familia de iconos y flecha sin disco.
        XCTAssertEqual(ThemeCatalog.ciudadNocturna.name, "GTA V")
        XCTAssertEqual(ThemeCatalog.ciudadNocturna.activeCartography.resourceName, "style-ciudad-nocturna")
        XCTAssertEqual(ThemeCatalog.ciudadNocturna.activeCartography.poiIconSet, .gameBadges)
        XCTAssertNil(ThemeCatalog.ciudadNocturna.activeCartography.userArrowBadgeHex)
        XCTAssertEqual(ThemeCatalog.ciudadNocturna.activeCartography.minimapShape, .fadedRectangle)
        XCTAssertEqual(ThemeCatalog.theme(for: .costaTropical).id, .costaTropical)
    }

    func testReferenceIsHonestAboutSourcesAndComparison() throws {
        let metadata = try XCTUnwrap(style["metadata"] as? [String: Any])
        let reference = try XCTUnwrap(metadata["questmap:reference"] as? String)
        XCTAssertTrue(reference.contains("no verificado"), "no se afirma que las capturas sean oficiales")
        XCTAssertTrue(reference.contains("NO realizada"))
        XCTAssertTrue(reference.contains("aproximados"))
        XCTAssertEqual(metadata["questmap:style-id"] as? String, "costaTropical")
    }

    // MARK: Sin ocultación de zonas

    func testWholeMapIsVisibleWithoutFogOrDarkMasks() {
        for id in ids {
            XCTAssertFalse(id.contains("fog") || id.contains("undiscovered") || id.contains("mask"), id)
        }
        XCTAssertGreaterThan(luminance(color("background", "background-color")), 0.5, "el fondo es la zona descubierta, clara")
        // Ninguna capa de relleno es casi negra.
        for layer in layers where layer["type"] as? String == "fill" {
            if let fill = (layer["paint"] as? [String: Any])?["fill-color"] as? String {
                XCTAssertGreaterThan(luminance(fill.lowercased()), 0.3, "\(layer["id"] ?? "")")
            }
        }
    }

    // MARK: Paleta de la ficha

    func testWaterIsTurquoiseAndBuildingsStandOutFromUrbanGround() {
        let water = rgb(color("water", "fill-color"))
        XCTAssertGreaterThan(water.b, water.r + 0.3, "agua turquesa: azul y verde muy por encima del rojo")
        XCTAssertGreaterThan(water.g, water.r + 0.3)
        let edge = color("water-edge", "line-color")
        XCTAssertGreaterThan(luminance(edge), luminance(color("water", "fill-color")), "costa con borde claro")

        let ground = color("background", "background-color")
        let building = rgb(color("building", "fill-color"))
        XCTAssertGreaterThan(building.b, building.r + 0.1, "edificios azul pizarra")
        XCTAssertNotEqual(color("building", "fill-color"), ground)
        XCTAssertGreaterThan(luminance(ground) - luminance(color("building", "fill-color")), 0.04, "edificios distinguibles del suelo")
    }

    func testNaturalAreasAreSoftGreen() throws {
        let fill = try XCTUnwrap(paint("landcover", "fill-color") as? [Any])
        let text = String(describing: fill).lowercased()
        XCTAssertTrue(text.contains("#78a892"), "hierba y humedal en verde agua")
        XCTAssertTrue(text.contains("#5f957f"), "bosque algo más oscuro")
    }

    // MARK: Red viaria

    func testRoadHierarchyByWidthAndHighwaysAreCream() throws {
        for zoom in [12.0, 14.0, 16.0, 18.0] {
            let order = ["motorway", "primary", "secondary", "tertiary", "minor", "service"]
            var previous = Double.infinity
            for tier in order {
                let w = try XCTUnwrap(width("road-\(tier)", atZoom: zoom), "\(tier) z\(zoom)")
                XCTAssertLessThan(w, previous, "\(tier) más fina que el nivel anterior a zoom \(zoom)")
                previous = w
            }
        }
        let motorway = rgb(color("road-motorway", "line-color"))
        XCTAssertGreaterThan(motorway.r, motorway.b + 0.05, "autopista crema, distinta de las calles blancas")
        XCTAssertGreaterThan(luminance(color("road-minor", "line-color")), luminance(color("background", "background-color")),
                             "calles claras sobre el suelo")
        for id in ["ramp-motorway", "bridge-motorway", "tunnel-motorway", "road-casing-motorway"] {
            XCTAssertNotNil(layer(id), "\(id): enlaces, puentes, túneles y contorno")
        }
    }

    func testHighwaysAreNotWiderThanInGTAV() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        let url = try XCTUnwrap(bundle.url(forResource: "style-ciudad-nocturna", withExtension: "json"))
        let gtaV = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["layers"] as? [[String: Any]])
        for zoom in [14.0, 16.0] {
            let mine = try XCTUnwrap(width("road-motorway", atZoom: zoom))
            let theirs = try XCTUnwrap(width("road-motorway", atZoom: zoom, in: gtaV))
            XCTAssertLessThan(mine, theirs, "autopistas finas: no tapan cruces ni calles paralelas (z\(zoom))")
        }
    }

    // MARK: Etiquetas, iconos y navegación

    func testPlaceNamesAreWhiteWithDarkOutlineAndRoadNamesStayReadable() {
        XCTAssertEqual(color("label-place-city", "text-color"), "#ffffff")
        XCTAssertLessThan(luminance(color("label-place-city", "text-halo-color")), 0.3)
        XCTAssertLessThan(luminance(color("label-place-small", "text-halo-color")), 0.4)
        XCTAssertLessThan(luminance(color("label-road-minor", "text-color")), 0.4, "calles: texto oscuro con halo claro")
        XCTAssertGreaterThan(luminance(color("label-road-minor", "text-halo-color")), 0.8)
        XCTAssertFalse(json.contains("\"text-transform\": \"uppercase\""), "nombres reales con sus mayúsculas y tildes")
    }

    func testPOIsKeepCategoriesShortNamesAndHaveOwnBubbleIcons() throws {
        for category in ["food", "shops", "parking", "health", "fuel", "transit", "other"] {
            let poi = try XCTUnwrap(layer("poi-icon-\(category)"), category)
            let text = String(describing: (poi["layout"] as? [String: Any])?["text-field"] as Any)
            XCTAssertTrue(text.contains("slice"), "\(category): nombre corto bajo el icono")
        }
        XCTAssertEqual(ThemeCatalog.costaTropical.activeCartography.poiIconSet, .gameBubbles)
        XCTAssertEqual(PoiIconSet.gameBubbles.assetPrefix, "gta6-poi")
        let bundle = Bundle(for: AppEnvironment.self)
        for asset in Set(GameIcons.styleNameToAsset.values) {
            XCTAssertNotNil(UIImage(named: GameIcons.assetName(for: asset, prefix: "gta6-poi"), in: bundle, compatibleWith: nil),
                            "Falta gta6-poi-\(asset)")
        }
    }

    func testNavigationLayersStayOnTopAndUseTheReferenceColors() throws {
        XCTAssertEqual(color("route-core", "line-color"), "#f0559e", "ruta rosa del minimapa del avance oficial")
        XCTAssertEqual(color("route-casing", "line-color"), "#ffffff")
        let destination = try XCTUnwrap(layer("destination-core"))
        XCTAssertEqual((destination["layout"] as? [String: Any])?["icon-image"] as? String, "poi-destination")
        let order = ids
        let building3D = try XCTUnwrap(order.firstIndex(of: "building-3d"))
        for above in ["route-core", "poi-icon-fuel", "selection-arrows", "saved-places", "destination-core", "user-arrow"] {
            XCTAssertLessThan(building3D, try XCTUnwrap(order.firstIndex(of: above)), "\(above) por encima de los edificios")
        }
        let selection = try XCTUnwrap(order.firstIndex(of: "selection-arrows"))
        XCTAssertLessThan(selection, try XCTUnwrap(order.firstIndex(of: "user-arrow")))
        XCTAssertTrue(ThemeCatalog.costaTropical.activeCartography.supportsBuildings3D)
        XCTAssertEqual(ThemeCatalog.costaTropical.activeCartography.userArrowBadgeHex, 0x16181D, "flecha blanca en círculo negro")
        XCTAssertEqual(ThemeCatalog.costaTropical.activeCartography.minimapShape, .roundedRectangle)
    }

    /// Nombres `poi-*` que el JSON usa como imagen (excluye los identificadores de capa).
    private func iconNamesUsed(in source: [String: Any]) throws -> Set<String> {
        let data = try JSONSerialization.data(withJSONObject: source["layers"] as Any)
        let text = String(decoding: data, as: UTF8.self)
        let regex = try NSRegularExpression(pattern: "\"(poi-[a-z0-9-]+)\"")
        let found = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
        let layerIDs = Set(((source["layers"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String })
        return Set(found).subtracting(layerIDs)
    }

    func testEveryIconOfTheExtendedFamilyIsRegisteredAndHasAnAsset() throws {
        let used = try iconNamesUsed(in: style)
        let registered = Set(GameIcons.styleNameToAsset.keys).union(GameIcons.bubbleOnlyAssets.map { "poi-\($0)" })
        XCTAssertTrue(used.isSubset(of: registered), "sin registrar: \(used.subtracting(registered).sorted())")
        let bundle = Bundle(for: AppEnvironment.self)
        for asset in GameIcons.bubbleOnlyAssets {
            XCTAssertNotNil(UIImage(named: GameIcons.assetName(for: asset, prefix: "gta6-poi"), in: bundle, compatibleWith: nil),
                            "Falta gta6-poi-\(asset)")
        }
        XCTAssertGreaterThanOrEqual(GameIcons.bubbleOnlyAssets.count, 40)
        XCTAssertEqual(Set(GameIcons.bubbleOnlyAssets).count, GameIcons.bubbleOnlyAssets.count)
    }

    func testRealCategoriesFromTheReferenceGetTheirOwnIcon() throws {
        let food = String(describing: (layer("poi-icon-food")?["layout"] as? [String: Any])?["icon-image"] as Any)
        for icon in ["poi-burger", "poi-mug", "poi-nightclub", "poi-bakery", "poi-ice-cream"] {
            XCTAssertTrue(food.contains(icon), "comida y bebida: \(icon)")
        }
        let shops = String(describing: (layer("poi-icon-shops")?["layout"] as? [String: Any])?["icon-image"] as Any)
        for icon in ["poi-clothes", "poi-shoes", "poi-beauty", "poi-tattoo", "poi-electronics", "poi-basket", "poi-bottle",
                     "poi-car-repair", "poi-car-wash"] {
            XCTAssertTrue(shops.contains(icon), "tiendas y vehículos: \(icon)")
        }
        let fuel = String(describing: (layer("poi-icon-fuel")?["layout"] as? [String: Any])?["icon-image"] as Any)
        XCTAssertTrue(fuel.contains("poi-charging"), "puntos de recarga distintos de gasolineras")
        let other = try XCTUnwrap(layer("poi-icon-other"))
        let otherFilter = String(describing: other["filter"] as Any)
        for cls in ["harbor", "sports_centre", "golf", "post", "fire_station"] {
            XCTAssertTrue(otherFilter.contains(cls), "otros lugares: \(cls)")
        }
        XCTAssertTrue(String(describing: layer("poi-icon-transit")?["filter"] as Any).contains("ferry_terminal"))
    }

    func testHouseNumbersNoLongerHidePlaces() throws {
        let order = ids
        let housenumber = try XCTUnwrap(order.firstIndex(of: "label-housenumber"))
        for poi in order where poi.hasPrefix("poi-icon") {
            XCTAssertLessThan(housenumber, try XCTUnwrap(order.firstIndex(of: poi)), "\(poi) gana la colisión a los portales")
        }
    }

    func testGTAVDoesNotUseTheNewIcons() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        let url = try XCTUnwrap(bundle.url(forResource: "style-ciudad-nocturna", withExtension: "json"))
        let gtaV = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let used = try iconNamesUsed(in: gtaV)
        XCTAssertTrue(used.isDisjoint(with: GameIcons.bubbleOnlyAssets.map { "poi-\($0)" }), "GTA V conserva sus iconos")
    }

    func testUserArrowBadgeOnlyChangesTheClassicArrow() {
        let plain = MapAvatar.arrow.image(fill: .white, border: .black)
        let badged = MapAvatar.arrow.image(fill: .white, border: .black, badge: .black)
        XCTAssertEqual(plain.size, badged.size)
        XCTAssertNotEqual(plain.pngData(), badged.pngData(), "la flecha clásica lleva disco")
        XCTAssertEqual(MapAvatar.car.image(fill: .white, border: .black).pngData(),
                       MapAvatar.car.image(fill: .white, border: .black, badge: .black).pngData(), "el resto de avatares no cambia")
    }
}
