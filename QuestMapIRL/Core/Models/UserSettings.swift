import Foundation
import SwiftData

/// Ajustes del usuario (una sola fila). Se guarda en SwiftData, en el dispositivo.
/// Las propiedades añadidas después de la primera versión llevan valor por defecto para que la
/// migración automática no falle.
@Model
final class UserSettings {
    var themeRawValue: String
    var useMetricUnits: Bool
    var voiceEnabled: Bool
    var nightModeOverride: String = "auto"   // sin uso en la interfaz; se conserva por compatibilidad
    var headingUp: Bool             // true: el mapa gira con el rumbo; false: norte arriba
    var showCompass: Bool
    var mapAvatarRaw: String = MapAvatar.arrow.rawValue
    var saveSearchHistory: Bool = true
    var defaultModeRaw: String = RouteMode.driving.rawValue

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
