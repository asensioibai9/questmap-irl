import SwiftUI
import SwiftData

@main
struct QuestMapIRLApp: App {
    @State private var environment = AppEnvironment()

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
