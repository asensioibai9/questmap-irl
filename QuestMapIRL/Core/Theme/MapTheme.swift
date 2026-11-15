import SwiftUI

/// Identificador estable de cada tema (se guarda en UserSettings).
enum MapThemeID: String, CaseIterable, Codable, Identifiable {
    case neonNocturno
    case mundoVoxel
    case mapaAventura
    case retroArcade
    case mapaMinimalista
    case cyberCity

    var id: String { rawValue }
}

/// Tokens visuales de un tema. Nunca afectan a datos de ruta ni a precisión.
struct MapTheme: Equatable {
    let id: MapThemeID
    let name: String

    // Colores de UI
    let background: Color
    let panel: Color
    let accent: Color
    let routeCore: Color
    let routeGlow: Color
    let textPrimary: Color
    let textSecondary: Color

    // Ruta
    let routeCoreWidth: CGFloat
    let routeGlowWidth: CGFloat

    // Tipografía (diseño de fuente; sin fuentes de terceros en MVP)
    let titleDesign: Font.Design

    // Overlay sobre el mapa base (opacidad 0...1 y modo de mezcla)
    let overlayOpacity: Double
    let overlayBlend: BlendMode

    /// Mapa base de MapKit: estilo elegido para acompañar al tema.
    let isDark: Bool
}

extension MapTheme {
    /// Color de tinte para marcadores y el jugador.
    var playerTint: Color { accent }
}
