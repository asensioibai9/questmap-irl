import Foundation
import SwiftData

/// Esquema único de la app (el mismo en producción y en pruebas).
enum AppSchema {
    static var schema: Schema {
        Schema([UserSettings.self, SavedPlace.self, RecentSearch.self, TripRecord.self, VisitedCell.self])
    }
}

enum StorageMode: Equatable {
    /// Datos en disco: sobreviven al cierre de la app.
    case persistent
    /// No se pudo abrir el almacén en disco: los datos de esta sesión se pierden al cerrar la app.
    case temporary
}

/// Estado del almacenamiento para avisar al usuario (nunca se degrada en silencio). Se fija una sola vez, al
/// abrir el contenedor, antes de que exista ninguna vista.
final class PersistenceStatus: @unchecked Sendable {
    static let shared = PersistenceStatus()
    private let lock = NSLock()
    private var stored: StorageMode = .persistent
    private var storedError: String?
    var mode: StorageMode {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
    /// Error real (dominio y código) que impidió abrir el almacén en disco; nil si abrió bien.
    var lastError: String? {
        get { lock.lock(); defer { lock.unlock() }; return storedError }
        set { lock.lock(); storedError = newValue; lock.unlock() }
    }
}

enum ContainerFactory {
    struct Outcome {
        let container: ModelContainer
        let mode: StorageMode
        let error: String?
    }

    /// Contenedor único de la app (una sola instancia por proceso).
    static let shared: ModelContainer = {
        StoreBackup.ensureParentDirectory(of: StoreBackup.defaultStoreURL)
        // Copia de los archivos existentes ANTES de abrirlos (una vez por versión): protege los datos si una
        // migración sale mal. No se borra nada.
        StoreBackup.backupIfNeeded(tag: "\(AppConfig.version)-\(AppConfig.build)")
        let outcome = make()
        PersistenceStatus.shared.mode = outcome.mode
        PersistenceStatus.shared.lastError = outcome.error
        return outcome.container
    }()

    /// Abre el almacén en disco. Si falla se reintenta una vez; si sigue fallando se usa uno temporal en memoria
    /// y se deja constancia (aviso al usuario + registro técnico). El archivo del disco NO se borra ni se sustituye.
    static func make(primary: () throws -> ModelContainer = { try ModelContainer(for: AppSchema.schema) }) -> Outcome {
        var lastError: String?
        for attempt in 1...2 {
            do {
                let container = try primary()
                StorageDiagnostics.record(operation: "open", outcome: "ok", note: "modo=disco intento=\(attempt)")
                return Outcome(container: container, mode: .persistent, error: nil)
            } catch {
                lastError = StorageErrorInfo.describe(error)
                StorageDiagnostics.record(operation: "open", outcome: "error", note: "intento=\(attempt) \(lastError ?? "")")
            }
        }
        StorageDiagnostics.record(operation: "open", outcome: "error", note: "modo=temporal")
        let memory = try! ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return Outcome(container: memory, mode: .temporary, error: lastError)
    }
}
