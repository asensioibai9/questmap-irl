import SwiftUI
import SwiftData

/// Raíz: onboarding o app, estilo de mapa guardado y animación de inicio.
struct RootView: View {
    @AppStorage("questmap.onboardingDone") private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    /// La animación de inicio se muestra una vez por arranque de la app (no al volver del segundo plano).
    @State private var splashFinished = false

    let environment: AppEnvironment

    private var settings: UserSettings? { settingsRows.first }

    /// Un estilo sin cartografía terminada se sustituye por el de por defecto.
    private var theme: MapTheme {
        let candidate = ThemeCatalog.theme(for: settings?.themeID ?? .ciudadNocturna)
        return candidate.isCartographyReady ? candidate : ThemeCatalog.ciudadNocturna
    }

    var body: some View {
        ZStack {
            // La app se monta debajo de la animación: nunca se espera artificialmente al GPS ni a la red.
            Group {
                if onboardingDone {
                    HomeView(environment: environment, startupFinished: splashFinished)
                } else {
                    OnboardingView(locationService: environment.locationService)
                }
            }
            .environment(\.mapTheme, theme)

            if !splashFinished {
                SplashView { splashFinished = true }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.3), value: splashFinished)
        .preferredColorScheme(.dark)
        .onAppear {
            // Garantiza una única fila de ajustes antes de que la UI la edite.
            if settingsRows.isEmpty { modelContext.insert(UserSettings()) }
            environment.speech.isMuted = !(settings?.voiceEnabled ?? true)
        }
    }
}
