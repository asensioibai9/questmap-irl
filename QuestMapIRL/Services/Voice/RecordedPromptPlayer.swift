import AVFoundation
import Foundation

/// Reproduce una secuencia de fragmentos grabados como UNA sola frase: recorta los silencios largos (sin tocar el archivo),
/// aplica la ganancia guardada, suaviza 10 ms los bordes para que no haya chasquidos y deja una pausa breve entre
/// fragmentos («En doscientos metros» · «gira a la derecha»).
@MainActor
protocol RecordedPromptPlaying: AnyObject {
    var isPlaying: Bool { get }
    /// `completion(true)` al terminar; `false` si se interrumpió o falló.
    func play(_ segments: [VoicePromptSegment], volume: Float, completion: @escaping @MainActor (Bool) -> Void) throws
    func stop()
}

enum RecordedPromptError: Error {
    case emptySequence
    case unreadable
    case formatMismatch
}

@MainActor
final class RecordedPromptPlayer: RecordedPromptPlaying {
    static let gapSeconds = 0.12
    static let fadeSeconds = 0.01

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var attachedFormat: AVAudioFormat?
    private var completion: (@MainActor (Bool) -> Void)?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private(set) var isPlaying = false

    init() {
        engine.attach(node)
        let center = NotificationCenter.default
        // Llamada, Siri, otra app que toma el audio, o cambio de salida (CarPlay, auriculares): se corta la frase.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finish(false) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finish(false) }
        })
    }

    func play(_ segments: [VoicePromptSegment], volume: Float, completion: @escaping @MainActor (Bool) -> Void) throws {
        guard !segments.isEmpty else { throw RecordedPromptError.emptySequence }
        stop()
        let buffers = try Self.buffers(for: segments)
        guard let format = buffers.first?.format else { throw RecordedPromptError.unreadable }
        if attachedFormat != format {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            attachedFormat = format
        }
        node.volume = volume
        generation += 1
        let current = generation
        self.completion = completion
        try engine.start()
        for (index, buffer) in buffers.enumerated() {
            if index == buffers.count - 1 {
                node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == current else { return }
                        self.finish(true)
                    }
                }
            } else {
                node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            }
        }
        node.play()
        isPlaying = true
    }

    func stop() {
        generation += 1
        if node.isPlaying { node.stop() }
        if engine.isRunning { engine.stop() }
        let pending = completion
        completion = nil
        let wasPlaying = isPlaying
        isPlaying = false
        if wasPlaying { pending?(false) }
    }

    private func finish(_ ok: Bool) {
        guard isPlaying else { return }
        generation += 1
        let pending = completion
        completion = nil
        isPlaying = false
        if node.isPlaying { node.stop() }
        if engine.isRunning { engine.stop() }
        pending?(ok)
    }

    /// Lee cada fragmento (solo la parte con voz), aplica ganancia y fundidos, e intercala silencios breves.
    static func buffers(for segments: [VoicePromptSegment]) throws -> [AVAudioPCMBuffer] {
        var result: [AVAudioPCMBuffer] = []
        var format: AVAudioFormat?
        for (index, segment) in segments.enumerated() {
            let file: AVAudioFile
            do { file = try AVAudioFile(forReading: segment.url) } catch { throw RecordedPromptError.unreadable }
            let fileFormat = file.processingFormat
            if let format, format != fileFormat { throw RecordedPromptError.formatMismatch }
            format = fileFormat
            let rate = fileFormat.sampleRate
            let startFrame = AVAudioFramePosition(max(0, segment.start) * rate)
            let endFrame = min(file.length, AVAudioFramePosition(max(segment.end, segment.start) * rate))
            let count = AVAudioFrameCount(max(0, endFrame - startFrame))
            guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: count) else {
                throw RecordedPromptError.unreadable
            }
            do {
                file.framePosition = startFrame
                try file.read(into: buffer, frameCount: count)
            } catch {
                throw RecordedPromptError.unreadable
            }
            shape(buffer, gain: Float(segment.gain), fadeFrames: Int(rate * fadeSeconds))
            result.append(buffer)
            if index < segments.count - 1, let gap = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: AVAudioFrameCount(rate * gapSeconds)) {
                gap.frameLength = gap.frameCapacity          // ceros: silencio
                if let channels = gap.floatChannelData {
                    for channel in 0..<Int(fileFormat.channelCount) {
                        channels[channel].update(repeating: 0, count: Int(gap.frameLength))
                    }
                }
                result.append(gap)
            }
        }
        return result
    }

    /// Ganancia (con tope para no saturar) y fundido de entrada/salida.
    static func shape(_ buffer: AVAudioPCMBuffer, gain: Float, fadeFrames: Int) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let fade = min(fadeFrames, frames / 2)
        for channel in 0..<Int(buffer.format.channelCount) {
            let data = channels[channel]
            for i in 0..<frames {
                var factor = gain
                if fade > 0 {
                    if i < fade { factor *= Float(i) / Float(fade) }
                    if i >= frames - fade { factor *= Float(frames - 1 - i) / Float(fade) }
                }
                data[i] = max(-1, min(1, data[i] * factor))
            }
        }
    }
}
