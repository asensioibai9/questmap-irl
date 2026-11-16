import SwiftUI
import SwiftData
import CoreLocation

extension MapTheme {
    /// Imagen de previsualización del catálogo de recursos. Noir, Claro, Isla y Bloques: capturas del estilo; los demás: esquemas dibujados con su paleta (no son capturas).
    var previewAsset: String? {
        switch id {
        case .ciudadNocturna: return "StylePreviewNoir"
        case .minimalistaPro: return "StylePreviewLight"
        case .islaRoyale: return "StylePreviewIsla"
        case .mundoBloques: return "StylePreviewBloques"
        case .salvajeOeste: return "StylePreviewOeste"
        case .ciudadCiber: return "StylePreviewCiber"
        case .mapaFantasia: return "StylePreviewFantasia"
        case .redUrbana: return "StylePreviewRed"
        case .rutasRally: return "StylePreviewRally"
        default: return nil
        }
    }
}

// MARK: - Estilo de mapa

/// Galería de estilos cartográficos. Cambiar de estilo no borra destino, ruta ni favoritos:
/// el mapa vuelve a aplicar su estado tras cargar el nuevo estilo.
struct MapStyleGalleryView: View {
    @Query private var settingsRows: [UserSettings]
    @Environment(\.modelContext) private var context

