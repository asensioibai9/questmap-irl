import Foundation

/// Precisión de ubicación que el usuario ha concedido a la app.
enum LocationAccuracyMode: Equatable {
    /// Ubicación precisa.
    case full
    /// "Ubicación aproximada": iOS entrega lecturas de varios kilómetros.
    case reduced
}

/// Estado de la ubicación tal y como ocurre de verdad. No existe un estado "GPS perdido" genérico:
/// la ausencia de movimiento, un error temporal o una lectura imprecisa NO son una pérdida.
enum LocationStatus: Equatable {
    /// Falta decidir el permiso.
    case requestingPermission
    /// Permiso concedido y todavía no ha llegado la primera lectura (o se está actualizando tras volver a la app).
    case acquiring
    /// Hay una lectura reciente y suficientemente precisa.
    case available
    /// El usuario concedió solo ubicación aproximada.
    case reducedAccuracy
    /// Hay lectura reciente pero imprecisa (± metros).
    case lowAccuracy(meters: Int)
    /// La última lectura es antigua y no se ha podido confirmar que siga vigente.
    case lastKnown(ageSeconds: Int)
    /// iOS informa de un fallo temporal (p. ej. interior o señal débil) y aún no hay lectura.
    case temporaryError
    case denied
    case restricted
    case servicesDisabled

    /// ¿Hay motivo para avisar al usuario?
    var needsAttention: Bool {
        switch self {
        case .available, .acquiring, .requestingPermission: return false
        default: return true
        }
    }

    /// Texto corto para el indicador.
    var title: String {
        switch self {
        case .requestingPermission: return "Permiso pendiente"
        case .acquiring: return "Obteniendo ubicación…"
        case .available: return "Ubicación disponible"
        case .reducedAccuracy: return "Ubicación aproximada"
        case .lowAccuracy(let meters): return "Precisión baja (±\(meters) m)"
        case .lastKnown(let age): return "Sin confirmar (hace \(Self.age(age)))"
        case .temporaryError: return "Sin ubicación por ahora"
        case .denied: return "Permiso denegado"
        case .restricted: return "Ubicación restringida"
        case .servicesDisabled: return "Localización desactivada"
        }
    }

    /// Texto explicativo para el aviso de pantalla.
    var explanation: String? {
        switch self {
        case .requestingPermission:
            return "Permite la ubicación para verte en el mapa."
        case .acquiring:
            return "Obteniendo tu ubicación…"
        case .available:
            return nil
        case .reducedAccuracy:
            return "Solo tienes concedida la ubicación aproximada: la posición puede estar a varios kilómetros. Activa la ubicación precisa para rutas y navegación."
        case .lowAccuracy(let meters):
            return "La precisión de la ubicación es baja (±\(meters) m). Mejora en exteriores y con cielo despejado."
        case .lastKnown(let age):
            return "Mostramos tu última ubicación conocida (hace \(Self.age(age))). No hemos podido confirmar que siga vigente."
        case .temporaryError:
            return "iOS no consigue localizarte todavía (interior o señal débil). Seguimos intentándolo."
        case .denied:
            return "Sin acceso a la ubicación no podemos guiarte. Actívala en Ajustes › QuestMap IRL › Ubicación."
        case .restricted:
            return "La ubicación está restringida en este dispositivo (control parental o perfil)."
        case .servicesDisabled:
            return "Los servicios de localización están desactivados en este iPhone. Actívalos en Ajustes › Privacidad y seguridad › Localización."
        }
    }

    /// Nombre estable para registros (sin datos personales).
    var logName: String {
        switch self {
        case .requestingPermission: return "requestingPermission"
        case .acquiring: return "acquiring"
        case .available: return "available"
        case .reducedAccuracy: return "reducedAccuracy"
        case .lowAccuracy: return "lowAccuracy"
        case .lastKnown: return "lastKnown"
        case .temporaryError: return "temporaryError"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .servicesDisabled: return "servicesDisabled"
        }
    }

    private static func age(_ seconds: Int) -> String {
        seconds < 90 ? "\(seconds) s" : "\(seconds / 60) min"
    }
}

/// Datos de entrada de la evaluación (todo lo que hace falta para decidir el estado).
struct LocationSnapshot: Equatable {
    var auth: LocationAuthState
    var accuracyMode: LocationAccuracyMode = .full
    var hasFix = false
    var fixAccuracy: Double = 0
    /// Edad del `timestamp` de la última lectura válida.
    var fixAge: TimeInterval = 0
    /// La última lectura iba a más de 1,5 m/s.
    var moving = false
    var mode: LocationMode = .idle
    /// Tiempo desde el último arranque de las actualizaciones.
    var sinceStart: TimeInterval = 0
    /// Ha llegado al menos una lectura válida desde el último arranque.
    var freshSinceStart = false
    /// iOS informó de `locationUnknown` en los últimos segundos.
    var recentTemporaryError = false
}

enum LocationStatusEvaluator {
    /// Antigüedad a partir de la cual una lectura deja de poder darse por vigente. Quieto no se
    /// espera ninguna lectura nueva (el sistema no las entrega sin movimiento), por eso el margen es
    /// grande; en movimiento, mucho menor.
    static func staleLimit(mode: LocationMode, moving: Bool) -> TimeInterval {
        switch (mode, moving) {
        case (.navigating, true): return 10
        case (.navigating, false): return 25
        case (.idle, true): return 20
        case (.idle, false): return 75
        }
    }

    /// A partir de esta edad se pide una lectura nueva al sistema para confirmar la vigencia.
    static func refreshAge(mode: LocationMode, moving: Bool) -> TimeInterval {
        staleLimit(mode: mode, moving: moving) / 2
    }

    /// Margen tras arrancar durante el cual una lectura antigua se considera "actualizando".
    static let resumeGrace: TimeInterval = 8
    /// Tiempo sin lectura antes de reconocer un error temporal como estado visible.
    static let temporaryErrorAfter: TimeInterval = 12

    static func evaluate(_ s: LocationSnapshot) -> LocationStatus {
        switch s.auth {
        case .servicesDisabled: return .servicesDisabled
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .requestingPermission
        case .authorizedWhenInUse, .authorizedAlways: break
        }

        guard s.hasFix else {
            return (s.recentTemporaryError && s.sinceStart > temporaryErrorAfter) ? .temporaryError : .acquiring
        }

        let limit = staleLimit(mode: s.mode, moving: s.moving)
        if s.fixAge > limit {
            // Justo después de volver a la app o arrancar, la lectura vieja es lo esperable: se está actualizando.
            if !s.freshSinceStart && s.sinceStart < resumeGrace { return .acquiring }
            return .lastKnown(ageSeconds: Int(s.fixAge))
        }
        if s.accuracyMode == .reduced { return .reducedAccuracy }
        if s.fixAccuracy > 100 { return .lowAccuracy(meters: Int(s.fixAccuracy)) }
        return .available
    }

    /// Por qué se descarta una lectura (nil = se acepta). Las lecturas imprecisas o antiguas NO se descartan:
    /// se aceptan y el estado indica su calidad.
    static func discardReason(horizontalAccuracy: Double, latitude: Double, longitude: Double,
                              timestamp: Date, newestAccepted: Date?) -> String? {
        if horizontalAccuracy < 0 { return "precisión negativa (sin fix)" }
        if !(-90...90).contains(latitude) || !(-180...180).contains(longitude) { return "coordenada inválida" }
        if latitude == 0 && longitude == 0 { return "coordenada 0,0" }
        if let newestAccepted, timestamp < newestAccepted { return "lectura más antigua que la ya aceptada" }
        return nil
    }
}
