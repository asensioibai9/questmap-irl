import Foundation
import SwiftData

/// Viaje completado. Solo se guarda en el dispositivo.
@Model
final class TripRecord {
    var startedAt: Date
    var distanceMeters: Double
    var durationSeconds: Double
    var destinationName: String
    var destinationKey: String   // coordenada redondeada, para contar destinos distintos
    var modeRawValue: String

    init(startedAt: Date, distanceMeters: Double, durationSeconds: Double,
         destinationName: String, destinationKey: String, modeRawValue: String) {
        self.startedAt = startedAt
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.destinationName = destinationName
        self.destinationKey = destinationKey
        self.modeRawValue = modeRawValue
    }
}
