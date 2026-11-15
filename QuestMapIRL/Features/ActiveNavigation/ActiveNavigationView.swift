import SwiftUI
import MapKit

/// Navegación activa: maniobra grande, ETA, velocidad y controles mínimos.
struct ActiveNavigationView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: ActiveNavigationViewModel
    let locationService: LocationServiceProtocol
    let speech: SpeechService
    let useMetric: Bool

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var showFullRoute = false

    var body: some View {
        ZStack {
            Map(position: $camera) {
                UserAnnotation()
                MapPolyline(viewModel.route.route.polyline)
                    .stroke(theme.routeGlow, lineWidth: theme.routeGlowWidth)
                MapPolyline(viewModel.route.route.polyline)
                    .stroke(theme.routeCore, lineWidth: theme.routeCoreWidth)
                Annotation(viewModel.destinationName, coordinate: viewModel.destination) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(theme.accent)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            MapOverlayView(theme: theme).allowsHitTesting(false).ignoresSafeArea()

            VStack {
                ManeuverCard(instruction: viewModel.currentInstruction,
                             distance: Formatters.distance(viewModel.snapshot.distanceToManeuver, metric: useMetric),
                             isRecalculating: viewModel.isRecalculating,
                             theme: theme)
                Spacer()
                bottomPanel
            }
            .padding(16)
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.start()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: locationService.currentLocation) { _, location in
            guard let location else { return }
            viewModel.update(with: location)
        }
        .onChange(of: viewModel.finished) { _, finished in
            if finished { saveAndDismiss() }
        }
        .onChange(of: showFullRoute) { _, full in
            withAnimation(.smooth) {
                camera = full
                    ? .rect(viewModel.route.route.polyline.boundingMapRect.insetBy(dx: -800, dy: -800))
                    : .userLocation(followsHeading: true, fallback: .automatic)
            }
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            ProgressView(value: viewModel.snapshot.progress)
                .tint(theme.accent)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(viewModel.eta, style: .time)
                        .font(.system(.title, design: theme.titleDesign).weight(.bold))
                    Text("llegada").font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                VStack {
                    Text(Formatters.distance(viewModel.snapshot.remainingMeters, metric: useMetric))
                        .font(.title3.weight(.semibold))
                    Text("restan").font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Formatters.speed(viewModel.speedKmh, metric: useMetric))
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text("velocidad").font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .foregroundStyle(theme.textPrimary)

            NavControlsBar(theme: theme,
                           isMuted: speech.isMuted,
                           showFullRoute: showFullRoute,
                           onMute: { speech.toggleMute() },
                           onToggleRoute: { showFullRoute.toggle() },
                           onEnd: { viewModel.stop() })
        }
        .padding(18)
        .background(theme.panel, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.accent.opacity(0.5), lineWidth: 1))
    }

    private func saveAndDismiss() {
        try? TripRepository(context: modelContext).save(viewModel.summary())
        dismiss()
    }
}

struct ManeuverCard: View {
    let instruction: String
    let distance: String
    let isRecalculating: Bool
    let theme: MapTheme

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isRecalculating ? "arrow.triangle.2.circlepath" : "arrow.turn.up.right")
                .font(.system(size: 40, weight: .bold))
                .symbolEffect(.pulse, isActive: isRecalculating)
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(distance)
                    .font(.system(.largeTitle, design: theme.titleDesign).weight(.heavy))
                Text(isRecalculating ? "Recalculando…" : instruction)
                    .font(.title3.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .foregroundStyle(theme.textPrimary)
        .padding(18)
        .background(theme.panel, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.accent.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct NavControlsBar: View {
    let theme: MapTheme
    let isMuted: Bool
    let showFullRoute: Bool
    let onMute: () -> Void
    let onToggleRoute: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            control(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", "Silenciar voz", onMute)
            control(showFullRoute ? "location.fill" : "map.fill", "Ver ruta completa", onToggleRoute)
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
                .font(.title2)
                .frame(width: 56, height: 56)
                .foregroundStyle(theme.accent)
                .background(theme.background.opacity(0.6), in: .rect(cornerRadius: 16))
        }
        .accessibilityLabel(label)
    }
}

enum Formatters {
    static func distance(_ meters: Double, metric: Bool) -> String {
        if metric {
            return meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded(toNearest: 10))) m"
        }
        let feet = meters * 3.28084
        return feet >= 1000 ? String(format: "%.1f mi", feet / 5280) : "\(Int(feet.rounded(toNearest: 50))) ft"
    }

    static func speed(_ kmh: Double, metric: Bool) -> String {
        metric ? "\(Int(kmh)) km/h" : "\(Int(kmh * 0.621371)) mph"
    }
}

private extension Double {
    func rounded(toNearest step: Double) -> Double { (self / step).rounded() * step }
}
