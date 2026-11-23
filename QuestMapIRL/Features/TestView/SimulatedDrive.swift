import AVFoundation
import CoreLocation
import Observation
import SwiftUI

// MARK: - Datos simulados (Vista de pruebas)
//
// Todo lo de este archivo es SIMULADO y está aislado de lo real:
// - No toca el servicio de ubicación de la app (el GPS real sigue igual) ni el centro de navegación (`NavigationHub`).
// - No guarda viajes, no consulta servicios de rutas ni de límites, y su voz está muda y sin sesión de audio.
// - Los nombres de calles y el recorrido son inventados y lo dicen; el punto de partida es fijo (no tu ubicación).

/// Recorrido de demostración en una zona fija. Calles ficticias, marcadas como simuladas.
enum SimulatedRouteFactory {
    /// Origen fijo de la demostración (no es tu ubicación).
    static let origin = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)

    static func demoRoute(longNames: Bool) -> Route {
        let a = origin
        let b = offset(a, north: 600, east: 0)
        let c = offset(b, north: 0, east: 450)
        let d = offset(c, north: 350, east: 0)
        let street1 = longNames ? "Avenida Simulada del Ingeniero de Pruebas y de los Textos Muy Largos" : "Calle Simulada"
        let street2 = longNames ? "Paseo Ficticio de la Comprobación de Paneles con Nombre Extenso" : "Avenida de Prueba"
        let street3 = longNames ? "Ronda Imaginaria de las Etiquetas que No Deben Cortarse" : "Ronda Ficticia"
        return makeRoute(name: "Recorrido simulado", points: [a, b, c, d], steps: [
            ("Sal hacia el norte por \(street1)", "arrow.up", street1, ManeuverInfo(type: "depart")),
            ("Gira a la derecha en \(street2)", "arrow.turn.up.right", street2, ManeuverInfo(type: "turn", modifier: "right")),
            ("Gira a la izquierda en \(street3)", "arrow.turn.up.left", street3, ManeuverInfo(type: "turn", modifier: "left")),
            ("Has llegado a tu destino (simulado)", "flag.checkered", "", ManeuverInfo(type: "arrive")),
        ])
    }

    /// Ruta «recalculada» simulada: de donde está el punto simulado al destino, en dos tramos.
    static func detour(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> Route {
        let corner = CLLocationCoordinate2D(latitude: destination.latitude, longitude: origin.longitude)
        return makeRoute(name: "Recorrido simulado (recalculado)", points: [origin, corner, destination], steps: [
            ("Continúa por la ruta recalculada (simulada)", "arrow.up", "Calle Simulada", ManeuverInfo(type: "depart")),
            ("Gira hacia tu destino (simulado)", "arrow.turn.up.right", "Avenida de Prueba", ManeuverInfo(type: "turn", modifier: "right")),
            ("Has llegado a tu destino (simulado)", "flag.checkered", "", ManeuverInfo(type: "arrive")),
        ])
    }

    /// Une los vértices con puntos cada ~20 m; cada vértice es una maniobra.
    private static func makeRoute(name: String, points: [CLLocationCoordinate2D],
                                  steps: [(String, String, String, ManeuverInfo)]) -> Route {
        var coordinates: [CLLocationCoordinate2D] = []
        var legLengths: [Double] = []
        for (start, end) in zip(points, points.dropLast()) {
            let length = distance(start, end)
            legLengths.append(length)
            let count = max(1, Int(length / 20))
            for i in 0..<count {
                let t = Double(i) / Double(count)
                coordinates.append(CLLocationCoordinate2D(latitude: start.latitude + (end.latitude - start.latitude) * t,
                                                          longitude: start.longitude + (end.longitude - start.longitude) * t))
            }
        }
        coordinates.append(points.last!)
        let routeSteps = steps.enumerated().map { index, step in
            RouteStep(instruction: step.0, distanceMeters: index < legLengths.count ? legLengths[index] : 0,
                      symbol: step.1, streetName: step.2, maneuver: step.3)
        }
        let total = legLengths.reduce(0, +)
        return Route(name: name, coordinates: coordinates, distanceMeters: total, durationSeconds: total / 13.9, steps: routeSteps)
    }

    static func offset(_ c: CLLocationCoordinate2D, north: Double, east: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude + north / 111_320,
                               longitude: c.longitude + east / (111_320 * cos(c.latitude * .pi / 180)))
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180, Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return HeadingMath.normalized(atan2(y, x) * 180 / .pi)
    }
}

