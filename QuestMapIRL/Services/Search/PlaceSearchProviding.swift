import CoreLocation

/// Categorías de lugar que la app sabe buscar de verdad (cada una tiene su consulta real).
enum PlaceCategory: String, CaseIterable, Identifiable {
    case fuel, food, cafe, parking, supermarket, pharmacy, hospital, atm, hotel, transit, shop, police

    var id: String { rawValue }

    /// Categorías de la cuadrícula del panel, en este orden.
    static let grid: [PlaceCategory] = [
        .fuel, .food, .cafe, .parking, .supermarket, .pharmacy, .hospital, .atm, .hotel, .transit
    ]

    var title: String {
        switch self {
        case .fuel: return "Gasolineras"
        case .food: return "Restaurantes"
        case .cafe: return "Cafeterías"
        case .parking: return "Aparcamientos"
        case .supermarket: return "Supermercados"
        case .pharmacy: return "Farmacias"
        case .hospital: return "Hospitales"
        case .atm: return "Cajeros"
        case .hotel: return "Hoteles"
        case .transit: return "Transporte"
        case .shop: return "Compras"
        case .police: return "Policía"
        }
    }

    /// Singular, para nombrar un resultado sin nombre propio (p. ej. un cajero).
    var singular: String {
        switch self {
        case .fuel: return "Gasolinera"
        case .food: return "Restaurante"
        case .cafe: return "Cafetería"
        case .parking: return "Aparcamiento"
        case .supermarket: return "Supermercado"
        case .pharmacy: return "Farmacia"
        case .hospital: return "Hospital"
        case .atm: return "Cajero"
        case .hotel: return "Hotel"
        case .transit: return "Estación"
        case .shop: return "Centro comercial"
        case .police: return "Comisaría"
        }
    }

    var symbol: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .parking: return "parkingsign"
        case .supermarket: return "cart.fill"
        case .pharmacy: return "pills.fill"
        case .hospital: return "cross.fill"
        case .atm: return "eurosign.circle.fill"
        case .hotel: return "bed.double.fill"
        case .transit: return "tram.fill"
        case .shop: return "bag.fill"
        case .police: return "shield.lefthalf.filled"
        }
    }

    /// Filtros de OpenStreetMap (clave, valor) que definen la categoría. Se unen con "o".
    var osmFilters: [(key: String, value: String)] {
        switch self {
        case .fuel: return [("amenity", "fuel")]
        case .food: return [("amenity", "restaurant")]
        case .cafe: return [("amenity", "cafe")]
        case .parking: return [("amenity", "parking")]
        case .supermarket: return [("shop", "supermarket")]
        case .pharmacy: return [("amenity", "pharmacy")]
        case .hospital: return [("amenity", "hospital")]
        case .atm: return [("amenity", "atm")]
        case .hotel: return [("tourism", "hotel")]
        case .transit: return [("railway", "station"), ("public_transport", "station")]
        case .shop: return [("shop", "mall"), ("shop", "department_store")]
        case .police: return [("amenity", "police")]
        }
    }

    /// Etiqueta de OpenStreetMap para filtrar el geocodificador (solo la primera).
    var osmTag: String {
        let first = osmFilters[0]
        return "\(first.key):\(first.value)"
    }

    var poiKind: POIKind {
        switch self {
        case .fuel: return .fuel
        case .food, .cafe: return .food
        case .parking: return .parking
        case .hospital, .pharmacy: return .hospital
        case .police: return .police
        case .shop, .supermarket: return .shop
        case .atm, .hotel, .transit: return .poi
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

/// Búsqueda de lugares de una categoría alrededor de un punto.
protocol NearbySearchProviding {
    func nearby(_ category: PlaceCategory, around: CLLocationCoordinate2D, radiusMeters: Int) async throws -> [Place]
}
