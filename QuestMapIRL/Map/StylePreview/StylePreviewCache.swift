import CryptoKit
import Foundation
import UIKit

/// Caché en disco de las previsualizaciones. La clave incluye el CONTENIDO del estilo (ya resuelto), la versión de la
/// composición, la versión de la app y la escala: si cambia cualquiera de ellas, la preview anterior deja de valer y se
/// borra. Vive en Caches (el sistema puede limpiarla; se regenera).
struct StylePreviewCache {
    var directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QuestMapStylePreviews", isDirectory: true)
    var fileManager: FileManager = .default

    /// Huella del estilo y de la composición.
    static func fingerprint(styleData: Data, specVersion: Int = StylePreviewSpec.version, appBuild: String, scale: CGFloat) -> String {
        var hasher = SHA256()
        hasher.update(data: styleData)
        hasher.update(data: Data("|spec\(specVersion)|build\(appBuild)|@\(Int(scale))x".utf8))
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func url(styleID: String, fingerprint: String) -> URL {
        directory.appendingPathComponent("\(styleID)-\(fingerprint).png")
    }

    /// Archivo de la preview si existe (sin decodificarlo).
    func existingURL(styleID: String, fingerprint: String) -> URL? {
        let url = url(styleID: styleID, fingerprint: fingerprint)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func load(styleID: String, fingerprint: String) -> UIImage? {
        let path = url(styleID: styleID, fingerprint: fingerprint).path
        guard fileManager.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    /// Guarda la preview y borra las versiones antiguas de ESE estilo.
    func store(_ image: UIImage, styleID: String, fingerprint: String) throws {
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(styleID: styleID, fingerprint: fingerprint), options: .atomic)
        invalidateOldVersions(styleID: styleID, keeping: fingerprint)
    }

    func invalidateOldVersions(styleID: String, keeping fingerprint: String) {
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent.hasPrefix("\(styleID)-") && !item.lastPathComponent.contains(fingerprint) {
            try? fileManager.removeItem(at: item)
        }
    }

    func removeAll() {
        try? fileManager.removeItem(at: directory)
    }
}
