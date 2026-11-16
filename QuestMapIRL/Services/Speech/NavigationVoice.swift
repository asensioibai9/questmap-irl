import AVFoundation
import Observation

// MARK: - Voz elegida por el usuario

enum NavigationVoiceGender: String, CaseIterable, Identifiable {
    case girl, boy

    var id: String { rawValue }
    /// Texto del selector.
    var title: String { self == .girl ? "Chica" : "Chico" }
    /// Texto en minúscula para frases ("Voz actual: española — chica").
    var label: String { self == .girl ? "chica" : "chico" }
    /// Tono (pitchMultiplier): algo más agudo para chica y algo más grave para chico.
    var pitch: Float { self == .girl ? 1.08 : 0.9 }
}

// MARK: - Catálogo y selección de voces (lógica pura, comprobable sin dispositivo)

/// Resumen de una voz instalada. Se separa de `AVSpeechSynthesisVoice` para poder probar la selección.
struct VoiceInfo: Equatable {
    let identifier: String
    let name: String
    let language: String
    /// 1 = estándar, 2 = mejorada, 3 = premium.
    let quality: Int
    /// nil si el sistema no declara el género y el nombre no es reconocible.
    let gender: NavigationVoiceGender?

    init(identifier: String, name: String, language: String, quality: Int, gender: NavigationVoiceGender?) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.quality = quality
        self.gender = gender
    }

    init(_ voice: AVSpeechSynthesisVoice) {
        let quality: Int
        switch voice.quality {
        case .premium: quality = 3
        case .enhanced: quality = 2
        default: quality = 1
        }
        var gender: NavigationVoiceGender?
        switch voice.gender {
        case .female: gender = .girl
        case .male: gender = .boy
        default: gender = Self.genderFromName(voice.name)
        }
        self.init(identifier: voice.identifier, name: voice.name, language: voice.language, quality: quality, gender: gender)
    }

    /// Respaldo cuando el sistema no declara el género: nombres de voces españolas de Apple conocidos.
    static func genderFromName(_ name: String) -> NavigationVoiceGender? {
        let lower = name.lowercased()
        let female = ["mónica", "monica", "marisol", "paulina", "soledad", "angélica", "angelica", "francisca", "luciana", "ximena"]
        let male = ["jorge", "juan", "diego", "carlos", "enrique", "tomás", "tomas"]
        if female.contains(where: { lower.contains($0) }) { return .girl }
        if male.contains(where: { lower.contains($0) }) { return .boy }
        return nil
    }
}

/// Resultado de elegir voz y qué tan cerca está de lo que pidió el usuario.
struct VoiceSelection: Equatable {
    enum Match: Equatable {
        /// Voz de España del género pedido.
        case exact
        /// Voz del género pedido, pero de otra variante del español (México, Argentina…).
        case exactOutsideSpain
        /// Hay voces de España, pero ninguna del género pedido.
        case fallbackSpain
        /// Solo hay voces españolas de otras regiones y ninguna del género pedido.
        case fallbackSpanish
        /// No hay ninguna voz en español instalada.
        case noSpanishVoice
    }

    let voice: VoiceInfo?
    let match: Match
}

enum VoiceSelector {
    /// Prefiere es-ES del género pedido; luego mejor calidad. Si no existe, la mejor voz española
    /// disponible, y lo indica en `match` para que la interfaz avise.
    static func select(from voices: [VoiceInfo], gender: NavigationVoiceGender) -> VoiceSelection {
        let spain = voices.filter { $0.language == "es-ES" }
        let spanish = voices.filter { $0.language.hasPrefix("es") }

        if let voice = best(spain.filter { $0.gender == gender }) { return VoiceSelection(voice: voice, match: .exact) }
        if let voice = best(spanish.filter { $0.gender == gender }) { return VoiceSelection(voice: voice, match: .exactOutsideSpain) }
        if let voice = best(spain) { return VoiceSelection(voice: voice, match: .fallbackSpain) }
        if let voice = best(spanish) { return VoiceSelection(voice: voice, match: .fallbackSpanish) }
        return VoiceSelection(voice: nil, match: .noSpanishVoice)
    }

