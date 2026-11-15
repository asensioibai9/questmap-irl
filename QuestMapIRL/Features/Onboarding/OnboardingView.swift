import SwiftUI

/// Onboarding de 3 pasos: concepto, permiso de ubicación y aviso de tráfico.
struct OnboardingView: View {
    @Environment(\.mapTheme) private var theme
    @AppStorage("questmap.onboardingDone") private var onboardingDone = false
    let locationService: LocationServiceProtocol

    @State private var page = 0

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                step(icon: "map.fill", title: "Tu ciudad, como un minimapa",
                     text: "Navegación GPS real con datos de Apple Maps y una estética de videojuego propia. Las rutas y tiempos son siempre precisos.")
                    .tag(0)
                step(icon: "location.fill", title: "Necesitamos tu ubicación",
                     text: "Solo mientras usas la app, para situarte en el mapa y guiarte. Tus recorridos se guardan únicamente en tu dispositivo.")
                    .tag(1)
                step(icon: "exclamationmark.triangle.fill", title: "Conduce con cabeza",
                     text: "QuestMap IRL es una herramienta de navegación. Respeta las normas de tráfico y no manipules el teléfono mientras conduces.")
                    .tag(2)
            }
            .tabViewStyle(.page)

            Button {
                if page == 1 { locationService.requestWhenInUseAuthorization() }
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    onboardingDone = true
                }
            } label: {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private var buttonTitle: String {
        switch page {
        case 1: return "Permitir ubicación al usar la app"
        case 2: return "Entendido, empezar"
        default: return "Siguiente"
        }
    }

    private func step(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(theme.accent)
                .shadow(color: theme.accent.opacity(0.6), radius: 16)
            Text(title)
                .font(.system(.title, design: theme.titleDesign).weight(.bold))
                .multilineTextAlignment(.center)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)
        }
        .foregroundStyle(theme.textPrimary)
        .padding(32)
    }
}
