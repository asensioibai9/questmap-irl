import SwiftData
import SwiftUI

/// Lista guiada de frases de un perfil: progreso, filtros, grabar / escuchar / repetir / borrar, probar la voz y usarla.
struct VoiceProfileDetailView: View {
    let profile: VoiceProfile
    let environment: AppEnvironment

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todas", pending = "Pendientes", recorded = "Grabadas"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.mapTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecordings: [VoiceRecording]
    @Query private var settingsRows: [UserSettings]

    @State private var filter: Filter = .all
    @State private var recordingPhrase: VoicePhrase?
    @State private var confirmDelete: VoicePhrase?
    @State private var confirmDeleteProfile = false
    @State private var showRename = false
    @State private var newName = ""
    @State private var message: String?

    private var store: VoiceProfileStore { VoiceProfileStore(context: context) }
    private var settings: UserSettings? { settingsRows.first }
    private var phrases: [VoicePhrase] { VoicePromptCatalog.phrases(language: profile.languageCode) }
    private var recordings: [VoiceRecording] { allRecordings.filter { $0.profileID == profile.profileID } }
    private var recorded: Set<VoicePhraseID> {
        _ = allRecordings.count
        return store.recordedPhrases(for: profile.profileID)
    }
    private var progress: VoiceProfileProgress { VoiceProfileProgress.make(recorded: recorded, language: profile.languageCode) }
    private var isActive: Bool { settings?.activeVoiceProfileID == profile.profileID }
    private var strategy: VoiceFallbackStrategy { settings?.voiceFallback ?? .hybrid }
    private var isNavigating: Bool { environment.hub.isNavigating }