    private static func best(_ voices: [VoiceInfo]) -> VoiceInfo? {
        voices.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            return $0.identifier < $1.identifier       // desempate estable
        }.first
    }
}

// MARK: - Dependencias sustituibles (para pruebas)

protocol SpeechSynthesizing: AnyObject {
    var isSpeaking: Bool { get }
    func speak(_ utterance: AVSpeechUtterance)
    @discardableResult func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechSynthesizing {}

protocol AudioSessionControlling {
    /// Fija categoría, modo y opciones (sin activar).
    func configure() throws
    func activate() throws
    func deactivate()
}

/// Sesión de audio real del sistema.
struct SystemAudioSession: AudioSessionControlling {
    func configure() throws {
        try AVAudioSession.sharedInstance().setCategory(
            NavigationVoice.audioCategory, mode: NavigationVoice.audioMode, options: NavigationVoice.audioOptions)
    }

    func activate() throws {
        try configure()
        try AVAudioSession.sharedInstance().setActive(true)
    }

    /// Devuelve el volumen a la música que se hubiera bajado.
    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Voz de navegación

/// Lee en voz alta las indicaciones del mapa con las voces nativas de iOS (AVSpeechSynthesizer).
/// Sin servicios externos, claves ni pagos.
///
/// RECOMENDACIÓN (no integrada): una voz neuronal más natural exigiría una descarga de modelo o un
/// servicio con cuenta/clave (p. ej. un modelo Piper/Sherpa-ONNX empaquetado, de unos 20-80 MB por
/// voz, o un TTS en la nube de pago). Se deja la voz nativa como solución principal; ver
/// docs/11-voz-de-navegacion.md.
@MainActor
@Observable
final class NavigationVoice {
    static let testPhrase = "Prueba de voz. En doscientos metros, gira a la derecha."
    static let defaultRate: Float = 0.48

    /// Sesión de audio: suena aunque el iPhone esté en silencio y baja la música mientras habla.
    static let audioCategory: AVAudioSession.Category = .playback
    static let audioMode: AVAudioSession.Mode = .spokenAudio
    static let audioOptions: AVAudioSession.CategoryOptions = [.duckOthers]

    static let genderKey = "questmap.navigationVoiceGender"
    static let volumeKey = "questmap.voiceVolume"

    var isMuted = false

    /// Chica o chico. Se guarda al instante y se aplica a la siguiente indicación.
    var gender: NavigationVoiceGender {
        didSet { defaults.set(gender.rawValue, forKey: Self.genderKey) }
    }

