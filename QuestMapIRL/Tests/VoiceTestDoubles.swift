import AVFoundation
@testable import QuestMapIRL

/// Sintetizador falso: registra lo que se le pide sin producir audio.
final class FakeSynthesizer: SpeechSynthesizing {
    var isSpeaking = false
    var spoken: [AVSpeechUtterance] = []
    var stopCount = 0

    func speak(_ utterance: AVSpeechUtterance) { spoken.append(utterance) }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stopCount += 1
        return true
    }
}

/// Sesión de audio falsa de la voz.
final class FakeSession: AudioSessionControlling {
    struct Failure: Error {}
    var configureCount = 0
    var activateCount = 0
    var deactivateCount = 0
    var activateFails = false

    func configure() throws { configureCount += 1 }
    func activate() throws {
        activateCount += 1
        if activateFails { throw Failure() }
    }
    func deactivate() { deactivateCount += 1 }
}

/// Registra qué se pide a `AVAudioSession` sin tocar la sesión real del simulador.
final class FakeAudioDriver: AudioSessionDriver {
    var categories: [AVAudioSession.Category] = []
    var modes: [AVAudioSession.Mode] = []
    var options: [AVAudioSession.CategoryOptions] = []
    var activations: [Bool] = []
    var deactivationOptions: [AVAudioSession.SetActiveOptions] = []

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        categories.append(category)
        modes.append(mode)
        self.options.append(options)
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activations.append(active)
        if !active { deactivationOptions.append(options) }
    }
}

func testVoice(_ id: String, name: String = "V", lang: String = "es-ES", quality: Int = 1,
               gender: NavigationVoiceGender?) -> VoiceInfo {
    VoiceInfo(identifier: id, name: name, language: lang, quality: quality, gender: gender)
}
