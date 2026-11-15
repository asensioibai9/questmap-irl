import SwiftUI
import SwiftData

/// Raíz: decide entre onboarding y la app, y aplica el tema guardado.
struct RootView: View {
    @AppStorage("questmap.onboardingDone") private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    let environment: AppEnvironment

    private var settings: UserSettings? { settingsRows.first }

    private var theme: MapTheme {
        let id = MapThemeID(rawValue: settings?.themeRawValue ?? "") ?? .neonNocturno
        let candidate = ThemeCatalog.theme(for: id)
        // Sin Premium, un tema bloqueado vuelve al tema por defecto.
        if !SettingsView.freeThemes.contains(id), !environment.store.isPremium {
            return ThemeCatalog.neonNocturno
        }
        return candidate
    }

    var body: some View {
        Group {
            if onboardingDone {
                MainTabView(environment: environment, useMetric: settings?.useMetricUnits ?? true)
            } else {
                OnboardingView(locationService: environment.locationService)
            }
        }
        .environment(\.mapTheme, theme)
        .onAppear {
            // Garantiza una única fila de ajustes antes de que la UI la edite.
            if settingsRows.isEmpty { modelContext.insert(UserSettings()) }
        }
    }
}

struct MainTabView: View {
    @Environment(\.mapTheme) private var theme
    let environment: AppEnvironment
    let useMetric: Bool

    var body: some View {
        TabView {
            HomeView(environment: environment, useMetric: useMetric)
                .tabItem { Label("Mapa", systemImage: "map.fill") }
            ProfileView()
                .tabItem { Label("Explorador", systemImage: "rosette") }
            SettingsView(speech: environment.speech, store: environment.store)
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
        .tint(theme.accent)
    }
}
