import SwiftUI
import SwiftData

/// Panel "Perfil": ajustes y personalización agrupados en tarjetas oscuras. Todo es local y
/// gratuito; las filas cuyo destino no está configurado (valoración, comunidad) no se muestran.
struct ProfileSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var settingsRows: [UserSettings]

    let environment: AppEnvironment

    @State private var confirmErase = false
    @State private var erased = false
    @State private var eraseFailed = false

    private var settings: UserSettings? { settingsRows.first }
    private var theme: MapTheme { ThemeCatalog.theme(for: settings?.themeID ?? .ciudadNocturna) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    PanelHeader(title: "Perfil") { dismiss() }
                        .padding(.horizontal, -20)   // la cabecera ya trae su propio margen

                    SettingsGroup {
                        link("map.fill", "Estilo de mapa", value: theme.name) { MapStyleGalleryView() }
                        RowDivider()
                        link("person.crop.circle.fill", "Avatar del mapa", value: settings?.mapAvatar.title) { AvatarPickerView() }
                        RowDivider()
                        link("gearshape.fill", "Ajustes de navegación") { NavigationSettingsView(environment: environment) }
                        RowDivider()
                        link("trophy.fill", "Estadísticas y logros") { ExplorerStatsView() }
                        RowDivider()
                        link("sparkles", "Novedades", value: "v\(AppConfig.version)") { WhatsNewView() }
                        RowDivider()
                        link("app.fill", "Icono de la app") { AppIconPickerView() }
                    }

                    SettingsGroup {
                        ShareLink(item: "Descubre \(AppConfig.appName): navegación GPS con mapas de estilo videojuego, sin anuncios ni compras.") {
                            SettingsRowLabel(systemImage: "square.and.arrow.up", title: "Compartir", showsChevron: false)
                        }
                        .buttonStyle(PressableStyle())
                        if let review = AppConfig.reviewURL {
                            RowDivider()
                            Button { openURL(review) } label: {
                                SettingsRowLabel(systemImage: "star.fill", title: "Valóranos", showsChevron: false)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        if let discord = AppConfig.discordInvite {
                            RowDivider()
                            Button { openURL(discord) } label: {
                                SettingsRowLabel(systemImage: "bubble.left.and.bubble.right.fill", title: "Comunidad de Discord", showsChevron: false)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        RowDivider()
                        link("questionmark.circle.fill", "Centro de ayuda") { HelpView(environment: environment) }
                        RowDivider()
                        link("hand.raised.fill", "Política de privacidad") { LegalDocumentView(document: .privacy) }
                        RowDivider()
                        link("doc.text.fill", "Términos de servicio") { LegalDocumentView(document: .terms) }
                        RowDivider()
                        link("map", "Créditos del mapa") { MapCreditsView() }
                        RowDivider()
                        Button { confirmErase = true } label: {
                            SettingsRowLabel(systemImage: "trash.fill", title: "Eliminar mis datos",
                                             tint: AppColor.danger, showsChevron: false)
                        }
                        .buttonStyle(PressableStyle())
                    }

                    Text("\(AppConfig.appName) · versión \(AppConfig.version) (\(AppConfig.build))")
                        .font(.footnote).foregroundStyle(AppColor.textSecondary)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(AppColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(theme.accent)
        .confirmationDialog("¿Eliminar tus datos?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Eliminar mis datos", role: .destructive) {
                if DataEraser.eraseAll(context: context, speech: environment.speech) { erased = true } else { eraseFailed = true }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(DataEraser.explanation)
        }
        .alert("No se pudieron eliminar los datos", isPresented: $eraseFailed) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("No se ha borrado nada. Inténtalo de nuevo.")
        }
        .alert("Datos eliminados", isPresented: $erased) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Se han borrado los datos guardados en este iPhone. Los servicios externos que usa la app pueden conservar sus propios registros técnicos: no podemos borrarlos desde aquí.")
        }
    }

    private func link<Destination: View>(_ icon: String, _ title: String, value: String? = nil,
                                         @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowLabel(systemImage: icon, title: title, value: value)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Borrado real de los datos que guarda la app en el dispositivo.
enum DataEraser {
    static let explanation = "Se eliminarán de este iPhone: Casa, Trabajo y lugares guardados, el historial de búsquedas, tus rutas y estadísticas, las zonas exploradas y tus preferencias (estilo de mapa, avatar, voz y ajustes). No afecta a datos que tengan los servicios externos de mapas, búsqueda y rutas."

    /// Devuelve false si no se pudo borrar (no se muestra «Datos eliminados» en ese caso).
    @MainActor
    @discardableResult
    static func eraseAll(context: ModelContext, speech: SpeechService) -> Bool {
        do {
            try eraseStoredData(context: context)
        } catch {
            return false
        }
        speech.resetPreferences()
        speech.isMuted = false
        return true
    }

    /// Borra casa, trabajo, favoritos, historial, viajes, zonas y ajustes, y guarda. Separado para poder probarlo.
    @MainActor
    static func eraseStoredData(context: ModelContext) throws {
        try context.delete(model: SavedPlace.self)
        try context.delete(model: RecentSearch.self)
        try context.delete(model: TripRecord.self)
        try context.delete(model: VisitedCell.self)
        try context.delete(model: UserSettings.self)
        context.insert(UserSettings())
        try PersistenceCommit.save(context, operation: "erase-all")
    }
}
