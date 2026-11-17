import XCTest
import CoreLocation
@testable import QuestMapIRL

/// Movimiento visual de la flecha con recorridos reproducibles (sin GPS real ni ubicaciones simuladas en la app).
final class MarkerMotionTests: XCTestCase {
    private let origin = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let frame = 1.0 / 60

    /// Punto a `meters` hacia `bearing` grados desde `from`.
    private func offset(_ from: CLLocationCoordinate2D, meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let r = 6_371_000.0
        let b = bearing * .pi / 180
        let dLat = meters * cos(b) / r
        let dLon = meters * sin(b) / (r * cos(from.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: from.latitude + dLat * 180 / .pi, longitude: from.longitude + dLon * 180 / .pi)
    }

    private func distance(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Double {
        guard let a, let b else { return .infinity }
        return MarkerMotion.distance(a, b)
    }

    /// Simula fotogramas a 60 Hz desde `start` hasta `end`, devolviendo las posiciones dibujadas.
    @discardableResult
    private func run(_ motion: inout MarkerMotion, from start: Double, to end: Double) -> [CLLocationCoordinate2D] {
        var shown: [CLLocationCoordinate2D] = []
        var t = start
        while t < end - 1e-9 {
            t += frame
            motion.step(now: t)
            if let d = motion.displayed { shown.append(d) }
        }
        return shown
    }

    // MARK: Ángulos

    func testShortestAngleCrossesNorthWithoutAFullTurn() {
        XCTAssertEqual(Angle.shortestDelta(from: 359, to: 1), 2, accuracy: 1e-9)
        XCTAssertEqual(Angle.shortestDelta(from: 1, to: 359), -2, accuracy: 1e-9)
        XCTAssertEqual(Angle.shortestDelta(from: 10, to: 190), 180, accuracy: 1e-9)
        XCTAssertEqual(Angle.normalized(-90), 270, accuracy: 1e-9)
        XCTAssertEqual(Angle.normalized(725), 5, accuracy: 1e-9)
    }

    func testRotationFrom359To1PassesThroughNorth() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 10, accuracy: 5, now: 0, reduceMotion: false)
        motion.receive(heading: 359, reduceMotion: false)
        motion.step(now: 0)
        XCTAssertEqual(motion.displayedHeading, 359, accuracy: 1e-9)
        motion.receive(heading: 1, reduceMotion: false)
        var t = 0.0
        for _ in 0..<60 {
            t += frame
            motion.step(now: t)
            let h = motion.displayedHeading
            XCTAssertTrue(h >= 358.9 || h <= 1.1, "nunca debe pasar por el sur: \(h)")
        }
        XCTAssertEqual(Angle.shortestDelta(from: motion.displayedHeading, to: 1), 0, accuracy: 0.3)
    }

