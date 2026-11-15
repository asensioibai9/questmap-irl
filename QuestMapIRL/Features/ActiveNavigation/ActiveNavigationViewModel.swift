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
    private(set) var recalculationFailed = false
    private(set) var speedKmh: Double = 0
    private(set) var visitedKeys: Set<String> = []
    var finished = false

    let destinationName: String
    let destination: CLLocationCoordinate2D
    let mode: RouteMode
    let startedAt = Date()
    let useMetric: Bool

    private var engine: NavigationEngine
    private var offRouteCount = 0
    private var announcedForStep: (index: Int, band: Int)?
    private var lastLocation: CLLocation?
    private var traveledMeters: Double = 0
    private var lastRecalculation = Date.distantPast

    private let routeService: RouteServiceProtocol
    private let speech: SpeechService

    init(route: RouteOption, destinationName: String, destination: CLLocationCoordinate2D,
         mode: RouteMode, routeService: RouteServiceProtocol, speech: SpeechService, useMetric: Bool) {
        self.route = route
        self.destinationName = destinationName
        self.destination = destination
        self.mode = mode
        self.routeService = routeService
        self.speech = speech
        self.useMetric = useMetric
        self.engine = Self.makeEngine(route)
    }

    var currentInstruction: String {
        let steps = route.steps
        guard snapshot.stepIndex < steps.count else { return "Has llegado a tu destino" }
        let text = steps[snapshot.stepIndex].instruction
        return text.isEmpty ? "Continúa por la ruta" : text
    }

    /// Instrucción del paso siguiente (para el HUD "después").
    var nextInstruction: String? {
        let steps = route.steps
        let next = snapshot.stepIndex + 1
        guard next < steps.count, !steps[next].instruction.isEmpty else { return nil }
        return steps[next].instruction
    }

    var maneuverSymbol: String { ManeuverFormatter.symbol(for: currentInstruction) }
    var eta: Date { Date().addingTimeInterval(snapshot.remainingSeconds) }

    func start() {
        speech.announce("Empezamos la ruta hacia \(destinationName). " +
                        ManeuverFormatter.spoken(instruction: currentInstruction,
                                                 distance: snapshot.distanceToManeuver, metric: useMetric))
    }

    func update(with location: CLLocation) {
        if let last = lastLocation {
            let delta = location.distance(from: last)
            if delta < 200 { traveledMeters += delta }   // ignora teletransportes por mala señal
        }
        lastLocation = location
        speedKmh = max(0, location.speed) * 3.6
        visitedKeys.insert(FogGrid.key(for: location.coordinate))

        snapshot = engine.update(with: location.coordinate)
        announceIfNeeded()

        if snapshot.hasArrived {
            speech.announce("Has llegado a tu destino.", interrupt: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            finished = true
            return
        }

        offRouteCount = snapshot.isOffRoute ? offRouteCount + 1 : 0
        if offRouteCount >= 3, !isRecalculating, Date().timeIntervalSince(lastRecalculation) > 8 {
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

    /// Anuncia a ~500 m, ~150 m y en el punto; una vez por banda y paso.
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
        speech.announce(ManeuverFormatter.spoken(instruction: currentInstruction, distance: distance, metric: useMetric))
    }

    private func recalculate(from origin: CLLocationCoordinate2D) async {
        isRecalculating = true
        recalculationFailed = false
        lastRecalculation = Date()
        defer { isRecalculating = false }
        speech.announce("Recalculando la ruta.", interrupt: true)
        do {
            if let newRoute = try await routeService.routes(from: origin, to: destination, mode: mode).first {
                route = newRoute
                engine = Self.makeEngine(newRoute)
                announcedForStep = nil
                offRouteCount = 0
            }
        } catch {
            recalculationFailed = true
            speech.announce("No he podido recalcular. Vuelve a la ruta marcada.")
        }
    }

    private static func makeEngine(_ option: RouteOption) -> NavigationEngine {
        NavigationEngine(points: option.route.polyline.coordinates,
                         steps: option.steps,
                         expectedSeconds: option.route.expectedTravelTime)
    }
}
