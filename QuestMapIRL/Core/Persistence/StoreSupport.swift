import Foundation

/// Resume un error de almacenamiento (dominio, código y errores internos) para el registro técnico y para
/// que se pueda leer en pantalla. No contiene datos del usuario.
enum StorageErrorInfo {
    static func describe(_ error: Error) -> String {
        var parts: [String] = []
        var current: NSError? = error as NSError
        var depth = 0
        while let item = current, depth < 4 {
            parts.append("\(item.domain)#\(item.code)")
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        let reason = (error as NSError).localizedDescription.replacingOccurrences(of: "\n", with: " ")
        return parts.joined(separator: " > ") + " · " + String(reason.prefix(140))
    }
}

/// Copias de seguridad de los archivos del almacén. Nunca borra el original.
enum StoreBackup {
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    static var backupsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "StoreBackups", directoryHint: .isDirectory)
    }

    /// SwiftData/SQLite puede repartir los datos entre el archivo principal y sus -wal / -shm.
    static func files(for storeURL: URL) -> [URL] {
        [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"), URL(fileURLWithPath: storeURL.path + "-shm")]
    }

    /// El directorio de Application Support puede no existir en una instalación nueva.
    static func ensureParentDirectory(of storeURL: URL, fileManager: FileManager = .default) {
        try? fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    /// Copia los archivos del almacén existente UNA VEZ por versión de la app, antes de abrirlo (y por tanto antes
    /// de una posible migración). Se conservan las 3 copias más recientes. Devuelve la carpeta creada.
    @discardableResult
    static func backupIfNeeded(storeURL: URL = defaultStoreURL, tag: String, defaults: UserDefaults = .standard,
                               backupsDirectory: URL = StoreBackup.backupsDirectory,
                               fileManager: FileManager = .default) -> URL? {
        let key = "questmap.storeBackupTag"
        guard fileManager.fileExists(atPath: storeURL.path), defaults.string(forKey: key) != tag else { return nil }
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let folder = backupsDirectory.appending(path: "\(tag)-\(stamp)", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in files(for: storeURL) where fileManager.fileExists(atPath: file.path) {
                try fileManager.copyItem(at: file, to: folder.appending(path: file.lastPathComponent))
            }
            defaults.set(tag, forKey: key)
            prune(backupsDirectory, keep: 3, fileManager: fileManager)
            return folder
        } catch {
            StorageDiagnostics.record(operation: "backup", outcome: "error", note: StorageErrorInfo.describe(error))
            return nil
        }
    }

    /// Aparta (MUEVE, no borra) los archivos del almacén a la carpeta de copias para poder empezar con uno limpio.
    /// Solo se llama cuando el usuario lo pide explícitamente.
    static func setAside(storeURL: URL = defaultStoreURL, backupsDirectory: URL = StoreBackup.backupsDirectory,
                         fileManager: FileManager = .default) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let folder = backupsDirectory.appending(path: "apartado-\(stamp)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files(for: storeURL) where fileManager.fileExists(atPath: file.path) {
            try fileManager.moveItem(at: file, to: folder.appending(path: file.lastPathComponent))
        }
        return folder
    }

    private static func prune(_ directory: URL, keep: Int, fileManager: FileManager) {
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let regular = items.filter { !$0.lastPathComponent.hasPrefix("apartado-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in regular.dropLast(keep) { try? fileManager.removeItem(at: old) }
    }
}
