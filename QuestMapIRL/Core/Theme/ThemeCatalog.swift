import SwiftUI

/// Catálogo de temas. Los nombres visibles son propios y se pueden cambiar sin tocar el
/// renderizador. Las referencias a videojuegos viven solo en la documentación interna
/// (docs/07-*, tools/); la app no se presenta como oficial ni afiliada a ninguno.
///
/// Solo los temas con `cartography != nil` tienen mapa propio terminado. El resto conserva su
/// paleta de HUD pero se muestra como "Próximamente" hasta tener su estilo cartográfico.
enum ThemeCatalog {
    static let all: [MapTheme] = [ciudadNocturna, minimalistaPro, islaRoyale, mundoBloques, mapaFantasia, retroArcade]

    static func theme(for id: MapThemeID) -> MapTheme {
        all.first { $0.id == id } ?? ciudadNocturna
    }

    private static let attribution = "© OpenStreetMap contributors · © OpenMapTiles · OpenFreeMap"

    // MARK: - Terminados

    static let ciudadNocturna = MapTheme(
        id: .ciudadNocturna, name: "Ciudad nocturna",
        tagline: "Asfalto oscuro, siluetas de edificios y una ruta que no se pierde.",
        isDark: true,
        background: Color(hex: 0x0B0D10),
        panel: Color(hex: 0x15181E, opacity: 0.94),
        panelBorder: Color(hex: 0xF2C14E, opacity: 0.55),
        accent: Color(hex: 0xF2C14E),
        textPrimary: Color(hex: 0xF5F5F0),
        textSecondary: Color(hex: 0xA3A8B3),
        routeCore: Color(hex: 0xA855E8), routeBorder: Color(hex: 0x0F0F0F),
        destination: Color(hex: 0xFFD400), player: Color(hex: 0x4CC9F0),
        titleDesign: .default, iconWeight: .bold, cornerRadius: 14,
        poiIcons: [.fuel: "fuelpump.fill", .food: "fork.knife", .parking: "parkingsign", .hospital: "cross.fill",
                   .police: "shield.lefthalf.filled", .shop: "bag.fill", .poi: "star.fill", .quest: "flag.fill"],
        cartography: CartographyStyle(
            resourceName: "style-ciudad-nocturna", backgroundHex: 0x17191D, userArrowHex: 0xFFFFFF,
            defaultZoom: 15.5, navigationZoom: 17, navigationPitch: 35,
            minimapZoom: 16.5, minimapShape: .fadedRectangle, minimapBorderHex: 0x0A0B0D, attribution: attribution,
            poiIconSet: .gameBadges, supportsBuildings3D: true)
    )

    static let minimalistaPro = MapTheme(
        id: .minimalistaPro, name: "Minimalista Pro",
        tagline: "Solo lo que necesitas para conducir de día.",
        isDark: false,
        background: Color(hex: 0xFFFFFF),
        panel: Color(hex: 0xFFFFFF, opacity: 0.96),
        panelBorder: Color(hex: 0x000000, opacity: 0.12),
        accent: Color(hex: 0x0A84FF),
        textPrimary: Color(hex: 0x111111),
        textSecondary: Color(hex: 0x5C5C5C),
        routeCore: Color(hex: 0x0A84FF), routeBorder: Color(hex: 0xFFFFFF),
        destination: Color(hex: 0xFF3B30), player: Color(hex: 0x0A84FF),
        titleDesign: .default, iconWeight: .semibold, cornerRadius: 16,
        poiIcons: [.fuel: "fuelpump", .food: "fork.knife", .parking: "parkingsign", .hospital: "cross",
                   .police: "shield", .shop: "bag", .poi: "mappin", .quest: "flag"],
        cartography: CartographyStyle(
            resourceName: "style-minimalista-pro", backgroundHex: 0xF3F4F7, userArrowHex: 0x0A84FF,
            defaultZoom: 15.5, navigationZoom: 17, navigationPitch: 0,
            minimapZoom: 16.5, minimapShape: .roundedSquare, minimapBorderHex: 0xFFFFFF, attribution: attribution,
            poiIconHex: 0x2B2F3A, poiOutlineHex: 0xFFFFFF)
    )

    // MARK: - Isla y Mundo de bloques (texturas procedurales)
    // Los siguientes (fantasía, arcade) siguen sin cartografía: solo paleta de HUD.

