import SwiftUI
import SwiftData

/// Ajustes: tema, voz, unidades, orientación del mapa, modo noche y privacidad.
/// Todo está disponible desde el inicio: la app es gratuita y sin límites.
struct SettingsView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    @Bindable var speech: SpeechService

    var body: some View {
        NavigationStack {
            Group {
                if let settings = settingsRows.first {
                    form(for: settings)
                } else {
                    ProgressView().onAppear { modelContext.insert(UserSettings()) }
                }
            }
            .navigationTitle("Ajustes")
        }
        .tint(theme.accent)
    }

    private func form(for settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Form {
            Section("Tema del mapa") {
                ForEach(ThemeCatalog.all) { candidate in
                    Button { settings.themeID = candidate.id } label: {
                        HStack(spacing: 12) {
                            ThemeSwatch(theme: candidate)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name).foregroundStyle(.primary)
                                Text(candidate.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if !candidate.isCartographyReady {
                                Text("Próximamente").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            } else if settings.themeID == candidate.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .disabled(!candidate.isCartographyReady)
                    .opacity(candidate.isCartographyReady ? 1 : 0.55)
                    .accessibilityAddTraits(settings.themeID == candidate.id ? .isSelected : [])
                }
            }

            Section("Mapa") {
                Picker("Orientación", selection: $settings.headingUp) {
                    Text("Según el rumbo").tag(true)
                    Text("Norte arriba").tag(false)
                }
                Toggle("Mostrar brújula", isOn: $settings.showCompass)
                Picker("Modo noche", selection: $settings.nightModeOverride) {
                    Text("Según el tema").tag("auto")
                    Text("Día").tag("day")
                    Text("Noche").tag("night")
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
                Button("Probar voz") { speech.announce("En doscientos metros, gira a la derecha.", interrupt: true) }
                    .disabled(!settings.voiceEnabled)
            }

            Section("Unidades") {
                Picker("Distancias", selection: $settings.useMetricUnits) {
                    Text("Métricas (km, m)").tag(true)
                    Text("Imperiales (mi, ft)").tag(false)
                }
            }

            Section("Privacidad y legal") {
                Text("Tu ubicación, favoritos e historial se guardan solo en este dispositivo. No hay cuentas, anuncios ni venta de datos.")
                    .font(.footnote)
                Text("QuestMap IRL es una herramienta de navegación. Respeta siempre las normas de tráfico y no manipules el teléfono mientras conduces.")
                    .font(.footnote)
                Link("Política de privacidad", destination: URL(string: "https://example.com/privacidad")!)
                Link("Términos de uso", destination: URL(string: "https://example.com/terminos")!)
            }

            Section {
                LabeledContent("Versión", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }

            Section("Datos y atribución") {
                Text("Mapa: © OpenStreetMap contributors, © OpenMapTiles, servido por OpenFreeMap. Rutas: OSRM. Búsqueda: Photon. Todos sobre datos de OpenStreetMap (ODbL).")
                    .font(.footnote)
                Link("Copyright de OpenStreetMap", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
        }
    }
}

/// Muestra en miniatura la paleta de un tema: fondo, ruta y acento.
struct ThemeSwatch: View {
    let theme: MapTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.background)
            Path { p in
                p.move(to: CGPoint(x: 8, y: 30)); p.addLine(to: CGPoint(x: 20, y: 18)); p.addLine(to: CGPoint(x: 36, y: 22)); p.addLine(to: CGPoint(x: 48, y: 8))
            }
            .stroke(theme.routeBorder, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            Path { p in
                p.move(to: CGPoint(x: 8, y: 30)); p.addLine(to: CGPoint(x: 20, y: 18)); p.addLine(to: CGPoint(x: 36, y: 22)); p.addLine(to: CGPoint(x: 48, y: 8))
            }
            .stroke(theme.routeCore, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            Circle().fill(theme.destination).frame(width: 8, height: 8).offset(x: 20, y: -11)
        }
        .frame(width: 56, height: 38)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.accent, lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}
