import SwiftUI

/// Catálogo de temas originales. Colores propios; no reproducen paletas de juegos reales.
enum ThemeCatalog {
    static let all: [MapTheme] = [neonNocturno, mapaMinimalista, retroArcade,
                                   mundoVoxel, mapaAventura, cyberCity]

    static func theme(for id: MapThemeID) -> MapTheme {
        all.first { $0.id == id } ?? neonNocturno
    }

    static let neonNocturno = MapTheme(
        id: .neonNocturno, name: "Neón nocturno",
        background: Color(red: 0.04, green: 0.04, blue: 0.10),
        panel: Color(red: 0.08, green: 0.07, blue: 0.18).opacity(0.92),
        accent: Color(red: 1.00, green: 0.25, blue: 0.75),
        routeCore: Color(red: 0.55, green: 1.00, blue: 0.95),
        routeGlow: Color(red: 0.20, green: 0.80, blue: 1.00).opacity(0.35),
        textPrimary: .white,
        textSecondary: Color(white: 0.7),
        routeCoreWidth: 6, routeGlowWidth: 16,
        titleDesign: .rounded,
        overlayOpacity: 0.25, overlayBlend: .plusLighter,
        isDark: true
    )

    static let mapaMinimalista = MapTheme(
        id: .mapaMinimalista, name: "Mapa minimalista",
        background: .white,
        panel: .white.opacity(0.95),
        accent: .black,
        routeCore: .black,
        routeGlow: Color.black.opacity(0.12),
        textPrimary: .black,
        textSecondary: Color(white: 0.35),
        routeCoreWidth: 5, routeGlowWidth: 10,
        titleDesign: .default,
        overlayOpacity: 0.0, overlayBlend: .normal,
        isDark: false
    )

    static let retroArcade = MapTheme(
        id: .retroArcade, name: "Retro arcade",
        background: Color(red: 0.10, green: 0.02, blue: 0.20),
        panel: Color(red: 0.20, green: 0.05, blue: 0.30),
        accent: Color(red: 1.00, green: 0.85, blue: 0.10),
        routeCore: Color(red: 1.00, green: 0.35, blue: 0.20),
        routeGlow: Color(red: 1.00, green: 0.85, blue: 0.10).opacity(0.4),
        textPrimary: Color(red: 1.00, green: 0.95, blue: 0.70),
        textSecondary: Color(red: 0.6, green: 0.9, blue: 1.0),
        routeCoreWidth: 9, routeGlowWidth: 14,
        titleDesign: .monospaced,
        overlayOpacity: 0.20, overlayBlend: .overlay,
        isDark: true
    )

    // Temas de versión 1.1 (definidos ya para validar el catálogo).
    static let mundoVoxel = MapTheme(
        id: .mundoVoxel, name: "Mundo voxel",
        background: Color(red: 0.55, green: 0.80, blue: 0.95),
        panel: Color(red: 0.95, green: 0.97, blue: 0.90),
        accent: Color(red: 0.35, green: 0.70, blue: 0.25),
        routeCore: Color(red: 0.98, green: 0.80, blue: 0.20),
        routeGlow: Color.black.opacity(0.25),
        textPrimary: Color(red: 0.12, green: 0.20, blue: 0.12),
        textSecondary: Color(red: 0.30, green: 0.40, blue: 0.30),
        routeCoreWidth: 8, routeGlowWidth: 12,
        titleDesign: .rounded,
        overlayOpacity: 0.15, overlayBlend: .multiply,
        isDark: false
    )

    static let mapaAventura = MapTheme(
        id: .mapaAventura, name: "Mapa de aventura",
        background: Color(red: 0.93, green: 0.85, blue: 0.68),
        panel: Color(red: 0.97, green: 0.92, blue: 0.80),
        accent: Color(red: 0.45, green: 0.25, blue: 0.10),
        routeCore: Color(red: 0.70, green: 0.15, blue: 0.10),
        routeGlow: Color(red: 0.45, green: 0.25, blue: 0.10).opacity(0.25),
        textPrimary: Color(red: 0.25, green: 0.15, blue: 0.05),
        textSecondary: Color(red: 0.40, green: 0.30, blue: 0.20),
        routeCoreWidth: 5, routeGlowWidth: 9,
        titleDesign: .serif,
        overlayOpacity: 0.35, overlayBlend: .multiply,
        isDark: false
    )

    static let cyberCity = MapTheme(
        id: .cyberCity, name: "Cyber-city",
        background: Color(red: 0.03, green: 0.05, blue: 0.08),
        panel: Color(red: 0.06, green: 0.10, blue: 0.14).opacity(0.94),
        accent: Color(red: 1.00, green: 0.10, blue: 0.60),
        routeCore: Color(red: 0.00, green: 0.95, blue: 1.00),
        routeGlow: Color(red: 1.00, green: 0.10, blue: 0.60).opacity(0.30),
        textPrimary: Color(red: 0.85, green: 0.98, blue: 1.00),
        textSecondary: Color(red: 0.45, green: 0.65, blue: 0.75),
        routeCoreWidth: 6, routeGlowWidth: 18,
        titleDesign: .monospaced,
        overlayOpacity: 0.30, overlayBlend: .screen,
        isDark: true
    )
}

// MARK: - Environment

private struct MapThemeKey: EnvironmentKey {
    static let defaultValue: MapTheme = ThemeCatalog.neonNocturno
}

extension EnvironmentValues {
    var mapTheme: MapTheme {
        get { self[MapThemeKey.self] }
        set { self[MapThemeKey.self] = newValue }
    }
}
