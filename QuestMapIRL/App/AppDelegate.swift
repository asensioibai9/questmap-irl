import UIKit
import CarPlay

/// Delegado de aplicación solo para decidir la escena que se conecta: la de CarPlay (plantillas, declarada en el Info.plist
/// con el nombre «CarPlay») o la normal del iPhone (SwiftUI). Sin el entitlement de CarPlay de Apple el sistema nunca
/// conecta la escena de CarPlay, así que esto no cambia nada en el iPhone.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            // La misma configuración que declara el Info.plist (clase de escena y delegado).
            let configuration = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            configuration.sceneClass = CPTemplateApplicationScene.self
            configuration.delegateClass = CarPlaySceneDelegate.self
            return configuration
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}
