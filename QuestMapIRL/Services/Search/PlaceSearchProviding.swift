import CoreLocation

enum PlaceCategory: String, CaseIterable, Identifiable {
    case fuel, food, parking, hospital, police, shop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fuel: return "Gasolinera"
        case .food: return "Restaurante"
        case .parking: return "Parking"
        case .hospital: return "Hospital"
        case .police: return "Policía"
        case .shop: return "Centro comercial"
        }
    }

    /// Etiqueta de OpenStreetMap para filtrar la búsqueda.
    var osmTag: String {
        switch self {
        case .fuel: return "amenity:fuel"
        case .food: return "amenity:restaurant"
        case .parking: return "amenity:parking"
        case .hospital: return "amenity:hospital"
        case .police: return "amenity:police"
        case .shop: return "shop:mall"
        }
    }

    var poiKind: POIKind {
        switch self {
        case .fuel: return .fuel
        case .food: return .food
        case .parking: return .parking
        case .hospital: return .hospital
        case .police: return .police
        case .shop: return .shop
        }
    }
}

enum SearchError: LocalizedError, Equatable {
    case offline
    case rateLimited
    case server

    var errorDescription: String? {
        switch self {
        case .offline: return "Sin conexión"
        case .rateLimited: return "Demasiadas búsquedas seguidas"
        case .server: return "No se pudo buscar"
        }
    }
}

/// Búsqueda de lugares independiente del renderizador de mapas.
protocol PlaceSearchProviding {
    func search(_ query: String, near: CLLocationCoordinate2D?, category: PlaceCategory?) async throws -> [Place]
}
