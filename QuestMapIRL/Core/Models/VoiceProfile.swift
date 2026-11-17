import Foundation
import SwiftData

/// Perfil de voz grabada por el usuario. Solo guarda metadatos: los audios están en archivos privados de la app
/// (ver `VoiceRecordingFiles`). REGLA del proyecto: toda propiedad lleva valor por defecto en el modelo.
@Model
final class VoiceProfile {
    /// Identificador estable (también nombra su carpeta de audios).
    var profileID: UUID = UUID()
    var name: String = ""
    var languageCode: String = VoicePromptCatalog.defaultLanguage
    var createdAt: Date = Date()
    /// Versión del catálogo con la que se creó o se revisó por última vez.
    var catalogVersion: Int = VoicePromptCatalog.version
    /// Símbolo del avatar (SF Symbol).
    var avatarSymbol: String = "person.wave.2.fill"

    init(name: String, languageCode: String = VoicePromptCatalog.defaultLanguage, avatarSymbol: String = "person.wave.2.fill") {
        self.profileID = UUID()
        self.name = name
        self.languageCode = languageCode
        self.createdAt = Date()
        self.catalogVersion = VoicePromptCatalog.version
        self.avatarSymbol = avatarSymbol
    }
}

/// Una grabación confirmada de una frase de un perfil. La clave es (perfil, id ESTABLE de la frase), nunca el texto.
@Model
final class VoiceRecording {
    var profileID: UUID = UUID()
    var phraseIDRaw: String = ""
    /// Ruta RELATIVA al directorio de voces de la app («<perfil>/<archivo>.m4a»).
    var relativePath: String = ""
    var duration: Double = 0
    var recordedAt: Date = Date()
    /// Inicio y fin de la voz dentro del archivo (sin silencios largos); el archivo original no se recorta.
    var speechStart: Double = 0
    var speechEnd: Double = 0
    /// Ganancia de reproducción para un volumen coherente entre frases (sin pasar de -1 dBFS de pico).
    var playbackGain: Double = 1

    init(profileID: UUID, phraseID: VoicePhraseID, relativePath: String, analysis: AudioAnalysis) {
        self.profileID = profileID
        self.phraseIDRaw = phraseID.rawValue
        self.relativePath = relativePath
        self.duration = analysis.duration
        self.recordedAt = Date()
        self.speechStart = analysis.speechStart
        self.speechEnd = analysis.speechEnd
        self.playbackGain = analysis.playbackGain
    }

    var phraseID: VoicePhraseID? { VoicePhraseID(rawValue: phraseIDRaw) }
}

extension UserSettings {
    /// Perfil de voz activo (nil = voz del sistema).
    var activeVoiceProfileID: UUID? {
        get { UUID(uuidString: activeVoiceProfileRaw) }
        set { activeVoiceProfileRaw = newValue?.uuidString ?? "" }
    }

    var voiceFallback: VoiceFallbackStrategy {
        get { VoiceFallbackStrategy(rawValue: voiceFallbackRaw) ?? .hybrid }
        set { voiceFallbackRaw = newValue.rawValue }
    }
}
