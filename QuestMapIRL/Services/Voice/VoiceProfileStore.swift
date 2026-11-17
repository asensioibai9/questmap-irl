import Foundation
import SwiftData

/// Dónde viven los audios: `Application Support/VoiceProfiles/<id del perfil>/<frase>-<uuid>.m4a`. Carpeta PRIVADA y
/// persistente de la app (no la caché ni la carpeta temporal, que iOS puede vaciar). Entra en la copia de seguridad del
/// iPhone (iCloud o el ordenador) como el resto de datos de la app; no se sube a ningún servidor de QuestMap IRL.
struct VoiceRecordingFiles {
    var baseURL: URL

    static var standard: VoiceRecordingFiles {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return VoiceRecordingFiles(baseURL: support.appendingPathComponent("VoiceProfiles", isDirectory: true))
    }

    func directory(for profileID: UUID) -> URL {
        baseURL.appendingPathComponent(profileID.uuidString, isDirectory: true)
    }

    func url(forRelativePath path: String) -> URL { baseURL.appendingPathComponent(path) }

    /// Espacio libre para datos importantes (nil si iOS no lo dice).
    func availableCapacity() -> Int64? {
        do {
            let values = try FileManager.default.temporaryDirectory
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            return nil
        }
    }
}

enum VoiceStoreError: LocalizedError, Equatable {
    case missingRecording
    case notEnoughSpace
    case fileSystem(String)
    case database(String)
    case invalidName

    var errorDescription: String? {
        switch self {
        case .missingRecording: return "No se encontró la grabación temporal. Vuelve a grabar."
        case .notEnoughSpace: return "No hay espacio suficiente en el iPhone para guardar la grabación."
        case .fileSystem(let detail): return "No se pudo guardar el archivo de audio (\(detail)). La grabación anterior se conserva."
        case .database(let detail): return "No se pudo guardar la grabación (\(detail)). La grabación anterior se conserva."
        case .invalidName: return "Escribe un nombre para el perfil."
        }
    }
}

/// Fragmento de audio listo para reproducir.
struct VoicePromptSegment: Equatable {
    var url: URL
    var start: Double
    var end: Double
    var gain: Double
}

/// Perfiles de voz: metadatos en SwiftData + audios en archivos. Coordina ambos para no dejar referencias rotas:
/// el archivo nuevo se escribe ANTES de cambiar los metadatos y el antiguo solo se borra cuando todo se ha guardado.
@MainActor
final class VoiceProfileStore {
    let context: ModelContext
    let files: VoiceRecordingFiles
    /// Mínimo de espacio libre para aceptar una grabación nueva.
    var minimumFreeBytes: Int64 = 20 * 1024 * 1024
    var fileManager = FileManager.default

    init(context: ModelContext, files: VoiceRecordingFiles = .standard) {
        self.context = context
        self.files = files
    }

    // MARK: Perfiles

