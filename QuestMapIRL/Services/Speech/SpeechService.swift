import AVFoundation
import Observation

/// Voz de guía. Usa voces del sistema en español en el MVP;
/// las voces originales propias llegarán con un TTS licenciado (versión premium).
@MainActor
@Observable
final class SpeechService {
    enum VoiceStyle: String, CaseIterable, Identifiable {
        case clara, firme
        var id: String { rawValue }

        var title: String {
            switch self {
            case .clara: return "Clara"
            case .firme: return "Firme"
            }
        }
        var pitch: Float { self == .clara ? 1.1 : 0.85 }
        var rate: Float { self == .clara ? 0.5 : 0.46 }
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
            .playback, mode: .voicePrompt, options: [.duckOthers]
        )
    }

    func announce(_ text: String) {
        guard !isMuted, !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        utterance.pitchMultiplier = style.pitch
        utterance.rate = style.rate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted { stop() }
    }
}
