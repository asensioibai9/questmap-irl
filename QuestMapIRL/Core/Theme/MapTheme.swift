import SwiftUI
import MapKit

/// Identificador estable de cada tema (se guarda en UserSettings).
enum MapThemeID: String, CaseIterable, Codable, Identifiable {
    case ciudadNocturna
    case islaRoyale
    case mundoBloques
    case mapaFantasia
    case retroArcade
    case minimalistaPro

    var id: String { rawValue }
}

/// Tipos de punto de interés con iconografía propia por tema.
enum POIKind: String, CaseIterable, Identifiable {
    case fuel, food, parking, hospital, police, shop, poi, quest
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fuel: return "Combustible"
        case .food: return "Comida"
        case .parking: return "Parking"
        case .hospital: return "Hospital"
        case .police: return "Policía"
        case .shop: return "Tienda"
        case .poi: return "Punto de interés"
        case .quest: return "Misión"
        }
    }
}

/// Efecto decorativo que se dibuja encima del mapa real (nunca encima del HUD).
enum OverlayEffect: Equatable {
    case none
    case vignette              // oscurece bordes
    case neonGrid              // rejilla synthwave en perspectiva
    case parchment             // tinte pergamino + grano
    case voxelGrid             // cuadrícula de bloques
    case scanlines             // líneas horizontales finas
}

/// Estilo del mapa base de MapKit que acompaña al tema.
enum BaseMapKind: Equatable {
    case standard       // calles normales con POIs reducidos
    case muted          // calles atenuadas (mejor para HUD)
    case imagery        // satélite (isla)
}

/// Tokens visuales de un tema. Nunca afectan a datos de ruta ni a precisión.
struct MapTheme: Equatable, Identifiable {
    let id: MapThemeID
    let name: String
    let tagline: String
    let isDark: Bool
    let baseMap: BaseMapKind

    // Superficies y texto del HUD
    let background: Color
    let panel: Color
    let panelBorder: Color
    let accent: Color
    let textPrimary: Color
    let textSecondary: Color

    // Ruta (tres capas: borde, resplandor, núcleo)
    let routeCore: Color
    let routeBorder: Color
    let routeGlow: Color
    let routeCoreWidth: CGFloat
    let routeBorderWidth: CGFloat
    let routeGlowWidth: CGFloat
    let routeAnimated: Bool

    // Marcadores
    let origin: Color
    let destination: Color
    let player: Color

    // Colores "de mundo": tintes de leyenda y overlays (MapKit no recolorea el mapa base)
    let road: Color
    let water: Color
    let vegetation: Color
    let building: Color

    // Tipografía e iconos
    let titleDesign: Font.Design
    let iconWeight: Font.Weight
    let cornerRadius: CGFloat
    let poiIcons: [POIKind: String]

    // Efecto sobre el mapa
    let overlay: OverlayEffect
    let overlayOpacity: Double

    var mapStyle: MapStyle {
        switch baseMap {
        case .standard:
            return .standard(elevation: .realistic, emphasis: .automatic, pointsOfInterest: .excludingAll)
        case .muted:
            return .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .imagery:
            return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }

    func icon(for kind: POIKind) -> String {
        poiIcons[kind] ?? "mappin"
    }
}

// MARK: - Environment

private struct MapThemeKey: EnvironmentKey {
    static let defaultValue: MapTheme = ThemeCatalog.ciudadNocturna
}

extension EnvironmentValues {
    var mapTheme: MapTheme {
        get { self[MapThemeKey.self] }
        set { self[MapThemeKey.self] = newValue }
    }
}

// MARK: - Color desde HEX

extension Color {
    /// `Color(hex: 0x1A2B3C)`; opacidad opcional.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
