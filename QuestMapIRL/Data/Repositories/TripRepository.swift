import Foundation
import SwiftData

/// Guarda viajes y celdas de niebla al terminar una navegación.
@MainActor
struct TripRepository {
    let context: ModelContext

    func save(_ summary: TripSummary) throws {
        context.insert(TripRecord(
            startedAt: summary.startedAt,
            distanceMeters: summary.distanceMeters,
            durationSeconds: summary.durationSeconds,
            destinationName: summary.destinationName,
            destinationKey: summary.destinationKey,
            modeRawValue: summary.modeRawValue
        ))

        let existing = try context.fetch(FetchDescriptor<VisitedCell>())
        let known = Set(existing.map(\.key))
        for key in summary.visitedKeys where !known.contains(key) {
            context.insert(VisitedCell(key: key))
        }
        try context.save()
    }
}

struct TripSummary {
    let startedAt: Date
    let distanceMeters: Double
    let durationSeconds: Double
    let destinationName: String
    let destinationKey: String
    let modeRawValue: String
    let visitedKeys: Set<String>
}
