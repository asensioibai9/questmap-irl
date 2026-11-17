import UIKit
import MapLibre
import CoreLocation

/// Familia de iconos PROPIA del estilo «Ciudad nocturna» (siluetas con contorno oscuro y un color de
/// acento por categoría). Los PNG están en el catálogo de recursos (`gta-poi-*`), generados por
/// `tools/make_poi_icons.py`. Se registran en el estilo con los mismos nombres `poi-*` que usa el JSON.
enum GameIcons {
    /// Nombre usado en el estilo -> recurso del catálogo (sin el prefijo `gta-poi-`).
    static let styleNameToAsset: [String: String] = [
        "poi-fuel": "fuel", "poi-parking": "parking", "poi-health": "hospital", "poi-police": "police",
        "poi-food": "food", "poi-cafe": "cafe", "poi-bar": "bar", "poi-grocery": "shop", "poi-shop": "shop",
        "poi-culture": "bank", "poi-bank": "bank", "poi-lodging": "lodging", "poi-transit": "transit",
        "poi-bike": "bike", "poi-bus-stop": "bus-stop", "poi-traffic-signal": "signal",
        "poi-destination": "destination", "poi-home": "home", "poi-work": "work",
        "selection-arrows": "selection-arrows",
    ]

    static func assetName(for asset: String) -> String { "gta-poi-\(asset)" }

    /// Imagen lista para el mapa: los PNG están pensados a @3x.
    static func image(asset: String) -> UIImage? {
        guard let cg = UIImage(named: assetName(for: asset))?.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: 3, orientation: .up)
    }

    static func register(in style: MLNStyle) {
        for (styleName, asset) in styleNameToAsset {
            if let image = image(asset: asset) { style.setImage(image, forName: styleName) }
        }
    }

    /// Icono de Casa/Trabajo en el mapa para un lugar guardado.
    static func savedIconName(for kind: PlaceKind) -> String? {
        switch kind {
        case .home: return "poi-home"
        case .work: return "poi-work"
        default: return nil
        }
    }
}

/// Qué hay bajo el dedo cuando se toca el mapa.
struct MapTappedFeature: Equatable {
    var name: String?
    /// Clase del punto de interés (esquema OpenMapTiles) o nombre de icono guardado.
    var kind: String?
    var isSavedPlace = false
}

struct MapTap {
    let coordinate: CLLocationCoordinate2D
    let feature: MapTappedFeature?
}

/// Nombre en español de la clase de un punto de interés (sin tocar los nombres originales de los lugares).
enum PoiClassTitles {
    static func title(for poiClass: String) -> String {
        switch poiClass {
        case "fuel": return "Gasolinera"
        case "restaurant": return "Restaurante"
        case "fast_food": return "Comida rápida"
        case "cafe": return "Cafetería"
        case "bakery": return "Panadería"
        case "ice_cream": return "Heladería"
        case "bar", "pub", "beer": return "Bar"
        case "parking": return "Aparcamiento"
        case "hospital": return "Hospital"
        case "pharmacy": return "Farmacia"
        case "doctors", "dentist": return "Salud"
        case "veterinary": return "Veterinario"
        case "bank": return "Banco"
        case "atm": return "Cajero"
        case "lodging": return "Alojamiento"
        case "railway": return "Estación"
        case "bus": return "Estación de autobuses"
        case "grocery": return "Supermercado"
        case "shop", "clothing_store", "butcher", "alcohol_shop", "laundry", "hairdresser": return "Tienda"
        case "police": return "Policía"
        case "fire_station": return "Bomberos"
        case "museum": return "Museo"
        case "library": return "Biblioteca"
        case "theatre", "cinema": return "Ocio"
        case "attraction", "monument", "castle", "art_gallery": return "Lugar de interés"
        default: return "Lugar"
        }
    }

    /// Lugar listo para previsualizar a partir de lo tocado. El nombre original se conserva tal cual.
    static func place(from tap: MapTap) -> Place {
        let c = tap.coordinate
        let id = String(format: "tap-%.5f,%.5f", c.latitude, c.longitude)
        guard let feature = tap.feature else {
            return Place(id: id, name: "Punto en el mapa", subtitle: "", latitude: c.latitude, longitude: c.longitude)
        }
        if feature.isSavedPlace {
            let title = feature.kind == "poi-work" ? "Trabajo" : "Casa"
            return Place(id: id, name: title, subtitle: "Lugar guardado", latitude: c.latitude, longitude: c.longitude)
        }
        let category = feature.kind.map(title(for:)) ?? "Lugar"
        let name = (feature.name?.isEmpty == false) ? feature.name! : category
        return Place(id: id, name: name, subtitle: (feature.name?.isEmpty == false) ? category : "Sin nombre en el mapa",
                     latitude: c.latitude, longitude: c.longitude)
    }
}
