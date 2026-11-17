import Foundation
import os

/// Instrumentación de rendimiento sin datos personales (solo nombres de operación y milisegundos).
/// - Intervalos `os_signpost` (visibles con Instruments si algún día hay un Mac).
/// - Las operaciones que tardan más que su umbral se anotan en el registro de diagnóstico que ya existe
///   (Perfil › Centro de ayuda › Diagnóstico de conexión › Compartir), con servicio «performance».
enum PerformanceTrace {
    static let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "QuestMapIRL", category: "performance")

    private final class LastOperation: @unchecked Sendable {
        let lock = NSLock()
        var value: (name: String, at: Date)?
    }
    private static let last = LastOperation()

    /// Última operación medida (para dar contexto a un bloqueo del hilo principal).
    static var lastOperation: (name: String, at: Date)? {
        last.lock.lock(); defer { last.lock.unlock() }
        return last.value
    }

    /// Mide un trabajo síncrono. Si supera `thresholdMs`, se anota.
    @discardableResult
    static func measure<T>(_ name: StaticString, thresholdMs: Double = 50, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            finish("\(name)", start: start, thresholdMs: thresholdMs)
        }
        return try work()
    }

    /// Mide un trabajo asíncrono (tiempo hasta completar la operación, NO tiempo de bloqueo de la interfaz).
    @discardableResult
    static func measureAsync<T>(_ name: StaticString, thresholdMs: Double = 1000, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            finish("\(name)", start: start, thresholdMs: thresholdMs)
        }
        return try await work()
    }

    private static func finish(_ name: String, start: UInt64, thresholdMs: Double) {
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        last.lock.lock()
        last.value = (name, Date())
        last.lock.unlock()
        guard ms >= thresholdMs else { return }
        DiagnosticsLog.shared.record(DiagnosticEvent(date: Date(), service: "performance", operation: name, outcome: "slow",
                                                     durationMs: Int(ms.rounded()), attempt: 1, note: nil))
    }
}

/// Detector de bloqueos del hilo principal SIN Instruments: dos veces por segundo, desde una cola de baja prioridad, pide
/// al hilo principal que responda. Si tarda ≥ 250 ms, lo anota (duración y última operación medida). Solo funciona con la
/// app en primer plano; coste: un mensaje cada 0,5 s.
final class MainThreadHangMonitor: @unchecked Sendable {
    static let shared = MainThreadHangMonitor()
    static let thresholdMs: Double = 250

    private let queue = DispatchQueue(label: "questmap.hang-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pingSentAt: UInt64?
    private var lastReportAt: UInt64 = 0

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 1, repeating: .milliseconds(500), leeway: .milliseconds(100))
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            pingSentAt = nil
        }
    }

    private func tick() {
        guard pingSentAt == nil else { return }          // aún esperando la respuesta anterior
        let sent = DispatchTime.now().uptimeNanoseconds
        pingSentAt = sent
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let answered = DispatchTime.now().uptimeNanoseconds
            self.queue.async { self.answered(sent: sent, at: answered) }
        }
    }

    private func answered(sent: UInt64, at answered: UInt64) {
        pingSentAt = nil
        let ms = Double(answered - sent) / 1_000_000
        guard ms >= Self.thresholdMs, answered - lastReportAt > 2_000_000_000 else { return }
        lastReportAt = answered
        var note: String?
        if let last = PerformanceTrace.lastOperation, Date().timeIntervalSince(last.at) < 5 { note = "última=\(last.name)" }
        DiagnosticsLog.shared.record(DiagnosticEvent(date: Date(), service: "performance", operation: "main-thread-hang",
                                                     outcome: "slow", durationMs: Int(ms.rounded()), attempt: 1, note: note))
    }
}
