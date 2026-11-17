import CoreLocation
import Foundation

/// Ángulos en grados, siempre normalizados a [0, 360).
enum HeadingMath {
    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Diferencia más corta de `from` a `to`, en (-180, 180]. De 359° a 1° son +2°, no -358°.
    static func shortestDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }
}

/// Movimiento VISUAL de la flecha del usuario. Lógica pura (sin UIKit ni MapLibre) para poder probarla con recorridos
/// reproducibles.
///
/// Separa dos cosas:
/// - **Posición confirmada**: la última lectura que llegó del sistema (`confirmed`). Es la única que vale para datos.
/// - **Posición presentada**: dónde se dibuja la flecha ahora (`displayed`). Va de la posición presentada actual a la
///   lectura nueva en línea recta y a velocidad constante, en lo que tarda en llegar la siguiente lectura (medido con las
///   marcas de tiempo reales de las lecturas). Así no frena ni acelera en cada lectura.
///
/// Nunca va más allá de la última lectura (no extrapola): si dejan de llegar lecturas, la flecha se queda en la última
/// posición confirmada. La posición presentada NO se usa para rutas, llegada ni desvíos.
struct MarkerMotion {
    struct Config {
        /// Duración mínima y máxima de una transición. El máximo limita el retraso visual respecto a la lectura.
        var minDuration: Double = 0.12
        var maxDuration: Double = 1.0
        /// Si dejan de llegar lecturas más de esto, la siguiente se alcanza en `recoveryDuration` (no a la cadencia).
        var gapThreshold: Double = 3.0
        var recoveryDuration: Double = 0.3
        /// Por debajo de esta velocidad (m/s) se considera que el usuario está quieto.
        var stillSpeed: Double = 0.6
        /// Parado, se ignoran movimientos menores que max(stillMinimum, precisión × stillAccuracyFactor), con tope.
        var stillMinimum: Double = 2.5
        var stillAccuracyFactor: Double = 0.4
        var stillMaximum: Double = 12
        /// Saltos mayores que max(snapMinimum, velocidad × snapSeconds + precisión) se aplican de golpe (corrección grande,
        /// recuperación de señal): la flecha no cruza la ciudad lentamente.
        var snapMinimum: Double = 120
        var snapSeconds: Double = 4
        /// Constante de tiempo del giro (s): menor = más rápido. En marcha responde en curvas; parado, filtra la brújula.
        var rotationTauMoving: Double = 0.14
        var rotationTauStill: Double = 0.3
        /// Parado, cambios de rumbo menores que esto se ignoran (vibración de la brújula).
        var stillHeadingDeadband: Double = 4
        /// Por debajo de esto el giro se da por terminado.
        var rotationEpsilon: Double = 0.25
    }

    var config = Config()

    /// Última lectura recibida (la real). Nil hasta la primera.
    private(set) var confirmed: CLLocationCoordinate2D?
    /// Posición dibujada en el último `step`.
    private(set) var displayed: CLLocationCoordinate2D?
    private(set) var displayedHeading: Double = 0
    private(set) var targetHeading: Double = 0

    private var from: CLLocationCoordinate2D?
    private var startTime: Double = 0
    private var duration: Double = 0
    private var lastFixTimestamp: Date?
    private var lastHeadingStep: Double?
    private var hasHeading = false
    /// Cadencia estimada de las lecturas (s), media móvil de los intervalos reales.
    private(set) var interval: Double = 1.0
    private(set) var isStill = true

    init(config: Config = Config()) { self.config = config }

    var isMoving: Bool {
        guard let displayed, let confirmed else { return false }
        return !Self.same(displayed, confirmed)
    }

    var isRotating: Bool { abs(HeadingMath.shortestDelta(from: displayedHeading, to: targetHeading)) > config.rotationEpsilon }

    var isAnimating: Bool { isMoving || isRotating }

    // MARK: - Entradas

