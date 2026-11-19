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
    var music: MusicPlayerModel?
    var supports3D = false
    var is3D = false
    var onToggle3D: () -> Void = {}
    var speedSign: SpeedSignAppearance = .defaults
    /// Distribución calculada con el espacio real (nil = vertical, como siempre).
    var layout: MapScreenLayout? = nil
    let onSearch: () -> Void
    let onEnd: () -> Void

    @AppStorage(SpeedLimitDiagnosticsCard.storageKey) private var limitDiagnostics = false
    @State private var showCredits = false

    private var limitSign: some View {
        VStack(alignment: .leading, spacing: 6) {
            if limitDiagnostics { SpeedLimitDiagnosticsCard(diagnostic: viewModel.speedLimitDiagnostic) }
            SpeedLimitSign(display: viewModel.speedLimit, metric: useMetric, appearance: speedSign,
                           countryCode: viewModel.speedLimitCountry, currentSpeedKmh: viewModel.currentSpeedKmh)
        }
    }

    private var signIsEmpty: Bool { SpeedLimitSign.isEmpty(viewModel.speedLimit, appearance: speedSign) && !limitDiagnostics }

    private var isSideBySide: Bool { layout?.isSideBySide ?? false }
    private var showsTopSign: Bool { speedSign.position != .automatic && !signIsEmpty }

    /// Vertical: maniobra y estado arriba, panel abajo (como siempre).
    /// Horizontal, misma estructura que sin ruta: panel de navegación a la izquierda, mapa libre en medio con un grupo
    /// discreto de GPS, velocidad y límite, y a la derecha el mismo grupo de controles y el crédito del mapa.
    /// La zona central (HUD y minimapa) conserva su identidad al girar: no se recrea el minimapa ni se pierde nada.
    var body: some View {
        let outer = isSideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(spacing: 10))
        outer {
            if isSideBySide {
                sideColumn.frame(width: layout?.sidePanelWidth ?? 320)
            } else {
                header
            }

            centerArea

            if isSideBySide {
                if display == .map { rightColumn }
            } else {
                // El reproductor va en su propia fila, encima del panel: no tapa la ruta, la maniobra ni la señal.
                if let music, music.isVisible {
                    MiniPlayerCard(model: music)
                }
                bottomPanel
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .sheet(isPresented: $showCredits) { MapCreditsView(onClose: { showCredits = false }) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ManeuverCard(viewModel: viewModel, theme: theme, useMetric: useMetric)
            statusRow
            // Posiciones «arriba»: fila propia bajo la maniobra y el estado, así no tapa nada.
            if showsTopSign { topSignRow }
        }
    }

    private var topSignRow: some View {
        HStack {
            if speedSign.position == .topTrailing { Spacer() }
            limitSign
            if speedSign.position == .topLeading { Spacer() }
        }
    }

    /// Panel de navegación (horizontal): maniobra, avisos de la ruta y datos de llegada con sus acciones. Ocupa el alto útil
    /// y, si con texto grande no cabe, se desplaza el panel, nunca el mapa. Sustituye al buscador (no se apila encima).
    private var sideColumn: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 8) {
                ManeuverCard(viewModel: viewModel, theme: theme, useMetric: useMetric)
                routeNotices
                Spacer(minLength: 8)
                bottomPanel
            }
            ScrollView {
                VStack(spacing: 8) {
                    ManeuverCard(viewModel: viewModel, theme: theme, useMetric: useMetric)
                    routeNotices
                    bottomPanel
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Zona del mapa. Vertical: señal y botones (o HUD). Horizontal: grupo de GPS, velocidad y límite arriba y el
    /// reproductor abajo (o HUD con minimapa).
    private var centerArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSideBySide, display == .map {
                indicatorGroup
            }
            if display == .hud {
                hudBody
            } else {
                Spacer(minLength: 0)
                if isSideBySide {
                    if let music, music.isVisible {
                        MiniPlayerCard(model: music).frame(maxWidth: 320)
                    }
                } else {
                    HStack(alignment: .bottom) {
                        if speedSign.position == .automatic { limitSign }
                        Spacer()
                        sideButtons
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// GPS discreto, velocidad actual y límite de la vía juntos, sin invadir el panel. La velocidad actual y el límite se
    /// siguen viendo por separado; si no hay límite fiable, la señal aplica su lógica de siempre («—» o nada).
    private var indicatorGroup: some View {
        HStack(alignment: .top, spacing: 8) {
            GPSIndicator(theme: theme, status: location.status, accuracy: location.currentLocation?.horizontalAccuracy, compact: true)
                .fixedSize()
            Text(Formatters.speed(viewModel.speedKmh, metric: useMetric))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(theme.panel, in: .capsule)
                .overlay(Capsule().stroke(theme.panelBorder, lineWidth: 1))
                .accessibilityLabel("Velocidad actual \(Formatters.speed(viewModel.speedKmh, metric: useMetric))")
            if !signIsEmpty { limitSign }
        }
    }

    /// Derecha (horizontal): el mismo grupo de controles que sin ruta y el crédito del mapa en la esquina inferior.
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer(minLength: 0)
            sideButtons
            MapAttributionLabel(text: theme.activeCartography.attribution) { showCredits = true }
                .fixedSize()
        }
    }

    /// Avisos de la ruta en el panel lateral (el indicador GPS va en el grupo del mapa).
    @ViewBuilder
    private var routeNotices: some View {
        if viewModel.recalculationFailed || network.showsOfflineNotice {
            HStack(spacing: 6) {
                if viewModel.recalculationFailed { chip("Vuelve a la ruta", "arrow.uturn.backward", .red) }
                if network.showsOfflineNotice { chip("Sin conexión", "wifi.slash", .orange) }
                Spacer(minLength: 0)
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
            if isSideBySide, !signIsEmpty, speedSign.position != .automatic { topSignRow }
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
                if speedSign.position == .automatic { limitSign }
            }
        }
    }

    // MARK: - Controles laterales (modo mapa)

    /// Vertical: botones redondos. Horizontal: el mismo grupo compacto que sin ruta.
    @ViewBuilder
    private var sideButtons: some View {
        if isSideBySide {
            MapControlCluster(items: controlItems, accent: theme.accent, background: theme.panel, border: theme.panelBorder,
                              iconWeight: theme.iconWeight)
        } else {
            VStack(spacing: 12) {
                ForEach(controlItems) { item in
                    MapRoundButton(theme: theme, systemImage: item.systemImage, label: item.label, isActive: item.isActive,
                                   action: item.action)
                }
            }
        }
    }

    /// Orientación (brújula / «N») y recentrar (flecha de ubicación) son funciones distintas, con iconos distintos.
    private var controlItems: [MapControlItem] {
        var items = [
            MapControlItem(id: "orientation", systemImage: MapOrientationIcon.symbol(headingUp: headingUp),
                           label: headingUp ? "El mapa gira con tu rumbo. Cambiar a norte arriba" : "Norte arriba. Cambiar a mapa según tu rumbo",
                           isActive: headingUp) {
                headingUp.toggle()
                showFullRoute = false
                onRecenter()
            },
        ]
        if supports3D {
            items.append(MapControlItem(id: "3d", systemImage: is3D ? "view.3d" : "view.2d",
                                        label: is3D ? "Cambiar a vista 2D" : "Cambiar a vista 3D", isActive: is3D) { onToggle3D() })
        }
        items.append(MapControlItem(id: "recenter", systemImage: "location.fill", label: "Recentrar") {
            showFullRoute = false
            onRecenter()
        })
        return items
    }

    // MARK: - Panel inferior

    private var bottomPanel: some View {
        QuestPanel(theme: theme) {
            VStack(spacing: 12) {
                ProgressView(value: viewModel.snapshot.progress)
                    .tint(theme.accent)
                    .accessibilityLabel("Progreso de la ruta \(Int(viewModel.snapshot.progress * 100)) por ciento")

                if isSideBySide {
                    // Horizontal: llegada, tiempo y distancia restantes (la velocidad va en el grupo del mapa).
                    HStack(alignment: .firstTextBaseline) {
                        metric(Text(viewModel.eta, style: .time), "llegada", alignment: .leading)
                        Spacer(minLength: 4)
                        metric(Text(NavigationTimeText.remaining(viewModel.snapshot.remainingSeconds)), "tiempo", alignment: .center)
                        Spacer(minLength: 4)
                        metric(Text(Formatters.distance(viewModel.snapshot.remainingMeters, metric: useMetric)), "restan", alignment: .trailing)
                    }
                    .foregroundStyle(theme.textPrimary)
                } else {
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
                }

                NavControlsBar(theme: theme,
                               isMuted: speech.isMuted,
                               showFullRoute: showFullRoute,
                               isHUD: display == .hud,
                               stacked: isSideBySide,
                               onMute: { speech.toggleMute() },
                               onToggleRoute: { showFullRoute.toggle() },
                               onSearch: onSearch,
                               onToggleDisplay: { display = display == .map ? .hud : .map },
                               onEnd: onEnd)

                // En horizontal con mapa, el crédito va en la esquina inferior derecha (como sin ruta).
                if !isSideBySide || display == .hud {
                    Text(theme.activeCartography.attribution)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityHidden(true)
                }
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
    /// Columna estrecha (horizontal): botones de 44 pt (mínimo táctil) en una sola fila, para que el panel quepa en
    /// poca altura. «Finalizar» muestra el texto si cabe y, si no, solo la «X» (con la misma etiqueta de accesibilidad).
    var stacked = false
    let onMute: () -> Void
    let onToggleRoute: () -> Void
    let onSearch: () -> Void
    let onToggleDisplay: () -> Void
    let onEnd: () -> Void

    private var side: CGFloat { stacked ? 44 : 52 }

    var body: some View {
        HStack(spacing: stacked ? 6 : 8) {
            controls
            endButton
        }
    }

    @ViewBuilder
    private var controls: some View {
        control(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", isMuted ? "Activar voz" : "Silenciar voz", onMute)
        if !isHUD {
            control(showFullRoute ? "location.fill" : "map.fill", showFullRoute ? "Volver a seguirme" : "Ver ruta completa", onToggleRoute)
        }
        control("magnifyingglass", "Buscar otro destino", onSearch)
        control(isHUD ? "map" : "rectangle.inset.filled.bottomleading", isHUD ? "Abrir mapa completo" : "Modo HUD con minimapa", onToggleDisplay)
    }

    private var endButton: some View {
        Button(action: onEnd) {
            ViewThatFits(in: .horizontal) {
                Label("Finalizar", systemImage: "xmark").lineLimit(1)
                Image(systemName: "xmark")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: side)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityLabel("Finalizar la navegación")
    }

    private func control(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: theme.iconWeight))
                .frame(width: stacked ? 44 : 48, height: side)
                .foregroundStyle(theme.accent)
                .background(theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        }
        .accessibilityLabel(label)
    }
}

/// Tiempo restante del motor de navegación en texto corto («8 min», «1 h 05 min»). Menos de un minuto: «<1 min».
enum NavigationTimeText {
    static func remaining(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }
}
