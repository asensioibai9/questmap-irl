import Foundation

/// Configuración de marca y enlaces externos. Todo lo que sea `nil` queda FUERA de la interfaz:
/// no se inventan webs, invitaciones ni identificadores de App Store.
enum AppConfig {
    static let appName = "QuestMap IRL"
    static let creditLine = "Creado por Ibai Asensio"

    /// Identificador numérico de la app en App Store (se conoce al crearla en App Store Connect).
    /// Mientras sea nil no se muestra "Valóranos".
    static let appStoreID: String? = nil

    /// Invitación real a la comunidad. Mientras sea nil no se muestra la fila de Discord.
    static let discordInvite: URL? = nil

    static var reviewURL: URL? {
        guard let appStoreID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
