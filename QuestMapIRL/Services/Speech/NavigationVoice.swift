import AVFoundation
import Observation
import UIKit

// MARK: - Voz elegida por el usuario

enum NavigationVoiceGender: String, CaseIterable, Identifiable {
    case girl, boy

    var id: String { rawValue }
    /// Texto del selector.
    var title: String { self == .girl ? "Chica" : "Chico" }
    /// Texto en minúscula para frases ("Voz actual: española — chica").
    var label: String { self == .girl ? "chica" : "chico" }
    /// Tono (pitchMultiplier). Se usa el tono NATURAL de la voz para las dos opciones: cambiar el
    /// tono para "simular" chica o chico empeora la naturalidad. El género lo da la voz elegida.
    var pitch: Float { 1.0 }
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

    /// "Estándar", "Mejorada" o "Premium" (la calidad que declara iOS para esa voz).
    var qualityLabel: String {
        switch quality {
        case 3: return "Premium"
        case 2: return "Mejorada"
        default: return "Estándar"
        }
    }

    /// Idioma y región como los devuelve iOS (p. ej. "es-ES").
    var languageLabel: String { language }

    /// Voces de efecto o broma que iOS instala en español y que no valen para dar indicaciones.
    var isNovelty: Bool {
        ["grandma", "grandpa", "bubbles", "bahh", "bells", "boing", "cellos", "organ", "whisper", "wobble",
         "zarvox", "trinoids", "jester", "superstar", "deranged", "hysterical"].contains { name.lowercased().contains($0) }
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
        /// Voz elegida a mano por el usuario, cuyo género coincide con el pedido.
        case chosen
        /// Voz elegida a mano cuyo género iOS no declara: la responsabilidad de la elección es del usuario.
        case chosenGenderUnknown
        /// Hay voces de España, pero ninguna del género pedido.
        case fallbackSpain
        /// Solo hay voces españolas de otras regiones y ninguna del género pedido.
        case fallbackSpanish
        /// No hay ninguna voz en español instalada.
        case noSpanishVoice
    }

    let voice: VoiceInfo?
    let match: Match
    /// La voz que el usuario había elegido ya no está instalada (se usa la automática).
    var preferredMissing = false
}

enum VoiceSelector {
    /// Voces españolas útiles para navegar (sin voces de efecto), ordenadas: España primero,
    /// después mayor calidad y por último nombre.
    static func spanishVoices(_ voices: [VoiceInfo]) -> [VoiceInfo] {
        voices.filter { $0.language.hasPrefix("es") && !$0.isNovelty }.sorted {
            let aSpain = $0.language == "es-ES", bSpain = $1.language == "es-ES"
            if aSpain != bSpain { return aSpain }
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            return ($0.name, $0.identifier) < ($1.name, $1.identifier)
        }
    }

    /// Voces que el usuario puede elegir para un género: las que iOS declara de ese género y, aparte,
    /// las de género no declarado. Nunca se incluyen voces del género contrario.
    static func choices(from voices: [VoiceInfo], gender: NavigationVoiceGender) -> (matching: [VoiceInfo], unspecified: [VoiceInfo]) {
        let spanish = spanishVoices(voices)
        return (spanish.filter { $0.gender == gender }, spanish.filter { $0.gender == nil })
    }

