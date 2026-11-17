import CoreGraphics
import Foundation

/// Diseño de la señal de límite. Solo cambia el DIBUJO: nunca el límite, la vía elegida ni las unidades.
enum SpeedSignStyle: String, CaseIterable, Identifiable {
    /// Según el país del tramo que indica el proveedor de límites. Si no se sabe: circular europea (documentado).
    case automatic
    case european
    case unitedStates
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automático según país"
        case .european: return "Circular europea"
        case .unitedStates: return "Rectangular (EE. UU.)"
        case .minimal: return "Minimalista"
        }
    }

    /// Países (ISO 3166-1) que usan la señal rectangular «SPEED LIMIT»: Estados Unidos y sus territorios. No se incluyen
    /// países con otros diseños rectangulares (p. ej. Canadá, «MAXIMUM»): para ellos se usa el diseño por defecto.
    static let unitedStatesStyleCountries: Set<String> = ["US", "PR", "GU", "VI", "AS", "MP", "UM"]

    /// Diseño que se dibuja de verdad. `countryCode` viene del proveedor (nil = no se sabe).
    func resolved(countryCode: String?) -> SpeedSignStyle {
        guard self == .automatic else { return self }
        if let code = countryCode?.uppercased(), Self.unitedStatesStyleCountries.contains(code) { return .unitedStates }
        return .european
    }
}

enum SpeedSignSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Pequeño"
        case .medium: return "Mediano"
        case .large: return "Grande"
        }
    }

    /// Lado de referencia (pt) antes de aplicar el tamaño de texto del sistema.
    var side: CGFloat {
        switch self {
        case .small: return 48
        case .medium: return 60
        case .large: return 76
        }
    }
}

/// Posiciones SEGURAS en el iPhone: todas son huecos reservados dentro del diseño de la pantalla (filas propias), así
/// que la señal nunca queda encima de la maniobra, los botones, la brújula, el buscador, el reproductor ni el sistema.
enum SpeedSignPosition: String, CaseIterable, Identifiable {
    /// Navegando: abajo a la izquierda, encima del panel. Sin ruta: arriba a la izquierda, bajo el indicador GPS.
    case automatic
    case topLeading
    case topTrailing
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automática"
        case .topLeading: return "Arriba a la izquierda"
        case .topTrailing: return "Arriba a la derecha"
        }
    }
}

/// Qué hacer cuando no hay límite que mostrar (sin dato o ubicación insuficiente).
enum SpeedSignNoData: String, CaseIterable, Identifiable {
    case dash
    case hide
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dash: return "Indicador neutro «—»"
        case .hide: return "Ocultar la señal"
        }
    }
}

/// Preferencias visuales de la señal, juntas. Se guardan en `UserSettings` (una sola configuración, sin duplicados).
struct SpeedSignAppearance: Equatable {
    var style: SpeedSignStyle = .automatic
    var size: SpeedSignSize = .medium
    var position: SpeedSignPosition = .automatic
    var noData: SpeedSignNoData = .dash
    var showsCurrentSpeed = false

    static let defaults = SpeedSignAppearance()
}

extension UserSettings {
    var speedSignAppearance: SpeedSignAppearance {
        get {
            SpeedSignAppearance(style: SpeedSignStyle(rawValue: speedSignStyleRaw) ?? .automatic,
                                size: SpeedSignSize(rawValue: speedSignSizeRaw) ?? .medium,
                                position: SpeedSignPosition(rawValue: speedSignPositionRaw) ?? .automatic,
                                noData: SpeedSignNoData(rawValue: speedSignNoDataRaw) ?? .dash,
                                showsCurrentSpeed: speedSignShowsCurrentSpeed)
        }
        set {
            speedSignStyleRaw = newValue.style.rawValue
            speedSignSizeRaw = newValue.size.rawValue
            speedSignPositionRaw = newValue.position.rawValue
            speedSignNoDataRaw = newValue.noData.rawValue
            speedSignShowsCurrentSpeed = newValue.showsCurrentSpeed
        }
    }

    /// Restablece SOLO la sección «Señal de límite de velocidad». No toca Casa, Trabajo, favoritos ni otros ajustes
    /// (tampoco las unidades, que son un ajuste general de la app).
    func resetSpeedSignSettings() {
        showSpeedLimit = true
        speedLimitWithoutRoute = false
        speedSignAppearance = .defaults
    }
}
