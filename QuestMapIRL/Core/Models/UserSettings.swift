import Foundation
import SwiftData

/// Ajustes del usuario (una sola fila en MVP). Se guarda en SwiftData, en el dispositivo.
@Model
final class UserSettings {
    var themeRawValue: String
    var useMetricUnits: Bool
    var voiceEnabled: Bool
    var nightModeOverride: String   // "auto" | "day" | "night"

    init(themeRawValue: String = MapThemeID.neonNocturno.rawValue,
         useMetricUnits: Bool = true,
         voiceEnabled: Bool = true,
         nightModeOverride: String = "auto") {
        self.themeRawValue = themeRawValue
        self.useMetricUnits = useMetricUnits
        self.voiceEnabled = voiceEnabled
        self.nightModeOverride = nightModeOverride
    }
}
