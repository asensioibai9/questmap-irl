import CoreLocation
import Foundation

/// Cámara de seguimiento suave. Lógica pura: dado el estado actual de la cámara y el objetivo (posición y rumbo
/// PRESENTADOS de la flecha, zoom e inclinación deseados), calcula el siguiente fotograma con una aproximación
/// exponencial (sin pasarse del objetivo y sin depender de la frecuencia de fotogramas).
///
/// Es la ÚNICA fuente de movimiento de cámara mientras se sigue al usuario: no se lanzan animaciones de cámara de MapLibre
/// en paralelo, así que no compiten ni se reinician en cada lectura.
struct FollowCameraSmoother {
    struct State: Equatable {
        var center: CLLocationCoordinate2D
        var zoom: Double
        var pitch: Double
        var direction: Double

        static func == (a: State, b: State) -> Bool {
            MarkerMotion.same(a.center, b.center) && a.zoom == b.zoom && a.pitch == b.pitch && a.direction == b.direction
        }
    }

    struct Config {
        /// Centro: muy rápido (la flecha ya va suave); el retraso en marcha es velocidad × tau (≈ 1,5 m a 50 km/h).
        var centerTau: Double = 0.1
        var zoomTau: Double = 0.22
        var pitchTau: Double = 0.22
        var directionTau: Double = 0.12
        var centerEpsilonMeters: Double = 0.05
        var zoomEpsilon: Double = 0.002
        var pitchEpsilon: Double = 0.05
        var directionEpsilon: Double = 0.05
    }

    var config = Config()

    static func approach(_ value: Double, _ target: Double, dt: Double, tau: Double) -> Double {
        guard tau > 0 else { return target }
        return value + (target - value) * (1 - exp(-dt / tau))
    }

    /// Siguiente estado. Con `immediate` (Reducir movimiento) va directamente al objetivo.
    func step(_ state: State, toward target: State, dt: Double, immediate: Bool) -> State {
        if immediate { return target }
        var next = state
        let k = 1 - exp(-max(0, dt) / config.centerTau)
        if MarkerMotion.distance(state.center, target.center) <= config.centerEpsilonMeters {
            next.center = target.center
        } else {
            next.center = CLLocationCoordinate2D(latitude: state.center.latitude + (target.center.latitude - state.center.latitude) * k,
                                                 longitude: state.center.longitude + (target.center.longitude - state.center.longitude) * k)
        }
        next.zoom = abs(target.zoom - state.zoom) <= config.zoomEpsilon
            ? target.zoom : Self.approach(state.zoom, target.zoom, dt: dt, tau: config.zoomTau)
        next.pitch = abs(target.pitch - state.pitch) <= config.pitchEpsilon
            ? target.pitch : Self.approach(state.pitch, target.pitch, dt: dt, tau: config.pitchTau)
        let delta = HeadingMath.shortestDelta(from: state.direction, to: target.direction)
        next.direction = abs(delta) <= config.directionEpsilon
            ? HeadingMath.normalized(target.direction)
            : HeadingMath.normalized(state.direction + delta * (1 - exp(-max(0, dt) / config.directionTau)))
        return next
    }

    func converged(_ state: State, _ target: State) -> Bool {
        MarkerMotion.distance(state.center, target.center) <= config.centerEpsilonMeters
            && abs(state.zoom - target.zoom) <= config.zoomEpsilon
            && abs(state.pitch - target.pitch) <= config.pitchEpsilon
            && abs(HeadingMath.shortestDelta(from: state.direction, to: target.direction)) <= config.directionEpsilon
    }
}
