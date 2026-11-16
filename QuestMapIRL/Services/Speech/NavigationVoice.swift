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

/// Lo mínimo de `AVAudioSession` que usa la voz. Permite comprobar en tests qué se configura
/// sin depender de que el simulador deje modificar la sesión real.
protocol AudioSessionDriver {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: AudioSessionDriver {}

/// Sesión de audio real del sistema.
struct SystemAudioSession: AudioSessionControlling {
    var driver: AudioSessionDriver = AVAudioSession.sharedInstance()

    func configure() throws {
        try driver.setCategory(NavigationVoice.audioCategory, mode: NavigationVoice.audioMode,
                               options: NavigationVoice.audioOptions)
    }

    func activate() throws {
        try configure()
        try driver.setActive(true, options: [])
    }

    /// Devuelve el volumen a la música que se hubiera bajado.
    func deactivate() {
        try? driver.setActive(false, options: .notifyOthersOnDeactivation)
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

    /// true mientras suena la frase del botón "Escuchar prueba de voz".
    private(set) var isPlayingTest = false

    /// Mensaje si no se pudo activar el audio del iPhone (la voz podría no oírse).
    private(set) var audioProblem: String?

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
    /// Frases lanzadas que aún no han terminado ni se han cancelado (por identidad).
    @ObservationIgnored private var active: [ObjectIdentifier: AVSpeechUtterance] = [:]
    @ObservationIgnored private var testUtterance: ObjectIdentifier?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    /// Segundos que se espera a que el sintetizador avise de que terminó antes de dar la frase por perdida.
    @ObservationIgnored var watchdogSeconds: (String) -> Double = { max(8, Double($0.count) * 0.25 + 4) }

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
        delegate.onFinish = { [weak self] utterance in
            Task { @MainActor in self?.utteranceEnded(utterance) }
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

    /// Aviso claro cuando la voz usada no coincide exactamente con lo elegido; nil si coincide.
    var warning: String? {
        switch selection.match {
        case .exact:
            return nil
        case .exactOutsideSpain:
            return "No hay una voz de \(gender.label) de España instalada. Se está usando una voz de \(gender.label) de otra variante del español."
        case .fallbackSpain, .fallbackSpanish:
            return "No hay una voz de \(gender.label) en español instalada. Se está usando la mejor voz española disponible."
        case .noSpanishVoice:
            return "No hay ninguna voz en español instalada. Se está usando la voz predeterminada del sistema, que puede leer mal las indicaciones."
        }
    }

    /// Cómo conseguir mejores voces (se muestra junto al aviso).
    static let downloadHint = "Puedes descargar más voces en Ajustes › Accesibilidad › Contenido hablado › Voces › Español."

    // MARK: Hablar

    /// Lee una indicación. Cancela la que esté sonando (salvo `interrupt: false`) y no repite la
    /// misma frase dos veces seguidas.
    func announce(_ text: String, interrupt: Bool = true, allowRepeat: Bool = false) {
        guard !isMuted, !text.isEmpty else { return }
        speak(text, interrupt: interrupt, allowRepeat: allowRepeat)
    }

    /// Botón "Escuchar prueba de voz": suena siempre, aunque las indicaciones estén desactivadas.
    func playTest() {
        speak(Self.testPhrase, interrupt: true, allowRepeat: true, isTest: true)
    }

    /// El botón de prueba alterna entre reproducir y parar.
    func toggleTest() {
        if isPlayingTest { stopImmediately() } else { playTest() }
    }

    /// Para YA cualquier voz (también las pendientes) y libera la sesión de audio.
    func stopImmediately() {
        synthesizer.stopSpeaking(at: .immediate)
        active.removeAll()           // las cancelaciones tardías de estas frases se ignoran
        testUtterance = nil
        isPlayingTest = false
        lastSpoken = nil
        watchdog?.cancel()
        watchdog = nil
        session.deactivate()
    }

    /// Nombre histórico.
    func stop() { stopImmediately() }

    /// Si solo está sonando la prueba, la corta (p. ej. al salir de la pantalla de ajustes).
    func stopTestIfPlaying() {
        if isPlayingTest { stopImmediately() }
    }

    /// Fin de navegación sin cortar la frase que esté sonando (p. ej. "Has llegado a tu destino"):
    /// olvida la última frase para que la próxima ruta pueda repetirla. La sesión de audio se
    /// libera sola cuando termine la frase.
    func releaseAfterSpeaking() {
        lastSpoken = nil
        if active.isEmpty { session.deactivate() }
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted { stopImmediately() }
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

    private func speak(_ text: String, interrupt: Bool, allowRepeat: Bool, isTest: Bool = false) {
        if !allowRepeat, text == lastSpoken { return }
        lastSpoken = text
        do {
            try session.activate()
            audioProblem = nil
        } catch {
            // Se intenta hablar igualmente, pero se avisa en la interfaz.
            audioProblem = "No se pudo activar el audio del iPhone, así que puede que la voz no se oiga."
        }
        if interrupt {
            synthesizer.stopSpeaking(at: .immediate)
            active.removeAll()
            testUtterance = nil
            isPlayingTest = false
        }
        let utterance = makeUtterance(text)
        active[ObjectIdentifier(utterance)] = utterance
        if isTest {
            testUtterance = ObjectIdentifier(utterance)
            isPlayingTest = true
        }
        synthesizer.speak(utterance)
        armWatchdog(for: text)
    }

    /// Una frase terminó o se canceló. Si ya no queda ninguna, se libera la sesión de audio.
    func utteranceEnded(_ utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        guard active.removeValue(forKey: id) != nil else { return }   // cancelación tardía de una frase ya descartada
        if testUtterance == id {
            testUtterance = nil
            isPlayingTest = false
        }
        if active.isEmpty {
            watchdog?.cancel()
            watchdog = nil
            session.deactivate()
        }
    }

    /// AVSpeechSynthesizer no informa de errores: si no avisa de que terminó en un tiempo razonable
    /// y deja de hablar, se da la frase por perdida para no quedar en "Reproduciendo…" ni con la
    /// sesión de audio activa para siempre.
    private func armWatchdog(for text: String) {
        watchdog?.cancel()
        let seconds = watchdogSeconds(text)
        watchdog = Task { [weak self] in
            for _ in 0..<3 {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                if self.active.isEmpty { return }
                if !self.synthesizer.isSpeaking {
                    self.recoverFromStall()
                    return
                }
            }
            self?.recoverFromStall()   // sigue "hablando" mucho más de lo razonable
        }
    }

    private func recoverFromStall() {
        synthesizer.stopSpeaking(at: .immediate)
        active.removeAll()
        testUtterance = nil
        isPlayingTest = false
        lastSpoken = nil
        watchdog = nil
        session.deactivate()
    }
}

/// Avisa de que una frase terminó o se canceló, para liberar la sesión de audio.
private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: ((AVSpeechUtterance) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish?(utterance) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onFinish?(utterance) }
}

/// Nombre histórico usado por el resto de la app.
typealias SpeechService = NavigationVoice
