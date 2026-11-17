import AVFoundation
import Foundation

/// Problema detectado en una grabación. Estas comprobaciones miden el SONIDO (duración, nivel, saturación, silencio):
/// NO comprueban que se haya dicho el texto correcto.
enum AudioIssue: Equatable, Hashable {
    case unreadable
    case tooShort
    case tooLong
    case empty
    case noSpeech
    case tooQuiet
    case clipping
    case longSilence

    /// Impide guardar (las demás son avisos: se puede guardar igualmente).
    var isBlocking: Bool {
        switch self {
        case .unreadable, .tooShort, .tooLong, .empty, .noSpeech: return true
        case .tooQuiet, .clipping, .longSilence: return false
        }
    }

    var message: String {
        switch self {
        case .unreadable: return "No se pudo leer el audio grabado. Vuelve a grabar."
        case .tooShort: return "La grabación es demasiado corta."
        case .tooLong: return "La grabación es demasiado larga para una indicación (máximo 10 s)."
        case .empty: return "No se oye nada: comprueba el micrófono y vuelve a grabar."
        case .noSpeech: return "Casi todo es silencio: no se detecta voz suficiente."
        case .tooQuiet: return "Se oye muy bajo. Acércate un poco más al micrófono."
        case .clipping: return "El audio satura (se distorsiona). Aléjate un poco o habla más suave."
        case .longSilence: return "Hay silencios largos al principio o al final (al reproducir se saltan)."
        }
    }
}

/// Resultado del análisis de una grabación.
struct AudioAnalysis: Equatable {
    var duration: Double
    var peak: Double
    /// Nivel medio de la parte con voz, en dBFS.
    var speechLevelDB: Double
    var clippedFraction: Double
    /// Inicio y fin de la voz (con un pequeño margen para no cortar consonantes).
    var speechStart: Double
    var speechEnd: Double
    /// Ganancia de reproducción para un volumen coherente, sin pasar de -1 dBFS de pico ni de +12 dB.
    var playbackGain: Double
    var issues: [AudioIssue]

    var canSave: Bool { !issues.contains(where: \.isBlocking) }
}

enum AudioQualityAnalyzer {
    static let minDuration = 0.3
    static let maxDuration = 10.0
    static let targetSpeechDB = -20.0
    static let maxGain = 4.0                 // +12 dB como mucho: no se amplifica el ruido sin límite
    static let maxPeakAfterGain = 0.89       // -1 dBFS
    /// Margen alrededor de la voz al recortar en reproducción (no se cortan consonantes).
    static let leadMargin = 0.08
    static let tailMargin = 0.15

    /// Analiza muestras mono en coma flotante (-1…1). Lógica pura: se prueba con señales sintéticas.
    static func analyze(samples: [Float], sampleRate: Double) -> AudioAnalysis {
        let duration = sampleRate > 0 ? Double(samples.count) / sampleRate : 0
        var issues: [AudioIssue] = []
        if duration < minDuration { issues.append(.tooShort) }
        if duration > maxDuration { issues.append(.tooLong) }

        let peak = Double(samples.lazy.map { abs($0) }.max() ?? 0)
        let clipped = samples.isEmpty ? 0 : Double(samples.lazy.filter { abs($0) >= 0.99 }.count) / Double(samples.count)

        // Energía por ventanas de 10 ms.
        let window = max(1, Int(sampleRate * 0.01))
        var levels: [Double] = []
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + window)
            var sum = 0.0
            for i in index..<end { sum += Double(samples[i]) * Double(samples[i]) }
            let rms = (sum / Double(end - index)).squareRoot()
            levels.append(rms > 0 ? 20 * log10(rms) : -120)
            index = end
        }
        let sorted = levels.sorted()
        let noiseFloor = sorted.isEmpty ? -120 : sorted[Int(Double(sorted.count - 1) * 0.1)]
        let threshold = max(-50, noiseFloor + 10)
        let speechWindows = levels.indices.filter { levels[$0] >= threshold }
        let windowSeconds = Double(window) / max(sampleRate, 1)

        var speechStart = 0.0, speechEnd = duration, speechDB = -120.0
        if peak < 0.01 {
            issues.append(.empty)
        } else if let first = speechWindows.first, let last = speechWindows.last, Double(speechWindows.count) * windowSeconds >= 0.25 {
            speechStart = max(0, Double(first) * windowSeconds - leadMargin)
            speechEnd = min(duration, Double(last + 1) * windowSeconds + tailMargin)
            let energy = speechWindows.reduce(0.0) { $0 + pow(10, levels[$1] / 10) } / Double(speechWindows.count)
            speechDB = 10 * log10(energy)
            if speechDB < -38 { issues.append(.tooQuiet) }
            if speechStart > 1.5 || duration - speechEnd > 1.5 { issues.append(.longSilence) }
        } else {
            issues.append(.noSpeech)
        }
        if clipped > 0.001 { issues.append(.clipping) }

        var gain = speechDB > -120 ? pow(10, (targetSpeechDB - speechDB) / 20) : 1
        gain = min(gain, maxGain)
        if peak > 0 { gain = min(gain, maxPeakAfterGain / peak) }
        gain = max(gain, 0.25)

        return AudioAnalysis(duration: duration, peak: peak, speechLevelDB: speechDB, clippedFraction: clipped,
                             speechStart: speechStart, speechEnd: speechEnd, playbackGain: gain, issues: issues)
    }

    /// Lee un archivo de audio y lo analiza (primer canal).
    static func analyze(fileAt url: URL) -> AudioAnalysis {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard file.length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
                return unreadable
            }
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?[0] else { return unreadable }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            return analyze(samples: samples, sampleRate: format.sampleRate)
        } catch {
            return unreadable
        }
    }

    static let unreadable = AudioAnalysis(duration: 0, peak: 0, speechLevelDB: -120, clippedFraction: 0, speechStart: 0,
                                          speechEnd: 0, playbackGain: 1, issues: [.unreadable])
}
