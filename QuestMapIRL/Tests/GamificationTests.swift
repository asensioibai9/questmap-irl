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

    func testAllThemesHaveUniqueIDs() {
        let ids = ThemeCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, MapThemeID.allCases.count)
    }
}
