import CoreLocation
import Observation
import SwiftUI

/// Estado de una navegación en curso. Recibe ubicaciones desde la vista
/// y delega la geometría en NavigationEngine (dominio puro).
@MainActor
@Observable
final class ActiveNavigationViewModel {
    private(set) var route: RouteOption
    private(set) var snapshot = NavigationSnapshot()
    private(set) var isRecalculating = false
    private(set) var speedKmh: Double = 0
    private(set) var visitedKeys: Set<String> = []
    var finished = false

    let destinationName: String
    let destination: CLLocationCoordinate2D
    let mode: RouteMode
    let startedAt = Date()

    private var engine: NavigationEngine
    private var offRouteCount = 0
    private var announcedForStep: (index: Int, band: Int)?
    private var lastLocation: CLLocation?
    private var traveledMeters: Double = 0

    private let routeService: RouteServiceProtocol
    private let speech: SpeechService

    init(route: RouteOption, destinationName: String, destination: CLLocationCoordinate2D,
         mode: RouteMode, routeService: RouteServiceProtocol, speech: SpeechService) {
        self.route = route
        self.destinationName = destinationName
        self.destination = destination
        self.mode = mode
        self.routeService = routeService
        self.speech = speech
        self.engine = Self.makeEngine(route)
    }

    var currentInstruction: String {
        let steps = route.steps
        guard snapshot.stepIndex < steps.count else { return "Has llegado" }
        let text = steps[snapshot.stepIndex].instruction
        return text.isEmpty ? "Continúa por la ruta" : text
    }

    var eta: Date { Date().addingTimeInterval(snapshot.remainingSeconds) }

    func start() {
        speech.announce("Empezamos la ruta hacia \(destinationName). \(currentInstruction)")
    }

    func update(with location: CLLocation) {
        if let last = lastLocation {
            traveledMeters += location.distance(from: last)
        }
        lastLocation = location
        speedKmh = max(0, location.speed) * 3.6
        visitedKeys.insert(FogGrid.key(for: location.coordinate))

        snapshot = engine.update(with: location.coordinate)
        announceIfNeeded()

        if snapshot.hasArrived {
            speech.announce("Has llegado a tu destino.")
            finished = true
            return
        }

        offRouteCount = snapshot.isOffRoute ? offRouteCount + 1 : 0
        if offRouteCount >= 3, !isRecalculating {
            Task { await recalculate(from: location.coordinate) }
        }
    }

    func stop() {
        speech.stop()
        finished = true
    }

    func summary() -> TripSummary {
        TripSummary(
            startedAt: startedAt,
            distanceMeters: traveledMeters,
            durationSeconds: Date().timeIntervalSince(startedAt),
            destinationName: destinationName,
            destinationKey: FogGrid.key(for: destination),
            modeRawValue: mode.rawValue,
            visitedKeys: visitedKeys.union(FogGrid.keys(along: route.route.polyline.coordinates))
        )
    }

    // MARK: - Privado

    private func announceIfNeeded() {
        let distance = snapshot.distanceToManeuver
        let band: Int
        switch distance {
        case ..<40: band = 0
        case ..<180: band = 1
        case ..<550: band = 2
        default: return
        }
        if let last = announcedForStep, last.index == snapshot.stepIndex, last.band <= band { return }
        announcedForStep = (snapshot.stepIndex, band)
        let prefix = band == 0 ? "" : "En \(Int(distance.rounded(toNearest: 50))) metros, "
        speech.announce(prefix + currentInstruction.lowercasedFirst)
    }

    private func recalculate(from origin: CLLocationCoordinate2D) async {
        isRecalculating = true
        defer { isRecalculating = false }
        speech.announce("Recalculando la ruta.")
        if let newRoute = try? await routeService.routes(from: origin, to: destination, mode: mode).first {
            route = newRoute
            engine = Self.makeEngine(newRoute)
            announcedForStep = nil
            offRouteCount = 0
        }
    }

    private static func makeEngine(_ option: RouteOption) -> NavigationEngine {
        NavigationEngine(points: option.route.polyline.coordinates,
                         steps: option.steps,
                         expectedSeconds: option.route.expectedTravelTime)
    }
}

private extension Double {
    func rounded(toNearest step: Double) -> Double { (self / step).rounded() * step }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