/// Servicio de rutas SIMULADO: el recálculo de la vista de pruebas no consulta ningún servidor.
struct SimulatedRouteService: RouteServiceProtocol {
    func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, mode: RouteMode) async throws -> [Route] {
        [SimulatedRouteFactory.detour(from: origin, to: destination)]
    }
}

/// Ubicación SIMULADA para los indicadores de la vista de pruebas. No usa Core Location ni cambia la ubicación real.
@MainActor
@Observable
final class SimulatedLocation: LocationServiceProtocol {
    var authState: LocationAuthState = .authorizedWhenInUse
    var currentLocation: CLLocation?
    var smoothedLocation: CLLocation?
    var displayHeading: Double = 0
    var quality: GPSQuality = .excellent
    var status: LocationStatus = .available
    var accuracyMode: LocationAccuracyMode = .full
    var isSignalLost = false
    var diagnosticSummary = "Ubicación simulada (vista de pruebas)"

    func requestWhenInUseAuthorization() {}
    func start(mode: LocationMode) {}
    func setMode(_ mode: LocationMode) {}
    func stop() {}
    func refreshNow() {}
    func requestTemporaryFullAccuracy() {}
}

// MARK: - Voz muda (sin duplicar la voz real)

private final class SilentSynthesizer: SpeechSynthesizing {
    var isSpeaking: Bool { false }
    func speak(_ utterance: AVSpeechUtterance) {}
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool { true }
}

private struct NoAudioSession: AudioSessionControlling {
    func configure() throws {}
    func activate() throws {}
    func deactivate() {}
}

@MainActor
private final class SilentPromptPlayer: RecordedPromptPlaying {
    var isPlaying: Bool { false }
    func play(_ segments: [VoicePromptSegment], volume: Float, completion: @escaping @MainActor (Bool) -> Void) throws {}
    func stop() {}
}

extension NavigationVoice {
    /// Voz de la vista de pruebas: muda, sin sintetizador real ni sesión de audio. No suena nunca ni interrumpe la voz
    /// real, la música ni los ajustes guardados.
    static func silentForPreview() -> NavigationVoice {
        let voice = NavigationVoice(defaults: UserDefaults(suiteName: "questmap.vista-pruebas") ?? .standard,
                                    synthesizer: SilentSynthesizer(), session: NoAudioSession(), voices: { [] },
                                    observeSystemEvents: false, recordedPlayer: SilentPromptPlayer())
        voice.isMuted = true
        return voice
    }
}

// MARK: - Recorrido simulado

/// Mueve un punto simulado por la ruta y alimenta con él una navegación APARTE (no la del centro de navegación).
@MainActor
@Observable
final class SimulatedDrive {
    private(set) var navigation: ActiveNavigationViewModel
    private(set) var isPlaying = false
    private(set) var position: CLLocation?
    private(set) var heading: Double = 0
    /// Velocidad simulada (m/s) y multiplicador para que la demostración no dure lo que un viaje real.
    var speed: Double = 13.9
    var timeScale: Double = 3

    let location = SimulatedLocation()
    let voice: NavigationVoice
    @ObservationIgnored private var along: Double = 0
    @ObservationIgnored private var cumulative: [Double] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var longNames: Bool
    @ObservationIgnored var onPosition: ((CLLocation, Double) -> Void)?
    @ObservationIgnored var onRouteChanged: ((Route) -> Void)?

    init(longNames: Bool = false, showsSpeedSign: Bool = true) {
        self.longNames = longNames
        let voice = NavigationVoice.silentForPreview()
        self.voice = voice
        navigation = Self.makeNavigation(longNames: longNames, voice: voice, showsSpeedSign: showsSpeedSign)
        adopt(navigation.route)
    }

    private static func makeNavigation(longNames: Bool, voice: NavigationVoice, showsSpeedSign: Bool) -> ActiveNavigationViewModel {
        let route = SimulatedRouteFactory.demoRoute(longNames: longNames)
        // Sin servicio de límites: si la señal está activa, muestra el estado «sin dato», nunca una cifra inventada.
        return ActiveNavigationViewModel(route: route, destinationName: "Destino simulado",
                                         destination: route.coordinates.last!, mode: .driving,
                                         routeService: SimulatedRouteService(), speech: voice, useMetric: true,
                                         speedLimitService: nil, showsSpeedLimit: showsSpeedSign)
    }

    var route: Route { navigation.route }
    var arrived: Bool { navigation.hasArrived }

