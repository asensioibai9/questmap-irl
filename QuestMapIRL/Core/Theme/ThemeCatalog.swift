import SwiftUI

/// Catálogo de temas originales. Paletas propias; no reproducen el arte de ningún juego.
/// La especificación completa (HEX, tipografías, reglas) está en docs/05-especificacion-temas.md.
enum ThemeCatalog {
    static let all: [MapTheme] = [ciudadNocturna, islaRoyale, mundoBloques, mapaFantasia, retroArcade, minimalistaPro]

    static func theme(for id: MapThemeID) -> MapTheme {
        all.first { $0.id == id } ?? ciudadNocturna
    }

    // A. Ciudad Criminal Nocturna
    static let ciudadNocturna = MapTheme(
        id: .ciudadNocturna, name: "Ciudad Criminal Nocturna",
        tagline: "Asfalto mojado, neón y una ruta que no se pierde.",
        isDark: true, baseMap: .muted,
        background: Color(hex: 0x0B0D10),
        panel: Color(hex: 0x15181E, opacity: 0.94),
        panelBorder: Color(hex: 0xF2C94C, opacity: 0.55),
        accent: Color(hex: 0xF2C94C),
        textPrimary: Color(hex: 0xF5F5F0),
        textSecondary: Color(hex: 0xA3A8B3),
        routeCore: Color(hex: 0xC8F542),
        routeBorder: Color(hex: 0x0B0D10),
        routeGlow: Color(hex: 0xC8F542, opacity: 0.35),
        routeCoreWidth: 7, routeBorderWidth: 11, routeGlowWidth: 20, routeAnimated: false,
        origin: Color(hex: 0x4CC9F0), destination: Color(hex: 0xF2C94C), player: Color(hex: 0xF5F5F0),
        road: Color(hex: 0x2A2E36), water: Color(hex: 0x0E1A26), vegetation: Color(hex: 0x16221A), building: Color(hex: 0x1C2027),
        titleDesign: .default, iconWeight: .bold, cornerRadius: 14,
        poiIcons: [.fuel: "fuelpump.fill", .food: "fork.knife", .parking: "parkingsign", .hospital: "cross.fill",
                   .police: "shield.lefthalf.filled", .shop: "bag.fill", .poi: "star.fill", .quest: "flag.fill"],
        overlay: .vignette, overlayOpacity: 0.55
    )

    // B. Isla Battle Royale
    static let islaRoyale = MapTheme(
        id: .islaRoyale, name: "Isla Battle Royale",
        tagline: "Color, sol y un marcador que se ve desde el cielo.",
        isDark: false, baseMap: .standard,
        background: Color(hex: 0xE8F6FF),
        panel: Color(hex: 0xFFFFFF, opacity: 0.94),
        panelBorder: Color(hex: 0x00C2FF, opacity: 0.6),
        accent: Color(hex: 0xFF2E93),
        textPrimary: Color(hex: 0x14213D),
        textSecondary: Color(hex: 0x4F5D75),
        routeCore: Color(hex: 0x00C2FF),
        routeBorder: Color(hex: 0xFFFFFF),
        routeGlow: Color(hex: 0x00C2FF, opacity: 0.25),
        routeCoreWidth: 8, routeBorderWidth: 12, routeGlowWidth: 18, routeAnimated: true,
        origin: Color(hex: 0x3DDC97), destination: Color(hex: 0xFF2E93), player: Color(hex: 0x14213D),
        road: Color(hex: 0xF4E9CD), water: Color(hex: 0x3FB8F0), vegetation: Color(hex: 0x7ED957), building: Color(hex: 0xFFB84C),
        titleDesign: .rounded, iconWeight: .heavy, cornerRadius: 20,
        poiIcons: [.fuel: "fuelpump.circle.fill", .food: "takeoutbag.and.cup.and.straw.fill", .parking: "p.circle.fill",
                   .hospital: "cross.case.fill", .police: "shield.fill", .shop: "cart.fill", .poi: "mappin.and.ellipse", .quest: "scope"],
        overlay: .none, overlayOpacity: 0
    )

    // C. Mundo de Bloques
    static let mundoBloques = MapTheme(
        id: .mundoBloques, name: "Mundo de Bloques",
        tagline: "Cada manzana es un bloque. Cada ruta, un camino de luz.",
        isDark: false, baseMap: .standard,
        background: Color(hex: 0x87CEEB),
        panel: Color(hex: 0x3B2A1E, opacity: 0.94),
        panelBorder: Color(hex: 0x8B5A2B),
        accent: Color(hex: 0xF5D547),
        textPrimary: Color(hex: 0xFFF6DC),
        textSecondary: Color(hex: 0xD2B48C),
        routeCore: Color(hex: 0xF5D547),
        routeBorder: Color(hex: 0x3B2A1E),
        routeGlow: Color(hex: 0xF5D547, opacity: 0.3),
        routeCoreWidth: 9, routeBorderWidth: 13, routeGlowWidth: 16, routeAnimated: false,
        origin: Color(hex: 0x5CB85C), destination: Color(hex: 0xE74C3C), player: Color(hex: 0x3B2A1E),
        road: Color(hex: 0x8C8C8C), water: Color(hex: 0x3F76E4), vegetation: Color(hex: 0x5CB85C), building: Color(hex: 0xB8860B),
        titleDesign: .monospaced, iconWeight: .black, cornerRadius: 4,
        poiIcons: [.fuel: "fuelpump.fill", .food: "carrot.fill", .parking: "square.fill", .hospital: "heart.fill",
                   .police: "shield.fill", .shop: "shippingbox.fill", .poi: "cube.fill", .quest: "flag.square.fill"],
        overlay: .voxelGrid, overlayOpacity: 0.18
    )