    var body: some View {
        List {
            header
            Section {
                Picker("Mostrar", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ForEach(VoicePhraseCategory.allCases) { category in
                let items = visible(in: category)
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items) { phrase in row(phrase) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { newName = profile.name; showRename = true } label: { Label("Renombrar", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDeleteProfile = true } label: { Label("Eliminar perfil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("Más opciones del perfil")
                }
            }
        }
        .sheet(item: $recordingPhrase) { phrase in
            VoiceRecordingView(profile: profile, initialPhrase: phrase, environment: environment) { current in
                nextPending(after: current)
            }
        }
        .confirmationDialog("¿Eliminar esta grabación?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { phrase in
            Button("Eliminar grabación", role: .destructive) {
                do { try store.deleteRecording(profileID: profile.profileID, phrase: phrase.id) } catch { message = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { phrase in
            Text("«\(phrase.text)» volverá a estar pendiente.")
        }
        .confirmationDialog("¿Eliminar el perfil «\(profile.name)»?", isPresented: $confirmDeleteProfile, titleVisibility: .visible) {
            Button("Eliminar perfil y grabaciones", role: .destructive) {
                // Primero se sale de la pantalla (no debe seguir leyendo un perfil borrado) y después se borra.
                let target = profile
                let store = store
                let settings = settings
                environment.speech.stopTestIfPlaying()
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    do {
                        try store.delete(target, settings: settings)
                    } catch {
                        StorageDiagnostics.record(operation: "voice-profile-delete", outcome: "error",
                                                  note: StorageErrorInfo.describe(error))
                    }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrarán todas sus grabaciones de este iPhone. No se puede deshacer.\(isActive ? " Las indicaciones volverán a la voz del sistema." : "")")
        }
        .alert("Renombrar perfil", isPresented: $showRename) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                do { try store.rename(profile, to: newName) } catch { message = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Aviso", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Cabecera

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: profile.avatarSymbol)
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(theme.accent.opacity(0.25), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(progress.recorded) de \(progress.total) grabadas").font(.headline)
                        Text(statusText).font(.caption).foregroundStyle(progress.isReady ? Color.green : AppColor.textSecondary)
                    }
                }
                ProgressView(value: Double(progress.recorded), total: Double(max(progress.total, 1))).tint(theme.accent)
                Text("Graba estas indicaciones para escucharlas durante tus rutas. Puedes repetir cada grabación cuando quieras.")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)

                if isNavigating {
                    Label("Termina la navegación para grabar o probar la voz.", systemImage: "car.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if let next = nextPending(after: nil) {
                    Button { recordingPhrase = next } label: {
                        Label("Continuar con la siguiente pendiente", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(isNavigating)
                }

                HStack(spacing: 10) {
                    Button { playDemo() } label: {
                        Label("Probar voz", systemImage: "play.circle.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isNavigating || demoSegments.isEmpty)

                    Button { activate() } label: {
                        Label(isActive ? "En uso" : "Usar esta voz", systemImage: isActive ? "checkmark.circle.fill" : "person.wave.2")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isActive)
                }
                if !progress.isReady {
                    Text(missingText)
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var statusText: String {
        if progress.isReady { return isActive ? "Lista para usar · en uso" : "Lista para usar" }
        return "Incompleta: faltan \(progress.missingRequired.count) obligatorias"
    }

    private var missingText: String {
        let names = progress.missingRequired.prefix(4).compactMap { VoicePromptCatalog.phrase($0, language: profile.languageCode)?.text }
        let more = progress.missingRequired.count > 4 ? " y \(progress.missingRequired.count - 4) más" : ""
        return "Obligatorias pendientes: \(names.map { "«\($0)»" }.joined(separator: ", "))\(more). Mientras falten, lo no grabado se dice con la voz del sistema."
    }

    // MARK: Filas

    private func visible(in category: VoicePhraseCategory) -> [VoicePhrase] {
        phrases.filter { $0.category == category }.filter {
            switch filter {
            case .all: return true
            case .pending: return !recorded.contains($0.id)
            case .recorded: return recorded.contains($0.id)
            }
        }
    }

    private func row(_ phrase: VoicePhrase) -> some View {
        let done = recorded.contains(phrase.id)
        let duration = recordings.first { $0.phraseID == phrase.id }?.duration
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("«\(phrase.text)»").font(.body.weight(.medium)).foregroundStyle(AppColor.textPrimary)
                HStack(spacing: 6) {
                    Text(phrase.required ? "Obligatoria" : "Opcional")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((phrase.required ? theme.accent : AppColor.surfaceRaised).opacity(0.3), in: Capsule())
                    if done, let duration {
                        Label(String(format: "%.1f s", duration), systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Label("Pendiente", systemImage: "circle.dashed").font(.caption).foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            Spacer(minLength: 4)
            if done {
                Button { play(phrase) } label: {
                    Image(systemName: "play.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .disabled(isNavigating)
                .accessibilityLabel("Escuchar «\(phrase.text)»")
            }
            Button { recordingPhrase = phrase } label: {
                Image(systemName: done ? "arrow.counterclockwise" : "mic.fill").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(isNavigating)
            .accessibilityLabel(done ? "Volver a grabar «\(phrase.text)»" : "Grabar «\(phrase.text)»")
        }
        .swipeActions(edge: .trailing) {
            if done {
                Button(role: .destructive) { confirmDelete = phrase } label: { Label("Eliminar", systemImage: "trash") }
            }
        }
        .contextMenu {
            if done {
                Button(role: .destructive) { confirmDelete = phrase } label: { Label("Eliminar grabación", systemImage: "trash") }
            }
        }
    }

    // MARK: Acciones

    /// Siguiente frase pendiente (obligatorias primero), después de `current` si se indica.
    private func nextPending(after current: VoicePhraseID?) -> VoicePhrase? {
        let done = store.recordedPhrases(for: profile.profileID)
        let ordered = phrases.filter(\.required) + phrases.filter { !$0.required }
        return ordered.first { !done.contains($0.id) && $0.id != current }
    }

    private func play(_ phrase: VoicePhrase) {
        guard let segment = store.segments(for: profile.profileID)[phrase.id] else {
            message = "No se encuentra el archivo de esta grabación. Vuelve a grabarla."
            return
        }
        environment.speech.playRecordedDemo([segment])
    }

    /// Demostración (no inicia ninguna ruta): frases ejemplo que el perfil tenga grabadas.
    private var demoSegments: [VoicePromptSegment] {
        _ = allRecordings.count
        let segments = store.segments(for: profile.profileID)
        let examples: [[VoicePhraseID]] = [[.in200m, .turnRight], [.in500m, .turnLeft], [.roundaboutExit2], [.arrived]]
        let usable = examples.filter { $0.allSatisfy { segments[$0] != nil } }.prefix(2)
        return usable.flatMap { $0.compactMap { segments[$0] } }
    }

    private func playDemo() {
        environment.speech.playRecordedDemo(demoSegments)
    }

    private func activate() {
        guard progress.canActivate(strategy: strategy) else {
            message = strategy == .recordingsOnly
                ? "Con «Solo mis grabaciones» el perfil necesita todas las frases obligatorias. Grábalas o cambia a «Híbrido» en la pantalla anterior."
                : "Graba al menos una frase para usar este perfil."
            return
        }
        settings?.activeVoiceProfileID = profile.profileID
        PersistenceCommit.saveQuietly(context, operation: "voice-select")
        if !progress.isReady {
            message = "Perfil activado. Mientras esté incompleto, las indicaciones sin grabación se dirán con la voz del sistema."
        }
    }
}
