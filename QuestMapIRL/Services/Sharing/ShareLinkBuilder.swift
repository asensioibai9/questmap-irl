import Foundation
import CoreLocation

/// Enlaces de Apple Maps para compartir un lugar o una ruta.
enum ShareLinkBuilder {
    static func placeURL(name: String, coordinate: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: name)
        ]
        return components?.url
    }

    static func routeURL(from origin: CLLocationCoordinate2D,
                         to destination: CLLocationCoordinate2D,
                         mode: RouteMode) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "saddr", value: "\(origin.latitude),\(origin.longitude)"),
            URLQueryItem(name: "daddr", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "dirflg", value: mode == .walking ? "w" : "d")
        ]
        return components?.url
    }
}
