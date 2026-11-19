import SwiftData
import SwiftUI

/// Ajustes de navegación › Voz de las indicaciones: voz del sistema, mis perfiles de voz grabada y qué hacer con lo que
/// no esté grabado. Todo gratuito y desbloqueado.
struct VoiceProfilesView: View {
    let environment: AppEnvironment

    @Environment(\.modelContext) private var context
    @Environment(\.mapTheme) private var theme
    @Query(sort: \VoiceProfile.createdAt) private var profiles: [VoiceProfile]
    /// Se observa para refrescar el progreso al grabar o borrar.
    @Query private var recordings: [VoiceRecording]
    @Query private var settingsRows: [UserSettings]

    @State private var showCreate = false
    @State private var openProfile: VoiceProfile?
    @State private var errorMessage: String?

    private var settings: UserSettings? { settingsRows.first }
    private var store: VoiceProfileStore { VoiceProfileStore(context: context) }
    private var packs: GeneratedVoicePackLoader { .shared }
    private var speech: SpeechService { environment.speech }

    var body: some View {
        Form {
            Section {
                Button {
                    select(nil)
                } label: {
                    HStack(spacing: 12) {
                        avatar("speaker.wave.2.fill", color: AppColor.surfaceRaised)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voz del sistema").foregroundStyle(AppColor.textPrimary)
                            Text("Lee cualquier indicación, con nombres de calles").font(.caption).foregroundStyle(AppColor.textSecondary)
                        }
                        Spacer()
                        if settings?.usesSystemVoice ?? true { selectedMark }
                    }
                }
                .accessibilityAddTraits(settings?.usesSystemVoice ?? true ? .isSelected : [])
            } header: {
                Text("Voz activa")
            }

            Section {
                ForEach(GeneratedVoicePacks.all) { info in packRow(packs.pack(info)) }
            } header: {
                Text("Voces disponibles")
            } footer: {
                Text("Voces generadas con IA (ElevenLabs) que vienen dentro de la app: funcionan sin conexión y no envían nada durante la ruta. Dicen frases fijas; los nombres de calles y los números de salida se ven en pantalla y, en modo híbrido, se dicen enteros con la voz del sistema.")
            }

            Section {
                if profiles.isEmpty {
                    emptyState
                } else {
                    ForEach(profiles) { profile in row(profile) }
                    Button {
                        showCreate = true
                    } label: {
                        Label("Crear nuevo perfil", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                Text("Mis perfiles de voz")
            }

            if let settings {
                Section {
                    Picker("Si falta una grabación", selection: Binding(
                        get: { settings.voiceFallback },
                        set: { settings.voiceFallback = $0; PersistenceCommit.saveQuietly(context, operation: "voice-fallback") })) {
                        ForEach(VoiceFallbackStrategy.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Indicaciones sin grabación")
                } footer: {
                    Text(settings.voiceFallback.explanation + " Un perfil incompleto siempre usa la voz del sistema para lo que falte.")
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Las grabaciones son reproducciones de tu voz, no una voz artificial: solo se pueden decir las frases grabadas. Los nombres de calles y los números de salida se ven en pantalla. Se guardan solo en este iPhone (y en su copia de seguridad de iCloud o del ordenador, como el resto de datos de la app); no se suben a ningún servidor ni se usan para analítica. Graba tu propia voz o la de alguien que te haya dado permiso.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("Voz de las indicaciones")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) {
            CreateVoiceProfileSheet { name, language in
                do {
                    let profile = try store.createProfile(name: name, language: language)
                    showCreate = false
                    openProfile = profile
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .navigationDestination(item: $openProfile) { profile in
            VoiceProfileDetailView(profile: profile, environment: environment)
        }
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { store.cleanupOrphans() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            Text("Navega con tu propia voz")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Crea un perfil y graba una lista guiada de indicaciones («Gira a la derecha», «En doscientos metros»…). Puedes grabarlas en varios días. Durante la ruta sonarán tus grabaciones; lo que no esté grabado se dirá con la voz del sistema.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColor.textSecondary)
            Button {
                showCreate = true
            } label: {
                Text("Crear mi primera voz")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private func row(_ profile: VoiceProfile) -> some View {
        _ = recordings.count
        let progress = store.progress(for: profile)
        let isActive = settings?.activeVoiceProfileID == profile.profileID
        return Button {
            openProfile = profile
        } label: {
            HStack(spacing: 12) {
                avatar(profile.avatarSymbol, color: theme.accent.opacity(0.25))
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name).font(.body.weight(.semibold)).foregroundStyle(AppColor.textPrimary)
                    Text("\(progress.recorded) de \(progress.total) grabadas · \(progress.isReady ? "Lista para usar" : "Incompleta")")
                        .font(.caption)
                        .foregroundStyle(progress.isReady ? Color.green : AppColor.textSecondary)
                    ProgressView(value: Double(progress.recorded), total: Double(max(progress.total, 1)))
                        .tint(theme.accent)
                }
                Spacer()
                if isActive { selectedMark }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name). \(progress.recorded) de \(progress.total) grabaciones. \(progress.isReady ? "Lista para usar" : "Incompleta")\(isActive ? ". Voz activa" : "")")
    }

    /// Fila de un paquete generado: nombre, idioma, descripción, estado, muestra y selección. Solo se puede elegir si está
    /// completo; si no, se explica por qué.
    private func packRow(_ pack: LoadedGeneratedVoicePack) -> some View {
        let info = pack.info
        let isActive = settings?.activeGeneratedVoicePackID == info.id
        let ready = pack.availability.isReady
        let demo = pack.demoSegments
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                selectPack(info.id)
            } label: {
                HStack(spacing: 12) {
                    avatar(info.gender == .girl ? "person.fill" : "person", color: theme.accent.opacity(ready ? 0.35 : 0.12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title).font(.body.weight(.semibold))
                            .foregroundStyle(ready ? AppColor.textPrimary : AppColor.textSecondary)
                        Text("\(info.languageLabel) · \(info.gender.label)").font(.caption).foregroundStyle(AppColor.textSecondary)
                        Text(info.summary).font(.caption).foregroundStyle(AppColor.textSecondary)
                        Text(pack.availability.label).font(.caption.weight(.semibold))
                            .foregroundStyle(ready ? Color.green : AppColor.textSecondary)
                    }
                    Spacer()
                    if isActive { selectedMark }
                }
            }
            .buttonStyle(.borderless)
            .disabled(!ready)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(info.title). \(info.languageLabel). \(pack.availability.label)\(isActive ? ". Voz activa" : "")")
            .accessibilityAddTraits(isActive ? .isSelected : [])

            HStack {
                Button {
                    if speech.isPlayingTest { speech.stopImmediately() } else { speech.playRecordedDemo(demo) }
                } label: {
                    Label(speech.isPlayingTest ? "Parar" : "Escuchar muestra",
                          systemImage: speech.isPlayingTest ? "stop.fill" : "play.circle.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .disabled(demo.isEmpty)
                .frame(minHeight: 44)
                Spacer()
                Text(info.provenance).font(.caption2).foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func selectPack(_ id: String) {
        settings?.activeGeneratedVoicePackID = id
        PersistenceCommit.saveQuietly(context, operation: "voice-select-pack")
    }

    private func avatar(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(AppColor.textPrimary)
            .frame(width: 40, height: 40)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }

    private var selectedMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(theme.accent)
            .accessibilityHidden(true)
    }

    private func select(_ id: UUID?) {
        settings?.activeVoiceProfileID = id
        PersistenceCommit.saveQuietly(context, operation: "voice-select")
    }
}

/// Crear un perfil: nombre e idioma. Después se abre su lista de frases.
struct CreateVoiceProfileSheet: View {
    let onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var language = VoicePromptCatalog.defaultLanguage

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Por ejemplo: Mi voz", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                    Picker("Idioma", selection: $language) {
                        ForEach(VoicePromptCatalog.supportedLanguages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                } header: {
                    Text("Nombre del perfil")
                } footer: {
                    Text("Graba estas indicaciones para escucharlas durante tus rutas. Puedes repetir cada grabación cuando quieras, y no hace falta grabarlas todas de una vez: el progreso se guarda.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Nuevo perfil de voz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { onCreate(name, language) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
