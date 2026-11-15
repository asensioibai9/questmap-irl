import Foundation
import SwiftData

/// Ajustes del usuario (una sola fila). Se guarda en SwiftData, en el dispositivo.
@Model
final class UserSettings {
    var themeRawValue: String
    var useMetricUnits: Bool
    var voiceEnabled: Bool
    var nightModeOverride: String   // "auto" | "day" | "night"
    var headingUp: Bool             // true: el mapa gira con el rumbo; false: norte arriba
    var showCompass: Bool

    init(themeRawValue: String = MapThemeID.ciudadNocturna.rawValue,
         useMetricUnits: Bool = true,
         voiceEnabled: Bool = true,
         nightModeOverride: String = "auto",
         headingUp: Bool = true,
         showCompass: Bool = true) {
        self.themeRawValue = themeRawValue
        self.useMetricUnits = useMetricUnits
        self.voiceEnabled = voiceEnabled
        self.nightModeOverride = nightModeOverride
        self.headingUp = headingUp
        self.showCompass = showCompass
    }

    var themeID: MapThemeID {
        get { MapThemeID(rawValue: themeRawValue) ?? .ciudadNocturna }
        set { themeRawValue = newValue.rawValue }
    }
}
