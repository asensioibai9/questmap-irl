import Foundation

/// Grupos del panel «Capas del mapa».
enum MapLayerGroup: String, CaseIterable, Identifiable {
    case places, transit, bicycle, traffic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .places: return "Lugares"
        case .transit: return "Transporte público"
        case .bicycle: return "Bicicleta"
        case .traffic: return "Tráfico"
        }
    }
}

/// Disponibilidad REAL de una capa con las fuentes actuales.
enum MapLayerAvailability: Equatable {
    /// Datos incluidos en las teselas del mapa (OpenMapTiles vía OpenFreeMap).
    case vectorTiles
    /// Se descargan bajo demanda de otra fuente gratuita (solo con la capa activada).
    case onDemand(source: String)
    /// No hay fuente gratuita: no se puede activar.
    case unavailable(reason: String)

    var canEnable: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

/// Capas que se pueden activar o desactivar sobre el estilo elegido. El estilo (GTA, Fortnite…) se elige aparte.
enum MapLayerID: String, CaseIterable, Identifiable {
    case food, shops, fuel, health, parking, otherPlaces
    case transitStations, busStops, transitLines
    case cycleways, bikeParking, bikeRental
    case trafficSignals, liveTraffic

    var id: String { rawValue }

    var group: MapLayerGroup {
        switch self {
        case .food, .shops, .fuel, .health, .parking, .otherPlaces: return .places
        case .transitStations, .busStops, .transitLines: return .transit
        case .cycleways, .bikeParking, .bikeRental: return .bicycle
        case .trafficSignals, .liveTraffic: return .traffic
        }
    }

    var title: String {
        switch self {
        case .food: return "Restaurantes y cafeterías"
        case .shops: return "Tiendas y supermercados"
        case .fuel: return "Gasolineras"
        case .health: return "Hospitales y farmacias"
        case .parking: return "Aparcamientos"
        case .otherPlaces: return "Otros lugares"
        case .transitStations: return "Estaciones"
        case .busStops: return "Paradas de autobús"
        case .transitLines: return "Líneas de metro y tren"
        case .cycleways: return "Vías ciclistas"
        case .bikeParking: return "Aparcamientos de bicicletas"
        case .bikeRental: return "Alquiler de bicicletas"
        case .trafficSignals: return "Semáforos"
        case .liveTraffic: return "Tráfico en tiempo real"
        }
    }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .shops: return "bag.fill"
        case .fuel: return "fuelpump.fill"
        case .health: return "cross.case.fill"
        case .parking: return "parkingsign"
        case .otherPlaces: return "building.columns.fill"
        case .transitStations: return "tram.fill"
        case .busStops: return "bus"
        case .transitLines: return "point.topleft.down.to.point.bottomright.curvepath"
        case .cycleways: return "road.lanes"
        case .bikeParking: return "bicycle"
        case .bikeRental: return "bicycle.circle"
        case .trafficSignals: return "light.beacon.max"
        case .liveTraffic: return "car.2.fill"
        }
    }

    /// Descripción breve solo donde hace falta aclarar qué se ve (y qué NO).
    var detail: String? {
        switch self {
        case .otherPlaces: return "Museos, bancos, alojamiento, policía…"
        case .transitStations: return "Metro, tren y estaciones de autobús. Sin horarios en directo."
        case .busStops: return "Ubicación de las paradas. Sin horarios en directo."
        case .transitLines: return "Recorrido de las vías; bajo tierra se ven más tenues. Las líneas de autobús no están en los datos."
        case .cycleways: return "Carriles bici segregados y caminos para bicicletas."
        case .bikeRental: return "Estaciones de bici compartida y alquiler. Sin bicis ni anclajes libres en directo."
        case .parking: return "Sin plazas libres ni precios en directo."
        case .trafficSignals, .liveTraffic: return availability.unavailableReason
        default: return nil
        }
    }

    var availability: MapLayerAvailability {
        switch self {
        case .trafficSignals:
            return .unavailable(reason: "Los semáforos no vienen en los datos del mapa. La fuente gratuita (API pública «Overpass» de OpenStreetMap) no admite el uso automático desde apps y ahora mismo está saturada. Alternativa: un servidor Overpass propio o teselas propias con semáforos.")
        case .liveTraffic:
            return .unavailable(reason: "No hay una fuente gratuita de tráfico en directo. Requiere un proveedor de pago (TomTom, HERE o Mapbox), que no está contratado.")
        default: return .vectorTiles
        }
    }

    /// Activada por defecto: lo que ya mostraba la app (lugares y estaciones). Lo nuevo empieza apagado.
    var defaultEnabled: Bool {
        switch self {
        case .food, .shops, .fuel, .health, .parking, .otherPlaces, .transitStations: return true
        default: return false
        }
    }

    /// Capas del estilo que controla (sus iconos y nombres van juntos en la misma capa).
    var styleLayerIDs: [String] {
        switch self {
        case .food: return ["poi-icon-food"]
        case .shops: return ["poi-icon-shops"]
        case .fuel: return ["poi-icon-fuel"]
        case .health: return ["poi-icon-health"]
        case .parking: return ["poi-icon-parking"]
        case .otherPlaces: return ["poi-icon-other"]
        case .transitStations: return ["poi-icon-transit"]
        case .busStops: return ["poi-icon-bus-stop"]
        case .transitLines: return ["layer-transit-lines"]
        case .cycleways: return ["layer-cycleways"]
        case .bikeParking: return ["poi-icon-bike-parking"]
        case .bikeRental: return ["poi-icon-bike-rental"]
        case .trafficSignals: return ["layer-traffic-signals"]
        case .liveTraffic: return []
        }
    }
}

