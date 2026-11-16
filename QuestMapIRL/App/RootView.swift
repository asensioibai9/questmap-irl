import SwiftUI
import SwiftData

/// Raíz: decide entre onboarding y la app, aplica el tema guardado y el modo día/noche.
struct RootView: View {
    @AppStorage("questmap.onboardingDone") private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    let environment: AppEnvironment

    private var settings: UserSettings? { settingsRows.first }

    /// Un tema sin estilo cartográfico terminado se sustituye por el tema por defecto, para que
    /// el HUD y el mapa nunca queden desajustados.
    private var theme: MapTheme {
        let candidate = ThemeCatalog.theme(for: settings?.themeID ?? .ciudadNocturna)
        return candidate.isCartographyReady ? candidate : ThemeCatalog.ciudadNocturna
    }

    /// Esquema de color efectivo: ajuste manual > tema.
    private var preferredScheme: ColorScheme? {
        switch settings?.nightModeOverride {
        case "day": return .light
        case "night": return .dark
        default: return theme.isDark ? .dark : .light
        }
    }

    var body: some View {
        Group {
            if onboardingDone {
                MainTabView(environment: environment, settings: settings)
            } else {
                OnboardingView(locationService: environment.locationService)
            }
        }
        .environment(\.mapTheme, theme)
        .preferredColorScheme(preferredScheme)
        .onAppear {
            // Garantiza una única fila de ajustes antes de que la UI la edite.
            if settingsRows.isEmpty { modelContext.insert(UserSettings()) }
            environment.speech.isMuted = !(settings?.voiceEnabled ?? true)
        }
    }
}

struct MainTabView: View {
    @Environment(\.mapTheme) private var theme
    let environment: AppEnvironment
    let settings: UserSettings?

    var body: some View {
        TabView {
            HomeView(environment: environment,
                     useMetric: settings?.useMetricUnits ?? true,
                     headingUp: settings?.headingUp ?? true,
                     showCompass: settings?.showCompass ?? true)
                .tabItem { Label("Mapa", systemImage: "map.fill") }
            ProfileView()
                .tabItem { Label("Explorador", systemImage: "rosette") }
            SettingsView(speech: environment.speech)
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
        .tint(theme.accent)
    }
}
