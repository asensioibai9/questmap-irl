import Foundation
import SwiftData

/// Operación sobre Casa o Trabajo (se conserva para poder reintentarla si el guardado falla).
enum PersonalAction {
    case set(PlaceKind, Place)
    case delete(PlaceKind)
}

/// Guardado explícito de cambios en SwiftData. Si falla, se deshace el cambio pendiente (para no dejar
/// el contexto a medias), se anota en el registro técnico SIN datos personales y se propaga el error.
enum PersistenceCommit {
    @MainActor
    static func save(_ context: ModelContext, operation: String = "save") throws {
        // Sin cambios pendientes no se escribe nada (evita guardados idénticos y refrescos de @Query innecesarios).
        guard context.hasChanges else { return }
        do {
            try PerformanceTrace.measure("swiftdata-save") { try context.save() }
        } catch {
            context.rollback()
            StorageDiagnostics.record(operation: operation, outcome: "error", note: "tipo=\(type(of: error))")
            throw error
        }
    }

    /// Para datos no críticos (historial): el fallo se anota pero no interrumpe al usuario.
    @MainActor
    static func saveQuietly(_ context: ModelContext, operation: String) {
        try? save(context, operation: operation)
    }
}

/// Registro técnico del almacenamiento. Nunca incluye direcciones, nombres ni coordenadas.
enum StorageDiagnostics {
    static func record(operation: String, outcome: String, note: String? = nil) {
        DiagnosticsLog.shared.record(DiagnosticEvent(date: .now, service: "storage", operation: operation,
                                                     outcome: outcome, durationMs: 0, attempt: 1, note: note))
    }
}

/// Casa y Trabajo. Cada uno es un único registro persistente de `SavedPlace` con: tipo, nombre ("Casa"/"Trabajo"),
/// dirección legible (nota), latitud y longitud. No depende de ninguna búsqueda por internet para recuperarse.
///
/// - Cada cambio se guarda al instante con `save()` (no se espera a que la app pase a segundo plano).
/// - Editar uno nunca toca al otro; borrar uno nunca borra al otro.
/// - Si el guardado falla se lanza el error y el cambio pendiente se deshace; los datos anteriores siguen intactos.
@MainActor
struct PersonalPlaceStore {
    let context: ModelContext
    /// Punto de guardado (se puede sustituir en pruebas para simular un fallo).
    let commit: @MainActor (ModelContext) throws -> Void

    init(context: ModelContext, commit: (@MainActor (ModelContext) throws -> Void)? = nil) {
        self.context = context
        self.commit = commit ?? { try PersistenceCommit.save($0, operation: "personal-place") }
    }

    static func name(for kind: PlaceKind) -> String { kind == .home ? "Casa" : "Trabajo" }
    static func icon(for kind: PlaceKind) -> String { kind == .home ? "house.fill" : "briefcase.fill" }

    /// Registros de ese tipo, el más reciente primero.
    private func rows(_ kind: PlaceKind) -> [SavedPlace] {
        let raw = kind.rawValue
        var descriptor = FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.kindRawValue == raw },
                                                     sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 20
        return (try? context.fetch(descriptor)) ?? []
    }

    func place(_ kind: PlaceKind) -> SavedPlace? { rows(kind).first }

    func apply(_ action: PersonalAction) throws {
        switch action {
        case .set(let kind, let place): try set(kind, place: place)
        case .delete(let kind): try delete(kind)
        }
    }

    /// Crea o actualiza (en el mismo registro) y guarda. Solo Casa o Trabajo.
    func set(_ kind: PlaceKind, place: Place) throws {
        guard kind == .home || kind == .work else { return }
        let address = place.subtitle.isEmpty ? place.name : "\(place.name), \(place.subtitle)"
        let existing = rows(kind)
        if let current = existing.first {
            current.name = Self.name(for: kind)
            current.note = address
            current.iconName = Self.icon(for: kind)
            current.latitude = place.latitude
            current.longitude = place.longitude
            existing.dropFirst().forEach(context.delete)
        } else {
            context.insert(SavedPlace(name: Self.name(for: kind), note: address, iconName: Self.icon(for: kind),
                                      kind: kind, latitude: place.latitude, longitude: place.longitude))
        }
        try commit(context)
    }

    /// Borra solo ese tipo y guarda.
    func delete(_ kind: PlaceKind) throws {
        let existing = rows(kind)
        guard !existing.isEmpty else { return }
        existing.forEach(context.delete)
        try commit(context)
    }

    /// Deja un único registro de Casa y uno de Trabajo (el más reciente). No crea ni cambia datos válidos.
    func normalizeDuplicates() {
        var changed = false
        for kind in [PlaceKind.home, .work] {
            let existing = rows(kind)
            if existing.count > 1 {
                existing.dropFirst().forEach(context.delete)
                changed = true
            }
        }
        if changed { try? commit(context) }
    }

    /// Resumen para el registro técnico: solo presencia, nunca direcciones ni coordenadas.
    var presenceSummary: String {
        "casa=\(place(.home) != nil ? "si" : "no") trabajo=\(place(.work) != nil ? "si" : "no")"
    }
}
