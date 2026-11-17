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

        try PerformanceTrace.measure("trip-save") {
            // Antes se cargaban TODAS las celdas exploradas (crece con el uso) al terminar cada ruta. Ahora solo se
            // consultan las claves de este viaje, y solo la propiedad necesaria.
            let keys = Array(summary.visitedKeys)
            var descriptor = FetchDescriptor<VisitedCell>(predicate: #Predicate { keys.contains($0.key) })
            descriptor.propertiesToFetch = [\.key]
            let known = Set(try context.fetch(descriptor).map(\.key))
            for key in summary.visitedKeys where !known.contains(key) {
                context.insert(VisitedCell(key: key))
            }
            try context.save()
        }
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
