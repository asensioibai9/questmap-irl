import XCTest
import CoreLocation
import UIKit
@testable import QuestMapIRL

@MainActor
private final class FakeRenderer: StylePreviewRendering {
    var rendered: [String] = []
    var failFor: Set<String> = []
    private(set) var running = 0
    private(set) var maxConcurrent = 0

    func render(style: CartographyStyle) async throws -> UIImage {
        running += 1
        maxConcurrent = max(maxConcurrent, running)
        defer { running -= 1 }
        await Task.yield()
        if failFor.contains(style.resourceName) { throw StylePreviewError.timedOut }
        rendered.append(style.resourceName)
        // Imagen distinta por estilo (el color depende del nombre) para detectar mezclas.
        let hue = CGFloat(abs(style.resourceName.hashValue % 100)) / 100
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 10)).image { context in
            UIColor(hue: hue, saturation: 0.8, brightness: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 10))
        }
    }
}

@MainActor
final class StylePreviewTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("previews-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func store(renderer: FakeRenderer, build: String = "1", data: @escaping (CartographyStyle) -> Data? = { Data($0.resourceName.utf8) }) -> StylePreviewStore {
        StylePreviewStore(cache: StylePreviewCache(directory: directory), renderer: renderer, scale: 2, build: build, loadStyleData: data)
    }

    private func waitUntilIdle(_ store: StylePreviewStore, themes: [MapTheme]) async {
        for _ in 0..<200 {
            let loading = themes.contains { if case .loading = store.state(for: $0.id) { return true } else { return false } }
            if !loading { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private var themes: [MapTheme] { ThemeCatalog.all.filter(\.isCartographyReady) }

    // MARK: Nombres

    func testVisibleNamesAreTheReferenceGamesAndInternalIDsDidNotChange() {
        let expected: [MapThemeID: (raw: String, name: String)] = [
            .ciudadNocturna: ("ciudadNocturna", "GTA V"), .islaRoyale: ("islaRoyale", "Fortnite"),
            .mundoBloques: ("mundoBloques", "Minecraft"), .salvajeOeste: ("salvajeOeste", "Red Dead Redemption 2"),
            .ciudadCiber: ("ciudadCiber", "Cyberpunk 2077"), .mapaFantasia: ("mapaFantasia", "Skyrim"),
            .redUrbana: ("redUrbana", "Watch Dogs 2"), .rutasRally: ("rutasRally", "Forza Horizon 5"),
            .minimalistaPro: ("minimalistaPro", "Minimalista Pro"),
        ]
        for (id, value) in expected {
            XCTAssertEqual(id.rawValue, value.raw, "el identificador guardado en las preferencias no debe cambiar")
            XCTAssertEqual(ThemeCatalog.theme(for: id).name, value.name)
        }
    }

    func testOldSavedPreferencesStillResolveToTheSameStyle() {
        for raw in ["ciudadNocturna", "islaRoyale", "mundoBloques", "minimalistaPro", "salvajeOeste", "ciudadCiber", "mapaFantasia"] {
            let id = try? XCTUnwrap(MapThemeID(rawValue: raw))
            XCTAssertNotNil(id, raw)
        }
    }

    func testNoPlaceholderAppearsInTheSelectorAndEveryNameIsUnique() {
        XCTAssertFalse(themes.contains { $0.id == .retroArcade }, "un placeholder no se muestra como estilo terminado")
        XCTAssertEqual(Set(themes.map(\.name)).count, themes.count)
        XCTAssertEqual(themes.count, 9)
    }

    func testDisclaimerStatesNoAffiliationAndAppNameIsUnchanged() {
        XCTAssertTrue(MapStyleNames.disclaimer.contains("no es oficial"))
        XCTAssertTrue(MapStyleNames.disclaimer.contains("afiliada"))
        XCTAssertEqual(AppConfig.appName, "QuestMap IRL")
    }

    // MARK: Zona de la preview

    func testSpecIsPublicAndTheSampleRouteFitsTheFrame() {
        XCTAssertEqual(StylePreviewSpec.size.width / StylePreviewSpec.size.height, 1.6, accuracy: 0.001)
        // Madrid Río: no es ninguna ubicación del usuario.
        XCTAssertEqual(StylePreviewSpec.center.latitude, 40.398, accuracy: 0.01)
        let metersPerPoint = 78_271.5 * cos(StylePreviewSpec.center.latitude * .pi / 180) / pow(2, StylePreviewSpec.zoom)
        let halfWidth = Double(StylePreviewSpec.size.width) / 2 * metersPerPoint
        let halfHeight = Double(StylePreviewSpec.size.height) / 2 * metersPerPoint
        let center = CLLocation(latitude: StylePreviewSpec.center.latitude, longitude: StylePreviewSpec.center.longitude)
        for point in StylePreviewSpec.route {
            let dx = CLLocation(latitude: center.coordinate.latitude, longitude: point.longitude).distance(from: center)
            let dy = CLLocation(latitude: point.latitude, longitude: center.coordinate.longitude).distance(from: center)
            XCTAssertLessThan(dx, halfWidth, "la ruta de ejemplo cabe en el encuadre")
            XCTAssertLessThan(dy, halfHeight)
        }
        XCTAssertGreaterThan(StylePreviewSpec.route.count, 10)
        XCTAssertTrue((0..<360).contains(StylePreviewSpec.user.heading))
    }

    // MARK: Caché

    func testFingerprintChangesWithStyleContentSpecBuildAndScale() {
        let base = StylePreviewCache.fingerprint(styleData: Data("a".utf8), specVersion: 1, appBuild: "1", scale: 2)
        XCTAssertNotEqual(base, StylePreviewCache.fingerprint(styleData: Data("b".utf8), specVersion: 1, appBuild: "1", scale: 2))
        XCTAssertNotEqual(base, StylePreviewCache.fingerprint(styleData: Data("a".utf8), specVersion: 2, appBuild: "1", scale: 2))
        XCTAssertNotEqual(base, StylePreviewCache.fingerprint(styleData: Data("a".utf8), specVersion: 1, appBuild: "2", scale: 2))
        XCTAssertNotEqual(base, StylePreviewCache.fingerprint(styleData: Data("a".utf8), specVersion: 1, appBuild: "1", scale: 3))
        XCTAssertEqual(base, StylePreviewCache.fingerprint(styleData: Data("a".utf8), specVersion: 1, appBuild: "1", scale: 2))
    }

    func testCacheStoresAndDeletesOldVersionsOfTheSameStyleOnly() throws {
        let cache = StylePreviewCache(directory: directory)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
        try cache.store(image, styleID: "a", fingerprint: "v1")
        try cache.store(image, styleID: "b", fingerprint: "v1")
        try cache.store(image, styleID: "a", fingerprint: "v2")
        XCTAssertNil(cache.load(styleID: "a", fingerprint: "v1"), "la versión antigua se invalida")
        XCTAssertNotNil(cache.load(styleID: "a", fingerprint: "v2"))
        XCTAssertNotNil(cache.load(styleID: "b", fingerprint: "v1"), "otros estilos no se tocan")
    }

    // MARK: Almacén

    func testSecondOpeningReadsTheCacheAndDoesNotRenderAgain() async {
        let renderer = FakeRenderer()
        let first = store(renderer: renderer)
        first.prepare(themes: themes, selected: .ciudadNocturna)
        await waitUntilIdle(first, themes: themes)
        XCTAssertEqual(renderer.rendered.count, themes.count)

        let second = store(renderer: renderer)           // «otra apertura»: almacén nuevo, misma caché
        second.prepare(themes: themes, selected: nil)
        await waitUntilIdle(second, themes: themes)          // la caché se decodifica fuera del hilo principal
        for theme in themes {
            if case .ready = second.state(for: theme.id) {} else { XCTFail("\(theme.name) debía salir de la caché") }
        }
        XCTAssertEqual(renderer.rendered.count, themes.count, "no se regeneró ninguna")
    }

    func testChangedStyleInvalidatesOnlyThatPreview() async {
        let renderer = FakeRenderer()
        let first = store(renderer: renderer)
        first.prepare(themes: themes, selected: nil)
        await waitUntilIdle(first, themes: themes)
        let before = renderer.rendered.count

        let second = store(renderer: renderer) { style in Data((style.resourceName + (style.resourceName == "style-isla" ? "-nuevo" : "")).utf8) }
        second.prepare(themes: themes, selected: nil)
        await waitUntilIdle(second, themes: themes)
        XCTAssertEqual(renderer.rendered.count - before, 1)
        XCTAssertEqual(renderer.rendered.last, "style-isla")
    }

    func testPreviewsAreGeneratedOneAtATimeStartingWithTheSelectedStyle() async {
        let renderer = FakeRenderer()
        let store = store(renderer: renderer)
        store.prepare(themes: themes, selected: .rutasRally)
        await waitUntilIdle(store, themes: themes)
        XCTAssertEqual(renderer.maxConcurrent, 1, "nunca varios mapas a la vez")
        XCTAssertEqual(renderer.rendered.first, "style-rutas-rally")
    }

    func testAFailedPreviewIsHonestAndNeverShowsAnotherStylesImage() async {
        let renderer = FakeRenderer()
        renderer.failFor = ["style-isla"]
        let store = store(renderer: renderer)
        store.prepare(themes: themes, selected: nil)
        await waitUntilIdle(store, themes: themes)
        if case .failed = store.state(for: .islaRoyale) {} else { XCTFail("Isla debía quedar como fallida") }
        if case .ready = store.state(for: .ciudadNocturna) {} else { XCTFail("las demás siguen bien") }

        renderer.failFor = []
        store.retry(ThemeCatalog.islaRoyale, themes: themes, selected: nil)
        await waitUntilIdle(store, themes: themes)
        if case .ready = store.state(for: .islaRoyale) {} else { XCTFail("tras reintentar sale la preview") }
    }

    // MARK: Render REAL con el motor (simulador)

    private func samples(_ image: UIImage) -> [Double] {
        let width = 32, height = 20
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let cg = image.cgImage,
              let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).flatMap { [Double(pixels[$0]), Double(pixels[$0 + 1]), Double(pixels[$0 + 2])] }
    }

    /// Renderiza de verdad cada estilo con MLNMapSnapshotter. Necesita red y render en el simulador: si el entorno no lo
    /// permite, el test se SALTA (y el resumen lo dice) en vez de dar por buena una preview que no existe.
    func testRealSnapshotsRenderEveryStyleAndAreDistinct() async throws {
        let renderer = StylePreviewRenderer()
        var images: [(String, UIImage)] = []
        for theme in themes {
            do {
                let image = try await renderer.render(style: theme.activeCartography, timeout: 45)
                images.append((theme.name, image))
            } catch {
                throw XCTSkip("No se pudo renderizar «\(theme.name)» en este entorno: \(error.localizedDescription)")
            }
        }
        var means: [String: [Double]] = [:]
        for (name, image) in images {
            XCTAssertEqual(image.size.width, StylePreviewSpec.size.width, accuracy: 1, "\(name): tamaño")
            let values = samples(image)
            XCTAssertFalse(values.isEmpty)
            let mean = values.reduce(0, +) / Double(values.count)
            let deviation = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
            XCTAssertGreaterThan(deviation, 3, "\(name): la preview no está en blanco")
            let r = stride(from: 0, to: values.count, by: 3).map { values[$0] }.reduce(0, +) / Double(values.count / 3)
            let g = stride(from: 1, to: values.count, by: 3).map { values[$0] }.reduce(0, +) / Double(values.count / 3)
            let b = stride(from: 2, to: values.count, by: 3).map { values[$0] }.reduce(0, +) / Double(values.count / 3)
            means[name] = [r, g, b]
            print("PREVIEW \(name): tamaño \(Int(image.size.width))x\(Int(image.size.height)) media RGB = \(Int(r)),\(Int(g)),\(Int(b)) desviación \(Int(deviation))")
        }
        for (i, a) in images.enumerated() {
            for b in images.dropFirst(i + 1) {
                let x = samples(a.1), y = samples(b.1)
                let difference = zip(x, y).map { abs($0 - $1) }.reduce(0, +) / Double(x.count)
                XCTAssertGreaterThan(difference, 6, "\(a.0) y \(b.0) no deben ser la misma imagen")
            }
        }
    }
}
