import MapKit

extension MKPolyline {
    /// Vértices de la polilínea como coordenadas.
    var coordinates: [CLLocationCoordinate2D] {
        var buffer = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&buffer, range: NSRange(location: 0, length: pointCount))
        return buffer
    }
}

extension RouteOption {
    var steps: [RouteStepInfo] {
        route.steps.map { RouteStepInfo(instruction: $0.instructions, distanceMeters: $0.distance) }
    }
}
