import Foundation
import CoreLocation

/// Lugares cercanos por categoría usando la API Overpass sobre datos de OpenStreetMap.
/// La instancia pública es de uso moderado y sin garantías de servicio: para publicar con muchos
/// usuarios hay que alojar una instancia propia o contratar un proveedor.
struct OverpassNearbyService: NearbySearchProviding {
    var endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    var session: URLSession = .shared
    var maxResults = 40

    func nearby(_ category: PlaceCategory, around: CLLocationCoordinate2D, radiusMeters: Int) async throws -> [Place] {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw SearchError.server }
        components.queryItems = [URLQueryItem(name: "data", value: Self.query(category, around: around, radiusMeters: radiusMeters))]
        guard let url = components.url else { throw SearchError.server }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("QuestMapIRL/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 || http.statusCode == 504 { throw SearchError.rateLimited }
                if !(200..<300).contains(http.statusCode) { throw SearchError.server }
            }
            let places = try Self.parse(data, category: category)
            return Self.sortedByDistance(places, from: around).prefix(maxResults).map { $0 }
        } catch let error as SearchError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw SearchError.offline
        } catch {
            throw SearchError.server
        }
    }

    // MARK: - Consulta y análisis (puros, con tests)

    static func query(_ category: PlaceCategory, around: CLLocationCoordinate2D, radiusMeters: Int) -> String {
        let lat = String(format: "%.5f", around.latitude)
        let lon = String(format: "%.5f", around.longitude)
        let clauses = category.osmFilters
            .map { "nwr[\"\($0.key)\"=\"\($0.value)\"](around:\(radiusMeters),\(lat),\(lon));" }
            .joined()
        return "[out:json][timeout:15];(\(clauses));out center 120;"
    }

    static func parse(_ data: Data, category: PlaceCategory) throws -> [Place] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { throw SearchError.server }
        var seen = Set<String>()
        var places: [Place] = []
        for element in elements {
            guard let type = element["type"] as? String, let osmID = element["id"] as? Int else { continue }
            let coordinate: CLLocationCoordinate2D
            if let lat = element["lat"] as? Double, let lon = element["lon"] as? Double {
                coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if let center = element["center"] as? [String: Any],
                      let lat = center["lat"] as? Double, let lon = center["lon"] as? Double {
                coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else { continue }

            let tags = element["tags"] as? [String: String] ?? [:]
            let name = tags["name"] ?? tags["brand"] ?? tags["operator"] ?? category.singular
            // Evita duplicados exactos (mismo nombre en el mismo punto).
            let key = "\(name)|\(String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude))"
            guard seen.insert(key).inserted else { continue }

            var streetParts: [String] = []
            if let street = tags["addr:street"] { streetParts.append(street) }
            if let number = tags["addr:housenumber"] { streetParts.append(number) }
            var subtitleParts: [String] = []
            if !streetParts.isEmpty { subtitleParts.append(streetParts.joined(separator: " ")) }
            if let city = tags["addr:city"] { subtitleParts.append(city) }
            let subtitle = subtitleParts.joined(separator: ", ")
            places.append(Place(id: "osm-\(type)-\(osmID)", name: name,
                                subtitle: subtitle.isEmpty ? category.singular : subtitle,
                                latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        return places
    }

    static func sortedByDistance(_ places: [Place], from origin: CLLocationCoordinate2D) -> [Place] {
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return places.sorted {
            here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < here.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }
}
