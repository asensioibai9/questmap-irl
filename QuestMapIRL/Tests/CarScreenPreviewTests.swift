import CoreLocation
import XCTest
@testable import QuestMapIRL

/// Vista de pruebas: datos simulados aislados (sin GPS real, sin navegación real, voz muda) y distribución correcta en
/// cada proporción. NO prueba CarPlay ni sus plantillas.
@MainActor
final class CarScreenPreviewTests: XCTestCase {
    func testEveryPresetUsesTheLandscapeLayoutWithAFreeMapArea() {
        for preset in CarScreenPreset.all {
            let layout = MapScreenLayout(size: preset.size)
            XCTAssertTrue(layout.isSideBySide, preset.title)
            let free = layout.freeMapRect
            XCTAssertGreaterThan(free.width, 200, "\(preset.title): queda mapa libre")
            XCTAssertGreaterThanOrEqual(free.minX, layout.sidePanelWidth, "no se solapa con el panel")
            XCTAssertLessThanOrEqual(free.maxX, preset.size.width - layout.controlsWidth, "ni con los controles")
        }
    }

    func testDemoRouteIsSimulatedAndHasRealManeuverData() {
        let route = SimulatedRouteFactory.demoRoute(longNames: false)
        XCTAssertEqual(route.steps.count, 4)
        XCTAssertTrue(route.name.contains("simulado"))
        XCTAssertEqual(route.steps.map { $0.maneuver?.type }, ["depart", "turn", "turn", "arrive"])
        XCTAssertEqual(route.distanceMeters, 1400, accuracy: 15, "600 + 450 + 350 m (desplazamientos aproximados)")
        XCTAssertEqual(route.steps[0].distanceMeters, 600, accuracy: 10, "cada paso mide su tramo, no cero")
        let long = SimulatedRouteFactory.demoRoute(longNames: true)
        XCTAssertGreaterThan(long.steps[1].instruction.count, 50, "variante para comprobar textos largos")
    }

    func testSimulatedDriveIsSilentAndAdvancesItsOwnNavigation() {
        let drive = SimulatedDrive()
        XCTAssertTrue(drive.voice.isMuted, "la voz de la vista de pruebas nunca suena")
        drive.begin()
        let before = drive.navigation.snapshot.remainingMeters
        drive.advance(meters: 200)
        XCTAssertLessThan(drive.navigation.snapshot.remainingMeters, before)
        XCTAssertEqual(drive.location.currentLocation?.horizontalAccuracy, 5, "ubicación simulada, no la real")
    }

    func testJumpAndArrivalUseTheRealNavigationEngine() {
        let drive = SimulatedDrive()
        drive.begin()
        drive.jumpToNextManeuver()
        XCTAssertLessThanOrEqual(drive.navigation.snapshot.distanceToManeuver, 140)
        drive.arrive()
        XCTAssertTrue(drive.arrived, "llegada confirmada por el motor")
        XCTAssertFalse(drive.isPlaying)
    }

    func testForcedDetourRecalculatesWithTheSimulatedServiceOnly() async throws {
        let drive = SimulatedDrive()
        drive.begin()
        drive.advance(meters: 100)
        drive.forceRecalculation()
        for _ in 0..<40 where !drive.navigation.route.name.contains("recalculado") {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(drive.navigation.route.name.contains("recalculado"), "recálculo con la ruta simulada, sin servidor")
        drive.advance(meters: 0)
        XCTAssertNotNil(drive.position)
    }
}
