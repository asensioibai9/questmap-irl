import XCTest
import CoreLocation
@testable import QuestMapIRL

final class CarPlayPresentationTests: XCTestCase {
    private let route = Route(
        name: "A-8", coordinates: [CLLocationCoordinate2D(latitude: 1, longitude: 1), CLLocationCoordinate2D(latitude: 1.1, longitude: 1)],
        distanceMeters: 5400, durationSeconds: 720,
        steps: [RouteStep(instruction: "Sal", distanceMeters: 100, symbol: "arrow.up", streetName: "Calle Mayor"),
                RouteStep(instruction: "Gira a la derecha", distanceMeters: 100, symbol: "arrow.turn.up.right", streetName: ""),
                RouteStep(instruction: "Has llegado", distanceMeters: 0, symbol: "flag", streetName: "")])

    func testManeuverVariantsGoFromLongToShort() {
        XCTAssertEqual(CarPlayPresentation.maneuverVariants(route.steps[0]), ["Sal · Calle Mayor", "Sal"])
        XCTAssertEqual(CarPlayPresentation.maneuverVariants(route.steps[1]), ["Gira a la derecha"])
    }

    func testRouteSummaryAndInformation() {
        XCTAssertEqual(CarPlayPresentation.routeSummary(route, metric: true).last, "12 min")
        XCTAssertTrue(CarPlayPresentation.routeSummary(route, metric: true).first?.hasPrefix("12 min · ") ?? false)
        XCTAssertEqual(CarPlayPresentation.routeInformation(route, index: 1, count: 3), ["Ruta 2 de 3 · Por A-8"])
        XCTAssertEqual(CarPlayPresentation.routeInformation(route, index: 0, count: 1), ["Por A-8"])
    }

    func testUpcomingManeuversAreNextAndFollowing() {
        var snapshot = NavigationSnapshot()
        snapshot.upcomingIndex = 0
        XCTAssertEqual(CarPlayPresentation.upcomingIndices(snapshot: snapshot, stepCount: 3), [0, 1])
        snapshot.upcomingIndex = 2
        XCTAssertEqual(CarPlayPresentation.upcomingIndices(snapshot: snapshot, stepCount: 3), [2])
        snapshot.upcomingIndex = 9
        XCTAssertEqual(CarPlayPresentation.upcomingIndices(snapshot: snapshot, stepCount: 3), [2], "nunca se sale de la lista")
        XCTAssertEqual(CarPlayPresentation.upcomingIndices(snapshot: snapshot, stepCount: 0), [])
    }

    func testSecondsUseTheAverageSpeedOfTheRouteItself() {
        XCTAssertEqual(CarPlayPresentation.seconds(forMeters: 750, route: route), 100, accuracy: 0.001)
        XCTAssertEqual(CarPlayPresentation.seconds(forMeters: 750, route: Route(name: "x", coordinates: route.coordinates, distanceMeters: 0,
                                                                                durationSeconds: 0, steps: [])), 0)
    }

    func testListsAreLimited() {
        XCTAssertEqual(CarPlayPresentation.limited(Array(1...20), max: 12).count, 12)
        XCTAssertEqual(CarPlayPresentation.limited([1, 2], max: 12), [1, 2])
        XCTAssertEqual(CarPlayPresentation.limited([1, 2], max: -3), [])
    }

    func testPlaceDetailJoinsAddressAndDistance() {
        let place = Place(id: "1", name: "Bar", subtitle: "Deba", latitude: 0, longitude: 0)
        XCTAssertTrue(CarPlayPresentation.detail(for: place, distanceMeters: 1200, metric: true).hasPrefix("Deba · "))
        XCTAssertEqual(CarPlayPresentation.detail(for: place, distanceMeters: nil, metric: true), "Deba")
    }

    // MARK: Configuración del proyecto

    func testInfoPlistAllowsTheSecondSceneAndKeepsOnlyNeededBackgroundModes() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        let manifest = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any])
        XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, true, "CarPlay es una segunda escena")
        let modes = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        XCTAssertEqual(Set(modes), ["location", "audio"], "no se añaden modos de fondo que no se necesitan")
    }
}
