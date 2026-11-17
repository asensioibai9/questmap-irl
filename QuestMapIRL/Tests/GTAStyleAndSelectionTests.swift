import XCTest
import CoreLocation
@testable import QuestMapIRL

/// Estilo «Ciudad nocturna» (GTA): paleta apagada, jerarquía de vías, ruta violeta, iconos propios
/// y selección con cuatro flechas. Valida el JSON que se publica en la app y el comportamiento de la selección.
@MainActor
final class GTAStyleTests: XCTestCase {
    private var layers: [[String: Any]] = []
    private var sources: [String: Any] = [:]
    private var json: String = ""

    override func setUpWithError() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        let url = try XCTUnwrap(bundle.url(forResource: "style-ciudad-nocturna", withExtension: "json"))
        let data = try Data(contentsOf: url)
        json = String(decoding: data, as: UTF8.self)
        let style = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        layers = try XCTUnwrap(style["layers"] as? [[String: Any]])
        sources = try XCTUnwrap(style["sources"] as? [String: Any])
    }

    private func layer(_ id: String) -> [String: Any]? { layers.first { $0["id"] as? String == id } }
    private func paint(_ id: String, _ key: String) -> Any? { (layer(id)?["paint"] as? [String: Any])?[key] }

    private func luminance(_ hex: String) -> Double {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        let r = Double((value >> 16) & 255), g = Double((value >> 8) & 255), b = Double(value & 255)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    }

    /// Valor de la expresión `interpolate` exponencial (base 1,4) de `line-width` a un zoom dado.
    private func width(_ id: String, atZoom zoom: Double) -> Double? {
        guard let expression = paint(id, "line-width") as? [Any], expression.count >= 5 else { return nil }
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
            let base = 1.4
            let t = (pow(base, zoom - pair.0.0) - 1) / (pow(base, pair.1.0 - pair.0.0) - 1)
            return pair.0.1 + (pair.1.1 - pair.0.1) * t
        }
        return nil
    }

    // MARK: Colores

    func testPaletteIsMutedAndLayersStayDistinct() {
        XCTAssertEqual((paint("background", "background-color") as? String)?.lowercased(), "#191919")
        XCTAssertEqual((paint("building", "fill-color") as? String)?.lowercased(), "#303030")
        XCTAssertEqual((paint("water", "fill-color") as? String)?.lowercased(), "#26343a")
        let land = luminance("#191919"), building = luminance("#303030")
        XCTAssertGreaterThan(building, land)                     // edificios distinguibles del terreno
        XCTAssertLessThan(building - land, 0.12)                 // pero sin dominar
    }

    func testRoadsAreMutedGrayNotWhite() {
        for tier in ["motorway", "trunk", "primary", "secondary", "tertiary", "minor", "service"] {
            let color = (paint("road-\(tier)", "line-color") as? String) ?? ""
            XCTAssertFalse(color.isEmpty, tier)
            XCTAssertLessThan(luminance(color), 0.70, "\(tier) \(color) parece blanco")
        }
        XCTAssertEqual((paint("road-primary", "line-color") as? String)?.lowercased(), "#a6a6a6")
        XCTAssertEqual((paint("road-secondary", "line-color") as? String)?.lowercased(), "#858585")
        XCTAssertGreaterThan(luminance("#a6a6a6"), luminance("#858585"))
        XCTAssertGreaterThan(luminance("#858585"), luminance("#707070"))     // jerarquía por tono
    }

    func testRoadWidthsFollowTheHierarchyAtEveryTestedZoom() throws {
        for zoom in [14.0, 16.0, 18.0] {
            let order = ["motorway", "primary", "secondary", "tertiary", "minor", "service"]
            var previous = Double.infinity
            for tier in order {
                let w = try XCTUnwrap(width("road-\(tier)", atZoom: zoom), "\(tier) z\(zoom)")
                XCTAssertLessThan(w, previous, "\(tier) debe ser más fina que el nivel anterior a zoom \(zoom)")
                previous = w
            }
        }
        // Las autopistas se reconocen por anchura, no por un color más blanco.
        XCTAssertGreaterThan(try XCTUnwrap(width("road-motorway", atZoom: 16)), 1.5 * (try XCTUnwrap(width("road-secondary", atZoom: 16))))
    }

    func testRouteIsPurpleWithDarkCasing() {
        XCTAssertEqual((paint("route-core", "line-color") as? String)?.lowercased(), "#a855e8")
        XCTAssertEqual((paint("route-casing", "line-color") as? String)?.lowercased(), "#0f0f0f")
        XCTAssertFalse(json.lowercased().contains("#f23fc4"), "no debe quedar el magenta anterior")
    }

    // MARK: Etiquetas e iconos

    func testLabelsAreNotForcedToUppercase() {
        XCTAssertFalse(json.contains("\"text-transform\" : \"uppercase\""))
        XCTAssertFalse(json.contains("\"text-transform\": \"uppercase\""))
    }

    func testPOIsAreSplitByCategoryAndImportantOnesAppearFirst() throws {
        func zoom(_ id: String) -> Double? {
            guard let l = layer(id) else { return nil }
            return l["minzoom"] as? Double ?? (l["minzoom"] as? Int).map(Double.init)
        }
        for id in ["poi-icon-fuel", "poi-icon-transit", "poi-icon-health", "poi-icon-parking", "poi-icon-food",
                   "poi-icon-shops", "poi-icon-other", "poi-icon-bus-stop", "poi-icon-bike-parking", "poi-icon-bike-rental"] {
            XCTAssertNotNil(layer(id), id)
            XCTAssertNotNil((layer(id)?["layout"] as? [String: Any])?["symbol-sort-key"], "prioridad por rango: \(id)")
        }
        XCTAssertNil(layer("poi-icon"))
        // Lo importante (gasolinera, estación) llega antes que restaurantes y tiendas.
        XCTAssertLessThan(try XCTUnwrap(zoom("poi-icon-fuel")), try XCTUnwrap(zoom("poi-icon-food")))
        XCTAssertLessThan(try XCTUnwrap(zoom("poi-icon-transit")), try XCTUnwrap(zoom("poi-icon-food")))
        // Las paradas de autobús van en su propia capa (desactivable); las estaciones no las incluyen.
        let transit = String(decoding: try JSONSerialization.data(withJSONObject: layer("poi-icon-transit")?["filter"] as Any), as: UTF8.self)
        XCTAssertTrue(transit.contains("bus_stop") && transit.contains("!="))
        // Prioridad de colocación: las capas más arriba ganan las colisiones.
        let ids = layers.compactMap { $0["id"] as? String }
        XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: "poi-icon-food")), try XCTUnwrap(ids.firstIndex(of: "poi-icon-transit")))
    }

    func testEveryIconNameUsedByTheStyleHasAnAsset() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        var names = Set<String>()
        func collect(_ value: Any) {
            if let text = value as? String, text.hasPrefix("poi-") || text == "selection-arrows" { names.insert(text) }
            else if let array = value as? [Any] { array.forEach(collect) }
            else if let dictionary = value as? [String: Any] { dictionary.values.forEach(collect) }
        }
        for layer in layers where (layer["type"] as? String) == "symbol" {
            if let layout = layer["layout"] { collect(layout) }
        }
        XCTAssertFalse(names.isEmpty)
        for name in names {
            guard let asset = GameIcons.styleNameToAsset[name] else {
                if name == "poi-home" || name == "poi-work" { continue }
                XCTFail("El estilo usa \(name) pero GameIcons no lo registra"); continue
            }
            XCTAssertNotNil(UIImage(named: GameIcons.assetName(for: asset), in: bundle, compatibleWith: nil), "Falta el recurso \(asset)")
        }
        for asset in Set(GameIcons.styleNameToAsset.values) {
            XCTAssertNotNil(UIImage(named: GameIcons.assetName(for: asset), in: bundle, compatibleWith: nil), asset)
        }
    }

    func testDestinationSavedPlacesAndSelectionLayersExist() {
        XCTAssertEqual(layer("destination-core")?["type"] as? String, "symbol")
        XCTAssertNotNil(sources["selection"])
        XCTAssertNotNil(sources["saved"])
        let arrows = layer("selection-arrows")
        let layout = arrows?["layout"] as? [String: Any]
        XCTAssertEqual(layout?["icon-image"] as? String, "selection-arrows")
        XCTAssertEqual(layout?["icon-rotation-alignment"] as? String, "viewport")      // no gira con el mapa
        XCTAssertEqual(layout?["icon-size"] as? Double ?? Double(layout?["icon-size"] as? Int ?? 0), 1)  // tamaño estable
        XCTAssertNotNil(layer("saved-places"))
    }

    func testSelectionLayerSitsBelowDestinationAndUser() throws {
        let ids = layers.compactMap { $0["id"] as? String }
        let selection = try XCTUnwrap(ids.firstIndex(of: "selection-arrows"))
        XCTAssertLessThan(selection, try XCTUnwrap(ids.firstIndex(of: "destination-core")))
        XCTAssertLessThan(selection, try XCTUnwrap(ids.firstIndex(of: "user-arrow")))
    }

    func testOtherStylesAreNotTouchedByTheGTAIconWork() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        for name in ["style-minimalista-pro", "style-isla", "style-bloques"] {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
            let style = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let otherSources = try XCTUnwrap(style["sources"] as? [String: Any])
            XCTAssertNil(otherSources["selection"], name)
            XCTAssertNil(otherSources["saved"], name)
            let ids = (style["layers"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            XCTAssertTrue(ids.contains("poi-icon-food") && ids.contains("poi-icon-fuel"), "\(name) tiene capas de POI por categoría")
        }
        XCTAssertEqual(ThemeCatalog.minimalistaPro.activeCartography.poiIconSet, .systemSymbols)
        XCTAssertEqual(ThemeCatalog.ciudadNocturna.activeCartography.poiIconSet, .gameBadges)
    }
}

