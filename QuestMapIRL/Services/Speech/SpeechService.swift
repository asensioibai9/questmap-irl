import AVFoundation
import Observation

/// Voz de guía en español con AVSpeechSynthesizer (voces del sistema).
@MainActor
@Observable
final class SpeechService {
    enum VoiceStyle: String, CaseIterable, Identifiable {
        case clara, firme, rapida
        var id: String { rawValue }

        var title: String {
            switch self {
            case .clara: return "Clara"
            case .firme: return "Firme"
            case .rapida: return "Rápida"
            }
        }
        var pitch: Float {
            switch self {
            case .clara: return 1.08
            case .firme: return 0.88
            case .rapida: return 1.0
            }
        }
        var rate: Float {
            switch self {
            case .clara: return 0.50
            case .firme: return 0.47
            case .rapida: return 0.56
            }
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let styleKey = "questmap.voiceStyle"

    var isMuted = false
    var style: VoiceStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: styleKey) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: styleKey) ?? ""
        style = VoiceStyle(rawValue: saved) ?? .clara
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
    }

    /// Mejor voz en español disponible: prefiere es-ES mejorada, si no cualquiera en español.
    private var voice: AVSpeechSynthesisVoice? {
        let spanish = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("es") }
        return spanish.first { $0.language == "es-ES" && $0.quality != .default }
            ?? spanish.first { $0.language == "es-ES" }
            ?? spanish.first
            ?? AVSpeechSynthesisVoice(language: "es-ES")
    }

    func announce(_ text: String, interrupt: Bool = false) {
        guard !isMuted, !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if interrupt { synthesizer.stopSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.pitchMultiplier = style.pitch
        utterance.rate = style.rate
        utterance.preUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted { synthesizer.stopSpeaking(at: .immediate) }
    }
}
