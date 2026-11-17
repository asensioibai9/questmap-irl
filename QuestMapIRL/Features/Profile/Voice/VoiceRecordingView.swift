import SwiftData
import SwiftUI

/// Grabar una frase: texto grande, cuenta atrás opcional, medidor de nivel, detener, escuchar, repetir, guardar y
/// siguiente. No graba nunca sin pulsar «Grabar» y no permite grabar durante una navegación.
struct VoiceRecordingView: View {
    let profile: VoiceProfile
    let environment: AppEnvironment
    let nextPhrase: (VoicePhraseID) -> VoicePhrase?

    @Environment(\.modelContext) private var context
    @Environment(\.mapTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phrase: VoicePhrase
    @State private var recorder = VoiceRecorder()
    @State private var saved = false
    @State private var saveError: String?

    init(profile: VoiceProfile, initialPhrase: VoicePhrase, environment: AppEnvironment,
         nextPhrase: @escaping (VoicePhraseID) -> VoicePhrase?) {
        self.profile = profile
        self.environment = environment
        self.nextPhrase = nextPhrase
        _phrase = State(initialValue: initialPhrase)
    }

    private var isNavigating: Bool { environment.hub.isNavigating }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Di exactamente:")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Text("«\(phrase.text)»")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColor.textPrimary)
                        .accessibilityLabel("Frase a grabar: \(phrase.text)")
                    if let hint = phrase.hint {
                        Text(hint).font(.footnote).foregroundStyle(AppColor.textSecondary).multilineTextAlignment(.center)
                    }

                    if isNavigating {
                        notice("Termina la navegación para grabar. No se usa el micrófono mientras conduces.", icon: "car.fill", color: .orange)
                    } else if recorder.permission == .denied {
                        permissionDenied
                    } else {
                        controls
                    }

                    tips
                }
                .padding(20)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .onAppear { environment.speech.stopTestIfPlaying() }
            .onDisappear { recorder.tearDown() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Controles

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .idle, .failed:
            if case .failed(let text) = recorder.state { notice(text, icon: "exclamationmark.triangle.fill", color: .orange) }
            if saved { notice("Grabación guardada.", icon: "checkmark.circle.fill", color: .green) }
            recordButton
            countdownPicker
            if saved, let next = nextPhrase(phrase.id) {
                Button { goTo(next) } label: {
                    Label("Siguiente frase", systemImage: "forward.fill").frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
            }
        case .countdown(let seconds):
            Text("\(seconds)")
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.accent)
                .accessibilityLabel("Empieza en \(seconds)")
            Button("Cancelar") { recorder.stop() }
                .frame(minHeight: 44)
        case .recording:
            recordingIndicator
            Button { recorder.stop() } label: {
                Label("Detener", systemImage: "stop.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        case .recorded(let analysis):
            result(analysis)
        }
    }

    private var recordButton: some View {
        Button {
            saved = false
            Task { await recorder.startRequested() }
        } label: {
            Label(saved ? "Grabar de nuevo" : "Grabar", systemImage: "mic.fill")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityHint("Empieza a grabar tras la cuenta atrás")
    }

    private var countdownPicker: some View {
        Picker("Cuenta atrás", selection: $recorder.countdownSeconds) {
            Text("Sin cuenta atrás").tag(0)
            Text("3 s").tag(3)
            Text("5 s").tag(5)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Cuenta atrás antes de grabar")
    }

    private var recordingIndicator: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 12, height: 12)
                Text("Grabando").font(.headline).foregroundStyle(.red)
                Text(String(format: "%.1f s", recorder.elapsed)).font(.headline.monospacedDigit()).foregroundStyle(AppColor.textPrimary)
            }
            .accessibilityElement(children: .combine)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.surfaceRaised)
                    Capsule().fill(recorder.level > 0.92 ? Color.red : Color.green)
                        .frame(width: proxy.size.width * recorder.level)
                        .animation(.linear(duration: 0.05), value: recorder.level)
                }
            }
            .frame(height: 14)
            .accessibilityLabel("Nivel del micrófono")
            Text("Máximo \(Int(VoiceRecorder.maxDuration)) s").font(.caption).foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder
    private func result(_ analysis: AudioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: "Duración: %.1f s", analysis.duration)).font(.subheadline).foregroundStyle(AppColor.textPrimary)
            if analysis.issues.isEmpty {
                Label("Sonido correcto (nivel, saturación y silencios).", systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
            }
            ForEach(analysis.issues, id: \.self) { issue in
                Label(issue.message, systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(issue.isBlocking ? Color.red : Color.orange)
            }
            Text("Comprobamos el sonido, no las palabras: escúchala para confirmar que dice el texto.")
                .font(.caption).foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        HStack(spacing: 10) {
            Button { recorder.isPlayingBack ? recorder.stopPlayback() : recorder.playBack() } label: {
                Label(recorder.isPlayingBack ? "Parar" : "Escuchar", systemImage: recorder.isPlayingBack ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            Button {
                recorder.reset()
                Task { await recorder.startRequested() }
            } label: {
                Label("Repetir", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
        }
        Button { save(analysis) } label: {
            Label("Guardar", systemImage: "square.and.arrow.down.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .disabled(!analysis.canSave)
        if let saveError { notice(saveError, icon: "exclamationmark.triangle.fill", color: .orange) }
    }

    private var permissionDenied: some View {
        VStack(spacing: 12) {
            notice("Sin permiso de micrófono no se puede grabar. Actívalo en Ajustes › QuestMap IRL › Micrófono.", icon: "mic.slash.fill", color: .orange)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .frame(minHeight: 44)
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Consejos").font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.textPrimary)
            ForEach(["Graba en un lugar tranquilo, sin música de fondo.",
                     "Mantén siempre la misma distancia al micrófono.",
                     "Habla con naturalidad y el mismo tono en todas las frases.",
                     "Empieza a hablar enseguida y no alargues el final."], id: \.self) { tip in
                Label(tip, systemImage: "lightbulb").font(.caption).foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func notice(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Acciones

    private func save(_ analysis: AudioAnalysis) {
        guard let url = recorder.temporaryURL else { saveError = VoiceStoreError.missingRecording.errorDescription; return }
        recorder.stopPlayback()
        do {
            try VoiceProfileStore(context: context).saveRecording(profileID: profile.profileID, phrase: phrase.id,
                                                                   from: url, analysis: analysis)
            saveError = nil
            saved = true
            recorder.reset()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func goTo(_ next: VoicePhrase) {
        recorder.reset()
        saved = false
        saveError = nil
        phrase = next
    }
}