    // D. Mapa de Fantasía
    static let mapaFantasia = MapTheme(
        id: .mapaFantasia, name: "Mapa de Fantasía",
        tagline: "Pergamino, tinta y una ruta dorada hacia la aventura.",
        isDark: false, baseMap: .muted,
        background: Color(hex: 0xEBDCB5),
        panel: Color(hex: 0xF6EBD0, opacity: 0.96),
        panelBorder: Color(hex: 0x7A4A1F),
        accent: Color(hex: 0x7A4A1F),
        textPrimary: Color(hex: 0x3B2412),
        textSecondary: Color(hex: 0x6E5438),
        routeCore: Color(hex: 0xD4A017),
        routeBorder: Color(hex: 0x3B2412),
        routeGlow: Color(hex: 0xD4A017, opacity: 0.3),
        routeCoreWidth: 5, routeBorderWidth: 8, routeGlowWidth: 14, routeAnimated: false,
        origin: Color(hex: 0x4A6B3A), destination: Color(hex: 0x9B1C1C), player: Color(hex: 0x3B2412),
        road: Color(hex: 0xC9A66B), water: Color(hex: 0x6A93B8), vegetation: Color(hex: 0x6B8E4E), building: Color(hex: 0xA0714F),
        titleDesign: .serif, iconWeight: .semibold, cornerRadius: 10,
        poiIcons: [.fuel: "flame.fill", .food: "cup.and.saucer.fill", .parking: "tent.fill", .hospital: "cross.vial.fill",
                   .police: "shield.checkered", .shop: "bag.fill", .poi: "sparkles", .quest: "scroll.fill"],
        overlay: .parchment, overlayOpacity: 0.4
    )

    // E. Retro Arcade
    static let retroArcade = MapTheme(
        id: .retroArcade, name: "Retro Arcade",
        tagline: "Rejilla infinita, neón y una ruta que late.",
        isDark: true, baseMap: .muted,
        background: Color(hex: 0x12022B),
        panel: Color(hex: 0x1F0A47, opacity: 0.94),
        panelBorder: Color(hex: 0xFF3CAC, opacity: 0.7),
        accent: Color(hex: 0xFFE14D),
        textPrimary: Color(hex: 0xFFF7D6),
        textSecondary: Color(hex: 0x7DF9FF),
        routeCore: Color(hex: 0xFF3CAC),
        routeBorder: Color(hex: 0x12022B),
        routeGlow: Color(hex: 0x7DF9FF, opacity: 0.4),
        routeCoreWidth: 7, routeBorderWidth: 11, routeGlowWidth: 22, routeAnimated: true,
        origin: Color(hex: 0x7DF9FF), destination: Color(hex: 0xFFE14D), player: Color(hex: 0xFFE14D),
        road: Color(hex: 0x2E1A5E), water: Color(hex: 0x0B2A4A), vegetation: Color(hex: 0x11363A), building: Color(hex: 0x3A1E6E),
        titleDesign: .monospaced, iconWeight: .heavy, cornerRadius: 6,
        poiIcons: [.fuel: "bolt.fill", .food: "gamecontroller.fill", .parking: "p.square.fill", .hospital: "plus.square.fill",
                   .police: "exclamationmark.shield.fill", .shop: "cart.fill", .poi: "star.square.fill", .quest: "trophy.fill"],
        overlay: .neonGrid, overlayOpacity: 0.35
    )

    // F. Minimalista Pro
    static let minimalistaPro = MapTheme(
        id: .minimalistaPro, name: "Minimalista Pro",
        tagline: "Solo lo que necesitas para conducir.",
        isDark: false, baseMap: .standard,
        background: Color(hex: 0xFFFFFF),
        panel: Color(hex: 0xFFFFFF, opacity: 0.96),
        panelBorder: Color(hex: 0x000000, opacity: 0.12),
        accent: Color(hex: 0x0A84FF),
        textPrimary: Color(hex: 0x111111),
        textSecondary: Color(hex: 0x5C5C5C),
        routeCore: Color(hex: 0x0A84FF),
        routeBorder: Color(hex: 0xFFFFFF),
        routeGlow: Color(hex: 0x0A84FF, opacity: 0.15),
        routeCoreWidth: 7, routeBorderWidth: 11, routeGlowWidth: 14, routeAnimated: false,
        origin: Color(hex: 0x34C759), destination: Color(hex: 0xFF3B30), player: Color(hex: 0x0A84FF),
        road: Color(hex: 0xE5E5EA), water: Color(hex: 0xBFD9F2), vegetation: Color(hex: 0xD5E8D0), building: Color(hex: 0xF2F2F7),
        titleDesign: .default, iconWeight: .semibold, cornerRadius: 16,
        poiIcons: [.fuel: "fuelpump", .food: "fork.knife", .parking: "parkingsign", .hospital: "cross",
                   .police: "shield", .shop: "bag", .poi: "mappin", .quest: "flag"],
        overlay: .none, overlayOpacity: 0
    )
}
