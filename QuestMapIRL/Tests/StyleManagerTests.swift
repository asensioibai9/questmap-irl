import XCTest
@testable import QuestMapIRL

final class StyleManagerTests: XCTestCase {
    private let template = """
    {"version":8,"glyphs":"{{GLYPHS_URL}}","sources":{"openmaptiles":{"type":"vector","url":"{{TILES_URL}}"}},
     "layers":[{"id":"background","type":"background"}]}
    """

    func testPlaceholdersAreResolved() throws {
        let data = try StyleManager.resolve(Data(template.utf8), provider: .openFreeMap)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("https://tiles.openfreemap.org/planet"))
        XCTAssertTrue(text.contains("{fontstack}/{range}"))
        XCTAssertFalse(text.contains("{{"))
    }

    func testMissingProviderConfigurationFailsClearly() {
        let empty = MapProviderConfig(tilesURL: "", glyphsURL: "")
        XCTAssertThrowsError(try StyleManager.resolve(Data(template.utf8), provider: empty)) {
            XCTAssertEqual($0 as? StyleError, .providerNotConfigured)
        }
    }

    func testInvalidStylesAreRejected() {
        XCTAssertThrowsError(try StyleManager.resolve(Data("{no json".utf8), provider: .openFreeMap))
        let wrongVersion = #"{"version":7,"sources":{},"layers":[{"id":"a"}]}"#
        XCTAssertThrowsError(try StyleManager.resolve(Data(wrongVersion.utf8), provider: .openFreeMap))
        let noLayers = #"{"version":8,"sources":{},"layers":[]}"#
        XCTAssertThrowsError(try StyleManager.resolve(Data(noLayers.utf8), provider: .openFreeMap))
    }

    /// Cada tema con estilo terminado debe tener su JSON dentro de la app y poder resolverse.
    @MainActor
    func testShippedStylesResolveAndKeepNavigationSources() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        for theme in ThemeCatalog.all where theme.isCartographyReady {
            let name = theme.activeCartography.resourceName
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "Falta \(name).json en el bundle")
            let data = try StyleManager.resolve(Data(contentsOf: url), provider: .openFreeMap)
            let style = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let sources = try XCTUnwrap(style["sources"] as? [String: Any])
            for required in ["openmaptiles", "route", "destination", "user", "results"] {
                XCTAssertNotNil(sources[required], "\(name): falta la fuente \(required)")
            }
            let layers = try XCTUnwrap(style["layers"] as? [[String: Any]])
            let ids = Set(layers.compactMap { $0["id"] as? String })
            for required in ["route-core", "destination-core", "user-arrow", "results-core"] {
                XCTAssertTrue(ids.contains(required), "\(name): falta la capa \(required)")
            }
        }
    }

    /// Las texturas que declara cada tema deben ser exactamente las que pide su JSON, y existir en el catálogo.
    @MainActor
    func testDeclaredTexturesMatchStyleMetadataAndExist() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        for theme in ThemeCatalog.all where theme.isCartographyReady {
            let cartography = theme.activeCartography
            let url = try XCTUnwrap(bundle.url(forResource: cartography.resourceName, withExtension: "json"))
            let style = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let metadata = style["metadata"] as? [String: Any] ?? [:]
            let wanted = Set(metadata["questmap:images"] as? [String] ?? [])
            XCTAssertEqual(wanted, Set(cartography.textures), "\(cartography.resourceName): texturas desalineadas")
            for name in wanted {
                XCTAssertNotNil(UIImage(named: name, in: bundle, compatibleWith: nil), "Falta la textura \(name)")
            }
        }
    }
}
