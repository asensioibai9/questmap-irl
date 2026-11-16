import XCTest
import CoreLocation
@testable import QuestMapIRL

final class MVTPOIDecoderTests: XCTestCase {
    func testDecodesOnlyPointsOfThePOILayerWithRealCoordinates() throws {
        let tile = makeFixtureTile(pois: [
            FixturePOI(poiClass: "pharmacy", subclass: "pharmacy", name: "Farmacia Sol", x: 2048, y: 2048),
            FixturePOI(poiClass: "fuel", subclass: "charging_station", name: nil, x: 0, y: 4096),
            FixturePOI(poiClass: "cafe", subclass: "cafe", name: "No es un punto", x: 1, y: 1, geometryType: 3),
        ])
        let pois = try MVTPOIDecoder.decode(tile, z: 14, x: 8023, y: 6177)
        XCTAssertEqual(pois.count, 2)                               // el polígono se ignora
        let pharmacy = try XCTUnwrap(pois.first)
        XCTAssertEqual(pharmacy.name, "Farmacia Sol")
        XCTAssertEqual(pharmacy.poiClass, "pharmacy")
        // Centro del tile 14/8023/6177 (Madrid): se calcula con la fórmula estándar de teselas.
        let n = pow(2.0, 14.0)
        XCTAssertEqual(pharmacy.longitude, (8023.5) / n * 360 - 180, accuracy: 1e-9)
        XCTAssertEqual(pharmacy.latitude, atan(sinh(.pi * (1 - 2 * 6177.5 / n))) * 180 / .pi, accuracy: 1e-9)
        XCTAssertTrue((40.3...40.5).contains(pharmacy.latitude) && (-3.8 ... -3.6).contains(pharmacy.longitude))
        XCTAssertNil(pois[1].name)
        XCTAssertEqual(pois[1].subclass, "charging_station")
    }

    func testMalformedDataThrowsInsteadOfCrashing() {
        XCTAssertThrowsError(try MVTPOIDecoder.decode(Data([0x1A, 0xFF, 0xFF, 0xFF]), z: 14, x: 0, y: 0))
        XCTAssertEqual(try MVTPOIDecoder.decode(Data(), z: 14, x: 0, y: 0), [])
    }
}

