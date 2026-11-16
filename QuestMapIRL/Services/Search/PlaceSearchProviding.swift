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

    /// Qué puntos de los tiles vectoriales (esquema OpenMapTiles, capa `poi`) cuentan como esta categoría.
    var tileMatch: TileMatch {
        switch self {
        case .fuel: return TileMatch(classes: ["fuel"], subclasses: ["fuel"])           // excluye puntos de recarga
        case .food: return TileMatch(classes: ["restaurant"])
        case .cafe: return TileMatch(classes: ["cafe"])
        case .parking: return TileMatch(classes: ["parking"], subclasses: ["parking"])
        case .supermarket: return TileMatch(classes: ["grocery"], subclasses: ["supermarket"])
        case .pharmacy: return TileMatch(classes: ["pharmacy"])
        case .hospital: return TileMatch(classes: ["hospital"], subclasses: ["hospital"])
        case .atm: return TileMatch(classes: ["atm"])
        case .hotel: return TileMatch(classes: ["lodging"], subclasses: ["hotel", "motel"])
        case .transit: return TileMatch(classes: ["railway"])
        case .shop: return TileMatch(classes: ["shop", "grocery"], subclasses: ["mall", "department_store"])
        case .police: return TileMatch(classes: ["police"])
        }
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

/// Por qué falló una petición a un servicio externo. Cada caso tiene su propio mensaje: un
/// servidor lento o saturado NO se presenta como "sin conexión".
enum SearchError: LocalizedError, Equatable {
    /// El sistema informa de que no hay internet (o datos móviles denegados).
    case offline
    /// La conexión se cortó a mitad de la petición.
    case connectionLost
    /// El servicio no respondió a tiempo.
    case timedOut
    /// El servicio respondió con un error del servidor (5xx) o no se pudo contactar.
    case serviceUnavailable
    /// El servicio limita las peticiones (429).
    case rateLimited
    /// Petición rechazada por configuración o autenticación (400, 401, 403, 404, TLS…).
    case configuration
    /// La respuesta llegó pero no se pudo interpretar.
    case decoding
    /// Cualquier otro error no clasificado.
    case unexpected

    var errorDescription: String? { userMessage }

    var userMessage: String {
        switch self {
        case .offline: return "Sin conexión a internet. Comprueba tu conexión e inténtalo de nuevo."
        case .connectionLost: return "Se ha cortado la conexión durante la búsqueda."
        case .timedOut: return "El servicio de búsqueda tarda demasiado en responder."
        case .serviceUnavailable: return "El servicio de búsqueda no está disponible en este momento."
        case .rateLimited: return "Demasiadas búsquedas seguidas. Espera unos segundos."
        case .configuration: return "El servicio de búsqueda ha rechazado la petición. Es un fallo de configuración, no de tu conexión."
        case .decoding: return "El servicio de búsqueda ha devuelto una respuesta que no se puede leer."
        case .unexpected: return "No se pudo completar la búsqueda."
        }
    }

    /// Nombre estable para diagnósticos y pruebas.
    var kind: String {
        switch self {
        case .offline: return "offline"
        case .connectionLost: return "connectionLost"
        case .timedOut: return "timedOut"
        case .serviceUnavailable: return "serviceUnavailable"
        case .rateLimited: return "rateLimited"
        case .configuration: return "configuration"
        case .decoding: return "decoding"
        case .unexpected: return "unexpected"
        }
    }

    /// ¿Merece la pena reintentar (a mano o automáticamente)?
    var isRetryable: Bool {
        switch self {
        case .connectionLost, .timedOut, .serviceUnavailable, .rateLimited, .offline: return true
        case .configuration, .decoding, .unexpected: return false
        }
    }

    /// Solo estos casos son realmente "un problema de conexión".
    var isConnectionProblem: Bool { self == .offline || self == .connectionLost }

    /// Clasifica un error de `URLSession`. Devuelve nil si es una cancelación normal.
    static func classify(_ error: URLError) -> SearchError? {
        switch error.code {
        case .cancelled:
            return nil
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return .offline
        case .networkConnectionLost:
            return .connectionLost
        case .timedOut:
            return .timedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .serviceUnavailable
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .appTransportSecurityRequiresSecureConnection, .badURL, .unsupportedURL:
            return .configuration
        case .cannotDecodeContentData, .cannotDecodeRawData, .cannotParseResponse, .badServerResponse, .zeroByteResource:
            return .decoding
        default:
            return .unexpected
        }
    }

    /// Clasifica un estado HTTP fuera de 200-299.
    static func classify(httpStatus status: Int) -> SearchError {
        switch status {
        case 429: return .rateLimited
        case 400, 401, 403, 404, 405, 406, 410, 414: return .configuration
        case 408: return .timedOut
        case 500..<600: return .serviceUnavailable
        default: return .unexpected
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

/// Filtro por clase (y opcionalmente subclase) de la capa `poi` de los tiles.
struct TileMatch: Equatable {
    let classes: Set<String>
    let subclasses: Set<String>?

    init(classes: Set<String>, subclasses: Set<String>? = nil) {
        self.classes = classes
        self.subclasses = subclasses
    }

    func matches(poiClass: String, subclass: String?) -> Bool {
        guard classes.contains(poiClass) else { return false }
        guard let subclasses else { return true }
        return subclass.map(subclasses.contains) ?? false
    }
}
