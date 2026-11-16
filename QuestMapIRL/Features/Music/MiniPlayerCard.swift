import SwiftUI

/// Tarjeta compacta de música: carátula, título, artista y anterior / reproducir-pausar / siguiente. Solo muestra datos
/// reales del servicio; cuando no hay información lo dice, sin canciones de ejemplo y sin botones simulados.
struct MiniPlayerCard: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.openURL) private var openURL
    let model: MusicPlayerModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 4)
                trailing
            }
            if let message = model.message {
                Text(message)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.panelBorder.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: Izquierda: carátula y textos

    private var leading: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = model.artwork {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    theme.accent.opacity(0.18)
                    Image(systemName: "music.note").font(.headline).foregroundStyle(theme.accent)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var title: String {
        switch model.status {
        case .playing, .paused: return model.track?.title ?? "Reproduciendo en Música"
        case .noPlaybackInfo: return "Sin información de reproducción"
        case .notConfigured: return "Música"
        case .connecting: return "Conectando…"
        case .denied: return "Permiso de Música denegado"
        case .restricted: return "Música restringida"
        case .unavailable: return "Música no disponible"
        }
    }

    private var subtitle: String {
        switch model.status {
        case .playing, .paused:
            if let artist = model.track?.artist, !artist.isEmpty { return artist }
            return model.track == nil ? "Sin datos de la canción" : model.serviceName
        case .noPlaybackInfo: return "Inicia música en \(model.serviceName)"
        case .notConfigured: return "Conecta \(model.serviceName) para controlarla"
        case .connecting: return "Acepta el permiso del sistema"
        case .denied: return "Actívalo en Ajustes del iPhone"
        case .restricted: return "Un perfil o control parental lo impide"
        case .unavailable: return "Inténtalo más tarde"
        }
    }

    // MARK: Derecha: controles o acción

    @ViewBuilder
    private var trailing: some View {
        switch model.status {
        case .notConfigured:
            action("Conectar") { Task { await model.connect() } }
        case .denied:
            action("Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .connecting:
            ProgressView().controlSize(.small)
        case .restricted, .unavailable:
            EmptyView()
        case .noPlaybackInfo, .playing, .paused:
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            control("backward.fill", "Canción anterior", enabled: model.canControl) { model.previous() }
            control(model.isPlaying ? "pause.fill" : "play.fill", model.isPlaying ? "Pausar" : "Reproducir",
                    enabled: model.canControl, prominent: true) { model.togglePlayPause() }
            control("forward.fill", "Canción siguiente", enabled: model.canControl) { model.next() }
        }
    }

    private func control(_ symbol: String, _ label: String, enabled: Bool, prominent: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 20 : 17, weight: .bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? theme.textPrimary : theme.textSecondary.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func action(_ text: String, perform: @escaping () -> Void) -> some View {
        Button(text, action: perform)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(theme.isDark ? Color.black : Color.white)
            .background(theme.accent, in: Capsule())
            .buttonStyle(.plain)
    }
}
