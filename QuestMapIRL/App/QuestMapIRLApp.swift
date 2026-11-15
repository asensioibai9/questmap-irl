import SwiftUI
import SwiftData

@main
struct QuestMapIRLApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
        .modelContainer(for: [UserSettings.self, SavedPlace.self, TripRecord.self, VisitedCell.self])
    }
}