extension MapLayerAvailability {
    var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// Qué capas están activadas. Se guarda como «id=1,id=0» para que una capa NUEVA en una versión futura tome su valor
/// por defecto en lugar de aparecer apagada para quien ya tenía preferencias guardadas.
struct MapLayerPreferences: Equatable {
    private(set) var enabled: Set<MapLayerID>

    static let defaults = MapLayerPreferences(enabled: Set(MapLayerID.allCases.filter(\.defaultEnabled)))
    static let defaultRaw = defaults.raw

    init(enabled: Set<MapLayerID>) {
        self.enabled = enabled.filter { $0.availability.canEnable }
    }

    init(raw: String) {
        var result = Set(MapLayerID.allCases.filter(\.defaultEnabled))
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=")
            guard parts.count == 2, let id = MapLayerID(rawValue: String(parts[0])) else { continue }
            if parts[1] == "1" { result.insert(id) } else { result.remove(id) }
        }
        self.init(enabled: result)
    }

    var raw: String {
        MapLayerID.allCases.map { "\($0.rawValue)=\(enabled.contains($0) ? 1 : 0)" }.joined(separator: ",")
    }

    func isEnabled(_ id: MapLayerID) -> Bool { enabled.contains(id) }

    /// Activa o desactiva. Una capa no disponible nunca queda activada.
    mutating func set(_ id: MapLayerID, _ on: Bool) {
        if on && id.availability.canEnable { enabled.insert(id) } else { enabled.remove(id) }
    }

    /// Visibilidad que debe tener cada capa del estilo.
    var styleLayerVisibility: [String: Bool] {
        var result: [String: Bool] = [:]
        for id in MapLayerID.allCases {
            for layer in id.styleLayerIDs { result[layer] = enabled.contains(id) }
        }
        return result
    }
}

extension UserSettings {
    var mapLayers: MapLayerPreferences {
        get { MapLayerPreferences(raw: mapLayersRaw) }
        set {
            let raw = newValue.raw
            if raw != mapLayersRaw { mapLayersRaw = raw }        // sin escrituras idénticas
        }
    }

    /// «Restablecer capas»: SOLO capas y nombres de lugares (no toca Casa, Trabajo, favoritos ni perfiles de voz).
    func resetMapLayers() {
        mapLayers = .defaults
        if !showPlaceNames { showPlaceNames = true }
    }
}
