import SwiftUI
import SwiftData

@main
struct QuestMapIRLApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Entorno único compartido con CarPlay (la escena del coche puede crearse antes que la del iPhone).
    @State private var environment = AppEnvironment.shared

    /// Contenedor SwiftData único del proceso. Si el almacén en disco no se puede abrir NO se degrada en
    /// silencio: `PersistenceStatus` pasa a `.temporary` y la app avisa al usuario (ver `ContainerFactory`).
    private let container: ModelContainer = ContainerFactory.shared

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
        .modelContainer(container)
    }
}
