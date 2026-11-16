import Foundation
import Security

/// Configuración de Spotify. El Client ID NO es un secreto, pero es de tu cuenta: se inyecta al compilar con el ajuste
/// `SPOTIFY_CLIENT_ID` (variable del repositorio en GitHub Actions) y llega aquí a través de la clave `QMSpotifyClientID` del
/// Info.plist. Si falta, Spotify aparece como «Falta configurar»: nunca hay error de compilación ni se muestra como conectado.
/// No existe ni se usa ningún client secret.
struct SpotifyConfig: Equatable {
    /// Esquema propio de la app (registrado en Info.plist › URL types).
    static let urlScheme = "questmap-irl"
    /// Redirect URI que hay que registrar EXACTAMENTE igual en el panel de Spotify for Developers.
    static let redirectURL = URL(string: "questmap-irl://spotify-login-callback")!

    let clientID: String

    var isConfigured: Bool {
        let value = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        // «$(SPOTIFY_CLIENT_ID)» sin sustituir significa que no se configuró.
        return !value.isEmpty && !value.hasPrefix("$(") && value.allSatisfy { $0.isLetter || $0.isNumber }
    }

    static func load(bundle: Bundle = .main) -> SpotifyConfig {
        SpotifyConfig(clientID: bundle.object(forInfoDictionaryKey: "QMSpotifyClientID") as? String ?? "")
    }

    /// ¿Es esta URL la vuelta de la autorización de Spotify?
    static func isCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == urlScheme && url.host?.lowercased() == redirectURL.host
    }
}

/// Almacén de un secreto (el token de acceso de Spotify). En la app es el Llavero de iOS; en los tests, memoria.
protocol SecretStoring: AnyObject {
    func load() -> String?
    func save(_ value: String)
    func clear()
}

/// Llavero de iOS (`kSecClassGenericPassword`), accesible tras el primer desbloqueo y SOLO en este dispositivo
/// (no viaja en copias ni a otros dispositivos). Nada se guarda en UserDefaults.
final class KeychainSecretStore: SecretStoring {
    private let service: String
    private let account: String

    init(service: String = "com.questmapirl.spotify", account: String = "app-remote-access-token") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) {
        clear()
        var request = query
        request[kSecValueData as String] = Data(value.utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(request as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

final class InMemorySecretStore: SecretStoring {
    private var value: String?
    init(_ value: String? = nil) { self.value = value }
    func load() -> String? { value }
    func save(_ value: String) { self.value = value }
    func clear() { value = nil }
}