    /// Lectura nueva del sistema. `now` es el reloj de la animación (monótono, en segundos).
    /// Devuelve true si cambió el destino de la flecha.
    @discardableResult
    mutating func receive(coordinate: CLLocationCoordinate2D, timestamp: Date, speed: Double, accuracy: Double,
                          now: Double, reduceMotion: Bool) -> Bool {
        let gap = lastFixTimestamp.map { timestamp.timeIntervalSince($0) }
        if let gap, gap <= 0 { return false }                     // misma lectura (p. ej. solo cambió la brújula)
        lastFixTimestamp = timestamp
        if let gap, gap < config.gapThreshold {
            interval = interval * 0.7 + gap * 0.3                 // cadencia real, suavizada
        }
        isStill = speed >= 0 && speed < config.stillSpeed

        // Posición presentada justo ahora (punto de partida si hay una transición en curso).
        let current = position(at: now) ?? coordinate
        guard let previousTarget = confirmed else { return snap(to: coordinate) }

        let jumpFromScreen = Self.distance(current, coordinate)
        let snapLimit = max(config.snapMinimum, max(0, speed) * config.snapSeconds + max(0, accuracy))
        if reduceMotion || jumpFromScreen > snapLimit { return snap(to: coordinate) }

        // Parado: no se persigue el ruido del GPS.
        if isStill || speed < 0 {
            let deadband = isStill
                ? min(config.stillMaximum, max(config.stillMinimum, max(0, accuracy) * config.stillAccuracyFactor))
                : config.stillMinimum
            if Self.distance(previousTarget, coordinate) < deadband { return false }
        }

        from = current
        displayed = current
        confirmed = coordinate
        startTime = now
        if let gap, gap >= config.gapThreshold {
            duration = config.recoveryDuration
        } else {
            duration = min(config.maxDuration, max(config.minDuration, interval))
        }
        return true
    }

    /// Rumbo objetivo nuevo (ya elegido entre GPS y brújula). Parado, se ignora la vibración pequeña.
    mutating func receive(heading: Double, reduceMotion: Bool) {
        let value = HeadingMath.normalized(heading)
        if hasHeading, isStill, abs(HeadingMath.shortestDelta(from: targetHeading, to: value)) < config.stillHeadingDeadband { return }
        targetHeading = value
        // El primer rumbo se aplica directamente (no hay de dónde girar).
        if reduceMotion || !hasHeading { displayedHeading = value }
        hasHeading = true
    }

    /// Coloca la flecha de golpe (sin transición).
    @discardableResult
    private mutating func snap(to coordinate: CLLocationCoordinate2D) -> Bool {
        confirmed = coordinate
        displayed = coordinate
        from = coordinate
        duration = 0
        return true
    }

    // MARK: - Fotograma

    /// Avanza la animación hasta `now`. Devuelve true si aún queda movimiento o giro pendiente.
    @discardableResult
    mutating func step(now: Double) -> Bool {
        displayed = position(at: now)
        let dt = lastHeadingStep.map { max(0, now - $0) } ?? 0
        lastHeadingStep = now
        let delta = HeadingMath.shortestDelta(from: displayedHeading, to: targetHeading)
        if abs(delta) <= config.rotationEpsilon {
            displayedHeading = targetHeading
        } else {
            let tau = isStill ? config.rotationTauStill : config.rotationTauMoving
            // Aproximación exponencial: independiente de la frecuencia de fotogramas y sin pasarse del objetivo.
            let factor = 1 - exp(-dt / tau)
            displayedHeading = HeadingMath.normalized(displayedHeading + delta * factor)
        }
        if !isAnimating { lastHeadingStep = nil }
        return isAnimating
    }

    /// Reinicia el reloj del giro (p. ej. al volver de segundo plano) para que el primer fotograma no salte.
    mutating func resetClock() { lastHeadingStep = nil }

    private func position(at now: Double) -> CLLocationCoordinate2D? {
        guard let confirmed else { return nil }
        guard let from, duration > 0 else { return confirmed }
        let t = min(1, max(0, (now - startTime) / duration))     // lineal: velocidad constante entre lecturas
        if t >= 1 { return confirmed }
        return CLLocationCoordinate2D(latitude: from.latitude + (confirmed.latitude - from.latitude) * t,
                                      longitude: from.longitude + (confirmed.longitude - from.longitude) * t)
    }

    // MARK: - Geometría

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1e-9 && abs(a.longitude - b.longitude) < 1e-9
    }
}
