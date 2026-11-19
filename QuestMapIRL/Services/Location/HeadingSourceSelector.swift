import Foundation

/// Elige la orientación de la flecha entre el rumbo de desplazamiento del GPS (`course`) y la brújula.
///
/// - En marcha manda el `course` (es la dirección real del movimiento); parado, la brújula.
/// - Con histéresis: se pasa al GPS por encima de `enterCourseSpeed` y se vuelve a la brújula por debajo de
///   `leaveCourseSpeed`. Entre ambas se mantiene la fuente actual, así no alterna en cada lectura a velocidad límite.
/// - Un `course` negativo o con precisión peor que `maxCourseAccuracy` no se usa como orientación confirmada.
/// - Una lectura de brújula inválida (precisión negativa) se ignora.
/// El cambio de fuente no es brusco en pantalla: la flecha gira hacia el nuevo valor por el camino más corto
/// (`MarkerMotion`).
struct HeadingSourceSelector {
    enum Source: Equatable { case compass, course }

    var enterCourseSpeed: Double = 2.0
    var leaveCourseSpeed: Double = 1.0
    var maxCourseAccuracy: Double = 45
    /// Brújula con un error mayor (interferencias, sin calibrar) no mueve la flecha: se conserva el último valor fiable.
    var maxCompassAccuracy: Double = 45

    private(set) var source: Source = .compass
    private(set) var heading: Double?
    private var compass: Double?

    /// Lectura del GPS. Devuelve el rumbo a mostrar si cambió.
    @discardableResult
    mutating func ingestFix(speed: Double, course: Double, courseAccuracy: Double) -> Double? {
        // courseAccuracy negativo = desconocido (lecturas antiguas o simuladas): solo cuenta el course.
        let courseValid = course >= 0 && (courseAccuracy < 0 || courseAccuracy <= maxCourseAccuracy)
        switch source {
        case .compass where courseValid && speed > enterCourseSpeed:
            source = .course
        case .course where !courseValid || speed < leaveCourseSpeed:
            source = .compass
        default:
            break
        }
        if source == .course {
            heading = course
        } else if let compass {
            heading = compass
        }
        return heading
    }

    /// Lectura de la brújula. Solo cambia el rumbo mostrado si la fuente activa es la brújula.
    @discardableResult
    mutating func ingestCompass(_ value: Double, accuracy: Double) -> Double? {
        guard accuracy >= 0, accuracy <= maxCompassAccuracy, value >= 0 else { return nil }
        compass = value
        guard source == .compass else { return nil }
        heading = value
        return value
    }

    /// Cambió el borde de referencia de la brújula (giro de la interfaz). La última lectura ya no vale como dato nuevo,
    /// pero el rumbo mostrado se conserva hasta la siguiente lectura (sin saltos ni rumbos inventados).
    mutating func referenceChanged() {
        compass = nil
    }
}
