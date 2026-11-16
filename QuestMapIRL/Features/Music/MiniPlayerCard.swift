import SwiftUI

/// Tarjeta compacta de música: servicio activo, carátula, título, artista y anterior / reproducir-pausar / siguiente. Solo
/// muestra datos reales del servicio; cuando no hay información lo dice, sin canciones de ejemplo y sin botones simulados.
/// Cada control se activa solo si el servicio lo permite en ese momento.
struct MiniPlayerCard: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.openURL) private var openURL
    let model: MusicPlayerModel
    @State private var confirmSpotify = false

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
        .confirmationDialog("Conectar Spotify", isPresented: $confirmSpotify, titleVisibility: .visible) {
            Button("Abrir Spotify y conectar") { Task { await model.connect() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(MusicServiceNotes.spotifyConnectWarning)
        }
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
                HStack(spacing: 4) {
                    Image(systemName: model.service.symbol).font(.caption2.weight(.bold))
                    Text(subtitle).lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
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
        case .playing, .paused: return model.track?.title ?? "Reproduciendo en \(model.serviceName)"
        case .noPlaybackInfo: return "Sin información de reproducción"
        case .notConfigured: return model.serviceName
        case .connecting: return "Conectando…"
        case .denied: return "Permiso denegado"
        case .restricted: return "\(model.serviceName) restringido"
        case .unavailable: return "\(model.serviceName) no disponible"
        case .missingConfiguration: return "Falta configurar \(model.serviceName)"
        case .notInstalled: return "\(model.serviceName) no está instalado"
        case .expired: return "Sesión caducada"
        case .connectionError: return "No se pudo conectar"
        }
    }

    private var subtitle: String {
        let name = model.serviceName
        switch model.status {
        case .playing, .paused:
            if let artist = model.track?.artist, !artist.isEmpty { return "\(name) · \(artist)" }
            return model.track == nil ? "\(name) · sin datos de la canción" : name
        case .noPlaybackInfo:
            return model.service == .systemExperimental ? "Si suena algo y no sale aquí, iOS bloquea esta vía" : "\(name) · inicia música en la app"
        case .notConfigured: return "Conecta \(name) para controlarla"
        case .connecting: return model.service == .spotify ? "Vuelve aquí tras aceptar en Spotify" : "Acepta el permiso del sistema"
        case .denied: return model.service == .appleMusic ? "Actívalo en Ajustes del iPhone" : "Spotify rechazó la autorización"
        case .restricted: return "Un perfil o control parental lo impide"
        case .unavailable: return "Inténtalo más tarde"
        case .missingConfiguration: return "Mira Ajustes de navegación › Música"
        case .notInstalled: return "Instálalo desde App Store"
        case .expired: return "Vuelve a conectar \(name)"
        case .connectionError: return model.service == .spotify ? "Abre Spotify y toca Reconectar" : "Inténtalo de nuevo"
        }
    }

    // MARK: Derecha: controles o acción

    @ViewBuilder
    private var trailing: some View {
        switch model.status {
        case .notConfigured:
            action("Conectar") { startConnect() }
        case .expired, .connectionError:
            action("Reconectar") { startConnect() }
        case .denied:
            if model.service == .appleMusic {
                action("Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else {
                action("Reintentar") { startConnect() }
            }
        case .connecting:
            ProgressView().controlSize(.small)
        case .restricted, .unavailable, .missingConfiguration, .notInstalled:
            EmptyView()
        case .noPlaybackInfo, .playing, .paused:
            controls
        }
    }

    private func startConnect() {
        if model.service == .spotify { confirmSpotify = true } else { Task { await model.connect() } }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            control("backward.fill", "Canción anterior", enabled: model.canPrevious) { model.previous() }
            control(model.isPlaying ? "pause.fill" : "play.fill", model.isPlaying ? "Pausar" : "Reproducir",
                    enabled: model.canPlayPause, prominent: true) { model.togglePlayPause() }
            control("forward.fill", "Canción siguiente", enabled: model.canNext) { model.next() }
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

/// Textos de requisitos y avisos por servicio (centralizados).
enum MusicServiceNotes {
    static let spotifyConnectWarning = "Se abrirá la app de Spotify para autorizar a QuestMap IRL. Según Spotify, al conectar así puede reanudarse tu última canción o empezar otra. Después vuelve a esta app. Solo se pide permiso para controlar la reproducción (app-remote-control)."

    static func requirements(for service: MusicServiceID) -> String {
        switch service {
        case .appleMusic:
            return "Controla lo que suena en la app Música del iPhone. Conectar solo pide permiso de lectura: no cambia tu cola ni inicia música. Para revocar el permiso, usa Ajustes del iPhone."
        case .systemExperimental:
            return "EXPERIMENTAL · usa una API privada de Apple (MediaRemote) para ver y controlar lo que suene en cualquier app (YouTube Music, podcasts, radio…). Solo para uso personal: App Store rechaza apps que la usan, puede dejar de funcionar con cualquier actualización de iOS y es muy posible que iOS 17 o posterior la bloquee y no muestre nada. Para saberlo hay que probarlo con música sonando."
        case .spotify:
            return "Controla la app de Spotify instalada (no reproduce dentro de esta app). Requisitos: la app de Spotify instalada y con sesión iniciada; un Client ID propio en Spotify for Developers con el Redirect URI questmap-irl://spotify-login-callback; en modo desarrollo, el dueño necesita Spotify Premium y solo pueden usarlo hasta 5 usuarios añadidos a la lista. Saltar canciones depende de lo que permita tu cuenta. La conexión se corta al salir de la app y se recupera al volver si Spotify está abierto."
        }
    }
}