// MARK: - Selección y "Cómo llegar"

private final class CountingRouteService: RouteServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
    func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, mode: RouteMode) async throws -> [Route] {
        lock.lock(); _calls += 1; lock.unlock()
        return []
    }
}

@MainActor
final class MapSelectionTests: XCTestCase {
    private func makeViewModel(router: CountingRouteService) -> HomeViewModel {
        let manager = FakeLocationManager()
        let clock = TestClock()
        let service = LocationService(manager: manager, diagnostics: DiagnosticsLog(), clock: { clock.now },
                                      servicesEnabledProvider: { true }, startTimer: false)
        service.resolveAuth(status: .authorizedWhenInUse, accuracy: .fullAccuracy, servicesEnabled: true)
        service.start(mode: .idle)
        service.ingest(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038), altitude: 0,
                                  horizontalAccuracy: 10, verticalAccuracy: 5, course: 0, speed: 0, timestamp: clock.now))
        return HomeViewModel(locationService: service, routeService: router, headingUp: true)
    }

    private func place(_ name: String, _ lat: Double = 40.4170) -> Place {
        Place(id: name, name: name, subtitle: "", latitude: lat, longitude: -3.7040)
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(80)) }

    func testSelectingAPlaceDoesNotStartARoute() async {
        let router = CountingRouteService()
        let viewModel = makeViewModel(router: router)
        viewModel.select(place("Farmacia"))
        await settle()
        XCTAssertEqual(viewModel.selection?.name, "Farmacia")
        XCTAssertNil(viewModel.destination)
        XCTAssertEqual(router.calls, 0)
        XCTAssertEqual(viewModel.routeState, .idle)
    }

    func testOnlyOneSelectionExistsAndTheNewOneReplacesTheOld() {
        let viewModel = makeViewModel(router: CountingRouteService())
        viewModel.select(place("A"))
        viewModel.select(place("B"))
        XCTAssertEqual(viewModel.selection?.name, "B")
        viewModel.clearSelection()
        XCTAssertNil(viewModel.selection)
    }

    func testDirectionsConfirmationSetsTheDestinationAndCalculatesTheRoute() async {
        let router = CountingRouteService()
        let viewModel = makeViewModel(router: router)
        viewModel.select(place("Hotel"))
        viewModel.confirmSelection()
        await settle()
        XCTAssertNil(viewModel.selection)
        XCTAssertEqual(viewModel.destination?.name, "Hotel")
        XCTAssertEqual(router.calls, 1)
    }

    func testTouchingAnotherPlaceKeepsTheExistingRouteUntilConfirmed() async {
        let router = CountingRouteService()
        let viewModel = makeViewModel(router: router)
        viewModel.setDestination(place("Destino actual"))
        await settle()
        let callsBefore = router.calls
        viewModel.select(place("Otro lugar"))
        await settle()
        XCTAssertEqual(viewModel.destination?.name, "Destino actual")      // la ruta no se borra
        XCTAssertEqual(viewModel.selection?.name, "Otro lugar")            // se previsualiza la nueva selección
        XCTAssertEqual(router.calls, callsBefore)                          // sin recalcular todavía
        viewModel.confirmSelection()
        await settle()
        XCTAssertEqual(viewModel.destination?.name, "Otro lugar")          // ahora sí sustituye al destino
        XCTAssertNil(viewModel.selection)
    }

    func testConfirmingWithoutSelectionDoesNothing() {
        let viewModel = makeViewModel(router: CountingRouteService())
        viewModel.confirmSelection()
        XCTAssertNil(viewModel.destination)
    }

    // MARK: Datos del toque

    func testTappedPlaceKeepsTheOriginalNameWithAccentsAndSpaces() {
        let coordinate = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)
        let named = PoiClassTitles.place(from: MapTap(coordinate: coordinate,
                                                      feature: MapTappedFeature(name: "Café  Ñandú del Peñón", kind: "cafe")))
        XCTAssertEqual(named.name, "Café  Ñandú del Peñón")
        XCTAssertEqual(named.subtitle, "Cafetería")

        let unnamed = PoiClassTitles.place(from: MapTap(coordinate: coordinate, feature: MapTappedFeature(name: nil, kind: "fuel")))
        XCTAssertEqual(unnamed.name, "Gasolinera")

        let saved = PoiClassTitles.place(from: MapTap(coordinate: coordinate,
                                                      feature: MapTappedFeature(name: nil, kind: "poi-work", isSavedPlace: true)))
        XCTAssertEqual(saved.name, "Trabajo")

        let pin = PoiClassTitles.place(from: MapTap(coordinate: coordinate, feature: nil))
        XCTAssertEqual(pin.name, "Punto en el mapa")
    }

    func testEveryTierClassHasASpanishTitle() {
        for poiClass in ["fuel", "restaurant", "cafe", "bar", "parking", "hospital", "pharmacy", "bank", "atm", "lodging", "railway", "grocery", "shop", "police"] {
            XCTAssertNotEqual(PoiClassTitles.title(for: poiClass), "Lugar", poiClass)
        }
    }

    func testSavedPlaceKindsMapToHomeAndWorkIconsOnly() {
        XCTAssertEqual(GameIcons.savedIconName(for: .home), "poi-home")
        XCTAssertEqual(GameIcons.savedIconName(for: .work), "poi-work")
        XCTAssertNil(GameIcons.savedIconName(for: .favorite))
    }
}