    func profiles() throws -> [VoiceProfile] {
        try context.fetch(FetchDescriptor<VoiceProfile>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func profile(id: UUID) -> VoiceProfile? {
        do {
            return try context.fetch(FetchDescriptor<VoiceProfile>(predicate: #Predicate { $0.profileID == id })).first
        } catch {
            return nil
        }
    }

    @discardableResult
    func createProfile(name: String, language: String = VoicePromptCatalog.defaultLanguage) throws -> VoiceProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceStoreError.invalidName }
        let profile = VoiceProfile(name: String(trimmed.prefix(40)), languageCode: language)
        context.insert(profile)
        try commit("voice-profile-create")
        return profile
    }

    func rename(_ profile: VoiceProfile, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceStoreError.invalidName }
        profile.name = String(trimmed.prefix(40))
        try commit("voice-profile-rename")
    }

    /// Borra el perfil, sus grabaciones y su carpeta. Si era el activo, la app vuelve a la voz del sistema.
    func delete(_ profile: VoiceProfile, settings: UserSettings?) throws {
        let id = profile.profileID
        for recording in try recordings(for: id) { context.delete(recording) }
        context.delete(profile)
        if settings?.activeVoiceProfileID == id { settings?.activeVoiceProfileID = nil }
        try commit("voice-profile-delete")
        do {
            if fileManager.fileExists(atPath: files.directory(for: id).path) {
                try fileManager.removeItem(at: files.directory(for: id))
            }
        } catch {
            // Los metadatos ya no apuntan a estos archivos: quedan como huérfanos y se limpian más tarde.
            StorageDiagnostics.record(operation: "voice-profile-delete-files", outcome: "error", note: StorageErrorInfo.describe(error))
        }
    }

    // MARK: Grabaciones

    func recordings(for profileID: UUID) throws -> [VoiceRecording] {
        try context.fetch(FetchDescriptor<VoiceRecording>(predicate: #Predicate { $0.profileID == profileID }))
    }

    func recording(for profileID: UUID, phrase: VoicePhraseID) -> VoiceRecording? {
        let raw = phrase.rawValue
        do {
            return try context.fetch(FetchDescriptor<VoiceRecording>(
                predicate: #Predicate { $0.profileID == profileID && $0.phraseIDRaw == raw })).first
        } catch {
            return nil
        }
    }

    /// Frases con grabación cuyo archivo EXISTE de verdad (un archivo perdido cuenta como pendiente).
    func recordedPhrases(for profileID: UUID) -> Set<VoicePhraseID> {
        do {
            return Set(try recordings(for: profileID).filter { fileManager.fileExists(atPath: files.url(forRelativePath: $0.relativePath).path) }
                .compactMap(\.phraseID))
        } catch {
            return []
        }
    }

    func progress(for profile: VoiceProfile) -> VoiceProfileProgress {
        VoiceProfileProgress.make(recorded: recordedPhrases(for: profile.profileID), language: profile.languageCode)
    }

    /// Guarda una grabación confirmada de forma atómica. La anterior (si la había) se conserva hasta que la nueva y sus
    /// metadatos están guardados.
    func saveRecording(profileID: UUID, phrase: VoicePhraseID, from temporaryURL: URL, analysis: AudioAnalysis) throws {
        guard fileManager.fileExists(atPath: temporaryURL.path) else { throw VoiceStoreError.missingRecording }
        if let free = files.availableCapacity(), free < minimumFreeBytes { throw VoiceStoreError.notEnoughSpace }

        let relative = "\(profileID.uuidString)/\(phrase.rawValue)-\(UUID().uuidString).m4a"
        let destination = files.url(forRelativePath: relative)
        do {
            try fileManager.createDirectory(at: files.directory(for: profileID), withIntermediateDirectories: true)
            try fileManager.copyItem(at: temporaryURL, to: destination)
        } catch {
            removeQuietly(destination)
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError { throw VoiceStoreError.notEnoughSpace }
            throw VoiceStoreError.fileSystem("\(nsError.domain) \(nsError.code)")
        }

        let existing = recording(for: profileID, phrase: phrase)
        let oldPath = existing?.relativePath
        if let existing {
            existing.relativePath = relative
            existing.duration = analysis.duration
            existing.recordedAt = Date()
            existing.speechStart = analysis.speechStart
            existing.speechEnd = analysis.speechEnd
            existing.playbackGain = analysis.playbackGain
        } else {
            context.insert(VoiceRecording(profileID: profileID, phraseID: phrase, relativePath: relative, analysis: analysis))
        }
        do {
            try commit("voice-recording-save")
        } catch {
            removeQuietly(destination)      // los metadatos siguen apuntando a la anterior
            throw error
        }
        if let oldPath, oldPath != relative { removeQuietly(files.url(forRelativePath: oldPath)) }
        removeQuietly(temporaryURL)
    }

    func deleteRecording(profileID: UUID, phrase: VoicePhraseID) throws {
        guard let existing = recording(for: profileID, phrase: phrase) else { return }
        let path = existing.relativePath
        context.delete(existing)
        try commit("voice-recording-delete")
        removeQuietly(files.url(forRelativePath: path))
    }

    /// Fragmentos reproducibles de un perfil: solo frases con archivo existente.
    func segments(for profileID: UUID) -> [VoicePhraseID: VoicePromptSegment] {
        var result: [VoicePhraseID: VoicePromptSegment] = [:]
        do {
            for recording in try recordings(for: profileID) {
                guard let id = recording.phraseID else { continue }
                let url = files.url(forRelativePath: recording.relativePath)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                let end = recording.speechEnd > recording.speechStart ? recording.speechEnd : recording.duration
                result[id] = VoicePromptSegment(url: url, start: recording.speechStart, end: end, gain: recording.playbackGain)
            }
        } catch {
            StorageDiagnostics.record(operation: "voice-segments", outcome: "error", note: StorageErrorInfo.describe(error))
        }
        return result
    }

    /// Borra archivos de audio que ya no tiene ninguna grabación (p. ej. tras un fallo a medio guardar) y carpetas de
    /// perfiles que ya no existen. Nunca toca un archivo referenciado.
    @discardableResult
    func cleanupOrphans() -> Int {
        guard fileManager.fileExists(atPath: files.baseURL.path) else { return 0 }
        let referenced: Set<String>
        let profileIDs: Set<String>
        do {
            referenced = Set(try context.fetch(FetchDescriptor<VoiceRecording>()).map(\.relativePath))
            profileIDs = Set(try profiles().map(\.profileID.uuidString))
        } catch {
            return 0                    // sin poder leer los metadatos no se borra nada
        }
        var removed = 0
        let folders = contents(of: files.baseURL)
        for folder in folders where !folder.hasPrefix(".") {
            let folderURL = files.baseURL.appendingPathComponent(folder, isDirectory: true)
            guard profileIDs.contains(folder) else {
                removeQuietly(folderURL)
                removed += 1
                continue
            }
            for file in contents(of: folderURL) where !referenced.contains("\(folder)/\(file)") {
                removeQuietly(folderURL.appendingPathComponent(file))
                removed += 1
            }
        }
        return removed
    }

    // MARK: Privado

    private func commit(_ operation: String) throws {
        do {
            try PersistenceCommit.save(context, operation: operation)
        } catch {
            throw VoiceStoreError.database(StorageErrorInfo.describe(error))
        }
    }

    private func contents(of url: URL) -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: url.path)
        } catch {
            StorageDiagnostics.record(operation: "voice-list-files", outcome: "error", note: StorageErrorInfo.describe(error))
            return []
        }
    }

    private func removeQuietly(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            StorageDiagnostics.record(operation: "voice-file-remove", outcome: "error", note: StorageErrorInfo.describe(error))
        }
    }
}
