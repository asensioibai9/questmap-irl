import CarPlay
import UIKit

/// Escena de CarPlay. Solo se conecta cuando el sistema la crea, lo que exige el entitlement de navegación de Apple.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayCoordinator?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: UIWindow) {
        MainActor.assumeIsolated {
            let coordinator = CarPlayCoordinator(environment: AppEnvironment.shared, interfaceController: interfaceController, window: window)
            self.coordinator = coordinator
            coordinator.start()
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: UIWindow) {
        MainActor.assumeIsolated {
            coordinator?.stop()
            coordinator = nil
        }
    }
}
