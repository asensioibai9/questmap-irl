import Foundation
import SwiftData

/// Lugar abierto desde el buscador. Se guarda solo en el dispositivo y solo si el usuario
/// mantiene activado el historial de búsquedas.
@Model
final class RecentSearch {
    var placeID: String
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var date: Date

    init(place: Place) {
        self.placeID = place.id
        self.name = place.name
        self.subtitle = place.subtitle
        self.latitude = place.latitude
        self.longitude = place.longitude
        self.date = .now
    }

    var place: Place {
        Place(id: placeID, name: name, subtitle: subtitle, latitude: latitude, longitude: longitude)
    }
}
