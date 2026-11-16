import Foundation
import CoreLocation

/// Búsqueda con Photon (geocodificador sobre datos de OpenStreetMap, pensado para autocompletar).
/// Instancia pública sin clave: ver el aviso de `ServiceEndpoints`.
/// Nota: Photon no ofrece resultados en español (`lang` solo admite default, en, de, fr), así que se
/// usan los nombres locales que devuelve por defecto.
struct PhotonSearchService: PlaceSearchProviding {
    var endpoints = ServiceEndpoints.default
    var client = ServiceClient(service: "photon")

    func search(_ query: String, near: CLLocationCoordinate2D?, category: PlaceCategory?) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        guard var components = URLComponents(url: endpoints.geocoder, resolvingAgainstBaseURL: false) else {
            throw SearchError.configuration
        }
        var items = [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "limit", value: "12")]
        if let near {
            items.append(URLQueryItem(name: "lat", value: String(format: "%.5f", near.latitude)))
            items.append(URLQueryItem(name: "lon", value: String(format: "%.5f", near.longitude)))
        }
        components.queryItems = items
        guard let url = components.url else { throw SearchError.configuration }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("QuestMapIRL/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let data = try await client.data(for: request, operation: "search")
        return try Self.parse(data)
    }

    // MARK: - Decodificación (separada para poder probarla sin red)

    static func parse(_ data: Data) throws -> [Place] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response: PhotonResponse
        do { response = try decoder.decode(PhotonResponse.self, from: data) }
        catch { throw SearchError.decoding }

        var seenIDs = Set<String>()
        var seenLabels = Set<String>()
        var places: [Place] = []

        for feature in response.features {
            guard let coords = feature.geometry?.coordinates, coords.count >= 2 else { continue }
            let p = feature.properties
            let streetLine = [p.street, p.housenumber].compactMap { $0 }.joined(separator: " ")
            let title = p.name ?? (streetLine.isEmpty ? (p.city ?? "Lugar") : streetLine)

            var parts: [String] = []
            if p.name != nil, !streetLine.isEmpty { parts.append(streetLine) }
            if let district = p.district ?? p.locality { parts.append(district) }
            if let city = p.city { parts.append(city) }
            if parts.isEmpty, let state = p.state { parts.append(state) }
            let subtitle = parts.filter { $0 != title }.joined(separator: ", ")

            let id = (p.osmType != nil && p.osmId != nil)
                ? "\(p.osmType!)\(p.osmId!)"
                : String(format: "%.5f,%.5f", coords[1], coords[0])
            let label = (title + "|" + subtitle).lowercased()
            guard seenIDs.insert(id).inserted, seenLabels.insert(label).inserted else { continue }

            places.append(Place(id: id, name: title, subtitle: subtitle, latitude: coords[1], longitude: coords[0]))
        }
        return places
    }
}

private struct PhotonResponse: Decodable {
    let features: [PhotonFeature]
}

private struct PhotonFeature: Decodable {
    let geometry: PhotonGeometry?
    let properties: PhotonProperties
}

private struct PhotonGeometry: Decodable {
    let coordinates: [Double]
}

private struct PhotonProperties: Decodable {
    let name: String?
    let street: String?
    let housenumber: String?
    let city: String?
    let district: String?
    let locality: String?
    let state: String?
    let osmType: String?
    let osmId: Int64?
}