    func testNinetyDegreeTurnIsFollowedQuicklyWithoutOvershoot() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 10, accuracy: 5, now: 0, reduceMotion: false)
        motion.receive(heading: 0, reduceMotion: false)
        motion.step(now: 0)
        motion.receive(heading: 90, reduceMotion: false)
        var t = 0.0
        var previous = 0.0
        while t < 0.5 {
            t += frame
            motion.step(now: t)
            XCTAssertGreaterThanOrEqual(motion.displayedHeading, previous - 1e-9, "gira en un solo sentido")
            XCTAssertLessThanOrEqual(motion.displayedHeading, 90 + 1e-9, "no se pasa del objetivo")
            previous = motion.displayedHeading
        }
        XCTAssertGreaterThan(motion.displayedHeading, 85, "en marcha responde en menos de medio segundo")
    }

    func testCompassJitterIsIgnoredWhenStill() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 0, accuracy: 5, now: 0, reduceMotion: false)
        motion.receive(heading: 100, reduceMotion: false)
        motion.step(now: 0)
        for (i, wobble) in [102.0, 98.5, 101.5, 99.0, 103.0].enumerated() {
            motion.receive(heading: wobble, reduceMotion: false)
            motion.step(now: Double(i + 1) * 0.1)
        }
        XCTAssertEqual(motion.displayedHeading, 100, accuracy: 1e-9)
        XCTAssertFalse(motion.isAnimating, "sin vibración, sin animación")
        motion.receive(heading: 150, reduceMotion: false)   // un giro real sí cuenta
        XCTAssertTrue(motion.isRotating)
    }

    // MARK: Posición

    func testStillUserDoesNotChaseGPSNoise() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 0, accuracy: 10, now: 0, reduceMotion: false)
        motion.step(now: 0)
        for i in 1...10 {
            let noisy = offset(origin, meters: 3, bearing: Double(i * 77 % 360))
            XCTAssertFalse(motion.receive(coordinate: noisy, timestamp: base.addingTimeInterval(Double(i)), speed: 0.2,
                                          accuracy: 10, now: Double(i), reduceMotion: false))
        }
        XCTAssertEqual(distance(motion.displayed, origin), 0, accuracy: 1e-6)
    }

    func testLinearTransitionUsesTheRealCadenceAndHasNoStopAndGo() {
        var motion = MarkerMotion()
        var now = 0.0
        var point = origin
        motion.receive(coordinate: point, timestamp: base, speed: 14, accuracy: 5, now: now, reduceMotion: false)
        motion.step(now: now)
        var shown: [CLLocationCoordinate2D] = []
        // Conducción recta a 14 m/s (≈ 50 km/h) con lecturas a 1 Hz.
        for i in 1...8 {
            point = offset(point, meters: 14, bearing: 45)
            motion.receive(coordinate: point, timestamp: base.addingTimeInterval(Double(i)), speed: 14, accuracy: 5,
                           now: now, reduceMotion: false)
            shown += run(&motion, from: now, to: now + 1)
            now += 1
        }
        // Velocidad por fotograma: constante (14 m/s ⇒ ≈ 0,233 m por fotograma); sin frenazos ni saltos.
        let steps = zip(shown, shown.dropFirst()).map { MarkerMotion.distance($0, $1) }.dropFirst(60)
        XCTAssertLessThan(steps.max() ?? 0, 0.27, "sin saltos")
        XCTAssertGreaterThan(steps.min() ?? 0, 0.19, "sin paradas entre lecturas")
        // Retraso acotado: nunca más de una lectura (14 m) por detrás de la última recibida.
        XCTAssertLessThanOrEqual(distance(motion.displayed, point), 14.5)
    }

    func testNewReadingMidTransitionContinuesFromTheDisplayedPosition() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 10, accuracy: 5, now: 0, reduceMotion: false)
        motion.step(now: 0)
        let a = offset(origin, meters: 10, bearing: 90)
        motion.receive(coordinate: a, timestamp: base.addingTimeInterval(1), speed: 10, accuracy: 5, now: 0, reduceMotion: false)
        motion.step(now: 0.4)
        let before = motion.displayed!
        let b = offset(a, meters: 10, bearing: 0)
        motion.receive(coordinate: b, timestamp: base.addingTimeInterval(1.4), speed: 10, accuracy: 5, now: 0.4, reduceMotion: false)
        motion.step(now: 0.4)
        XCTAssertEqual(distance(motion.displayed, before), 0, accuracy: 0.01, "no vuelve al inicio de la animación anterior")
        motion.step(now: 0.4 + frame)
        XCTAssertLessThan(distance(motion.displayed, before), 0.5)
    }

    func testNeverExtrapolatesBeyondTheLastReadingWhenSignalIsLost() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 14, accuracy: 5, now: 0, reduceMotion: false)
        motion.step(now: 0)
        let last = offset(origin, meters: 14, bearing: 0)
        motion.receive(coordinate: last, timestamp: base.addingTimeInterval(1), speed: 14, accuracy: 5, now: 0, reduceMotion: false)
        run(&motion, from: 0, to: 6)                         // 5 s sin lecturas
        XCTAssertEqual(distance(motion.displayed, last), 0, accuracy: 1e-6, "se queda en la última lectura real")
        XCTAssertFalse(motion.isAnimating, "el bucle de animación se puede parar")
    }

    func testSignalRecoveryAfterAGapIsShortAndBigCorrectionsSnap() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 10, accuracy: 5, now: 0, reduceMotion: false)
        motion.step(now: 0)
        // 10 s sin señal y luego 60 m más allá: transición corta, no a la cadencia habitual.
        let back = offset(origin, meters: 60, bearing: 0)
        motion.receive(coordinate: back, timestamp: base.addingTimeInterval(10), speed: 10, accuracy: 5, now: 10, reduceMotion: false)
        run(&motion, from: 10, to: 10.35)
        XCTAssertEqual(distance(motion.displayed, back), 0, accuracy: 1e-6)
        // Corrección de 2 km: se aplica de golpe, no cruza la ciudad.
        let far = offset(back, meters: 2000, bearing: 90)
        motion.receive(coordinate: far, timestamp: base.addingTimeInterval(11), speed: 10, accuracy: 5, now: 11, reduceMotion: false)
        motion.step(now: 11)
        XCTAssertEqual(distance(motion.displayed, far), 0, accuracy: 1e-6)
    }

    func testIrregularReadingsAdaptTheDurationWithinLimits() {
        var motion = MarkerMotion()
        var point = origin
        motion.receive(coordinate: point, timestamp: base, speed: 8, accuracy: 5, now: 0, reduceMotion: false)
        var time = 0.0
        for gap in [0.2, 0.25, 0.2, 0.3, 0.2, 0.2, 0.25] {
            time += gap
            point = offset(point, meters: 8 * gap, bearing: 0)
            motion.receive(coordinate: point, timestamp: base.addingTimeInterval(time), speed: 8, accuracy: 5, now: time, reduceMotion: false)
        }
        XCTAssertLessThan(motion.interval, 0.5, "la cadencia medida sigue a las lecturas reales (≈ 0,2 s)")
        for gap in [2.0, 2.5, 2.0, 2.2] {
            time += gap
            point = offset(point, meters: 8 * gap, bearing: 0)
            motion.receive(coordinate: point, timestamp: base.addingTimeInterval(time), speed: 8, accuracy: 5, now: time, reduceMotion: false)
        }
        run(&motion, from: time, to: time + 1.0 + frame)
        XCTAssertEqual(distance(motion.displayed, point), 0, accuracy: 1e-6, "nunca tarda más del máximo (1 s)")
    }

    func testCurvedDriveKeepsTheArrowOnTheChordsBetweenRealReadings() {
        var motion = MarkerMotion()
        // Rotonda/curva: 12 lecturas a 1 Hz girando 15° por lectura a 10 m/s.
        var points = [origin]
        var bearing = 0.0
        for _ in 1...12 {
            bearing += 15
            points.append(offset(points.last!, meters: 10, bearing: bearing))
        }
        motion.receive(coordinate: points[0], timestamp: base, speed: 10, accuracy: 5, now: 0, reduceMotion: false)
        motion.step(now: 0)
        var maxOffChord = 0.0
        for i in 1..<points.count {
            let now = Double(i - 1)
            motion.receive(coordinate: points[i], timestamp: base.addingTimeInterval(Double(i)), speed: 10, accuracy: 5,
                           now: now, reduceMotion: false)
            motion.receive(heading: Double(i) * 15, reduceMotion: false)
            for shown in run(&motion, from: now, to: now + 1) {
                // Distancia al segmento [anterior, actual] ≤ lo que separa los extremos: nunca sale disparada.
                let d = min(distance(shown, points[i - 1]), distance(shown, points[i]))
                maxOffChord = max(maxOffChord, d)
            }
        }
        XCTAssertLessThanOrEqual(maxOffChord, 10.5)
        XCTAssertEqual(Angle.shortestDelta(from: motion.displayedHeading, to: 180), 0, accuracy: 1, "sigue la curva")
    }

    func testReduceMotionPlacesTheArrowDirectly() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 10, accuracy: 5, now: 0, reduceMotion: true)
        let next = offset(origin, meters: 12, bearing: 0)
        motion.receive(coordinate: next, timestamp: base.addingTimeInterval(1), speed: 10, accuracy: 5, now: 0, reduceMotion: true)
        motion.receive(heading: 200, reduceMotion: true)
        motion.step(now: 0)
        XCTAssertEqual(distance(motion.displayed, next), 0, accuracy: 1e-6)
        XCTAssertEqual(motion.displayedHeading, 200, accuracy: 1e-9)
    }

    func testHeadingOnlyUpdatesDoNotRestartTheMovement() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 10, accuracy: 5, now: 0, reduceMotion: false)
        let next = offset(origin, meters: 10, bearing: 0)
        XCTAssertTrue(motion.receive(coordinate: next, timestamp: base.addingTimeInterval(1), speed: 10, accuracy: 5, now: 0, reduceMotion: false))
        motion.step(now: 0.5)
        // Misma lectura reenviada (solo cambió la brújula): no cambia nada.
        XCTAssertFalse(motion.receive(coordinate: next, timestamp: base.addingTimeInterval(1), speed: 10, accuracy: 5, now: 0.5, reduceMotion: false))
        motion.step(now: 1.0)
        XCTAssertEqual(distance(motion.displayed, next), 0, accuracy: 1e-6)
    }

    func testBackgroundReturnDoesNotJumpTheRotationOnTheFirstFrame() {
        var motion = MarkerMotion()
        motion.receive(coordinate: origin, timestamp: base, speed: 10, accuracy: 5, now: 0, reduceMotion: false)
        motion.receive(heading: 0, reduceMotion: false)
        motion.step(now: 0)
        motion.receive(heading: 90, reduceMotion: false)
        motion.resetClock()                                  // bucle parado en segundo plano y vuelto a crear
        motion.step(now: 500)
        XCTAssertEqual(motion.displayedHeading, 0, accuracy: 1e-9, "primer fotograma tras volver: dt = 0")
        motion.step(now: 500 + frame)
        XCTAssertGreaterThan(motion.displayedHeading, 0)
    }
}

