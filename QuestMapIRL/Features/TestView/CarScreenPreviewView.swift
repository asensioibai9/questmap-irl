import CoreLocation
import SwiftUI

/// «Vista de pruebas»: la distribución HORIZONTAL de esta app (la misma del iPhone en horizontal) dibujada en otras
/// proporciones de pantalla, con un recorrido SIMULADO. Sirve para revisar paneles, textos largos, controles y zona libre
/// del mapa.
///
/// No es CarPlay: no usa sus plantillas ni su escena, no se conecta a ningún coche y no demuestra que la integración de
/// CarPlay funcione. Tampoco usa el GPS real, ni la navegación real, ni la voz (está muda), ni guarda nada.
struct CarScreenPreviewView: View {
    let environment: AppEnvironment

    @Environment(\.mapTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var preset = CarScreenPreset.all[0]
    @State private var longNames = false
    @State private var showsSpeedSign = true
    @State private var showFreeArea = true
    @State private var drive = SimulatedDrive()
    @State private var display: NavDisplay = .map
    @State private var showFullRoute = false
    @State private var headingUp = true
    @State private var map = MapController()
    @State private var miniMap = MapController()
    @State private var info: String?

    private var layout: MapScreenLayout { MapScreenLayout(size: preset.size) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                notice
                GeometryReader { proxy in
                    let scale = min(proxy.size.width / preset.size.width, proxy.size.height / preset.size.height, 1)
                    screen
                        .frame(width: preset.size.width, height: preset.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppColor.separator, lineWidth: 2))
                        .scaleEffect(scale)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(minHeight: 160)
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Vista de pruebas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { close() } }
            }
            .alert("Vista de pruebas", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(info ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: setUp)
        .onDisappear { drive.pause() }
        .onChange(of: preset) { _, _ in applyCamera() }
        .onChange(of: headingUp) { _, _ in applyCamera() }
        // Recálculo simulado terminado: el punto sigue por la ruta nueva.
        .onChange(of: drive.navigation.route.id) { _, _ in drive.advance(meters: 0) }
        .onChange(of: showFullRoute) { _, full in
            if full { map.fit(drive.route.coordinates, insets: layout.fullRouteInsets) } else { applyCamera() }
        }
    }

    // MARK: Pantalla simulada

    /// Mapa y panel de navegación de la app a tamaño real de la pantalla elegida (se escala solo para que quepa aquí).
    private var screen: some View {
        ZStack(alignment: .top) {
            QuestMapView(controller: map, style: theme.activeCartography, interactive: false, showsCompass: false)
            if showFreeArea {
                let free = layout.freeMapRect
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(Color.yellow.opacity(0.8))
                    .frame(width: free.width, height: free.height)
                    .position(x: free.midX, y: free.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            NavigationOverlay(
                viewModel: drive.navigation,
                display: $display,
                showFullRoute: $showFullRoute,
                headingUp: $headingUp,
                location: drive.location,
                speech: drive.voice,
                network: environment.network,
                miniMap: miniMap,
                useMetric: true,
                onRecenter: { showFullRoute = false; applyCamera() },
                music: nil,
                supports3D: false,
                is3D: false,
                speedSign: .defaults,
                layout: layout,
                onSearch: { info = "La búsqueda no está disponible en la vista de pruebas: el recorrido es simulado." },
                onEnd: { restart() }
            )
            simulatedBadge
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()      // es una pantalla aparte: sin las áreas seguras del iPhone
    }

    private var simulatedBadge: some View {
        Text("DATOS SIMULADOS · VISTA DE PRUEBAS · NO ES CARPLAY")
            .font(.caption.weight(.heavy))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.yellow, in: Capsule())
            .foregroundStyle(.black)
            .padding(.top, 4)
            .allowsHitTesting(false)
    }

    // MARK: Avisos y controles

    private var notice: some View {
        Text("Distribución horizontal de esta app en otras proporciones de pantalla, con un recorrido simulado. No es CarPlay, no usa sus plantillas ni prueba que funcionen. No usa tu GPS, no inicia una navegación real y la voz está muda.")
            .font(.caption)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Proporción", selection: $preset) {
                ForEach(CarScreenPreset.all) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                button(drive.isPlaying ? "Pausa" : "Recorrer", drive.isPlaying ? "pause.fill" : "play.fill") {
                    if drive.isPlaying { drive.pause() } else { drive.play() }
                }
                button("Próxima maniobra", "forward.end.fill") { drive.jumpToNextManeuver() }
                button("Recálculo", "arrow.triangle.2.circlepath") { drive.forceRecalculation() }
                button("Llegada", "flag.checkered") { drive.arrive() }
            }

            HStack(spacing: 12) {
                Toggle("Textos largos", isOn: $longNames).onChange(of: longNames) { _, _ in restart() }
                Toggle("Zona libre", isOn: $showFreeArea)
            }
            .font(.subheadline)
            Toggle("Señal de límite (sin datos)", isOn: $showsSpeedSign)
                .font(.subheadline)
                .onChange(of: showsSpeedSign) { _, value in drive.navigation.setShowsSpeedLimit(value) }
        }
        .tint(theme.accent)
    }

    private func button(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .foregroundStyle(AppColor.textPrimary)
    }

    // MARK: Simulación

    private func setUp() {
        let map = self.map
        let miniMap = self.miniMap
        drive.onPosition = { fix, heading in
            map.setUser(fix, heading: heading)
            miniMap.setUser(fix, heading: heading)
        }
        drive.onRouteChanged = { route in
            map.setRoute(route.coordinates)
            map.setDestination(route.coordinates.last)
            miniMap.setRoute(route.coordinates)
            miniMap.setDestination(route.coordinates.last)
        }
        drive.onRouteChanged?(drive.route)
        drive.begin()
        applyCamera()
    }

    private func applyCamera() {
        let style = theme.activeCartography
        map.setFollow(headingUp ? .headingUp : .northUp, zoom: style.navigationZoom, pitch: 0,
                      insets: layout.navigationFollowInsets)
        miniMap.setFollow(headingUp ? .headingUp : .northUp, zoom: style.minimapZoom, pitch: 0, bottomInset: 0)
    }

    private func restart() {
        display = .map
        showFullRoute = false
        drive.reset(longNames: longNames, showsSpeedSign: showsSpeedSign)
        applyCamera()
    }

    private func close() {
        drive.pause()
        dismiss()
    }
}