    /// Prefiere la voz elegida a mano (si sigue instalada y no es del género contrario); si no, es-ES del
    /// género pedido con mayor calidad; si tampoco existe, la mejor voz española disponible, y lo indica
    /// en `match` para que la interfaz avise.
    static func select(from voices: [VoiceInfo], gender: NavigationVoiceGender, preferredID: String? = nil) -> VoiceSelection {
        let spanish = spanishVoices(voices)
        var missing = false

        if let preferredID {
            if let chosen = spanish.first(where: { $0.identifier == preferredID }),
               chosen.gender == gender || chosen.gender == nil {
                return VoiceSelection(voice: chosen, match: chosen.gender == nil ? .chosenGenderUnknown : .chosen)
            }
            missing = true
        }

        let spain = spanish.filter { $0.language == "es-ES" }
        var result: VoiceSelection
        if let voice = spain.first(where: { $0.gender == gender }) {
            result = VoiceSelection(voice: voice, match: .exact)
        } else if let voice = spanish.first(where: { $0.gender == gender }) {
            result = VoiceSelection(voice: voice, match: .exactOutsideSpain)
        } else if let voice = spain.first {
            result = VoiceSelection(voice: voice, match: .fallbackSpain)
        } else if let voice = spanish.first {
            result = VoiceSelection(voice: voice, match: .fallbackSpanish)
        } else {
            result = VoiceSelection(voice: nil, match: .noSpanishVoice)
        }
        result.preferredMissing = missing
        return result
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

    static func voiceKey(for gender: NavigationVoiceGender) -> String { "questmap.voiceID.\(gender.rawValue)" }

    var isMuted = false

    /// true mientras suena la frase del botón "Escuchar prueba de voz".
    private(set) var isPlayingTest = false

    /// Mensaje si no se pudo activar el audio del iPhone (la voz podría no oírse).
    private(set) var audioProblem: String?

    /// Cambia cuando se actualiza la lista de voces instaladas (al volver a la app o al descargar una).
    private(set) var voiceRevision = 0

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
    /// Identificador de la última voz pedida al sintetizador (para comprobar que coincide con la mostrada).
    @ObservationIgnored private(set) var lastRequestedVoiceID: String?
    /// Frases lanzadas que aún no han terminado ni se han cancelado (por identidad).
    @ObservationIgnored private var active: [ObjectIdentifier: AVSpeechUtterance] = [:]
    @ObservationIgnored private var testUtterance: ObjectIdentifier?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    /// Segundos que se espera a que el sintetizador avise de que terminó antes de dar la frase por perdida.
    @ObservationIgnored var watchdogSeconds: (String) -> Double = { max(8, Double($0.count) * 0.25 + 4) }

    // MARK: Voz grabada (perfiles del usuario)

    /// Perfil de voz grabada activo en este momento (nil = voz del sistema). Lo conecta la app; se consulta en cada
    /// indicación, así que un cambio de perfil se aplica a la siguiente.
    @ObservationIgnored var recordedVoice: (() -> RecordedVoiceSource?)?
    @ObservationIgnored private let recordedPlayer: RecordedPromptPlaying
    /// Indicaciones esperando a que termine la actual (como mucho 2: no se encolan tantas que lleguen tarde).
    @ObservationIgnored private var queue: [PendingOutput] = []
    @ObservationIgnored private var recordedIsTest = false
    @ObservationIgnored private var recordedWatchdog: Task<Void, Never>?
    /// true mientras se corta lo que suena para dar paso a una indicación nueva (no se libera el audio entre medias).
    @ObservationIgnored private var replacing = false
    static let maxQueued = 2

    private enum PendingOutput {
        case system(String)
        case recordings([VoicePromptSegment], fallback: String?)
    }

    init(defaults: UserDefaults = .standard,
         synthesizer: SpeechSynthesizing? = nil,
         session: AudioSessionControlling = SystemAudioSession(),
         voices: @escaping () -> [VoiceInfo] = NavigationVoice.installedVoices,
         observeSystemEvents: Bool = true,
         recordedPlayer: RecordedPromptPlaying? = nil) {
        let delegate = SynthesizerDelegate()
        self.delegate = delegate
        self.defaults = defaults
        self.session = session
        self.voices = voices
        self.recordedPlayer = recordedPlayer ?? RecordedPromptPlayer()
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

        if observeSystemEvents {
            // La lista de voces se vuelve a leer al volver a la app y cuando iOS avisa de cambios.
            let center = NotificationCenter.default
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshVoices() }
            }
            center.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshVoices() }
            }
        }
    }

    /// Fuerza a la interfaz a releer las voces instaladas.
    func refreshVoices() { voiceRevision += 1 }

    /// Voces instaladas, leídas UNA vez por revisión. `AVSpeechSynthesisVoice.speechVoices()` es lento (enumera todas las
    /// voces del sistema) y antes se llamaba varias veces en cada redibujado de Ajustes de navegación: cualquier cambio de
    /// un ajuste congelaba la interfaz. Se vuelve a leer al volver a la app o cuando iOS avisa de voces nuevas.
    @ObservationIgnored private var cachedVoices: (revision: Int, list: [VoiceInfo])?

    private var installedVoiceList: [VoiceInfo] {
        let revision = voiceRevision                 // dependencia de observación: la interfaz se actualiza al refrescar
        if let cachedVoices, cachedVoices.revision == revision { return cachedVoices.list }
        let list = PerformanceTrace.measure("installed-voices") { voices() }
        cachedVoices = (revision, list)
        return list
    }

    nonisolated static func installedVoices() -> [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices().map(VoiceInfo.init)
    }

    // MARK: Estado para la interfaz

    /// Voz elegida a mano para un género (nil = automática).
    func preferredVoiceID(for gender: NavigationVoiceGender) -> String? {
        defaults.string(forKey: Self.voiceKey(for: gender))
    }

    /// Elige una voz concreta para un género (nil vuelve a la automática). Se aplica a la siguiente frase.
    func setPreferredVoice(_ identifier: String?, for gender: NavigationVoiceGender) {
        if let identifier { defaults.set(identifier, forKey: Self.voiceKey(for: gender)) }
        else { defaults.removeObject(forKey: Self.voiceKey(for: gender)) }
        voiceRevision += 1
    }

    /// Voces instaladas entre las que elegir para el género actual.
    var voiceChoices: (matching: [VoiceInfo], unspecified: [VoiceInfo]) {
        VoiceSelector.choices(from: installedVoiceList, gender: gender)
    }

    /// Voz real que se usará, calculada con la misma lógica que `makeUtterance`.
    var selection: VoiceSelection {
        VoiceSelector.select(from: installedVoiceList, gender: gender, preferredID: preferredVoiceID(for: gender))
    }

    /// Solo hay voces de calidad estándar de España (las más robóticas) para el género actual.
    var onlyBasicVoicesInstalled: Bool {
        let spain = VoiceSelector.spanishVoices(installedVoiceList).filter { $0.language == "es-ES" }
        return !spain.isEmpty && !spain.contains { $0.quality >= 2 }
    }

    /// "Voz actual: española — chica (Mónica)".
    var statusText: String {
        let current = selection
        guard let voice = current.voice else { return "Voz actual: predeterminada del sistema" }
        switch current.match {
        case .exact, .chosen: return "Voz actual: española — \(gender.label) (\(voice.name))"
        case .exactOutsideSpain: return "Voz actual: española de otra región — \(gender.label) (\(voice.name))"
        default: return "Voz actual: española (\(voice.name))"
        }
    }

    /// Nombre, idioma y calidad REALES de la voz que se va a usar (lo mismo que recibe el sintetizador).
    var voiceDetails: String? {
        guard let voice = selection.voice else { return nil }
        return "\(voice.name) · \(voice.languageLabel) · \(voice.qualityLabel)"
    }

    /// Aviso claro cuando la voz usada no coincide exactamente con lo elegido; nil si coincide.
    var warning: String? {
        let current = selection
        var parts: [String] = []
        if current.preferredMissing {
            parts.append("La voz que habías elegido ya no está instalada. Se usa la automática.")
        }
        switch current.match {
        case .exact, .chosen:
            break
        case .chosenGenderUnknown:
            parts.append("iOS no indica si esta voz es de \(gender.label) o del otro género: la has elegido tú.")
        case .exactOutsideSpain:
            parts.append("No hay una voz de \(gender.label) de España instalada. Se está usando una voz de \(gender.label) de otra variante del español.")
        case .fallbackSpain, .fallbackSpanish:
            parts.append("No hay una voz de \(gender.label) en español instalada. Se está usando la mejor voz española disponible.")
        case .noSpanishVoice:
            parts.append("No hay ninguna voz en español instalada. Se está usando la voz predeterminada del sistema, que puede leer mal las indicaciones.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Cómo conseguir mejores voces (se muestra junto al aviso).
    static let downloadHint = "Puedes descargar más voces en Ajustes › Accesibilidad › Contenido hablado › Voces › Español."

    // MARK: Hablar

    /// Lee una indicación. Cancela la que esté sonando (salvo `interrupt: false`) y no repite la
    /// misma frase dos veces seguidas.
    func announce(_ text: String, interrupt: Bool = true, allowRepeat: Bool = false) {
        // Mismo camino que las indicaciones con grabación: una sola cola y un solo motor sonando.
        announce(VoiceCue.text(text), interrupt: interrupt, allowRepeat: allowRepeat)
    }

    /// Indicación de navegación con posible versión grabada. Sin perfil activo, igual que `announce(String)`.
    /// - Con perfil: si la indicación se puede formar con grabaciones existentes, suena tu voz; si no, según el respaldo
    ///   elegido: la frase COMPLETA con la voz del sistema (híbrido) o nada (solo en pantalla). Nunca suenan las dos voces
    ///   a la vez ni se mezclan en una misma frase.
    func announce(_ cue: VoiceCue, interrupt: Bool = true, allowRepeat: Bool = false) {
        guard !isMuted, !cue.text.isEmpty else { return }
        if !allowRepeat, cue.text == lastSpoken { return }
        guard let source = recordedVoice?() else {
            speakOrQueue(.system(cue.text), interrupt: interrupt)
            return
        }
        switch VoicePlaybackPlanner.plan(cue, available: Set(source.segments.keys), strategy: source.strategy) {
        case .recordings(let ids):
            let fallback = source.strategy == .hybrid || source.fallbackOnFailure ? cue.text : nil
            speakOrQueue(.recordings(ids.compactMap { source.segments[$0] }, fallback: fallback), interrupt: interrupt)
        case .system(let text):
            speakOrQueue(.system(text), interrupt: interrupt)
        case .silent:
            if interrupt { stopOutputsForNewInstruction() }   // la anterior ya no vale; esta queda solo en pantalla
        }
        lastSpoken = cue.text
    }

    /// «Probar voz» de un perfil: secuencia de demostración. No inicia ninguna ruta ni toca la navegación.
    func playRecordedDemo(_ segments: [VoicePromptSegment]) {
        guard !segments.isEmpty else { return }
        stopImmediately()
        startRecordings(segments, fallback: nil, isTest: true)
    }

    private var isBusy: Bool { !active.isEmpty || recordedPlayer.isPlaying }

    private func speakOrQueue(_ output: PendingOutput, interrupt: Bool) {
        if interrupt {
            stopOutputsForNewInstruction()
        } else if isBusy {
            // El sintetizador ya encola sus propias frases; lo demás espera su turno aquí.
            if case .system(let text) = output, !recordedPlayer.isPlaying, queue.isEmpty {
                speak(text, interrupt: false, allowRepeat: true)
                return
            }
            queue.append(output)
            if queue.count > Self.maxQueued { queue.removeFirst(queue.count - Self.maxQueued) }
            return
        }
        start(output)
    }

    private func start(_ output: PendingOutput) {
        switch output {
        case .system(let text): speak(text, interrupt: false, allowRepeat: true)
        case .recordings(let segments, let fallback): startRecordings(segments, fallback: fallback, isTest: false)
        }
    }

    private func startRecordings(_ segments: [VoicePromptSegment], fallback: String?, isTest: Bool) {
        do {
            try session.activate()
            audioProblem = nil
        } catch {
            audioProblem = "No se pudo activar el audio del iPhone, así que puede que la voz no se oiga."
        }
        do {
            try recordedPlayer.play(segments, volume: volume) { [weak self] _ in self?.recordedFinished() }
            recordedIsTest = isTest
            if isTest { isPlayingTest = true }
            let seconds = segments.reduce(0) { $0 + max(0, $1.end - $1.start) } + 3
            recordedWatchdog?.cancel()
            recordedWatchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self, self.recordedPlayer.isPlaying else { return }
                self.recordedPlayer.stop()
            }
        } catch {
            // Archivo dañado o ilegible: en híbrido se dice entera con la voz del sistema; si no, nada.
            if let fallback { speak(fallback, interrupt: false, allowRepeat: true) } else { finishIfIdle() }
        }
    }

    private func recordedFinished() {
        recordedWatchdog?.cancel()
        recordedWatchdog = nil
        if recordedIsTest { isPlayingTest = false }
        recordedIsTest = false
        if replacing { return }
        startNextOrFinish()
    }

    private func startNextOrFinish() {
        guard !isBusy else { return }
        if !queue.isEmpty {
            start(queue.removeFirst())
        } else {
            finishIfIdle()
        }
    }

    private func finishIfIdle() {
        guard !isBusy, queue.isEmpty else { return }
        watchdog?.cancel()
        watchdog = nil
        session.deactivate()
    }

    /// Una indicación nueva sustituye a las anteriores (sonando o pendientes).
    private func stopOutputsForNewInstruction() {
        queue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        active.removeAll()
        testUtterance = nil
        isPlayingTest = false
        recordedIsTest = false
        recordedWatchdog?.cancel()
        recordedWatchdog = nil
        replacing = true
        recordedPlayer.stop()
        replacing = false
    }

    /// Botón "Escuchar prueba de voz": suena siempre, aunque las indicaciones estén desactivadas.
    func playTest() {
        speak(Self.testPhrase, interrupt: true, allowRepeat: true, isTest: true)
    }

    /// Escucha una voz concreta de la lista sin cambiar la elegida.
    func preview(_ voice: VoiceInfo) {
        speak(Self.testPhrase, interrupt: true, allowRepeat: true, isTest: true, voiceOverride: voice)
    }

    /// El botón de prueba alterna entre reproducir y parar.
    func toggleTest() {
        if isPlayingTest { stopImmediately() } else { playTest() }
    }

    /// Para YA cualquier voz (también las pendientes) y libera la sesión de audio.
    func stopImmediately() {
        queue.removeAll()
        recordedIsTest = false
        recordedWatchdog?.cancel()
        recordedWatchdog = nil
        recordedPlayer.stop()
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
        queue.removeAll()
        if !isBusy { session.deactivate() }
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
        for g in NavigationVoiceGender.allCases { defaults.removeObject(forKey: Self.voiceKey(for: g)) }
        voiceRevision += 1
    }

    // MARK: Privado

    /// Utterance con la voz, velocidad, tono y volumen vigentes. Se lee en cada indicación, así que
    /// un cambio de voz se aplica a la siguiente.
    func makeUtterance(_ text: String, voiceOverride: VoiceInfo? = nil) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let info = voiceOverride ?? selection.voice
        lastRequestedVoiceID = info?.identifier
        if let info, let voice = AVSpeechSynthesisVoice(identifier: info.identifier) {
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

    private func speak(_ text: String, interrupt: Bool, allowRepeat: Bool, isTest: Bool = false, voiceOverride: VoiceInfo? = nil) {
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
            queue.removeAll()
            if recordedPlayer.isPlaying {
                replacing = true
                recordedPlayer.stop()          // nunca dos motores de voz a la vez
                replacing = false
            }
        }
        let utterance = makeUtterance(text, voiceOverride: voiceOverride)
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
            if queue.isEmpty && !recordedPlayer.isPlaying {
                session.deactivate()
            } else {
                startNextOrFinish()            // turno de una indicación grabada que esperaba
            }
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

/// Perfil de voz grabada listo para sonar: fragmentos con archivo existente y el respaldo elegido.
struct RecordedVoiceSource {
    var segments: [VoicePhraseID: VoicePromptSegment]
    var strategy: VoiceFallbackStrategy
    /// Si un archivo falla al reproducirse, decir la indicación completa con la voz del sistema aunque el respaldo sea
    /// «solo grabaciones» (paquetes generados: un archivo dañado nunca deja la navegación sin voz).
    var fallbackOnFailure = false
}

/// Avisa de que una frase terminó o se canceló, para liberar la sesión de audio.
private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: ((AVSpeechUtterance) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish?(utterance) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onFinish?(utterance) }
}

/// Nombre histórico usado por el resto de la app.
typealias SpeechService = NavigationVoice
