import MapKit

/// Búsqueda de lugares con MKLocalSearch (direcciones, comercios, ciudades, etc.).
struct PlaceSearchService {
    func search(_ query: String, near center: CLLocationCoordinate2D?) async throws -> [MKMapItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let center {
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 30_000,
                longitudinalMeters: 30_000
            )
        }
        return try await MKLocalSearch(request: request).start().mapItems
    }
}
