import Foundation
import SwiftData

enum PlaceKind: String, Codable, CaseIterable {
    case home, work, favorite, pin
}

/// Lugar guardado: Casa, Trabajo, favoritos o pines personalizados.
@Model
final class SavedPlace {
    var name: String
    var note: String
    var iconName: String
    var kindRawValue: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    init(name: String, note: String = "", iconName: String = "star.fill",
         kind: PlaceKind, latitude: Double, longitude: Double) {
        self.name = name
        self.note = note
        self.iconName = iconName
        self.kindRawValue = kind.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = .now
    }
}