    /// Empieza de cero (nueva navegación simulada).
    func reset(longNames: Bool, showsSpeedSign: Bool) {
        pause()
        self.longNames = longNames
        navigation = Self.makeNavigation(longNames: longNames, voice: voice, showsSpeedSign: showsSpeedSign)
        adopt(navigation.route)
        begin()
    }

    func begin() {
        navigation.start()
        feed(at: along)
    }

    func play() {
        guard task == nil, !arrived else { return }
        isPlaying = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.advance(meters: self.speed * self.timeScale * 0.5)
                if self.arrived { self.pause(); return }
            }
        }
    }

    func pause() {
        task?.cancel()
        task = nil
        isPlaying = false
    }

    func advance(meters: Double) {
        syncRouteIfRecalculated()
        along = min(along + meters, cumulative.last ?? 0)
        feed(at: along)
    }

    /// Salta a 120 m de la próxima maniobra.
    func jumpToNextManeuver() {
        syncRouteIfRecalculated()
        var target = 0.0
        for step in route.steps {
            target += step.distanceMeters
            if target - 120 > along { break }
        }
        along = max(along, min(target - 120, cumulative.last ?? 0))
        feed(at: along)
    }

    /// Llegada: el punto llega al final y el motor confirma la llegada como en una ruta real.
    func arrive() {
        pause()
        syncRouteIfRecalculated()
        along = cumulative.last ?? 0
        feed(at: along)
    }

    /// Desvío simulado: lecturas a 150 m de la ruta hasta que el motor recalcula (con el servicio de rutas simulado).
    func forceRecalculation() {
        pause()
        guard let base = position else { return }
        let side = SimulatedRouteFactory.offset(base.coordinate, north: 0, east: -150)
        for index in 0..<3 {
            let fix = CLLocation(coordinate: SimulatedRouteFactory.offset(side, north: Double(index) * 5, east: 0), altitude: 0,
                                 horizontalAccuracy: 5, verticalAccuracy: 5, course: heading, speed: speed, timestamp: Date())
            publish(fix)
            navigation.update(with: fix)
        }
    }

    /// Si el motor ya cambió de ruta (recálculo simulado), el punto continúa por la nueva desde su inicio.
    func syncRouteIfRecalculated() {
        guard navigation.route.id != adoptedRouteID else { return }
        adopt(navigation.route)
    }

    @ObservationIgnored private var adoptedRouteID: UUID?

    private func adopt(_ route: Route) {
        along = 0
        adoptedRouteID = route.id
        cumulative = [0]
        for (a, b) in zip(route.coordinates, route.coordinates.dropFirst()) {
            cumulative.append(cumulative.last! + SimulatedRouteFactory.distance(a, b))
        }
        onRouteChanged?(route)
    }

    private func feed(at distance: Double) {
        let coordinates = route.coordinates
        guard coordinates.count >= 2 else { return }
        var index = 0
        while index < cumulative.count - 2, cumulative[index + 1] < distance { index += 1 }
        let a = coordinates[index], b = coordinates[index + 1]
        let span = max(0.001, cumulative[index + 1] - cumulative[index])
        let t = min(1, max(0, (distance - cumulative[index]) / span))
        let point = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                           longitude: a.longitude + (b.longitude - a.longitude) * t)
        heading = SimulatedRouteFactory.bearing(a, b)
        let fix = CLLocation(coordinate: point, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                             course: heading, speed: isPlaying ? speed : 0, timestamp: Date())
        publish(fix)
        navigation.update(with: fix)
    }

    private func publish(_ fix: CLLocation) {
        position = fix
        location.currentLocation = fix
        location.smoothedLocation = fix
        location.displayHeading = heading
        onPosition?(fix, heading)
    }
}

/// Proporciones de pantalla horizontal para la vista de pruebas (en puntos de diseño, no en píxeles).
struct CarScreenPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let size: CGSize

    static let all: [CarScreenPreset] = [
        CarScreenPreset(id: "5x3", title: "800 × 480 · 5:3", size: CGSize(width: 800, height: 480)),
        CarScreenPreset(id: "16x9", title: "640 × 360 · 16:9", size: CGSize(width: 640, height: 360)),
        CarScreenPreset(id: "8x3", title: "960 × 360 · 8:3 panorámica", size: CGSize(width: 960, height: 360)),
        CarScreenPreset(id: "4x3", title: "640 × 480 · 4:3", size: CGSize(width: 640, height: 480)),
        CarScreenPreset(id: "iphone", title: "852 × 393 · iPhone en horizontal", size: CGSize(width: 852, height: 393)),
    ]
}
