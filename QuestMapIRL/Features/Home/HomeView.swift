import SwiftUI
import SwiftData
import CoreLocation

/// Pantalla principal: mapa vectorial real a pantalla completa, búsqueda, accesos rápidos,
/// vista previa de ruta y, al iniciar, el HUD de navegación sobre el mismo mapa.
struct HomeView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var savedPlaces: [SavedPlace]

    @State private var viewModel: HomeViewModel
    @State private var navigation: ActiveNavigationViewModel?
    @State private var navDisplay: NavDisplay = .map
    @State private var showFullRoute = false
    @State private var showSearch = false
    @State private var showSaveDialog = false
    @State private var mapLoad: MapLoadState = .loading
    @State private var mapToken = 0
    @State private var pendingPlace: Place?
    @State private var viewHeight: CGFloat = 800
    @State private var map = MapController()
    @State private var miniMap = MapController()

    let environment: AppEnvironment
    let useMetric: Bool
    let settingsHeadingUp: Bool
    let showCompass: Bool

    init(environment: AppEnvironment, useMetric: Bool, headingUp: Bool, showCompass: Bool) {
        self.environment = environment
        self.useMetric = useMetric
        self.settingsHeadingUp = headingUp
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
    private var followMode: FollowMode { viewModel.headingUp ? .headingUp : .northUp }
    private var navigationBottomInset: CGFloat { viewHeight * 0.22 }

    // MARK: - Cuerpo

    var body: some View {
        ZStack {
            mapLayer
            if let navigation {
                NavigationOverlay(
                    viewModel: navigation,
                    display: $navDisplay,
                    showFullRoute: $showFullRoute,
                    headingUp: $viewModel.headingUp,
                    location: location,
                    speech: environment.speech,
                    network: environment.network,
                    miniMap: miniMap,
                    useMetric: useMetric,
                    onRecenter: recenter,
                    onSearch: { showSearch = true },
                    onEnd: { navigation.stop() }
                )
            } else {
                browsingOverlay
            }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { viewHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in viewHeight = height }
        })
        .toolbar(navigation == nil ? .visible : .hidden, for: .tabBar)
        .animation(.smooth, value: viewModel.destination != nil)
        .animation(.smooth, value: viewModel.routeState)
        .onAppear(perform: setUp)
        .onChange(of: location.authState) { _, state in
            if state.isAuthorized { location.start(mode: navigation == nil ? .idle : .navigating) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Fuera de navegación, el GPS se apaga en segundo plano para ahorrar batería.
            guard navigation == nil else { return }
            if phase == .active { location.start(mode: .idle) } else { location.stop() }
        }
        .onChange(of: location.smoothedLocation) { _, _ in pushUser() }
        .onChange(of: location.displayHeading) { _, _ in pushUser() }
        .onChange(of: location.currentLocation) { _, reading in
            guard let reading, let navigation else { return }
            navigation.update(with: reading)
        }
        .onChange(of: navigation?.finished) { _, finished in
            if finished == true { endNavigation() }
        }
        .onChange(of: navigation?.route.id) { _, _ in
            guard let navigation else { return }
            map.setRoute(navigation.route.coordinates)
            miniMap.setRoute(navigation.route.coordinates)
        }
        .onChange(of: viewModel.destination) { _, place in
            map.setDestination(place?.coordinate)
            miniMap.setDestination(place?.coordinate)
        }
        .onChange(of: viewModel.selectedRouteID) { _, _ in
            guard navigation == nil else { return }
            map.setRoute(viewModel.selectedRoute?.coordinates ?? [])
        }
        .onChange(of: viewModel.routesVersion) { _, _ in fitSelectedRoute() }
        .onChange(of: showFullRoute) { _, full in
            if full, let navigation {
                map.fit(navigation.route.coordinates, insets: routeInsets(bottom: viewHeight * 0.38))
            } else if !full, navigation != nil {
                recenter()
            }
        }
        .onChange(of: settingsHeadingUp) { _, value in
            viewModel.headingUp = value
            recenter()
        }
        .onChange(of: navDisplay) { _, _ in
            // El mapa grande se recrea al volver desde el modo HUD: recupera su cámara de seguimiento.
            if navigation != nil { recenter() }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(search: environment.placeSearch, near: location.currentLocation?.coordinate) { place in
                if let session = navigation {
                    // Cambiar de destino en plena navegación: se cierra la actual y luego se ruta al nuevo.
                    pendingPlace = place
                    session.stop()
                } else {
                    viewModel.setDestination(place)
                }
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

    @ViewBuilder
    private var mapLayer: some View {
        if navigation != nil && navDisplay == .hud {
            theme.background.ignoresSafeArea()
        } else {
            QuestMapView(
                controller: map,
                style: theme.activeCartography,
                showsCompass: showCompass,
                onLongPress: { coordinate in
                    guard navigation == nil else { return }
                    viewModel.setDestination(.pin(at: coordinate))
                },
                onStateChange: { mapLoad = $0 }
            )
            .id(mapToken)
            .ignoresSafeArea(edges: navigation == nil ? [.top, .horizontal] : .all)
        }
    }

    // MARK: - Exploración

    private var browsingOverlay: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    searchBar
                    GPSIndicator(theme: theme, quality: location.quality, signalLost: location.isSignalLost)
                        .fixedSize()
                }
                if viewModel.destination == nil { quickAccess }
                banners
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                sideControls
            }
            .padding(.trailing, 16)
            .padding(.bottom, 8)

            if viewModel.destination != nil {
                routeCard
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Text(theme.activeCartography.attribution)
                .font(.system(size: 9))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(theme.panel.opacity(0.7), in: .capsule)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
        }
    }

    private var searchBar: some View {
        Button { showSearch = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.body.weight(theme.iconWeight))
                Text(viewModel.destination?.name ?? "¿A dónde vamos?").lineLimit(1)
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
            if let place {
                viewModel.setDestination(Place(id: "saved-\(place.createdAt.timeIntervalSince1970)", name: place.name,
                                               subtitle: place.kindTitle, latitude: place.latitude, longitude: place.longitude))
            } else {
                showSearch = true
            }
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

    // MARK: - Avisos

    @ViewBuilder
    private var banners: some View {
        if !environment.network.isOnline {
            infoBanner("Sin conexión: el mapa, la búsqueda y las rutas necesitan internet.", systemImage: "wifi.slash")
        }
        if case .failed(let message) = mapLoad {
            actionBanner(message, button: "Reintentar") { mapToken += 1 }
        }
        if let error = viewModel.errorMessage {
            infoBanner(error, systemImage: "exclamationmark.triangle.fill")
        }
        permissionBanner
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
                infoBanner("Señal GPS perdida. Mostramos tu última posición conocida.", systemImage: "location.slash.fill")
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

    // MARK: - Controles

    private var sideControls: some View {
        VStack(spacing: 12) {
            MapRoundButton(theme: theme,
                           systemImage: viewModel.headingUp ? "location.north.line.fill" : "safari",
                           label: viewModel.headingUp ? "Vista según rumbo. Cambiar a norte arriba" : "Norte arriba. Cambiar a vista según rumbo",
                           isActive: viewModel.headingUp) {
                viewModel.headingUp.toggle()
                recenter()
            }
            MapRoundButton(theme: theme,
                           systemImage: viewModel.isFollowing ? "location.fill" : "location",
                           label: "Recentrar en mi ubicación",
                           isActive: viewModel.isFollowing) { recenter() }
        }
    }

    private var routeCard: some View {
        QuestPanel(theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                if let destination = viewModel.destination {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination.name).font(.headline).lineLimit(1)
                        if !destination.subtitle.isEmpty {
                            Text(destination.subtitle).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                        }
                    }
                    .foregroundStyle(theme.textPrimary)
                }

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
                    Button("Cancelar", role: .cancel) { clearRoute() }
                    Spacer()
                    Button { showSaveDialog = true } label: { Image(systemName: "star") }
                        .accessibilityLabel("Guardar lugar")
                    if let origin = viewModel.origin, let destination = viewModel.destination,
                       let url = ShareLinkBuilder.routeURL(from: origin, to: destination.coordinate, mode: viewModel.mode) {
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
                            Text(Formatters.distance(option.distanceMeters, metric: useMetric)).font(.caption)
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
                    .accessibilityLabel("\(option.name), \(option.etaMinutes) minutos, \(Formatters.distance(option.distanceMeters, metric: useMetric))")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Mapa: cámara y estado

    private func setUp() {
        map.onFollowCancelled = { viewModel.isFollowing = false }
        if location.authState == .notDetermined { location.requestWhenInUseAuthorization() }
        location.start(mode: navigation == nil ? .idle : .navigating)
        pushUser()
        let style = theme.activeCartography
        map.setFollow(followMode, zoom: style.defaultZoom, pitch: 0, bottomInset: 0)
    }

    private func pushUser() {
        guard let reading = location.smoothedLocation else { return }
        let heading = location.displayHeading
        map.setUser(reading.coordinate, heading: heading)
        miniMap.setUser(reading.coordinate, heading: heading)
    }

    private func recenter() {
        showFullRoute = false
        viewModel.isFollowing = true
        let style = theme.activeCartography
        if navigation != nil {
            map.setFollow(followMode, zoom: style.navigationZoom, pitch: style.navigationPitch, bottomInset: navigationBottomInset)
            miniMap.setFollow(followMode, zoom: style.minimapZoom, pitch: 0, bottomInset: 0)
        } else {
            map.setFollow(followMode, zoom: style.defaultZoom, pitch: 0, bottomInset: 0)
        }
    }

    private func routeInsets(bottom: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(top: viewHeight * 0.22, left: 40, bottom: bottom, right: 40)
    }

    private func fitSelectedRoute() {
        guard navigation == nil, let route = viewModel.selectedRoute else { return }
        map.setRoute(route.coordinates)
        map.fit(route.coordinates, insets: routeInsets(bottom: viewHeight * 0.42))
        viewModel.isFollowing = false
    }

    // MARK: - Acciones

    private func startNavigation(_ route: Route) {
        guard let destination = viewModel.destination else { return }
        let style = theme.activeCartography
        location.setMode(.navigating)
        let session = ActiveNavigationViewModel(
            route: route,
            destinationName: destination.name,
            destination: destination.coordinate,
            mode: viewModel.mode,
            routeService: environment.routeService,
            speech: environment.speech,
            useMetric: useMetric
        )
        navigation = session
        navDisplay = .map
        showFullRoute = false
        UIApplication.shared.isIdleTimerDisabled = true
        session.start()

        map.setRoute(route.coordinates)
        map.setDestination(destination.coordinate)
        miniMap.setRoute(route.coordinates)
        miniMap.setDestination(destination.coordinate)
        viewModel.isFollowing = true
        map.setFollow(followMode, zoom: style.navigationZoom, pitch: style.navigationPitch, bottomInset: navigationBottomInset)
        miniMap.setFollow(followMode, zoom: style.minimapZoom, pitch: 0, bottomInset: 0)
        if let reading = location.currentLocation { session.update(with: reading) }
    }

    private func endNavigation() {
        guard let session = navigation else { return }
        let summary = session.summary()
        // Solo se guardan viajes con recorrido real o que llegaron al destino.
        if summary.distanceMeters >= 100 || session.hasArrived {
            try? TripRepository(context: modelContext).save(summary)
        }
        navigation = nil
        navDisplay = .map
        showFullRoute = false
        location.setMode(.idle)
        environment.speech.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        clearRoute()
        if let next = pendingPlace {
            pendingPlace = nil
            viewModel.setDestination(next)
        }
    }

    private func clearRoute() {
        viewModel.clearRoute()
        map.setRoute([])
        map.setDestination(nil)
        miniMap.setRoute([])
        miniMap.setDestination(nil)
        recenter()
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
        let name = kind == .home ? "Casa" : kind == .work ? "Trabajo" : destination.name
        modelContext.insert(SavedPlace(name: name, iconName: icon, kind: kind,
                                       latitude: destination.latitude, longitude: destination.longitude))
    }
}

extension SavedPlace {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