    private var settings: UserSettings? { settingsRows.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(ThemeCatalog.all.filter(\.isCartographyReady)) { candidate in
                    card(candidate)
                }
                Text("Todos los estilos dibujan las calles reales de tu ubicación. Aparecerán aquí los nuevos estilos cuando estén terminados.")
                    .font(.footnote).foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Estilo de mapa")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ candidate: MapTheme) -> some View {
        let selected = (settings?.themeID ?? .ciudadNocturna) == candidate.id
        return Button {
            if let settings { settings.themeID = candidate.id } else {
                context.insert(UserSettings(themeRawValue: candidate.id.rawValue))
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    preview(candidate)
                    if selected {
                        Label("En uso", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.7), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(10)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name).font(.headline).foregroundStyle(AppColor.textPrimary)
                    Text(candidate.tagline).font(.subheadline).foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(selected ? candidate.accent : Color.clear, lineWidth: 3))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(candidate.name). \(candidate.tagline)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func preview(_ candidate: MapTheme) -> some View {
        Group {
            if let asset = candidate.previewAsset {
                Image(asset).resizable().scaledToFill()
            } else {
                candidate.background
            }
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Avatar

struct AvatarPickerView: View {
    @Query private var settingsRows: [UserSettings]
    @Environment(\.mapTheme) private var theme

    private var settings: UserSettings? { settingsRows.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(MapAvatar.allCases) { avatar in tile(avatar) }
                }
                Text("La posición y la orientación son cosas distintas: el avatar solo gira cuando el GPS detecta un rumbo fiable, y se queda quieto si estás parado.")
                    .font(.footnote).foregroundStyle(AppColor.textSecondary)
            }
            .padding(16)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Avatar del mapa")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ avatar: MapAvatar) -> some View {
        let selected = (settings?.mapAvatar ?? .arrow) == avatar
        let hex = theme.activeCartography.userArrowHex
        let image = avatar.image(fill: UIColor(hex: hex), border: UIColor(hex: 0x0A0B0D))
        return Button {
            settings?.mapAvatar = avatar
        } label: {
            VStack(spacing: 10) {
                Image(uiImage: image).resizable().interpolation(avatar == .pixel ? .none : .high)
                    .frame(width: 72, height: 72)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(AppColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(avatar.title).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.textPrimary)
                Text(avatar.detail).font(.caption).foregroundStyle(AppColor.textSecondary).multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected ? theme.accent : Color.clear, lineWidth: 3))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(avatar.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Ajustes de navegación

/// Solo ajustes que cambian el comportamiento real de la app.
struct NavigationSettingsView: View {
    @Query private var settingsRows: [UserSettings]
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    let environment: AppEnvironment
    @Bindable private var speech: SpeechService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.speech = environment.speech
    }

    var body: some View {
        Group {
            if let settings = settingsRows.first {
                form(settings)
            } else {
                ProgressView()
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Ajustes de navegación")
        .navigationBarTitleDisplayMode(.inline)
        // Al salir de esta pantalla no debe quedarse sonando la prueba.
        .onDisappear { speech.stopTestIfPlaying() }
    }

    private func form(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle("Indicaciones de voz", isOn: Binding(
                    get: { settings.voiceEnabled },
                    set: { settings.voiceEnabled = $0; speech.isMuted = !$0 }
                ))
                Picker("Voz de navegación", selection: $speech.gender) {
                    ForEach(NavigationVoiceGender.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                NavigationLink {
                    VoicePickerView(speech: speech)
                } label: {
                    HStack {
                        Text("Elegir voz")
                        Spacer()
                        Text(speech.preferredVoiceID(for: speech.gender) == nil ? "Automática" : (speech.selection.voice?.name ?? "—"))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volumen")
                        Spacer()
                        Text("\(Int(speech.volume * 100)) %").foregroundStyle(AppColor.textSecondary).monospacedDigit()
                    }
                    Slider(value: Binding(get: { Double(speech.volume) }, set: { speech.volume = Float($0) }), in: 0.2...1)
                }
                Button { speech.toggleTest() } label: {
                    if speech.isPlayingTest {
                        Label("Reproduciendo… (toca para parar)", systemImage: "waveform")
                    } else {
                        Label("Escuchar prueba de voz", systemImage: "speaker.wave.2.fill")
                    }
                }
                .accessibilityLabel(speech.isPlayingTest ? "Reproduciendo la prueba de voz. Toca para parar" : "Escuchar prueba de voz")
                VStack(alignment: .leading, spacing: 6) {
                    Text(speech.statusText)
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                    if let details = speech.voiceDetails {
                        Text("Se usa: \(details)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    if speech.onlyBasicVoicesInstalled {
                        Label("Solo hay voces básicas de España instaladas; suenan más robóticas. Descarga una voz Mejorada o Premium en Ajustes › Accesibilidad › Contenido hablado › Voces › Español (tu iPhone tiene iOS \(UIDevice.current.systemVersion)).",
                              systemImage: "arrow.down.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if let warning = speech.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Text(NavigationVoice.downloadHint)
                            .font(.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if let problem = speech.audioProblem {
                        Label(problem, systemImage: "speaker.slash.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Voz de navegación")
            } footer: {
                Text("Las indicaciones se dicen en español con las voces instaladas en el iPhone. El volumen se aplica sobre el volumen del sistema. El botón de prueba suena aunque las indicaciones estén desactivadas.")
            }

            Section {
                Toggle("Mostrar límite de velocidad", isOn: $settings.showSpeedLimit)
                    .onChange(of: settings.showSpeedLimit) { _, _ in
                        PersistenceCommit.saveQuietly(context, operation: "speed-limit-setting")
                    }
            } header: {
                Text("Velocidad")
            } footer: {
                Text("El límite se obtiene de OpenStreetMap a través de un servicio público (Valhalla): al activarlo, la geometría de la ruta se envía a ese servicio. Solo aparece cuando hay dato fiable del tramo; puede estar incompleto o desactualizado y prevalece la señalización real. Desactivado, no se hace ninguna consulta.")
            }

            musicSection(settings)

            Section("Mapa") {
                Picker("Orientación", selection: $settings.headingUp) {
                    Text("Rumbo arriba").tag(true)
                    Text("Norte arriba").tag(false)
                }
                Toggle("Mostrar brújula", isOn: $settings.showCompass)
            }

            Section {
                Picker("Unidades", selection: $settings.useMetricUnits) {
                    Text("Kilómetros y metros").tag(true)
                    Text("Millas y pies").tag(false)
                }
                Picker("Desplazamiento preferido", selection: Binding(
                    get: { settings.defaultMode },
                    set: { settings.defaultMode = $0 }
                )) {
                    ForEach(RouteMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            } header: {
                Text("Rutas")
            } footer: {
                Text("El proveedor de rutas público no permite evitar peajes ni autopistas, por eso no se ofrecen esas opciones.")
            }

            Section {
                Toggle("Guardar historial de búsquedas", isOn: $settings.saveSearchHistory)
            } header: {
                Text("Privacidad")
            } footer: {
                Text("El historial solo se guarda en este iPhone. Si lo desactivas, no se añaden búsquedas nuevas.")
            }

            Section {
                LabeledContent("Permiso de ubicación", value: permissionText)
                if needsSystemSettings {
                    Button("Abrir Ajustes del sistema") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: {
                Text("Ubicación")
            } footer: {
                Text("La app solo usa tu ubicación mientras está abierta, para situarte en el mapa y guiarte.")
            }
        }
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func musicSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        let music = environment.music
        Section {
            Toggle("Mostrar minirreproductor", isOn: $settings.showMiniPlayer)
                .onChange(of: settings.showMiniPlayer) { _, _ in PersistenceCommit.saveQuietly(context, operation: "mini-player-setting") }
            Picker("Servicio", selection: $settings.musicServiceRaw) {
                Text("Apple Música").tag("appleMusic")
            }
            LabeledContent("Estado", value: music.statusText)
            if music.isConnected {
                Button("Desconectar", role: .destructive) { music.disconnect() }
            } else if music.status == .denied {
                Button("Abrir Ajustes del sistema") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else {
                Button("Conectar Apple Música") { Task { await music.connect() } }
                    .disabled(music.status == .connecting || music.status == .restricted)
            }
        } header: {
            Text("Música")
        } footer: {
            Text("Muestra y controla lo que suena en la app Música del iPhone. No controla Spotify ni otras apps (todavía no hay una integración compatible). Conectar solo pide permiso de lectura: no cambia tu cola ni inicia música. Para revocar el permiso, usa Ajustes del iPhone. Las indicaciones de voz bajan el volumen de la música y luego lo recuperan.")
        }
    }

    private var permissionText: String {
        switch environment.locationService.authState {
        case .notDetermined: return "Sin decidir"
        case .denied: return "Denegado"
        case .restricted: return "Restringido"
        case .servicesDisabled: return "Servicios desactivados"
        case .authorizedWhenInUse: return "Al usar la app"
        case .authorizedAlways: return "Siempre"
        }
    }

    private var needsSystemSettings: Bool {
        switch environment.locationService.authState {
        case .denied, .servicesDisabled, .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }
}

// MARK: - Novedades, ayuda y textos legales

struct WhatsNewView: View {
    private struct Release: Identifiable {
        let id: String
        let date: String
        let items: [String]
    }

    private let releases = [
        Release(id: "1.0", date: "Noviembre de 2026", items: [
            "Mapa vectorial real a pantalla completa con dos estilos: Ciudad nocturna y Minimalista Pro.",
            "Rutas en coche y a pie con indicaciones de voz en español y recálculo si te desvías.",
            "Buscador con recientes, Casa, Trabajo y Guardados, y búsqueda de lugares cercanos por categoría.",
            "Avatar del mapa a elegir y minimapa durante la navegación.",
            "Sin cuentas, anuncios ni compras: todas las funciones están disponibles.",
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(releases) { release in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Versión \(release.id)").font(.title2.weight(.bold)).foregroundStyle(AppColor.textPrimary)
                        Text(release.date).font(.footnote).foregroundStyle(AppColor.textSecondary)
                        ForEach(release.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text(item).foregroundStyle(AppColor.textPrimary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Novedades")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpView: View {
    let environment: AppEnvironment

    private let topics: [(String, String)] = [
        ("¿Cómo guardo Casa o Trabajo?",
         "En el buscador, toca «Añadir casa» o «Añadir trabajo», busca la dirección y elígela. Mantén pulsado el acceso para editarlo, verlo en el mapa o eliminarlo."),
        ("¿Cómo elijo un destino en el mapa?",
         "Mantén pulsado un punto del mapa para fijarlo como destino y calcular la ruta."),
        ("El mapa no carga",
         "El mapa, la búsqueda y las rutas necesitan conexión a internet. Comprueba tu conexión y pulsa «Reintentar» en el aviso."),
        ("No encuentro lugares cercanos",
         "Se necesita tu ubicación. Si no la has permitido, puedes elegir una zona manualmente al abrir una categoría."),
        ("La voz no se oye",
         "Revisa en Perfil › Ajustes de navegación que las indicaciones de voz estén activadas, el volumen y el volumen del iPhone."),
        ("¿De dónde sale el límite de velocidad?",
         "De las etiquetas de velocidad máxima de OpenStreetMap, para el tramo de tu ruta. Solo se muestra cuando hay dato; si no, verás «–». La información puede estar incompleta o desactualizada y prevalece la señalización real. Es el límite para un turismo y no incluye límites variables ni condicionales."),
        ("¿Qué pasa si me desvío de la ruta?",
         "La app espera varias lecturas fiables de GPS fuera de la ruta y recalcula desde tu posición actual."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(topics, id: \.0) { topic in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(topic.0).font(.headline).foregroundStyle(AppColor.textPrimary)
                        Text(topic.1).font(.subheadline).foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(16)

            SettingsGroup {
                NavigationLink {
                    ConnectivityDiagnosticsView(environment: environment)
                } label: {
                    SettingsRowLabel(systemImage: "stethoscope", title: "Diagnóstico de conexión y ubicación")
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Centro de ayuda")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Textos legales dentro de la app. Describen los servicios y datos que la app usa de verdad.
struct LegalDocumentView: View {
    enum Document { case privacy, terms }
    let document: Document

    private var title: String { document == .privacy ? "Política de privacidad" : "Términos de servicio" }

    private var sections: [(String, String)] {
        document == .privacy ? Self.privacy : Self.terms
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Última actualización: 16 de noviembre de 2026")
                    .font(.footnote).foregroundStyle(AppColor.textSecondary)
                ForEach(sections, id: \.0) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.0).font(.headline).foregroundStyle(AppColor.textPrimary)
                        Text(section.1).font(.subheadline).foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let privacy: [(String, String)] = [
        ("Qué guarda la app en tu iPhone",
         "Casa, Trabajo y lugares guardados; el historial de búsquedas (puedes desactivarlo); tus rutas completadas y estadísticas; las zonas exploradas; y tus preferencias. Todo se guarda solo en el dispositivo. No hay cuentas ni registro."),
        ("Tu ubicación",
         "La app usa tu ubicación solo mientras está abierta, para mostrarte en el mapa y guiarte. No se envía a ningún servidor propio, porque la app no tiene servidores."),
        ("Servicios externos que se contactan",
         "Para funcionar, la app envía solicitudes a servicios de terceros basados en datos de OpenStreetMap: OpenFreeMap (teselas del mapa: se pide la zona que miras), OSRM (rutas: origen y destino), Photon (búsqueda: el texto que escribes y tu posición aproximada para ordenar resultados) y, para «lugares cercanos», los mismos tiles de OpenFreeMap (se piden las zonas que rodean tu posición o la zona que elijas). Esos servicios pueden registrar tu dirección IP y los datos de la solicitud según sus propias políticas; la app no controla esos registros."),
        ("Lo que la app no hace",
         "No muestra anuncios, no incluye analíticas ni rastreadores propios, no vende datos y no comparte tu información con anunciantes."),
        ("Eliminar tus datos",
         "En Perfil › Eliminar mis datos se borran todos los datos que guarda la app en este iPhone. No se pueden borrar desde la app los registros técnicos que pudieran conservar los servicios externos."),
        ("Cambios",
         "Si cambian los servicios o los datos que usa la app, este texto se actualizará en la misma versión."),
    ]

    private static let terms: [(String, String)] = [
        ("Uso de la app",
         "QuestMap IRL es una ayuda a la navegación gratuita. Las rutas, tiempos e indicaciones son orientativos."),
        ("Conducción segura",
         "Respeta siempre las normas de tráfico y la señalización real. No manipules el teléfono mientras conduces; ante cualquier diferencia entre la app y la realidad, prevalece la realidad."),
        ("Datos de mapas",
         "Los mapas, rutas y lugares proceden de datos de OpenStreetMap (© colaboradores de OpenStreetMap, licencia ODbL) y pueden contener errores o estar desactualizados. Los servicios públicos utilizados no ofrecen garantía de disponibilidad."),
        ("Estilos de mapa",
         "Los estilos visuales son creaciones propias inspiradas en el lenguaje gráfico de los videojuegos. La app no está afiliada, patrocinada ni respaldada por ningún videojuego ni empresa de videojuegos."),
        ("Sin garantías",
         "La app se ofrece tal cual, sin garantías de funcionamiento ininterrumpido ni de exactitud. El uso es responsabilidad del usuario."),
        ("Gratuita",
         "Todas las funciones están disponibles sin pagos, suscripciones ni anuncios."),
    ]
}

// MARK: - Elegir voz

/// Lista las voces españolas realmente instaladas, con su calidad, para escucharlas y elegir una.
/// La lista se vuelve a leer al volver a la app (por ejemplo después de descargar una voz).
struct VoicePickerView: View {
    @Bindable var speech: SpeechService

    var body: some View {
        let choices = speech.voiceChoices
        let chosenID = speech.preferredVoiceID(for: speech.gender)
        List {
            Section {
                Button {
                    speech.setPreferredVoice(nil, for: speech.gender)
                } label: {
                    row(title: "Automática", detail: "La mejor voz de \(speech.gender.label) disponible",
                        selected: chosenID == nil, action: nil)
                }
            } footer: {
                Text("Se elige la voz de España de mayor calidad disponible para \(speech.gender.label).")
            }

            Section {
                if choices.matching.isEmpty {
                    Text("iOS no declara ninguna voz de \(speech.gender.label) en español instalada.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                ForEach(choices.matching, id: \.identifier) { voice in voiceRow(voice, chosenID: chosenID) }
            } header: {
                Text("Voces de \(speech.gender.label) instaladas")
            }

            if !choices.unspecified.isEmpty {
                Section {
                    ForEach(choices.unspecified, id: \.identifier) { voice in voiceRow(voice, chosenID: chosenID) }
                } header: {
                    Text("Género no indicado por iOS")
                } footer: {
                    Text("iOS no dice si estas voces son de chica o de chico. Si eliges una, es decisión tuya.")
                }
            }

            Section {
                Text("Para más voces: Ajustes › Accesibilidad › Contenido hablado › Voces › Español, y descarga las versiones Mejorada o Premium. Al volver a la app, la lista se actualiza sola. Solo aparecen las voces que iOS permite usar a las apps.")
                    .font(.footnote).foregroundStyle(AppColor.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Elegir voz")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { speech.refreshVoices() }
        .onDisappear { speech.stopTestIfPlaying() }
    }

    private func voiceRow(_ voice: VoiceInfo, chosenID: String?) -> some View {
        Button {
            speech.setPreferredVoice(voice.identifier, for: speech.gender)
            speech.preview(voice)
        } label: {
            row(title: voice.name, detail: "\(voice.languageLabel) · \(voice.qualityLabel)",
                selected: chosenID == voice.identifier, action: nil)
        }
        .accessibilityHint("Elige esta voz y la reproduce")
    }

    private func row(title: String, detail: String, selected: Bool, action: (() -> Void)?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(AppColor.textPrimary)
                Text(detail).font(.caption).foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
    }
}
