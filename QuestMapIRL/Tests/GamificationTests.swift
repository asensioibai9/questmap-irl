import XCTest
@testable import QuestMapIRL

final class GamificationTests: XCTestCase {
    func testStatsAggregation() {
        let trips = [
            TripSnapshot(date: .now, distanceMeters: 60_000, durationSeconds: 3600, destinationKey: "a"),
            TripSnapshot(date: .now, distanceMeters: 50_000, durationSeconds: 1800, destinationKey: "b"),
            TripSnapshot(date: .now, distanceMeters: 1_000, durationSeconds: 60, destinationKey: "a")
        ]
        let stats = TravelStats.make(trips: trips, revealedCells: 12)
        XCTAssertEqual(stats.kilometers, 111, accuracy: 0.01)
        XCTAssertEqual(stats.routesCompleted, 3)
        XCTAssertEqual(stats.uniqueDestinations, 2)
        XCTAssertEqual(stats.minutesNavigating, 91)
        XCTAssertEqual(stats.streakDays, 1)
    }

    func testHundredKmAchievementUnlocks() {
        var stats = TravelStats()
        stats.kilometers = 99
        XCTAssertFalse(Achievements.unlocked(for: stats).contains { $0.id == "km100" })
        stats.kilometers = 100
        XCTAssertTrue(Achievements.unlocked(for: stats).contains { $0.id == "km100" })
    }

    func testLevelIsCosmeticAndMonotonic() {
        XCTAssertEqual(Achievements.level(forXP: 0), 1)
        XCTAssertEqual(Achievements.level(forXP: 499), 1)
        XCTAssertEqual(Achievements.level(forXP: 500), 2)
    }

    @MainActor
    func testAllThemesAreDefinedAndUnique() {
        let ids = ThemeCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, MapThemeID.allCases.count)
        for id in MapThemeID.allCases {
            XCTAssertEqual(ThemeCatalog.theme(for: id).id, id, "Falta el tema \(id.rawValue)")
        }
    }

    @MainActor
    func testEveryThemeCoversEveryPOIKind() {
        for theme in ThemeCatalog.all {
            for kind in POIKind.allCases {
                XCTAssertFalse(theme.icon(for: kind).isEmpty, "\(theme.name) sin icono para \(kind.rawValue)")
            }
        }
    }
}

final class ManeuverFormatterTests: XCTestCase {
    func testRoundsToFriendlyDistance() {
        let text = ManeuverFormatter.spoken(instruction: "Gira a la derecha", distance: 212, metric: true)
        XCTAssertEqual(text, "En 200 metros, gira a la derecha")
    }

    func testKilometersUseCommaDecimal() {
        let text = ManeuverFormatter.spoken(instruction: "Continúa recto", distance: 1500, metric: true)
        XCTAssertTrue(text.contains("1,5 kilómetros"), text)
    }

    func testCloseManeuverHasNoDistancePrefix() {
        let text = ManeuverFormatter.spoken(instruction: "gira a la izquierda", distance: 20, metric: true)
        XCTAssertEqual(text, "Gira a la izquierda")
    }

    func testSymbolsMatchInstruction() {
        XCTAssertEqual(ManeuverFormatter.symbol(for: "Gira a la derecha"), "arrow.turn.up.right")
        XCTAssertEqual(ManeuverFormatter.symbol(for: "Has llegado a tu destino"), "flag.checkered")
        XCTAssertEqual(ManeuverFormatter.symbol(for: "Incorpórate a la A-6"), "arrow.merge")
    }
}
