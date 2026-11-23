import CarPlay
import UIKit

/// Escena principal de CarPlay (app de navegación). La declara el `Info.plist` (`CPTemplateApplicationSceneSessionRoleApplication`)
/// y solo se conecta cuando el sistema la crea, lo que exige el entitlement de navegación de Apple en la app FIRMADA.
///
/// Para apps de navegación CarPlay llama a `templateApplicationScene(_:didConnect:to:)` con una `CPWindow` (donde se dibuja
/// el mapa) y a `templateApplicationScene(_:didDisconnect:from:)` al desconectar. Las firmas deben coincidir EXACTAMENTE con
/// las del protocolo (son métodos opcionales de Objective-C: con otro tipo de parámetro no se llamarían nunca).
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayCoordinator?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        MainActor.assumeIsolated {
            let coordinator = CarPlayCoordinator(environment: AppEnvironment.shared, interfaceController: interfaceController, window: window)
            self.coordinator = coordinator
            coordinator.start()
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        MainActor.assumeIsolated {
            coordinator?.stop()
            coordinator = nil
        }
    }
}
