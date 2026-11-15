import SwiftUI
import SwiftData

@main
struct QuestMapIRLApp: App {
    @State private var environment = AppEnvironment()

    /// Contenedor SwiftData. Si el esquema cambia y falla la migración,
    /// se recrea en memoria para que la app abra igualmente.
    private let container: ModelContainer = {
        let schema = Schema([UserSettings.self, SavedPlace.self, TripRecord.self, VisitedCell.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            return try! ModelContainer(for: schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
        .modelContainer(container)
    }
}