    static let islaRoyale = MapTheme(
        id: .islaRoyale, name: "Isla",
        tagline: "Color saturado, costas y un marcador que se ve desde el cielo.",
        isDark: false,
        background: Color(hex: 0xE8F6FF), panel: Color(hex: 0xFFFFFF, opacity: 0.94),
        panelBorder: Color(hex: 0x00C2FF, opacity: 0.6), accent: Color(hex: 0xFF2E93),
        textPrimary: Color(hex: 0x14213D), textSecondary: Color(hex: 0x4F5D75),
        routeCore: Color(hex: 0x00C2FF), routeBorder: Color(hex: 0xFFFFFF),
        destination: Color(hex: 0xFF2E93), player: Color(hex: 0x14213D),
        titleDesign: .rounded, iconWeight: .heavy, cornerRadius: 20,
        poiIcons: [.fuel: "fuelpump.circle.fill", .food: "takeoutbag.and.cup.and.straw.fill", .parking: "p.circle.fill",
                   .hospital: "cross.case.fill", .police: "shield.fill", .shop: "cart.fill", .poi: "mappin.and.ellipse", .quest: "scope"],
        cartography: CartographyStyle(
            resourceName: "style-isla", backgroundHex: 0x74A83A, userArrowHex: 0xFFFFFF,
            defaultZoom: 15.5, navigationZoom: 16.5, navigationPitch: 0,
            minimapZoom: 16, minimapShape: .roundedSquare, minimapBorderHex: 0xFFFFFF, attribution: attribution,
            poiIconHex: 0xFFFFFF, poiOutlineHex: 0x18290F, textures: ["tex-canopy", "tex-grass"],
            supportsBuildings3D: true)
    )

    static let mundoBloques = MapTheme(
        id: .mundoBloques, name: "Mundo de bloques",
        tagline: "Cuadrícula, paleta limitada y un camino de bloques brillantes.",
        isDark: false,
        background: Color(hex: 0x87CEEB), panel: Color(hex: 0x3B2A1E, opacity: 0.94),
        panelBorder: Color(hex: 0x8B5A2B), accent: Color(hex: 0xF5D547),
        textPrimary: Color(hex: 0xFFF6DC), textSecondary: Color(hex: 0xD2B48C),
        routeCore: Color(hex: 0xF5D547), routeBorder: Color(hex: 0x3B2A1E),
        destination: Color(hex: 0xE74C3C), player: Color(hex: 0x3B2A1E),
        titleDesign: .monospaced, iconWeight: .black, cornerRadius: 4,
        poiIcons: [.fuel: "fuelpump.fill", .food: "carrot.fill", .parking: "square.fill", .hospital: "heart.fill",
                   .police: "shield.fill", .shop: "shippingbox.fill", .poi: "cube.fill", .quest: "flag.square.fill"],
        cartography: CartographyStyle(
            resourceName: "style-bloques", backgroundHex: 0x68A53F, userArrowHex: 0xFFFFFF,
            defaultZoom: 15.5, navigationZoom: 16.5, navigationPitch: 0,
            minimapZoom: 16, minimapShape: .roundedSquare, minimapBorderHex: 0x3B2A1E, attribution: attribution,
            poiIconHex: 0xFFFFFF, poiOutlineHex: 0x1D1D1D,
            textures: ["tex-block-grass", "tex-block-leaves", "tex-block-sand", "tex-block-path",
                       "tex-block-stone", "tex-block-water", "tex-block-planks"],
            supportsBuildings3D: true)
    )

    static let mapaFantasia = MapTheme(
        id: .mapaFantasia, name: "Mapa de fantasía",
        tagline: "Pergamino, tinta y una ruta dorada hacia la aventura.",
        isDark: false,
        background: Color(hex: 0xEBDCB5), panel: Color(hex: 0xF6EBD0, opacity: 0.96),
        panelBorder: Color(hex: 0x7A4A1F), accent: Color(hex: 0x7A4A1F),
        textPrimary: Color(hex: 0x3B2412), textSecondary: Color(hex: 0x6E5438),
        routeCore: Color(hex: 0xD4A017), routeBorder: Color(hex: 0x3B2412),
        destination: Color(hex: 0x9B1C1C), player: Color(hex: 0x3B2412),
        titleDesign: .serif, iconWeight: .semibold, cornerRadius: 10,
        poiIcons: [.fuel: "flame.fill", .food: "cup.and.saucer.fill", .parking: "tent.fill", .hospital: "cross.vial.fill",
                   .police: "shield.checkered", .shop: "bag.fill", .poi: "sparkles", .quest: "scroll.fill"],
        cartography: nil
    )

    static let retroArcade = MapTheme(
        id: .retroArcade, name: "Retro arcade",
        tagline: "Rejilla, neón y una ruta que late.",
        isDark: true,
        background: Color(hex: 0x12022B), panel: Color(hex: 0x1F0A47, opacity: 0.94),
        panelBorder: Color(hex: 0xFF3CAC, opacity: 0.7), accent: Color(hex: 0xFFE14D),
        textPrimary: Color(hex: 0xFFF7D6), textSecondary: Color(hex: 0x7DF9FF),
        routeCore: Color(hex: 0xFF3CAC), routeBorder: Color(hex: 0x12022B),
        destination: Color(hex: 0xFFE14D), player: Color(hex: 0xFFE14D),
        titleDesign: .monospaced, iconWeight: .heavy, cornerRadius: 6,
        poiIcons: [.fuel: "bolt.fill", .food: "gamecontroller.fill", .parking: "p.square.fill", .hospital: "plus.square.fill",
                   .police: "exclamationmark.shield.fill", .shop: "cart.fill", .poi: "star.square.fill", .quest: "trophy.fill"],
        cartography: nil
    )
}
