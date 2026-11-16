import Foundation

/// Proveedor de datos vectoriales. Los valores NO son secretos (el proveedor por defecto no usa
/// claves); si se cambia a uno con clave, debe inyectarse desde configuración, nunca escribirse
/// en el repositorio.
struct MapProviderConfig: Equatable {
    /// URL del TileJSON de los tiles vectoriales (esquema OpenMapTiles).
    var tilesURL: String
    /// Plantilla de glyphs con {fontstack} y {range}.
    var glyphsURL: String

    /// Instancia pública de OpenFreeMap. Sin SLA y puede discontinuarse: válida para desarrollo,
    /// no una base sólida para una app publicada (ver docs/07-auditoria-cartografia.md).
    static let openFreeMap = MapProviderConfig(
        tilesURL: "https://tiles.openfreemap.org/planet",
        glyphsURL: "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
    )

    var isComplete: Bool {
        !tilesURL.isEmpty && glyphsURL.contains("{fontstack}") && glyphsURL.contains("{range}")
    }
}

enum StyleError: LocalizedError, Equatable {
    case providerNotConfigured
    case resourceMissing(String)
    case invalidStyle(String)
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            return "Falta la configuración del proveedor de mapas (URL de tiles y glyphs)."
        case .resourceMissing(let name):
            return "No se encuentra el estilo de mapa «\(name)» en la app."
        case .invalidStyle(let reason):
            return "El estilo de mapa no es válido: \(reason)."
        case .cannotWrite:
            return "No se pudo preparar el estilo de mapa en el dispositivo."
        }
    }
}

/// Carga el JSON del estilo, sustituye las URLs del proveedor, lo valida y devuelve una URL de
/// archivo que MapLibre puede cargar. Los errores se devuelven claros en vez de un mapa en blanco.
struct StyleManager {
    var provider: MapProviderConfig = .openFreeMap
    var bundle: Bundle = .main

    func styleURL(for style: CartographyStyle) throws -> URL {
        guard provider.isComplete else { throw StyleError.providerNotConfigured }
        guard let source = bundle.url(forResource: style.resourceName, withExtension: "json") else {
            throw StyleError.resourceMissing(style.resourceName)
        }
        let resolved = try Self.resolve(Data(contentsOf: source), provider: provider)

        do {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("QuestMapStyles", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("\(style.resourceName).json")
            try resolved.write(to: destination, options: .atomic)
            return destination
        } catch {
            throw StyleError.cannotWrite
        }
    }

    /// Sustituye los marcadores y valida la estructura mínima de un estilo v8.
    static func resolve(_ data: Data, provider: MapProviderConfig) throws -> Data {
        guard provider.isComplete else { throw StyleError.providerNotConfigured }
        guard var text = String(data: data, encoding: .utf8) else { throw StyleError.invalidStyle("codificación") }
        text = text
            .replacingOccurrences(of: "{{TILES_URL}}", with: provider.tilesURL)
            .replacingOccurrences(of: "{{GLYPHS_URL}}", with: provider.glyphsURL)
        if text.contains("{{") { throw StyleError.invalidStyle("quedan marcadores sin sustituir") }

        let object: Any
        do { object = try JSONSerialization.jsonObject(with: Data(text.utf8)) }
        catch { throw StyleError.invalidStyle("JSON mal formado") }

        guard let style = object as? [String: Any],
              style["version"] as? Int == 8,
              style["sources"] is [String: Any],
              let layers = style["layers"] as? [[String: Any]], !layers.isEmpty else {
            throw StyleError.invalidStyle("estructura incompleta")
        }
        return Data(text.utf8)
    }
}
