import SwiftUI

enum NavDisplay {
    /// Mapa a pantalla completa con el HUD encima.
    case map
    /// HUD grande con minimapa compacto superpuesto.
    case hud
}

/// HUD de navegación activa. Se dibuja sobre el mismo mapa de la pantalla principal (misma
/// cámara, mismo estilo): no abre otro mapa. En modo `.hud` el mapa grande se sustituye por un
/// fondo y aparece el minimapa.
struct NavigationOverlay: View {
    @Environment(\.mapTheme) private var theme

    let viewModel: ActiveNavigationViewModel
    @Binding var display: NavDisplay
    @Binding var showFullRoute: Bool
    @Binding var headingUp: Bool
    let location: LocationServiceProtocol
    let speech: SpeechService
    let network: NetworkMonitor
    let miniMap: MapController
    let useMetric: Bool
    let onRecenter: () -> Void
    var supports3D = false
    var is3D = false
    var onToggle3D: () -> Void = {}
    let onSearch: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ManeuverCard(viewModel: viewModel, theme: theme, useMetric: useMetric)
            statusRow

            if display == .hud {
                hudBody
            } else {
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    SpeedLimitSign(display: viewModel.speedLimit, metric: useMetric)
                    Spacer()
                    sideButtons
                }
            }

            bottomPanel
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    // MARK: - Estado (GPS, conexión, recálculo)

    private var statusRow: some View {
        VStack(spacing: 6) {
            HStack {
                GPSIndicator(theme: theme, status: location.status, accuracy: location.currentLocation?.horizontalAccuracy)
                Spacer()
                if viewModel.recalculationFailed {
                    chip("Vuelve a la ruta", "arrow.uturn.backward", .red)
                }
                if network.showsOfflineNotice {
                    chip("Sin conexión", "wifi.slash", .orange)
                }
            }
            if location.isSignalLost {
                Label("Ubicación sin confirmar: las indicaciones se pausan hasta recibir una lectura nueva.", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.red)
            }
        }
    }

    private func chip(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(theme.panel, in: .capsule)
            .foregroundStyle(color)
    }

    // MARK: - Modo HUD con minimapa

    private var hudBody: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Text(Formatters.speed(viewModel.speedKmh, metric: useMetric))
                .font(.system(size: 64, weight: .heavy, design: theme.titleDesign).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(theme.textPrimary)
                .accessibilityLabel("Velocidad \(Formatters.speed(viewModel.speedKmh, metric: useMetric))")
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                MinimapView(controller: miniMap, size: 150) { display = .map }
                Spacer()
                SpeedLimitSign(display: viewModel.speedLimit, metric: useMetric)
            }
        }
    }

    // MARK: - Controles laterales (modo mapa)

    private var sideButtons: some View {
        VStack(spacing: 12) {
            MapRoundButton(theme: theme,
                           systemImage: headingUp ? "location.north.line.fill" : "safari",
                           label: headingUp ? "Cambiar a norte arriba" : "Cambiar a vista según rumbo",
                           isActive: headingUp) {
                headingUp.toggle()
                showFullRoute = false
                onRecenter()
            }
            if supports3D {
                MapRoundButton(theme: theme, systemImage: is3D ? "view.3d" : "view.2d",
                               label: is3D ? "Cambiar a vista 2D" : "Cambiar a vista 3D", isActive: is3D) { onToggle3D() }
            }
            MapRoundButton(theme: theme, systemImage: "location.fill", label: "Recentrar") {
                showFullRoute = false
                onRecenter()
            }
        }
    }

    // MARK: - Panel inferior

    private var bottomPanel: some View {
        QuestPanel(theme: theme) {
            VStack(spacing: 12) {
                ProgressView(value: viewModel.snapshot.progress)
                    .tint(theme.accent)
                    .accessibilityLabel("Progreso de la ruta \(Int(viewModel.snapshot.progress * 100)) por ciento")

                HStack(alignment: .firstTextBaseline) {
                    metric(Text(viewModel.eta, style: .time), "llegada", alignment: .leading, big: true)
                    Spacer()
                    metric(Text(Formatters.distance(viewModel.snapshot.remainingMeters, metric: useMetric)), "restan", alignment: .center)
                    if display == .map {
                        Spacer()
                        metric(Text(Formatters.speed(viewModel.speedKmh, metric: useMetric)), "velocidad", alignment: .trailing)
                    }
                }
                .foregroundStyle(theme.textPrimary)

                NavControlsBar(theme: theme,
                               isMuted: speech.isMuted,
                               showFullRoute: showFullRoute,
                               isHUD: display == .hud,
                               onMute: { speech.toggleMute() },
                               onToggleRoute: { showFullRoute.toggle() },
                               onSearch: onSearch,
                               onToggleDisplay: { display = display == .map ? .hud : .map },
                               onEnd: onEnd)

                Text(theme.activeCartography.attribution)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
    }

    private func metric(_ value: Text, _ label: String, alignment: HorizontalAlignment, big: Bool = false) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            value
                .font(.system(big ? .title : .title3, design: theme.titleDesign).weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tarjeta de maniobra

struct ManeuverCard: View {
    let viewModel: ActiveNavigationViewModel
    let theme: MapTheme
    let useMetric: Bool

    var body: some View {
        QuestPanel(theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Image(systemName: viewModel.isRecalculating ? "arrow.triangle.2.circlepath" : viewModel.maneuverSymbol)
                        .font(.system(size: 44, weight: .bold))
                        .symbolEffect(.pulse, isActive: viewModel.isRecalculating)
                        .foregroundStyle(theme.accent)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Formatters.distance(viewModel.snapshot.distanceToManeuver, metric: useMetric))
                            .font(.system(.largeTitle, design: theme.titleDesign).weight(.heavy).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(viewModel.isRecalculating ? "Recalculando…" : viewModel.currentInstruction)
                            .font(.title3.weight(.medium))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                if let next = viewModel.nextInstruction, !viewModel.isRecalculating {
                    HStack(spacing: 6) {
                        Text("Después").font(.caption.weight(.semibold))
                        Image(systemName: viewModel.nextSymbol).font(.caption.weight(.bold))
                        Text(next).font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .foregroundStyle(theme.textPrimary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Controles

struct NavControlsBar: View {
    let theme: MapTheme
    let isMuted: Bool
    let showFullRoute: Bool
    let isHUD: Bool
    let onMute: () -> Void
    let onToggleRoute: () -> Void
    let onSearch: () -> Void
    let onToggleDisplay: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            control(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", isMuted ? "Activar voz" : "Silenciar voz", onMute)
            if !isHUD {
                control(showFullRoute ? "location.fill" : "map.fill", showFullRoute ? "Volver a seguirme" : "Ver ruta completa", onToggleRoute)
            }
            control("magnifyingglass", "Buscar otro destino", onSearch)
            control(isHUD ? "map" : "rectangle.inset.filled.bottomleading", isHUD ? "Abrir mapa completo" : "Modo HUD con minimapa", onToggleDisplay)
            Button(action: onEnd) {
                Label("Finalizar", systemImage: "xmark")
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func control(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: theme.iconWeight))
                .frame(width: 48, height: 52)
                .foregroundStyle(theme.accent)
                .background(theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        }
        .accessibilityLabel(label)
    }
}
