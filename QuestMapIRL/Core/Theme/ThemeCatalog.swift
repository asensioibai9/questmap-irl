import SwiftUI

/// Catálogo de temas. Los nombres visibles son propios y se pueden cambiar sin tocar el
/// renderizador. Las referencias a videojuegos viven solo en la documentación interna
/// (docs/07-*, tools/); la app no se presenta como oficial ni afiliada a ninguno.
///
/// Solo los temas con `cartography != nil` tienen mapa propio terminado. El resto conserva su
/// paleta de HUD pero se muestra como "Próximamente" hasta tener su estilo cartográfico.
enum ThemeCatalog {
    static let all: [MapTheme] = [ciudadNocturna, costaTropical, minimalistaPro, islaRoyale, mundoBloques, salvajeOeste, ciudadCiber,
                                  mapaFantasia, redUrbana, rutasRally, retroArcade]

    static func theme(for id: MapThemeID) -> MapTheme {
        all.first { $0.id == id } ?? ciudadNocturna
    }

    private static let attribution = "© OpenStreetMap contributors · © OpenMapTiles · OpenFreeMap"

    // MARK: - Terminados

    static let ciudadNocturna = MapTheme(
        id: .ciudadNocturna, name: MapStyleNames.name(for: .ciudadNocturna),
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

    /// Referencia visual: mapa de pausa claro de GTA VI (capturas del usuario, origen no verificado) y minimapa del avance
    /// oficial. Ficha y diferencias en docs/30-estilo-gta-vi.md. El HUD es una adaptación propia a juego con el mapa.
    static let costaTropical = MapTheme(
        id: .costaTropical, name: MapStyleNames.name(for: .costaTropical),
        tagline: "Ciudad gris azulada, agua turquesa y una ruta rosa.",
        isDark: false,
        background: Color(hex: 0xB6BCC5),
        panel: Color(hex: 0xF4F5F8, opacity: 0.95),
        panelBorder: Color(hex: 0xF0559E, opacity: 0.45),
        accent: Color(hex: 0xE0408C),
        textPrimary: Color(hex: 0x1B1E26),
        textSecondary: Color(hex: 0x5A6172),
        routeCore: Color(hex: 0xF0559E), routeBorder: Color(hex: 0xFFFFFF),
        destination: Color(hex: 0x3FD8C2), player: Color(hex: 0x1B1E26),
        titleDesign: .default, iconWeight: .bold, cornerRadius: 16,
        poiIcons: [.fuel: "fuelpump.fill", .food: "fork.knife", .parking: "parkingsign", .hospital: "cross.fill",
                   .police: "shield.lefthalf.filled", .shop: "bag.fill", .poi: "mappin", .quest: "flag.fill"],
        cartography: CartographyStyle(
            resourceName: "style-costa-tropical", backgroundHex: 0xB6BCC5, userArrowHex: 0xFFFFFF,
            userArrowBadgeHex: 0x16181D,
            defaultZoom: 15.5, navigationZoom: 17, navigationPitch: 35,
            minimapZoom: 16.5, minimapShape: .roundedRectangle, minimapBorderHex: 0xF2F3F5, attribution: attribution,
            poiIconSet: .gameBubbles, supportsBuildings3D: true)
    )

    static let minimalistaPro = MapTheme(
        id: .minimalistaPro, name: MapStyleNames.name(for: .minimalistaPro),
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
        id: .islaRoyale, name: MapStyleNames.name(for: .islaRoyale),
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
        id: .mundoBloques, name: MapStyleNames.name(for: .mundoBloques),
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
        id: .mapaFantasia, name: MapStyleNames.name(for: .mapaFantasia),
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
        cartography: CartographyStyle(
            resourceName: "style-mapa-fantasia", backgroundHex: 0xC6AE84, userArrowHex: 0x3B2412,
            defaultZoom: 15, navigationZoom: 16.5, navigationPitch: 0,
            minimapZoom: 16, minimapShape: .circle, minimapBorderHex: 0x3B2412, attribution: attribution,
            poiIconHex: 0x3B2A1C, poiOutlineHex: 0xF0E0BD, textures: ["tex-ink-hills", "tex-ink-trees"])
    )

    // MARK: - Fase 4 (referencias y límites en docs/18)

    static let salvajeOeste = MapTheme(
        id: .salvajeOeste, name: MapStyleNames.name(for: .salvajeOeste),
        tagline: "Tinta fina sobre papel ocre: caminos, polvo y una ruta carmesí.",
        isDark: false,
        background: Color(hex: 0xE3D0A5), panel: Color(hex: 0xF1E2BD, opacity: 0.96),
        panelBorder: Color(hex: 0x4A3A28), accent: Color(hex: 0xA31F1F),
        textPrimary: Color(hex: 0x2B2118), textSecondary: Color(hex: 0x5C4A34),
        routeCore: Color(hex: 0xA31F1F), routeBorder: Color(hex: 0xF1E2BD),
        destination: Color(hex: 0xA31F1F), player: Color(hex: 0x2B2118),
        titleDesign: .serif, iconWeight: .semibold, cornerRadius: 8,
        poiIcons: [.fuel: "flame.fill", .food: "fork.knife", .parking: "tent.fill", .hospital: "cross.fill",
                   .police: "star.fill", .shop: "bag.fill", .poi: "mappin", .quest: "flag.fill"],
        cartography: CartographyStyle(
            resourceName: "style-salvaje-oeste", backgroundHex: 0xCFAE77, userArrowHex: 0x2B2118,
            defaultZoom: 15, navigationZoom: 16.5, navigationPitch: 0,
            minimapZoom: 16, minimapShape: .circle, minimapBorderHex: 0x2B2118, attribution: attribution,
            poiIconHex: 0x2B2118, poiOutlineHex: 0xF1E2BD, textures: ["tex-ink-stipple"])
    )

    static let ciudadCiber = MapTheme(
        id: .ciudadCiber, name: MapStyleNames.name(for: .ciudadCiber),
        tagline: "Manzanas rojas, vías de cian y una ruta amarilla que no se pierde.",
        isDark: true,
        background: Color(hex: 0x0A0710), panel: Color(hex: 0x14090F, opacity: 0.95),
        panelBorder: Color(hex: 0x2FD0E4, opacity: 0.6), accent: Color(hex: 0xFCEE0A),
        textPrimary: Color(hex: 0xF2F6F8), textSecondary: Color(hex: 0x8FB4BC),
        routeCore: Color(hex: 0xFCEE0A), routeBorder: Color(hex: 0x05080F),
        destination: Color(hex: 0xFCEE0A), player: Color(hex: 0x2FD0E4),
        titleDesign: .default, iconWeight: .bold, cornerRadius: 6,
        poiIcons: [.fuel: "bolt.fill", .food: "fork.knife", .parking: "parkingsign", .hospital: "cross.fill",
                   .police: "shield.lefthalf.filled", .shop: "bag.fill", .poi: "diamond.fill", .quest: "exclamationmark"],
        cartography: CartographyStyle(
            resourceName: "style-ciudad-ciber", backgroundHex: 0x14060C, userArrowHex: 0x2FD0E4,
            defaultZoom: 15.5, navigationZoom: 17, navigationPitch: 0,
            minimapZoom: 16.5, minimapShape: .roundedSquare, minimapBorderHex: 0x2FD0E4, attribution: attribution,
            poiIconHex: 0xE8F6F8, poiOutlineHex: 0x05080F, supportsBuildings3D: true)
    )

    static let redUrbana = MapTheme(
        id: .redUrbana, name: MapStyleNames.name(for: .redUrbana),
        tagline: "Una ciudad clara y plana: calles blancas, agua azul y autopistas amarillas.",
        isDark: false,
        background: Color(hex: 0xF4F5F7), panel: Color(hex: 0xFFFFFF, opacity: 0.96),
        panelBorder: Color(hex: 0x000000, opacity: 0.12), accent: Color(hex: 0xE8452C),
        textPrimary: Color(hex: 0x1F2128), textSecondary: Color(hex: 0x5A5E69),
        routeCore: Color(hex: 0xE8452C), routeBorder: Color(hex: 0xFFFFFF),
        destination: Color(hex: 0xE8452C), player: Color(hex: 0x1F6FE8),
        titleDesign: .rounded, iconWeight: .semibold, cornerRadius: 16,
        poiIcons: [.fuel: "fuelpump.fill", .food: "fork.knife", .parking: "parkingsign", .hospital: "cross.fill",
                   .police: "shield.fill", .shop: "bag.fill", .poi: "mappin", .quest: "flag.fill"],
        cartography: CartographyStyle(
            resourceName: "style-red-urbana", backgroundHex: 0xD9DADC, userArrowHex: 0x1F6FE8,
            defaultZoom: 15.5, navigationZoom: 17, navigationPitch: 0,
            minimapZoom: 16.5, minimapShape: .circle, minimapBorderHex: 0xFFFFFF, attribution: attribution,
            poiIconHex: 0x4A4D55, poiOutlineHex: 0xFFFFFF, supportsBuildings3D: true)
    )

    static let rutasRally = MapTheme(
        id: .rutasRally, name: MapStyleNames.name(for: .rutasRally),
        tagline: "Terreno vivo, carreteras claras y caminos de tierra discontinuos.",
        isDark: true,
        background: Color(hex: 0x131A12), panel: Color(hex: 0x1D2619, opacity: 0.95),
        panelBorder: Color(hex: 0xFF7A00, opacity: 0.65), accent: Color(hex: 0xFF7A00),
        textPrimary: Color(hex: 0xF7F5EC), textSecondary: Color(hex: 0xB3BFA6),
        routeCore: Color(hex: 0xFF7A00), routeBorder: Color(hex: 0xFFFFFF),
        destination: Color(hex: 0xFF7A00), player: Color(hex: 0xFFFFFF),
        titleDesign: .rounded, iconWeight: .heavy, cornerRadius: 14,
        poiIcons: [.fuel: "fuelpump.fill", .food: "fork.knife", .parking: "parkingsign", .hospital: "cross.fill",
                   .police: "shield.fill", .shop: "bag.fill", .poi: "mappin", .quest: "flag.checkered"],
        cartography: CartographyStyle(
            resourceName: "style-rutas-rally", backgroundHex: 0x6E8F45, userArrowHex: 0xFFFFFF,
            defaultZoom: 15, navigationZoom: 16.5, navigationPitch: 0,
            minimapZoom: 16, minimapShape: .circle, minimapBorderHex: 0xFFFFFF, attribution: attribution,
            poiIconHex: 0xFFFFFF, poiOutlineHex: 0x1D241A)
    )

    static let retroArcade = MapTheme(
        id: .retroArcade, name: MapStyleNames.name(for: .retroArcade),
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
