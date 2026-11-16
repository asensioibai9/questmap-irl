import XCTest
import CoreLocation
@testable import QuestMapIRL

final class NearbySearchTests: XCTestCase {
    private let fixture = """
    {"elements":[
      {"type":"node","id":1,"lat":40.4170,"lon":-3.7040,"tags":{"name":"Repsol","amenity":"fuel","addr:street":"Calle Mayor","addr:housenumber":"5","addr:city":"Madrid"}},
      {"type":"way","id":2,"center":{"lat":40.4200,"lon":-3.7000},"tags":{"amenity":"fuel","brand":"Cepsa"}},
      {"type":"node","id":3,"lat":40.4170,"lon":-3.7040,"tags":{"name":"Repsol","amenity":"fuel"}},
      {"type":"node","id":4,"tags":{"name":"Sin coordenadas"}},
      {"type":"node","id":5,"lat":40.4300,"lon":-3.7100,"tags":{"amenity":"fuel"}}
    ]}
    """

    func testParseUsesCentersNamesAndAddresses() throws {
        let places = try OverpassNearbyService.parse(Data(fixture.utf8), category: .fuel)
        // El duplicado exacto (mismo nombre y punto) y el elemento sin coordenadas se descartan.
        XCTAssertEqual(places.count, 3)
        XCTAssertEqual(places[0].name, "Repsol")
        XCTAssertEqual(places[0].subtitle, "Calle Mayor 5, Madrid")
        XCTAssertEqual(places[1].name, "Cepsa")                 // sin nombre: usa la marca
        XCTAssertEqual(places[1].latitude, 40.4200, accuracy: 0.0001)
        XCTAssertEqual(places[2].name, "Gasolinera")           // sin nombre ni marca: nombre de la categoría
    }

    func testParseRejectsUnexpectedPayload() {
        XCTAssertThrowsError(try OverpassNearbyService.parse(Data("{}".utf8), category: .fuel))
    }

    func testSortedByDistance() {
        let origin = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)
        let near = Place(id: "a", name: "A", subtitle: "", latitude: 40.4170, longitude: -3.7040)
        let far = Place(id: "b", name: "B", subtitle: "", latitude: 40.4300, longitude: -3.7100)
        XCTAssertEqual(OverpassNearbyService.sortedByDistance([far, near], from: origin).map(\.id), ["a", "b"])
    }

    func testQueryContainsRadiusCenterAndEveryFilter() {
        let query = OverpassNearbyService.query(.transit, around: CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038), radiusMeters: 2500)
        XCTAssertTrue(query.contains("around:2500,40.41680,-3.70380"))
        XCTAssertTrue(query.contains("\"railway\"=\"station\""))
        XCTAssertTrue(query.contains("\"public_transport\"=\"station\""))
        XCTAssertTrue(query.contains("out center"))
    }

    func testGridHasTheTenRequestedCategories() {
        XCTAssertEqual(PlaceCategory.grid.count, 10)
        XCTAssertEqual(Set(PlaceCategory.grid.map(\.title)).count, 10)
    }

    func testEveryAvatarDrawsAnImage() {
        for avatar in MapAvatar.allCases {
            let image = avatar.image(fill: .white, border: .black)
            XCTAssertEqual(image.size.width, 48)
        }
    }
}
