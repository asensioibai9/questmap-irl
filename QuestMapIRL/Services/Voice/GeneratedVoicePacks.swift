import Foundation

/// Paquetes de voz GENERADOS (ElevenLabs) incluidos en la app. Son otro origen de los mismos fragmentos que los perfiles
/// grabados por el usuario: mismas frases (`VoicePhraseID`), mismo compositor, misma cola y mismo reproductor. Durante la
/// ruta no se hace ninguna petición a ningún servicio: los audios van dentro de la app.
///
/// Los audios y su índice (`<slug>.voicepack.json`) los produce `tools/elevenlabs_voice_pack.py build`. Si una versión de
/// la app no los incluye, el paquete se muestra como «No incluida en esta versión» y nunca como lista para usar.
struct GeneratedVoicePackInfo: Identifiable, Equatable, Hashable {
    let id: String
    /// Prefijo de los archivos en el bundle (el bundle se copia plano: los nombres no pueden repetirse entre paquetes).
    let slug: String
    let title: String
    let gender: NavigationVoiceGender
    let languageCode: String
    let languageLabel: String
    let summary: String
    /// Aviso de transparencia: es una voz sintética.
    let provenance: String
}

enum GeneratedVoicePacks {
    static let all: [GeneratedVoicePackInfo] = [
        GeneratedVoicePackInfo(id: "elevenlabs-es-femenina", slug: "elf", title: "Voz generada · chica", gender: .girl,
                               languageCode: "es-ES", languageLabel: "Español (España)",
                               summary: "Voz femenina calmada y clara para indicaciones breves.",
                               provenance: "Voz generada con IA (ElevenLabs)"),
        GeneratedVoicePackInfo(id: "elevenlabs-es-masculina", slug: "elm", title: "Voz generada · chico", gender: .boy,
                               languageCode: "es-ES", languageLabel: "Español (España)",
                               summary: "Voz masculina calmada y clara para indicaciones breves.",
                               provenance: "Voz generada con IA (ElevenLabs)"),
    ]

    static func info(id: String) -> GeneratedVoicePackInfo? { all.first { $0.id == id } }

    /// Frases de la muestra «Escuchar muestra» (la misma que la prueba de la voz del sistema).
    static let demoPhrases: [VoicePhraseID] = [.in200m, .turnRight]
}

/// Índice de un paquete tal como lo escribe la herramienta de generación.
struct GeneratedVoicePackIndex: Decodable {
    struct Entry: Decodable {
        let file: String
        let start: Double
        let end: Double
        let gain: Double
    }
    let format: Int
    let id: String
    let catalogVersion: Int
    let voiceName: String?
    let phrases: [String: Entry]

    enum CodingKeys: String, CodingKey {
        case format, id, phrases
        case catalogVersion = "catalog_version"
        case voiceName = "voice_name"
    }
}

enum GeneratedVoicePackAvailability: Equatable {
    case ready
    /// Hay audios, pero faltan frases obligatorias.
    case incomplete(missingRequired: Int)
    /// Esta versión de la app no trae el paquete.
    case notIncluded
    /// El índice no se puede leer o no corresponde a este paquete.
    case damaged

    var isReady: Bool { self == .ready }

    var label: String {
        switch self {
        case .ready: return "Lista para usar"
        case .incomplete(let missing): return "No disponible: faltan \(missing) frases obligatorias"
        case .notIncluded: return "No incluida en esta versión"
        case .damaged: return "No disponible: paquete dañado"
        }
    }
}

struct LoadedGeneratedVoicePack {
    let info: GeneratedVoicePackInfo
    let availability: GeneratedVoicePackAvailability
    /// Solo frases con archivo existente y tiempos válidos.
    let segments: [VoicePhraseID: VoicePromptSegment]
    let voiceName: String?

    var demoSegments: [VoicePromptSegment] {
        let demo = GeneratedVoicePacks.demoPhrases.compactMap { segments[$0] }
        return demo.count == GeneratedVoicePacks.demoPhrases.count ? demo : []
    }
}

