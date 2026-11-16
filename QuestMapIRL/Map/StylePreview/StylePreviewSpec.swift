import CoreLocation
import UIKit

/// Zona, encuadre y tamaño IGUALES para todos los estilos, para poder compararlos. La zona es pública (Madrid Río: río
/// Manzanares, autovía M-30 con enlaces y túneles, parque, ferrocarril, manzanas de edificios y avenidas). Nunca se usan
/// ubicaciones del usuario (Casa, Trabajo…) y nada de esto se sube a ningún servidor distinto del proveedor de teselas.
enum StylePreviewSpec {
    /// Sube este número si cambia la composición (zona, zoom, ruta de ejemplo…) para invalidar las cachés.
    static let version = 1

    static let center = CLLocationCoordinate2D(latitude: 40.3978, longitude: -3.7170)
    static let zoom = 15.2
    static let bearing = 0.0
    static let pitch = 0.0
    /// Tamaño en puntos (relación 8:5). La imagen final usa la escala de la pantalla.
    static let size = CGSize(width: 640, height: 400)

    static let placeCaption = "Madrid Río · ruta de ejemplo"

    /// Ruta REAL de ejemplo por calles de la zona (calculada una vez con el servicio de rutas y simplificada). Sirve para
    /// enseñar cómo dibuja cada estilo la ruta, el destino y el marcador del usuario. No es un recorrido de nadie.
    static let route: [CLLocationCoordinate2D] = [
        (40.39652, -3.72107), (40.39655, -3.72057), (40.39664, -3.72029), (40.39681, -3.71992), (40.39687, -3.71939),
        (40.39615, -3.71877), (40.39639, -3.71834), (40.39659, -3.71798), (40.39688, -3.71745), (40.39702, -3.71719),
        (40.39719, -3.71688), (40.39746, -3.71642), (40.39750, -3.71598), (40.39757, -3.71568), (40.39771, -3.71542),
        (40.39795, -3.71517), (40.39805, -3.71477), (40.39796, -3.71434), (40.39776, -3.71382), (40.39768, -3.71347),
        (40.39762, -3.71312), (40.39756, -3.71281),
    ].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }

    static var destination: CLLocationCoordinate2D { route[route.count - 1] }

    /// Posición del marcador del usuario (sobre la ruta) y su rumbo según el tramo.
    static var user: (coordinate: CLLocationCoordinate2D, heading: Double) {
        let index = 6
        let a = route[index], b = route[index + 1]
        let dLon = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
        let dLat = b.latitude - a.latitude
        var degrees = atan2(dLon, dLat) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return (a, degrees)
    }
}