    /// Volumen de las indicaciones, de 0 a 1 (relativo al volumen del sistema).
    var volume: Float {
        didSet { defaults.set(volume, forKey: Self.volumeKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let synthesizer: SpeechSynthesizing
    @ObservationIgnored private let session: AudioSessionControlling
    @ObservationIgnored private let voices: () -> [VoiceInfo]
    @ObservationIgnored private let delegate: SynthesizerDelegate
    @ObservationIgnored private var lastSpoken: String?
    @ObservationIgnored private var pending = 0

    init(defaults: UserDefaults = .standard,
         synthesizer: SpeechSynthesizing? = nil,
         session: AudioSessionControlling = SystemAudioSession(),
         voices: @escaping () -> [VoiceInfo] = NavigationVoice.installedVoices) {
        let delegate = SynthesizerDelegate()
        self.delegate = delegate
        self.defaults = defaults
        self.session = session
        self.voices = voices
        gender = NavigationVoiceGender(rawValue: defaults.string(forKey: Self.genderKey) ?? "") ?? .girl
        volume = defaults.object(forKey: Self.volumeKey) as? Float ?? 1

        if let synthesizer {
            self.synthesizer = synthesizer
        } else {
            let real = AVSpeechSynthesizer()
            real.delegate = delegate
            self.synthesizer = real
        }
        delegate.onFinish = { [weak self] in
            Task { @MainActor in self?.utteranceEnded() }
        }
        try? session.configure()
    }

    nonisolated static func installedVoices() -> [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices().map(VoiceInfo.init)
    }

    // MARK: Estado para la interfaz

    var selection: VoiceSelection { VoiceSelector.select(from: voices(), gender: gender) }

    /// "Voz actual: española — chica".
    var statusText: String {
        let current = selection
        guard let voice = current.voice else { return "Voz actual: predeterminada del sistema" }
        switch current.match {
        case .exact: return "Voz actual: española — \(gender.label) (\(voice.name))"
        case .exactOutsideSpain: return "Voz actual: española de otra región — \(gender.label) (\(voice.name))"
        default: return "Voz actual: española (\(voice.name))"
        }
    }

    /// Aviso cuando no se puede cumplir exactamente lo pedido.
    var warning: String? {
        let tip = "Puedes descargar más voces en Ajustes › Accesibilidad › Contenido hablado › Voces › Español."
        switch selection.match {
        case .exact: return nil
        case .exactOutsideSpain: return "No hay una voz de \(gender.label) de España instalada; se usa una de otra región. \(tip)"
        case .fallbackSpain, .fallbackSpanish: return "No hay una voz de \(gender.label) instalada; se usa la mejor voz española disponible. \(tip)"
        case .noSpanishVoice: return "No hay voces en español instaladas; se usa la voz predeterminada del sistema. \(tip)"
        }
    }

    // MARK: Hablar

    /// Lee una indicación. Cancela la que esté sonando (salvo `interrupt: false`) y no repite la
    /// misma frase dos veces seguidas.
    func announce(_ text: String, interrupt: Bool = true, allowRepeat: Bool = false) {
        guard !isMuted, !text.isEmpty else { return }
        speak(text, interrupt: interrupt, allowRepeat: allowRepeat)
    }

    /// Botón "Escuchar prueba de voz": suena siempre, aunque las indicaciones estén desactivadas.
    func playTest() {
        speak(Self.testPhrase, interrupt: true, allowRepeat: true)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lastSpoken = nil
        pending = 0
        session.deactivate()
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted { stop() }
    }

    /// Borra las preferencias guardadas y vuelve a los valores iniciales.
    func resetPreferences() {
        gender = .girl
        volume = 1
        defaults.removeObject(forKey: Self.genderKey)
        defaults.removeObject(forKey: Self.volumeKey)
    }

    // MARK: Privado

    /// Utterance con la voz, velocidad, tono y volumen vigentes. Se lee en cada indicación, así que
    /// un cambio de voz se aplica a la siguiente.
    func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        if let info = selection.voice, let voice = AVSpeechSynthesisVoice(identifier: info.identifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        }
        utterance.rate = Self.defaultRate
        utterance.pitchMultiplier = gender.pitch
        utterance.volume = volume
        utterance.preUtteranceDelay = 0.05
        return utterance
    }

    private func speak(_ text: String, interrupt: Bool, allowRepeat: Bool) {
        if !allowRepeat, text == lastSpoken { return }
        lastSpoken = text
        try? session.activate()
        if interrupt { synthesizer.stopSpeaking(at: .immediate) }
        pending += 1
        synthesizer.speak(makeUtterance(text))
    }

    private func utteranceEnded() {
        pending = max(0, pending - 1)
        if pending == 0 { session.deactivate() }
    }
}

/// Avisa de que una frase terminó o se canceló, para liberar la sesión de audio.
private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish?() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onFinish?() }
}

/// Nombre histórico usado por el resto de la app.
typealias SpeechService = NavigationVoice