/// Lee los paquetes del bundle UNA vez (el bundle no cambia mientras la app está abierta). No carga audio en memoria: solo
/// el índice y la comprobación de que cada archivo existe. El audio se lee al reproducir cada indicación.
@MainActor
final class GeneratedVoicePackLoader {
    static let shared = GeneratedVoicePackLoader(resourceURL: Bundle.main.resourceURL)

    private let resourceURL: URL?
    private let fileManager: FileManager
    private var cache: [String: LoadedGeneratedVoicePack] = [:]

    init(resourceURL: URL?, fileManager: FileManager = .default) {
        self.resourceURL = resourceURL
        self.fileManager = fileManager
    }

    func pack(_ info: GeneratedVoicePackInfo) -> LoadedGeneratedVoicePack {
        if let cached = cache[info.id] { return cached }
        let loaded = PerformanceTrace.measure("voice-pack-load", thresholdMs: 30) { load(info) }
        cache[info.id] = loaded
        return loaded
    }

    func pack(id: String) -> LoadedGeneratedVoicePack? {
        GeneratedVoicePacks.info(id: id).map(pack)
    }

    private func load(_ info: GeneratedVoicePackInfo) -> LoadedGeneratedVoicePack {
        func result(_ availability: GeneratedVoicePackAvailability, _ segments: [VoicePhraseID: VoicePromptSegment] = [:],
                    _ voiceName: String? = nil) -> LoadedGeneratedVoicePack {
            LoadedGeneratedVoicePack(info: info, availability: availability, segments: segments, voiceName: voiceName)
        }
        guard let base = resourceURL else { return result(.notIncluded) }
        let indexURL = base.appendingPathComponent("\(info.slug).voicepack.json")
        guard fileManager.fileExists(atPath: indexURL.path) else { return result(.notIncluded) }
        let index: GeneratedVoicePackIndex
        do {
            index = try JSONDecoder().decode(GeneratedVoicePackIndex.self, from: Data(contentsOf: indexURL))
        } catch {
            StorageDiagnostics.record(operation: "voice-pack-index", outcome: "error", note: info.id)
            return result(.damaged)
        }
        guard index.id == info.id, index.format == 1 else { return result(.damaged) }

        var segments: [VoicePhraseID: VoicePromptSegment] = [:]
        for (raw, entry) in index.phrases {
            guard let phrase = VoicePhraseID(rawValue: raw),
                  !entry.file.contains("/"), entry.file.hasPrefix("\(info.slug)-"),
                  entry.end > entry.start, entry.start >= 0, (0.1...4).contains(entry.gain) else { continue }
            let url = base.appendingPathComponent(entry.file)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            segments[phrase] = VoicePromptSegment(url: url, start: entry.start, end: entry.end, gain: entry.gain)
        }
        let missing = VoicePromptCatalog.requiredIDs(language: info.languageCode).subtracting(segments.keys).count
        if segments.isEmpty { return result(.incomplete(missingRequired: missing)) }
        return result(missing == 0 ? .ready : .incomplete(missingRequired: missing), segments, index.voiceName)
    }
}

extension UserSettings {
    private static let packPrefix = "pack:"

    /// Paquete generado activo. Comparte campo con el perfil grabado activo, así que elegir uno deselecciona el otro y la
    /// elección se guarda igual que hasta ahora (sin cambiar el esquema de datos).
    var activeGeneratedVoicePackID: String? {
        get {
            activeVoiceProfileRaw.hasPrefix(Self.packPrefix) ? String(activeVoiceProfileRaw.dropFirst(Self.packPrefix.count)) : nil
        }
        set { activeVoiceProfileRaw = newValue.map { Self.packPrefix + $0 } ?? "" }
    }

    /// Ni perfil grabado ni paquete generado: voz del sistema.
    var usesSystemVoice: Bool { activeVoiceProfileID == nil && activeGeneratedVoicePackID == nil }
}
