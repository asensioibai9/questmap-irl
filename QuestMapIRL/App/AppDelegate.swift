import UIKit
import CarPlay

/// Delegado de aplicación solo para decidir la escena que se conecta: la de CarPlay (plantillas) o la normal del iPhone
/// (SwiftUI). Sin el entitlement de CarPlay de Apple el sistema nunca conecta la escena de CarPlay, así que esto no
/// cambia nada en el iPhone.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .carTemplateApplication {
            configuration.delegateClass = CarPlaySceneDelegate.self
        }
        return configuration
    }
}