final class TilePOISearchServiceTests: XCTestCase {
    private let center = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)   // Puerta del Sol
    private var diagnostics: DiagnosticsLog!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        diagnostics = DiagnosticsLog()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeService(retries: Int = 0) -> TilePOISearchService {
        let client = ServiceClient(service: "tiles", session: StubURLProtocol.session(),
                                   retry: instantRetry(maxRetries: retries), diagnostics: diagnostics)
        return TilePOISearchService(tileJSONURL: URL(string: "https://tiles.test/planet")!, client: client, cache: TileCache())
    }

    /// Posición en unidades del tile (extent 4096) de un punto cercano al centro, desplazado en metros.
    private func fixturePOI(_ cls: String, _ sub: String?, _ name: String?, eastMeters: Double, northMeters: Double) -> (poi: FixturePOI, tile: (Int, Int)) {
        let lat = center.latitude + northMeters / 111_320
        let lon = center.longitude + eastMeters / (111_320 * cos(center.latitude * .pi / 180))
        let n = pow(2.0, 14.0)
        let fx = (lon + 180) / 360 * n
        let fy = (1 - asinh(tan(lat * .pi / 180)) / .pi) / 2 * n
        let tx = Int(floor(fx)), ty = Int(floor(fy))
        return (FixturePOI(poiClass: cls, subclass: sub, name: name, x: Int((fx - Double(tx)) * 4096), y: Int((fy - Double(ty)) * 4096)), (tx, ty))
    }

    private func serve(_ items: [(poi: FixturePOI, tile: (Int, Int))], failTilesWith status: Int? = nil) {
        StubURLProtocol.responder = { request in
            let url = request.url!.absoluteString
            if url == "https://tiles.test/planet" { return ok(tileJSONData()) }
            if let status { return http(status) }
            let parts = url.split(separator: "/")
            let y = Int(parts.last!.replacingOccurrences(of: ".pbf", with: ""))!, x = Int(parts[parts.count - 2])!
            return ok(makeFixtureTile(pois: items.filter { $0.tile == (x, y) }.map(\.poi)))
        }
    }

    func testReturnsOnlyTheRequestedCategorySortedByDistanceWithoutDuplicates() async throws {
        let near = fixturePOI("fuel", "fuel", "Repsol", eastMeters: 300, northMeters: 0)
        let far = fixturePOI("fuel", "fuel", "Cepsa", eastMeters: 1500, northMeters: 200)
        let charger = fixturePOI("fuel", "charging_station", "EMT Carga", eastMeters: 100, northMeters: 0)
        let pharmacy = fixturePOI("pharmacy", "pharmacy", "Farmacia", eastMeters: 50, northMeters: 0)
        let duplicate = near
        serve([far, near, charger, pharmacy, duplicate])

        let places = try await makeService().nearby(.fuel, around: center, radiusMeters: 2000)
        XCTAssertEqual(places.map(\.name), ["Repsol", "Cepsa"])           // sin cargadores, sin farmacias, sin duplicados
    }

    func testRadiusLimitsResultsAndEmptyIsNotAnError() async throws {
        serve([fixturePOI("cafe", "cafe", "Lejos", eastMeters: 1800, northMeters: 0)])
        let none = try await makeService().nearby(.cafe, around: center, radiusMeters: 500)
        XCTAssertTrue(none.isEmpty)
        let some = try await makeService().nearby(.cafe, around: center, radiusMeters: 2000)
        XCTAssertEqual(some.map(\.name), ["Lejos"])
    }

    func testUnnamedPlaceUsesCategoryName() async throws {
        serve([fixturePOI("parking", "parking", nil, eastMeters: 100, northMeters: 0)])
        let places = try await makeService().nearby(.parking, around: center, radiusMeters: 1000)
        XCTAssertEqual(places.first?.name, "Aparcamiento")
    }

    func testTilesCoverTheSearchCircleWithTheCenterTileFirst() {
        let tiles = TilePOISearchService.tiles(around: center, radiusMeters: 2000, z: 14)
        XCTAssertFalse(tiles.isEmpty)
        XCTAssertEqual(tiles.first?.x, 8023)
        XCTAssertEqual(tiles.first?.y, 6177)
        XCTAssertLessThan(tiles.count, 10)
        XCTAssertEqual(Set(tiles).count, tiles.count)
    }

    func testServerErrorOnTilesIsReportedAsServiceUnavailableNotOffline() async {
        serve([], failTilesWith: 502)
        do {
            _ = try await makeService().nearby(.fuel, around: center, radiusMeters: 2000)
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? SearchError, .serviceUnavailable)
        }
    }

    func testRecoversAfterATransientServerError() async throws {
        var tileCalls = 0
        let item = fixturePOI("hotel", "hotel", "Hotel Europa", eastMeters: 80, northMeters: 0)
        StubURLProtocol.responder = { request in
            let url = request.url!.absoluteString
            if url == "https://tiles.test/planet" { return ok(tileJSONData()) }
            tileCalls += 1
            if tileCalls == 1 { return http(503) }
            let parts = url.split(separator: "/")
            let y = Int(parts.last!.replacingOccurrences(of: ".pbf", with: ""))!, x = Int(parts[parts.count - 2])!
            return ok(makeFixtureTile(pois: (x, y) == item.tile ? [item.poi] : []))
        }
        let places = try await makeService(retries: 2).nearby(.hotel, around: center, radiusMeters: 1000)
        XCTAssertEqual(places.map(\.name), ["Hotel Europa"])
    }

    func testBrokenTileIsADecodingErrorAndInvalidCoordinatesAreRejected() async {
        StubURLProtocol.responder = { request in
            request.url!.absoluteString == "https://tiles.test/planet" ? ok(tileJSONData()) : ok(Data([0x1A, 0xFF, 0xFF, 0xFF]))
        }
        do {
            _ = try await makeService().nearby(.fuel, around: center, radiusMeters: 1000)
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? SearchError, .decoding)
        }
        do {
            _ = try await makeService().nearby(.fuel, around: CLLocationCoordinate2D(latitude: 200, longitude: 0), radiusMeters: 1000)
            XCTFail("Debía rechazar coordenadas inválidas")
        } catch {
            XCTAssertEqual(error as? SearchError, .configuration)
        }
    }

    func testTileJSONParsing() throws {
        XCTAssertEqual(try TilePOISearchService.parseTileJSON(tileJSONData(maxZoom: 13)).maxZoom, 13)
        XCTAssertThrowsError(try TilePOISearchService.parseTileJSON(Data("{}".utf8)))
        XCTAssertThrowsError(try TilePOISearchService.parseTileJSON(Data("{\"tiles\":[\"https://x/{z}\"]}".utf8)))
    }

    func testEveryGridCategoryHasAFilter() {
        for category in PlaceCategory.grid {
            XCTAssertFalse(category.tileMatch.classes.isEmpty, category.title)
        }
        XCTAssertTrue(PlaceCategory.fuel.tileMatch.matches(poiClass: "fuel", subclass: "fuel"))
        XCTAssertFalse(PlaceCategory.fuel.tileMatch.matches(poiClass: "fuel", subclass: "charging_station"))
        XCTAssertFalse(PlaceCategory.hospital.tileMatch.matches(poiClass: "hospital", subclass: "clinic"))
    }
}
