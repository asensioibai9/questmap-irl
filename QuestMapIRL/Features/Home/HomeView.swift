import SwiftUI
import MapKit
import SwiftData

/// Pantalla principal: mapa a pantalla completa (bajo las safe areas), búsqueda,
/// accesos rápidos, calidad GPS y tarjeta de ruta.
struct HomeView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var savedPlaces: [SavedPlace]
    @State private var viewModel: HomeViewModel
    @State private var showSearch = false
    @State private var navigation: ActiveNavigationViewModel?
    @State private var showSaveDialog = false

    let environment: AppEnvironment
    let useMetric: Bool
    let showCompass: Bool

    init(environment: AppEnvironment, useMetric: Bool, headingUp: Bool, showCompass: Bool) {
        self.environment = environment
        self.useMetric = useMetric
        self.showCompass = showCompass
        _viewModel = State(initialValue: HomeViewModel(
            locationService: environment.locationService,
            routeService: environment.routeService,
            headingUp: headingUp
        ))
    }

    private var location: LocationServiceProtocol { environment.locationService }
    private var home: SavedPlace? { savedPlaces.first { $0.kindRawValue == PlaceKind.home.rawValue } }
    private var work: SavedPlace? { savedPlaces.first { $0.kindRawValue == PlaceKind.work.rawValue } }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                mapLayer
                MapOverlayView(theme: theme)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
            // Capa de HUD: respeta Dynamic Island / notch arriba y el indicador de inicio abajo.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        searchBar
                        GPSIndicator(theme: theme, quality: location.quality, signalLost: location.isSignalLost)
                            .fixedSize()
                    }
                    if viewModel.destination == nil { quickAccess }
                    if let error = viewModel.errorMessage { infoBanner(error, systemImage: "exclamationmark.triangle.fill") }
                    permissionBanner
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .overlay(alignment: .trailing) {
                sideControls.padding(.trailing, 16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.destination != nil {
                    routeCard
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.smooth, value: viewModel.destination != nil)
        .animation(.smooth, value: viewModel.routeState)
        .onAppear {
            if location.authState == .notDetermined { location.requestWhenInUseAuthorization() }
            location.start(mode: .idle)
        }
        .onChange(of: location.authState) { _, state in
            if state.isAuthorized { location.start(mode: .idle) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Fuera de navegación, el GPS se apaga en segundo plano para ahorrar batería.
            guard navigation == nil else { return }
            if phase == .active { location.start(mode: .idle) } else { location.stop() }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(near: viewModel.origin) { name, coordinate in
                viewModel.setDestination(coordinate, name: name)
            }
        }
        .fullScreenCover(item: $navigation) { nav in
            ActiveNavigationView(viewModel: nav,
                                 locationService: location,
                                 speech: environment.speech,
                                 useMetric: useMetric,
                                 headingUp: viewModel.headingUp)
                .onDisappear {
                    location.setMode(.idle)
                    viewModel.clearRoute()
                }
        }
        .confirmationDialog("Guardar este destino como", isPresented: $showSaveDialog, titleVisibility: .visible) {
            Button("Casa") { save(kind: .home) }
            Button("Trabajo") { save(kind: .work) }
            Button("Favorito") { save(kind: .favorite) }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: - Mapa

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $viewModel.cameraPosition) {
                if let loc = location.smoothedLocation {
                    Annotation("Tu posición", coordinate: loc.coordinate, anchor: .center) {
                        PlayerMarker(theme: theme, heading: viewModel.headingUp ? 0 : location.displayHeading)
                    }
                    .annotationTitles(.hidden)
                }

                ForEach(savedPlaces) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        Image(systemName: place.iconName)
                            .font(.system(size: 12, weight: theme.iconWeight))
                            .padding(7)
                            .background(theme.panel, in: .circle)
                            .overlay(Circle().stroke(theme.panelBorder, lineWidth: 1))
                            .foregroundStyle(theme.accent)
                    }
                }

                if let destination = viewModel.destination {
                    Annotation(viewModel.destinationName, coordinate: destination) {
                        DestinationPin(theme: theme)
                    }
                }

                if let route = viewModel.selectedRoute {
                    routeLayers(route.route.polyline, theme: theme)
                }
            }
            .mapStyle(theme.mapStyle)
            .mapControls {
                if showCompass { MapCompass() }
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { _ in
                // Si el usuario arrastra el mapa, dejamos de seguirle hasta que recentre.
                if viewModel.cameraPosition.positionedByUser { viewModel.isFollowing = false }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        if case .second(true, let drag?) = value,
                           let coordinate = proxy.convert(drag.location, from: .local) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            viewModel.setDestination(coordinate, name: "Punto del mapa")
                        }
                    }
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - HUD superior

    private var searchBar: some View {
        Button { showSearch = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.body.weight(theme.iconWeight))
                Text(viewModel.destination == nil ? "¿A dónde vamos?" : viewModel.destinationName)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(viewModel.destination == nil ? theme.textSecondary : theme.textPrimary)
            .font(.body.weight(.medium))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous).stroke(theme.panelBorder, lineWidth: 1))
        }
        .accessibilityLabel("Buscar destino")
    }

    private var quickAccess: some View {
        HStack(spacing: 10) {
            quickChip("house.fill", "Casa", home)
            quickChip("briefcase.fill", "Trabajo", work)
            Spacer()
        }
    }

    private func quickChip(_ icon: String, _ title: String, _ place: SavedPlace?) -> some View {
        Button {
            if let place { viewModel.setDestination(place.coordinate, name: place.name) } else { showSearch = true }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(theme.panel, in: .capsule)
                .overlay(Capsule().stroke(theme.panelBorder, lineWidth: 1))
                .foregroundStyle(place == nil ? theme.textSecondary : theme.accent)
        }
        .accessibilityHint(place == nil ? "Sin guardar. Toca para buscar." : "Ir a \(place!.name)")
    }

    @ViewBuilder
    private var permissionBanner: some View {
        switch location.authState {
        case .denied:
            actionBanner("Sin acceso a la ubicación no podemos guiarte.", button: "Abrir Ajustes", action: openSettings)
        case .restricted:
            infoBanner("La ubicación está restringida en este dispositivo (control parental o perfil).", systemImage: "lock.fill")
        case .servicesDisabled:
            actionBanner("Los servicios de localización están desactivados.", button: "Abrir Ajustes", action: openSettings)
        case .notDetermined:
            infoBanner("Permite la ubicación para verte en el mapa.", systemImage: "location.fill")
        case .authorizedWhenInUse, .authorizedAlways:
            if location.isSignalLost, location.currentLocation != nil {
                infoBanner("Señal GPS perdida. Mantenemos tu última posición conocida.", systemImage: "location.slash.fill")
            } else if location.currentLocation == nil {
                infoBanner("Buscando señal GPS…", systemImage: "location.viewfinder")
            }
        }
    }

    private func infoBanner(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(theme.textPrimary)
    }

    private func actionBanner(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.footnote.weight(.semibold))
            Spacer()
            Button(button, action: action).font(.footnote.weight(.bold)).tint(theme.accent)
        }
        .padding(10)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(theme.textPrimary)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: - Controles laterales

    private var sideControls: some View {
        VStack(spacing: 12) {
            MapRoundButton(theme: theme,
                           systemImage: viewModel.headingUp ? "location.north.line.fill" : "safari",
                           label: viewModel.headingUp ? "Vista según rumbo. Cambiar a norte arriba" : "Norte arriba. Cambiar a vista según rumbo",
                           isActive: viewModel.headingUp) { viewModel.toggleHeadingUp() }
            MapRoundButton(theme: theme,
                           systemImage: viewModel.isFollowing ? "location.fill" : "location",
                           label: "Recentrar en mi ubicación",
                           isActive: viewModel.isFollowing) { viewModel.recenter() }
        }
    }

    // MARK: - Tarjeta de ruta

    private var routeCard: some View {
        QuestPanel(theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Modo", selection: $viewModel.mode) {
                    ForEach(RouteMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.mode) { _, _ in viewModel.loadRoutes() }

                switch viewModel.routeState {
                case .loading:
                    HStack { ProgressView(); Text("Calculando rutas…").font(.subheadline) }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundStyle(theme.textSecondary)
                case .ready where !viewModel.routes.isEmpty:
                    routeAlternatives
                    if let route = viewModel.selectedRoute {
                        Button { startNavigation(route) } label: {
                            Label("Iniciar misión", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                        .foregroundStyle(theme.isDark ? theme.background : .white)
                    }
                case .failed:
                    Button("Reintentar") { viewModel.loadRoutes() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                default:
                    EmptyView()
                }

                HStack {
                    Button("Cancelar", role: .cancel) { viewModel.clearRoute() }
                    Spacer()
                    Button { showSaveDialog = true } label: { Image(systemName: "star") }
                        .accessibilityLabel("Guardar lugar")
                    if let origin = viewModel.origin, let destination = viewModel.destination,
                       let url = ShareLinkBuilder.routeURL(from: origin, to: destination, mode: viewModel.mode) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Compartir ruta")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
            }
        }
    }

    private var routeAlternatives: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.routes) { option in
                    let selected = option.id == viewModel.selectedRoute?.id
                    Button { viewModel.selectedRouteID = option.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(option.etaMinutes) min")
                                .font(.system(.title2, design: theme.titleDesign).weight(.bold))
                            Text(Formatters.distance(option.route.distance, metric: useMetric)).font(.caption)
                            Text(option.name).font(.caption2).lineLimit(1)
                        }
                        .padding(12)
                        .frame(width: 130, alignment: .leading)
                        .background(selected ? theme.accent.opacity(0.22) : theme.background.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: theme.cornerRadius - 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius - 4, style: .continuous)
                            .stroke(selected ? theme.accent : .clear, lineWidth: 2))
                    }
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityLabel("\(option.name), \(option.etaMinutes) minutos, \(Formatters.distance(option.route.distance, metric: useMetric))")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Acciones

    private func startNavigation(_ route: RouteOption) {
        guard let destination = viewModel.destination else { return }
        location.setMode(.navigating)
        navigation = ActiveNavigationViewModel(
            route: route,
            destinationName: viewModel.destinationName,
            destination: destination,
            mode: viewModel.mode,
            routeService: environment.routeService,
            speech: environment.speech,
            useMetric: useMetric
        )
    }

    private func save(kind: PlaceKind) {
        guard let destination = viewModel.destination else { return }
        if kind == .home || kind == .work {
            savedPlaces.filter { $0.kindRawValue == kind.rawValue }.forEach(modelContext.delete)
        }
        let icon: String
        switch kind {
        case .home: icon = "house.fill"
        case .work: icon = "briefcase.fill"
        case .favorite: icon = "star.fill"
        case .pin: icon = "mappin"
        }
        let name = kind == .home ? "Casa" : kind == .work ? "Trabajo" : viewModel.destinationName
        modelContext.insert(SavedPlace(name: name, iconName: icon, kind: kind,
                                       latitude: destination.latitude, longitude: destination.longitude))
    }
}

extension ActiveNavigationViewModel: Identifiable {}

extension SavedPlace {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension RouteMode {
    var symbol: String { self == .driving ? "car.fill" : "figure.walk" }
}

// MARK: - Componentes

private struct DestinationPin: View {
    let theme: MapTheme
    var body: some View {
        ZStack {
            Circle().fill(theme.destination.opacity(0.25)).frame(width: 44, height: 44)
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 32, weight: theme.iconWeight))
                .foregroundStyle(theme.destination)
                .shadow(color: theme.destination.opacity(0.7), radius: 8)
        }
        .accessibilityHidden(true)
    }
}
