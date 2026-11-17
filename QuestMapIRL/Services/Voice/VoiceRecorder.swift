import AVFoundation
import Foundation
import Observation

/// Graba UNA frase. Nunca empieza sin que el usuario pulse «Grabar». El permiso de micrófono se pide en ese momento (no
/// antes, y nunca durante una navegación). La grabación va a un archivo temporal hasta que el usuario pulsa «Guardar»;
/// entonces `VoiceProfileStore` la copia a su sitio definitivo.
@MainActor
@Observable
final class VoiceRecorder {
    enum Permission: Equatable { case undetermined, granted, denied }

    enum State: Equatable {
        case idle
        case countdown(Int)
        case recording
        case recorded(AudioAnalysis)
        case failed(String)
    }

    static let maxDuration: TimeInterval = 10
    static let countdownKey = "questmap.voiceCountdownSeconds"

    private(set) var state: State = .idle
    private(set) var permission: Permission = .undetermined
    private(set) var elapsed: TimeInterval = 0
    /// Nivel de entrada 0…1 para el medidor.
    private(set) var level: Double = 0
    private(set) var isPlayingBack = false

    /// Cuenta atrás antes de grabar (0 = sin cuenta atrás). Se recuerda.
    var countdownSeconds: Int {
        didSet { UserDefaults.standard.set(countdownSeconds, forKey: Self.countdownKey) }
    }

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private(set) var temporaryURL: URL?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private let files: VoiceRecordingFiles

    init(files: VoiceRecordingFiles = .standard) {
        self.files = files
        let stored = UserDefaults.standard.object(forKey: Self.countdownKey) as? Int
        countdownSeconds = stored ?? 3
        refreshPermission()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.interrupted() }
        }
    }

    var isBusy: Bool {
        switch state {
        case .countdown, .recording: return true
        default: return false
        }
    }

    var analysis: AudioAnalysis? {
        if case .recorded(let analysis) = state { return analysis }
        return nil
    }

    func refreshPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permission = .granted
        case .denied: permission = .denied
        default: permission = .undetermined
        }
    }

    /// Botón «Grabar»: pide el permiso si hace falta (con el texto de `NSMicrophoneUsageDescription`) y empieza tras la
    /// cuenta atrás.
    func startRequested() async {
        guard !isBusy else { return }
        stopPlayback()
        if permission == .undetermined {
            let granted = await AVAudioApplication.requestRecordPermission()
            permission = granted ? .granted : .denied
        }
        guard permission == .granted else { return }
        if let free = files.availableCapacity(), free < 20 * 1024 * 1024 {
            state = .failed(VoiceStoreError.notEnoughSpace.errorDescription ?? "Sin espacio")
            return
        }
        discardTemporary()
        if countdownSeconds > 0 {
            countdownTask = Task { [weak self] in
                guard let self else { return }
                for remaining in stride(from: self.countdownSeconds, through: 1, by: -1) {
                    self.state = .countdown(remaining)
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
                self.beginRecording()
            }
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maxDuration) else {
                state = .failed("No se pudo empezar a grabar. Cierra otras apps que usen el micrófono y vuelve a intentarlo.")
                releaseSession()
                return
            }
            self.recorder = recorder
            temporaryURL = url
            elapsed = 0
            level = 0
            state = .recording
            startMeter()
        } catch {
            state = .failed("No se pudo preparar el micrófono (\(StorageErrorInfo.describe(error))).")
            releaseSession()
        }
    }

    /// Medidor y contador: solo mientras se graba (~20 veces por segundo), se para al terminar.
    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let recorder = self.recorder else { return }
                if !recorder.isRecording {
                    self.finishRecording()                 // tope de 10 s alcanzado
                    return
                }
                recorder.updateMeters()
                self.elapsed = recorder.currentTime
                let db = Double(recorder.averagePower(forChannel: 0))
                self.level = max(0, min(1, (db + 50) / 50))
            }
        }
    }

    /// Botón «Detener».
    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        if case .countdown = state { state = .idle; return }
        finishRecording()
    }

    private func finishRecording() {
        guard let recorder else { return }
        meterTask?.cancel()
        meterTask = nil
        recorder.stop()
        self.recorder = nil
        level = 0
        releaseSession()
        guard let url = temporaryURL else { state = .failed("No se encontró la grabación."); return }
        state = .recorded(AudioQualityAnalyzer.analyze(fileAt: url))
    }

    /// Llamada, Siri u otra app: la grabación a medias se descarta (no se guarda nada).
    private func interrupted() {
        guard isBusy else { stopPlayback(); return }
        countdownTask?.cancel()
        meterTask?.cancel()
        recorder?.stop()
        recorder = nil
        discardTemporary()
        releaseSession()
        state = .failed("La grabación se interrumpió (llamada u otra app). Vuelve a grabar.")
    }

    // MARK: Preescucha (nunca mientras se graba)

    func playBack() {
        guard !isBusy, let url = temporaryURL else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.player = player
            isPlayingBack = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(player.duration + 0.2))
                guard let self, self.player === player else { return }
                self.stopPlayback()
            }
        } catch {
            state = .failed("No se pudo reproducir la grabación.")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        if isPlayingBack {
            isPlayingBack = false
            releaseSession()
        }
    }

    /// Tras guardar: el archivo temporal ya se copió.
    func reset() {
        stopPlayback()
        discardTemporary()
        state = .idle
        elapsed = 0
    }

    func discardTemporary() {
        guard let url = temporaryURL else { return }
        temporaryURL = nil
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } catch {
            StorageDiagnostics.record(operation: "voice-temp-remove", outcome: "error", note: StorageErrorInfo.describe(error))
        }
    }

    private func releaseSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Otra parte de la app puede seguir usando el audio: no es un error para el usuario.
        }
    }

    /// Al cerrar la pantalla de grabación.
    func tearDown() {
        countdownTask?.cancel()
        if isBusy { interrupted() }
        reset()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
    }
}
