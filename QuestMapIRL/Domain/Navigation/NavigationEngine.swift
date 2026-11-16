import CoreLocation

/// Instrucción de una maniobra, desacoplada de MapKit para poder testearla.
struct RouteStepInfo: Equatable {
    /// Maniobra que ocurre AL INICIO de este paso.
    let instruction: String
    /// Distancia recorrida en este paso hasta la siguiente maniobra.
    let distanceMeters: Double
    var symbol: String = "arrow.up"
}

struct NavigationSnapshot: Equatable {
    /// Paso (tramo) en el que está el usuario ahora.
    var stepIndex: Int = 0
    /// Paso cuya maniobra es la PRÓXIMA (la que hay que anunciar): el siguiente al actual.
    var upcomingIndex: Int = 0
    var distanceToManeuver: Double = 0
    var remainingMeters: Double = 0
    var remainingSeconds: Double = 0
    var progress: Double = 0
    var distanceFromRoute: Double = 0
    var isOffRoute: Bool = false
    var hasArrived: Bool = false
}

/// Motor puro: proyecta la posición sobre la polilínea y calcula progreso,
/// próxima maniobra y desvío. No conoce SwiftUI ni MapKit.
struct NavigationEngine {
    let points: [CLLocationCoordinate2D]
    let steps: [RouteStepInfo]
    let totalMeters: Double
    let expectedSeconds: Double
    let offRouteThreshold: Double
    let arrivalThreshold: Double

    private let cumulative: [Double]   // distancia acumulada en cada vértice
    private let stepEnds: [Double]     // distancia acumulada al final de cada maniobra

    init(points: [CLLocationCoordinate2D],
         steps: [RouteStepInfo],
         expectedSeconds: Double,
         offRouteThreshold: Double = 60,
         arrivalThreshold: Double = 25) {
        self.points = points
        self.steps = steps
        self.expectedSeconds = expectedSeconds
        self.offRouteThreshold = offRouteThreshold
        self.arrivalThreshold = arrivalThreshold

        var cum: [Double] = [0]
        if points.count > 1 {
            for i in 1..<points.count {
                cum.append(cum[i - 1] + Self.distance(points[i - 1], points[i]))
            }
        }
        cumulative = cum
        totalMeters = cum.last ?? 0

        var acc = 0.0
        stepEnds = steps.map { step in
            acc += step.distanceMeters
            return acc
        }
    }

    func update(with location: CLLocationCoordinate2D) -> NavigationSnapshot {
        guard points.count > 1 else {
            return NavigationSnapshot(hasArrived: true)
        }
        let projection = project(location)
        let along = projection.along
        let remaining = max(0, totalMeters - along)
        let stepIndex = stepEnds.firstIndex { $0 > along } ?? max(steps.count - 1, 0)
        let maneuverEnd = stepIndex < stepEnds.count ? stepEnds[stepIndex] : totalMeters
        let ratio = totalMeters > 0 ? remaining / totalMeters : 0

        return NavigationSnapshot(
            stepIndex: stepIndex,
            upcomingIndex: min(stepIndex + 1, max(steps.count - 1, 0)),
            distanceToManeuver: max(0, maneuverEnd - along),
            remainingMeters: remaining,
            remainingSeconds: expectedSeconds * ratio,
            progress: totalMeters > 0 ? min(1, along / totalMeters) : 1,
            distanceFromRoute: projection.offset,
            isOffRoute: projection.offset > offRouteThreshold,
            hasArrived: remaining <= arrivalThreshold
        )
    }

    // MARK: - Geometría

    /// Devuelve la distancia recorrida a lo largo de la ruta y la distancia perpendicular a ella.
    private func project(_ p: CLLocationCoordinate2D) -> (along: Double, offset: Double) {
        var best: (along: Double, offset: Double) = (0, .greatestFiniteMagnitude)
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            // Aproximación plana local: suficiente para tramos cortos.
            let cosLat = cos(a.latitude * .pi / 180)
            let bx = (b.longitude - a.longitude) * 111_320 * cosLat
            let by = (b.latitude - a.latitude) * 110_540
            let px = (p.longitude - a.longitude) * 111_320 * cosLat
            let py = (p.latitude - a.latitude) * 110_540
            let len2 = bx * bx + by * by
            let t = len2 > 0 ? min(1, max(0, (px * bx + py * by) / len2)) : 0
            let dx = px - t * bx
            let dy = py - t * by
            let offset = (dx * dx + dy * dy).squareRoot()
            if offset < best.offset {
                let segment = cumulative[i + 1] - cumulative[i]
                best = (cumulative[i] + t * segment, offset)
            }
        }
        return best
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