/// Cámara de seguimiento: suave, sin pasarse y por el giro más corto.
final class FollowCameraSmootherTests: XCTestCase {
    private typealias State = FollowCameraSmoother.State

    func testConvergesWithoutOvershootIncludingDirectionAcrossNorth() {
        let smoother = FollowCameraSmoother()
        var state = State(center: CLLocationCoordinate2D(latitude: 40.4, longitude: -3.7), zoom: 15, pitch: 0, direction: 350)
        let target = State(center: CLLocationCoordinate2D(latitude: 40.401, longitude: -3.7), zoom: 17, pitch: 45, direction: 10)
        var previousZoom = state.zoom
        for _ in 0..<180 {
            state = smoother.step(state, toward: target, dt: 1.0 / 60, immediate: false)
            XCTAssertLessThanOrEqual(state.zoom, 17 + 1e-9)
            XCTAssertGreaterThanOrEqual(state.zoom, previousZoom - 1e-9)
            previousZoom = state.zoom
            XCTAssertTrue(state.direction >= 349.9 || state.direction <= 10.1, "gira por el norte: \(state.direction)")
        }
        XCTAssertTrue(smoother.converged(state, target))
    }

    func testImmediateModeForReduceMotion() {
        let smoother = FollowCameraSmoother()
        let state = State(center: CLLocationCoordinate2D(latitude: 40.4, longitude: -3.7), zoom: 15, pitch: 0, direction: 0)
        let target = State(center: CLLocationCoordinate2D(latitude: 40.41, longitude: -3.71), zoom: 16, pitch: 40, direction: 90)
        XCTAssertEqual(smoother.step(state, toward: target, dt: 1.0 / 60, immediate: true), target)
    }

