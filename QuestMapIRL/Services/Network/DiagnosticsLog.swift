import Foundation
import os

/// Un hecho de red ya resumido. NO contiene coordenadas, textos de búsqueda, claves ni URLs completas:
/// solo servicio, operación, resultado, tipo/código de error, estado HTTP, duración e intento.
struct DiagnosticEvent: Codable, Equatable {
    var date: Date
    var service: String
    var operation: String
    /// "ok", "error" o "cancelled".
    var outcome: String
    var errorKind: String?
    /// Código de `URLError` cuando existe.
    var code: Int?
    var httpStatus: Int?
    var durationMs: Int
    var attempt: Int
    var note: String?

    /// Línea de texto sin datos personales (se usa en el registro del sistema y en el informe).
    var summary: String {
        var parts = ["\(service).\(operation)", outcome]
        if let errorKind { parts.append("kind=\(errorKind)") }
        if let code { parts.append("urlerror=\(code)") }
        if let httpStatus { parts.append("http=\(httpStatus)") }
        parts.append("\(durationMs)ms")
        if attempt > 1 { parts.append("intento=\(attempt)") }
        if let note { parts.append(note) }
        return parts.joined(separator: " ")
    }
}

/// Registro circular de eventos de red, guardado en el iPhone para poder exportarlo desde
/// Perfil › Centro de ayuda › Diagnóstico de conexión. Es seguro desde cualquier hilo.
final class DiagnosticsLog: @unchecked Sendable {
    static let shared = DiagnosticsLog(fileURL: DiagnosticsLog.defaultFileURL)

    private let capacity: Int
    private let fileURL: URL?
    private let lock = NSLock()
    private var stored: [DiagnosticEvent] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "QuestMapIRL", category: "network")
    private let writeQueue = DispatchQueue(label: "questmap.diagnostics.write", qos: .utility)

    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("network-diagnostics.json")
    }

    init(fileURL: URL? = nil, capacity: Int = 200) {
        self.fileURL = fileURL
        self.capacity = capacity
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) {
            stored = Array(decoded.suffix(capacity))
        }
    }

    var events: [DiagnosticEvent] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func record(_ event: DiagnosticEvent) {
        logger.info("\(event.summary, privacy: .public)")
        lock.lock()
        stored.append(event)
        if stored.count > capacity { stored.removeFirst(stored.count - capacity) }
        let snapshot = stored
        lock.unlock()
        persist(snapshot)
    }

    /// Espera a que terminen las escrituras pendientes en disco (útil en pruebas y antes de exportar).
    func flush() {
        writeQueue.sync {}
    }

    func clear() {
        lock.lock(); stored.removeAll(); lock.unlock()
        persist([])
    }

    private func persist(_ events: [DiagnosticEvent]) {
        guard let fileURL else { return }
        writeQueue.async {
            if let data = try? JSONEncoder().encode(events) { try? data.write(to: fileURL, options: .atomic) }
        }
    }

    /// Informe en texto para compartir. `header` lleva datos del dispositivo y de la red (sin ubicación).
    func report(header: [String]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["QuestMap IRL — diagnóstico de conexión"] + header
        lines.append("Eventos (más recientes al final):")
        let list = events
        if list.isEmpty { lines.append("  (ninguno)") }
        for event in list.suffix(80) {
            lines.append("  \(formatter.string(from: event.date)) \(event.summary)")
        }
        return lines.joined(separator: "\n")
    }
}
