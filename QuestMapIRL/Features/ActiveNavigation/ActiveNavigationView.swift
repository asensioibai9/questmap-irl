import SwiftUI
import MapKit

/// Navegación activa a pantalla completa: mapa detrás, maniobra grande arriba,
/// ETA / distancia / velocidad abajo y controles grandes.
struct ActiveNavigationView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var viewModel: ActiveNavigationViewModel
    let locationService: LocationServiceProtocol
    let speech: SpeechService
    let useMetric: Bool
    @State var headingUp: Bool

    @State private var camera: MapCameraPosition
    @State private var showFullRoute = false
    @State private var showSearch = false

    init(viewModel: ActiveNavigationViewModel, locationService: LocationServiceProtocol,
         speech: SpeechService, useMetric: Bool, headingUp: Bool) {
        self.viewModel = viewModel
        self.locationService = locationService
        self.speech = speech
        self.useMetric = useMetric
        _headingUp = State(initialValue: headingUp)
        _camera = State(initialValue: .userLocation(followsHeading: headingUp, fallback: .automatic))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                map
                MapOverlayView(theme: theme).allowsHitTesting(false).ignoresSafeArea()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 8) {
                    ManeuverCard(viewModel: viewModel, theme: theme, useMetric: useMetric)
                    HStack {
                        GPSIndicator(theme: theme, quality: locationService.quality, signalLost: locationService.isSignalLost)
                        Spacer()
                        if viewModel.recalculationFailed {
                            Label("Vuelve a la ruta", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).frame(height: 28)
                                .background(theme.panel, in: .capsule)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: 12) {
                    MapRoundButton(theme: theme,
                                   systemImage: headingUp ? "location.north.line.fill" : "safari",
                                   label: headingUp ? "Cambiar a norte arriba" : "Cambiar a vista según rumbo",
                                   isActive: headingUp) {
                        headingUp.toggle()
                        showFullRoute = false
                        follow()
                    }
                    MapRoundButton(theme: theme, systemImage: "location.fill", label: "Recentrar") {
                        showFullRoute = false
                        follow()
                    }
                }
                .padding(.trailing, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(theme.background.ignoresSafeArea())
        .statusBarHidden(false)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.start()
            if let loc = locationService.smoothedLocation { viewModel.update(with: loc) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: locationService.smoothedLocation) { _, location in
            guard let location else { return }
            viewModel.update(with: location)
        }
        .onChange(of: viewModel.finished) { _, finished in
            if finished { saveAndDismiss() }
        }
        .onChange(of: showFullRoute) { _, full in
            withAnimation(.smooth) {
                if full {
                    camera = .rect(viewModel.route.route.polyline.boundingMapRect.insetBy(dx: -900, dy: -900))
                } else {
                    follow()
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(near: locationService.smoothedLocation?.coordinate) { _, _ in
                // Cambiar de destino en plena navegación: cerramos y el Home recalcula.
                viewModel.stop()
            }
        }
    }

    // MARK: - Mapa

    private var map: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !theme.routeAnimated)) { timeline in
            let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * -32)
            Map(position: $camera) {
                if let loc = locationService.smoothedLocation {
                    Annotation("Tu posición", coordinate: loc.coordinate, anchor: .center) {
                        PlayerMarker(theme: theme, heading: headingUp ? 0 : locationService.displayHeading)
                    }
                    .annotationTitles(.hidden)
                }
                routeLayers(viewModel.route.route.polyline, theme: theme, phase: phase)
                Annotation(viewModel.destinationName, coordinate: viewModel.destination) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.system(size: 30, weight: theme.iconWeight))
                        .foregroundStyle(theme.destination)
                        .shadow(color: theme.destination.opacity(0.7), radius: 8)
                }
            }
            .mapStyle(theme.mapStyle)
            .mapControls { MapCompass() }
        }
        .ignoresSafeArea()
    }

    private func follow() {
        withAnimation(.smooth) {
            camera = .userLocation(followsHeading: headingUp, fallback: .automatic)
        }
    }

    // MARK: - Panel inferior

    private var bottomPanel: some View {
        QuestPanel(theme: theme) {
            VStack(spacing: 14) {
                ProgressView(value: viewModel.snapshot.progress)
                    .tint(theme.accent)
                    .accessibilityLabel("Progreso de la ruta \(Int(viewModel.snapshot.progress * 100)) por ciento")

                HStack(alignment: .firstTextBaseline) {
                    metric(Text(viewModel.eta, style: .time), "llegada", alignment: .leading, big: true)
                    Spacer()
                    metric(Text(Formatters.distance(viewModel.snapshot.remainingMeters, metric: useMetric)), "restan", alignment: .center)
                    Spacer()
                    metric(Text(Formatters.speed(viewModel.speedKmh, metric: useMetric)), "velocidad", alignment: .trailing)
                }
                .foregroundStyle(theme.textPrimary)

                NavControlsBar(theme: theme,
                               isMuted: speech.isMuted,
                               showFullRoute: showFullRoute,
                               onMute: { speech.toggleMute() },
                               onToggleRoute: { showFullRoute.toggle() },
                               onSearch: { showSearch = true },
                               onEnd: { viewModel.stop() })
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

    private func saveAndDismiss() {
        try? TripRepository(context: modelContext).save(viewModel.summary())
        dismiss()
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
                        Text("Después").font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary)
                        Image(systemName: ManeuverFormatter.symbol(for: next)).font(.caption.weight(.bold))
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
    let onMute: () -> Void
    let onToggleRoute: () -> Void
    let onSearch: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            control(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", isMuted ? "Activar voz" : "Silenciar voz", onMute)
            control(showFullRoute ? "location.fill" : "map.fill", showFullRoute ? "Volver a seguirme" : "Ver ruta completa", onToggleRoute)
            control("magnifyingglass", "Buscar otro destino", onSearch)
            Button(action: onEnd) {
                Label("Finalizar", systemImage: "xmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func control(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: theme.iconWeight))
                .frame(width: 56, height: 56)
                .foregroundStyle(theme.accent)
                .background(theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Formato

enum Formatters {
    static func distance(_ meters: Double, metric: Bool) -> String {
        if metric {
            if meters >= 10_000 { return String(format: "%.0f km", meters / 1000) }
            if meters >= 1000 { return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",") }
            return "\(Int(max(0, meters).rounded(toNearest: 10))) m"
        }
        let feet = meters * 3.28084
        if feet >= 1000 { return String(format: "%.1f mi", feet / 5280) }
        return "\(Int(max(0, feet).rounded(toNearest: 50))) ft"
    }

    static func speed(_ kmh: Double, metric: Bool) -> String {
        metric ? "\(Int(kmh)) km/h" : "\(Int(kmh * 0.621371)) mph"
    }
}

private extension Double {
    func rounded(toNearest step: Double) -> Double { (self / step).rounded() * step }
}