    func testSteadyFollowingLagIsSmall() {
        // Objetivo moviéndose a 14 m/s: la cámara va como mucho ≈ v·tau (1,4 m) por detrás.
        let smoother = FollowCameraSmoother()
        var target = State(center: CLLocationCoordinate2D(latitude: 40.4, longitude: -3.7), zoom: 16, pitch: 0, direction: 0)
        var state = target
        let metersPerDegree = 111_320.0
        for _ in 0..<240 {
            target.center.latitude += 14.0 / 60 / metersPerDegree
            state = smoother.step(state, toward: target, dt: 1.0 / 60, immediate: false)
        }
        XCTAssertLessThan(MarkerMotion.distance(state.center, target.center), 1.6)
    }
}

/// Elección entre rumbo del GPS y brújula, con histéresis.
final class HeadingSourceSelectorTests: XCTestCase {
    func testUsesCompassWhenStillAndCourseWhenMoving() {
        var selector = HeadingSourceSelector()
        selector.ingestCompass(120, accuracy: 10)
        XCTAssertEqual(selector.ingestFix(speed: 0.3, course: -1, courseAccuracy: -1), 120)
        XCTAssertEqual(selector.ingestFix(speed: 8, course: 45, courseAccuracy: 5), 45)
        XCTAssertEqual(selector.source, .course)
        XCTAssertNil(selector.ingestCompass(200, accuracy: 10), "en marcha la brújula no manda")
    }

    func testHysteresisAvoidsFlippingAtTheThresholdSpeed() {
        var selector = HeadingSourceSelector()
        selector.ingestCompass(300, accuracy: 10)
        selector.ingestFix(speed: 2.5, course: 10, courseAccuracy: 5)
        XCTAssertEqual(selector.source, .course)
        for speed in [1.6, 1.4, 1.8, 1.2, 1.5] {          // entre 1 y 2 m/s: se mantiene el GPS
            XCTAssertEqual(selector.ingestFix(speed: speed, course: 12, courseAccuracy: 8), 12)
        }
        selector.ingestFix(speed: 0.5, course: 12, courseAccuracy: 8)
        XCTAssertEqual(selector.source, .compass)
        for speed in [1.5, 1.8, 1.2] {                      // de nuevo entre umbrales: se mantiene la brújula
            XCTAssertEqual(selector.ingestFix(speed: speed, course: 15, courseAccuracy: 8), 300)
        }
    }

    func testInvalidCourseOrCompassIsNotUsedAsConfirmedHeading() {
        var selector = HeadingSourceSelector()
        selector.ingestCompass(90, accuracy: 10)
        XCTAssertEqual(selector.ingestFix(speed: 10, course: -1, courseAccuracy: -1), 90, "course inválido: sigue la brújula")
        XCTAssertEqual(selector.ingestFix(speed: 10, course: 200, courseAccuracy: 90), 90, "course con mala precisión: no")
        XCTAssertNil(selector.ingestCompass(180, accuracy: -1), "brújula sin calibrar: se ignora")
        XCTAssertEqual(selector.heading, 90)
    }
}
