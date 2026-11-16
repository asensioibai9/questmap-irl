import Foundation
import SwiftData

/// Ajustes del usuario (una sola fila). Se guarda en SwiftData, en el dispositivo.
/// REGLA: toda propiedad lleva valor por defecto EN EL MODELO (no solo en el init). Sin él, la migración
/// automática de un almacén creado por una versión anterior falla («loadIssueModelContainer») y la app
/// no puede abrir los datos guardados. Cubierto por LegacyStoreMigrationTests.
@Model
final class UserSettings {
    var themeRawValue: String = MapThemeID.ciudadNocturna.rawValue
    var useMetricUnits: Bool = true
    var voiceEnabled: Bool = true
    var nightModeOverride: String = "auto"   // sin uso en la interfaz; se conserva por compatibilidad
    var headingUp: Bool = true      // true: el mapa gira con el rumbo; false: norte arriba
    var showCompass: Bool = true
    var mapAvatarRaw: String = MapAvatar.arrow.rawValue
    var saveSearchHistory: Bool = true
    var defaultModeRaw: String = RouteMode.driving.rawValue
    /// Vista con edificios 3D (solo en estilos que la admiten). Por defecto, vista cenital 2D.
    var view3D: Bool = false
    /// Mostrar la señal de límite de velocidad durante la navegación.
    var showSpeedLimit: Bool = true

    init(themeRawValue: String = MapThemeID.ciudadNocturna.rawValue,
         useMetricUnits: Bool = true,
         voiceEnabled: Bool = true,
         headingUp: Bool = true,
         showCompass: Bool = true) {
        self.themeRawValue = themeRawValue
        self.useMetricUnits = useMetricUnits
        self.voiceEnabled = voiceEnabled
        self.headingUp = headingUp
        self.showCompass = showCompass
    }

    var themeID: MapThemeID {
        get { MapThemeID(rawValue: themeRawValue) ?? .ciudadNocturna }
        set { themeRawValue = newValue.rawValue }
    }

    var mapAvatar: MapAvatar {
        get { MapAvatar(rawValue: mapAvatarRaw) ?? .arrow }
        set { mapAvatarRaw = newValue.rawValue }
    }

    var defaultMode: RouteMode {
        get { RouteMode(rawValue: defaultModeRaw) ?? .driving }
        set { defaultModeRaw = newValue.rawValue }
    }
}
