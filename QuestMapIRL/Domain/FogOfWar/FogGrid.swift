import CoreLocation

/// Niebla de guerra: divide el mundo en celdas de ~200 m y marca las visitadas.
/// Las celdas se guardan solo en el dispositivo.
enum FogGrid {
    /// 500 celdas por grado ≈ 220 m en latitud.
    static let cellsPerDegree: Double = 500
    /// Distancia máxima entre muestras al interpolar, para no saltarse celdas.
    static let sampleSpacingMeters: Double = 50

    static func key(for coordinate: CLLocationCoordinate2D) -> String {
        key(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    static func key(latitude: Double, longitude: Double) -> String {
        let row = Int(floor(latitude * cellsPerDegree))
        let column = Int(floor(longitude * cellsPerDegree))
        return "\(row)_\(column)"
    }

    /// Celdas tocadas por una polilínea (interpolada cada ~50 m).
    static func keys(along points: [CLLocationCoordinate2D]) -> Set<String> {
        guard let first = points.first else { return [] }
        var result: Set<String> = [key(for: first)]
        guard points.count > 1 else { return result }

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let length = NavigationEngine.distance(a, b)
            let steps = max(1, Int(length / sampleSpacingMeters))
            for s in 0...steps {
                let t = Double(s) / Double(steps)
                let lat = a.latitude + (b.latitude - a.latitude) * t
                let lon = a.longitude + (b.longitude - a.longitude) * t
                result.insert(key(latitude: lat, longitude: lon))
            }
        }
        return result
    }
}
