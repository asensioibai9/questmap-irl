import SwiftUI

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

enum MinimapShape: Equatable {
    case circle
    case roundedSquare
    /// Rectángulo apaisado con los bordes desvanecidos (radar rectangular de estilo videojuego).
    case fadedRectangle
}

/// Qué iconos se registran en el estilo para los puntos de interés.
enum PoiIconSet: Equatable {
    case systemSymbols
    /// Familia propia con contorno marcado (`GameIcons`).
    case gameBadges
}

/// Cómo se dibuja el MAPA REAL de este tema. El estilo vectorial vive en un JSON (capas, colores,
/// anchos por zoom, etiquetas) y se renderiza con MapLibre; aquí solo van los parámetros de
/// cámara y de los elementos que dibuja la app.
struct CartographyStyle: Equatable {
    /// Nombre del archivo JSON del estilo (sin extensión) en el bundle.
    let resourceName: String
    /// Color de fondo mientras cargan los tiles (evita destellos blancos).
    let backgroundHex: UInt32
    let userArrowHex: UInt32
    let defaultZoom: Double
    let navigationZoom: Double
    let navigationPitch: Double
    let minimapZoom: Double
    let minimapShape: MinimapShape
    let minimapBorderHex: UInt32
    let attribution: String
    /// Color del símbolo de los puntos de interés y de su contorno.
    var poiIconHex: UInt32 = 0xFFFFFF
    var poiOutlineHex: UInt32 = 0x0A0B0D
    /// Familia de iconos de los puntos de interés: símbolos del sistema o iconos propios del estilo.
    var poiIconSet: PoiIconSet = .systemSymbols
    /// Texturas del catálogo de recursos que usa el estilo (`fill-pattern`). Deben coincidir con
    /// `metadata["questmap:images"]` del JSON (lo comprueba un test).
    var textures: [String] = []
    /// El JSON del estilo incluye la capa `building-3d` (edificios extruidos). Sin ella no se muestra el control 2D/3D.
    var supportsBuildings3D: Bool = false
}

/// Tokens del tema: HUD (paneles, texto, iconos) y cartografía. Cambiar de tema nunca altera
/// los datos de ruta ni de navegación.
struct MapTheme: Equatable, Identifiable {
    let id: MapThemeID
    let name: String
    let tagline: String
    let isDark: Bool

    // HUD
    let background: Color
    let panel: Color
    let panelBorder: Color
    let accent: Color
    let textPrimary: Color
    let textSecondary: Color

    // Colores de marcadores (el mapa los toma del JSON; estos pintan el HUD y las miniaturas)
    let routeCore: Color
    let routeBorder: Color
    let destination: Color
    let player: Color

    // Tipografía e iconos
    let titleDesign: Font.Design
    let iconWeight: Font.Weight
    let cornerRadius: CGFloat
    let poiIcons: [POIKind: String]

    /// nil mientras el estilo cartográfico de este tema no está terminado.
    let cartography: CartographyStyle?

    var isCartographyReady: Bool { cartography != nil }

    var activeCartography: CartographyStyle {
        cartography ?? ThemeCatalog.ciudadNocturna.cartography!
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

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
