import SwiftUI
import SwiftData

/// Ajustes: tema, voz, unidades, modo noche, privacidad y compras.
struct SettingsView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    @Bindable var speech: SpeechService
    @Bindable var store: StoreService
    @State private var showPaywall = false

    private var settings: UserSettings {
        if let existing = settingsRows.first { return existing }
        let created = UserSettings()
        modelContext.insert(created)
        return created
    }

    /// Temas gratuitos en el MVP; el resto exige Premium.
    static let freeThemes: Set<MapThemeID> = [.mapaMinimalista, .retroArcade, .neonNocturno]

    var body: some View {
        NavigationStack {
            Form {
                Section("Tema del mapa") {
                    ForEach(ThemeCatalog.all, id: \.id) { candidate in
                        let locked = !Self.freeThemes.contains(candidate.id) && !store.isPremium
                        Button {
                            if locked { showPaywall = true } else { settings.themeRawValue = candidate.id.rawValue }
                        } label: {
                            HStack {
                                Circle().fill(candidate.accent).frame(width: 22, height: 22)
                                Text(candidate.name).foregroundStyle(.primary)
                                Spacer()
                                if locked {
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                } else if settings.themeRawValue == candidate.id.rawValue {
                                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                                }
                            }
                        }
                    }
                }

                Section("Voz") {
                    Toggle("Guía por voz", isOn: Binding(
                        get: { settings.voiceEnabled },
                        set: { settings.voiceEnabled = $0; speech.isMuted = !$0 }
                    ))
                    Picker("Estilo de voz", selection: $speech.style) {
                        ForEach(SpeechService.VoiceStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Probar voz") { speech.announce("En doscientos metros, gira a la derecha.") }
                }

                Section("Unidades y aspecto") {
                    Picker("Unidades", selection: Binding(
                        get: { settings.useMetricUnits },
                        set: { settings.useMetricUnits = $0 }
                    )) {
                        Text("Métricas (km)").tag(true)
                        Text("Imperiales (mi)").tag(false)
                    }
                    Picker("Modo noche", selection: Binding(
                        get: { settings.nightModeOverride },
                        set: { settings.nightModeOverride = $0 }
                    )) {
                        Text("Automático").tag("auto")
                        Text("Día").tag("day")
                        Text("Noche").tag("night")
                    }
                }

                Section("Premium") {
                    if store.isPremium {
                        Label("Premium activo", systemImage: "checkmark.seal.fill").foregroundStyle(theme.accent)
                    } else {
                        Button("Desbloquear QuestMap Premium") { showPaywall = true }
                    }
                    Button("Restaurar compras") { Task { await store.restorePurchases() } }
                }

                Section("Privacidad y legal") {
                    Text("Tu ubicación, favoritos e historial se guardan solo en este dispositivo. No vendemos datos personales.")
                        .font(.footnote)
                    Text("QuestMap IRL es una herramienta de navegación. Respeta siempre las normas de tráfico y no manipules el teléfono mientras conduces.")
                        .font(.footnote)
                    Link("Política de privacidad", destination: URL(string: "https://example.com/privacidad")!)
                    Link("Términos de uso", destination: URL(string: "https://example.com/terminos")!)
                }
            }
            .navigationTitle("Ajustes")
        }
        .sheet(isPresented: $showPaywall) { PaywallView(store: store) }
    }
}
