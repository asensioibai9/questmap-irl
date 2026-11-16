import Foundation

/// Nombres VISIBLES de los estilos, centralizados. Cada estilo se llama como el videojuego que le sirve de REFERENCIA VISUAL.
/// Los identificadores internos (`MapThemeID.rawValue`, guardados en las preferencias de cada usuario) NO cambian: renombrar
/// un estilo es solo cambiar una línea aquí y no requiere migración.
///
/// Correspondencia (antes → ahora):
/// - ciudadNocturna: «Ciudad nocturna» → GTA V
/// - islaRoyale: «Isla» → Fortnite
/// - mundoBloques: «Mundo de bloques» → Minecraft
/// - salvajeOeste: «Mapa del salvaje oeste» → Red Dead Redemption 2
/// - ciudadCiber: «Ciudad ciber» → Cyberpunk 2077
/// - mapaFantasia: «Mapa de fantasía» → Skyrim
/// - redUrbana: «Red urbana» → Watch Dogs 2
/// - rutasRally: «Rutas de rally» → Forza Horizon 5
/// - minimalistaPro: «Minimalista Pro» (estilo propio, sin juego de referencia: no cambia)
/// - retroArcade: placeholder sin cartografía; no aparece en el selector
enum MapStyleNames {
    static func name(for id: MapThemeID) -> String {
        switch id {
        case .ciudadNocturna: return "GTA V"
        case .islaRoyale: return "Fortnite"
        case .mundoBloques: return "Minecraft"
        case .salvajeOeste: return "Red Dead Redemption 2"
        case .ciudadCiber: return "Cyberpunk 2077"
        case .mapaFantasia: return "Skyrim"
        case .redUrbana: return "Watch Dogs 2"
        case .rutasRally: return "Forza Horizon 5"
        case .minimalistaPro: return "Minimalista Pro"
        case .retroArcade: return "Retro arcade"
        }
    }

    /// Aviso que acompaña a los nombres de videojuegos.
    static let disclaimer = "Los nombres de videojuegos identifican solo la referencia visual de cada estilo. QuestMap IRL no es oficial ni está patrocinada ni afiliada a esos juegos ni a sus titulares; no usa logotipos ni recursos de ellos. Todos los estilos son gratuitos."
}
