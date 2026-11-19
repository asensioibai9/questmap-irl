import SwiftUI
import SwiftData
import CoreLocation

/// Ventanas que se abren desde el panel inferior (cuelgan de la propia hoja del panel).
enum HomeModal: Identifiable, Equatable {
    case profile, layers, saved, credits
    case address(AddressTarget)

    enum AddressTarget: String { case home, work, zone }

    var id: String {
        switch self {
        case .profile: return "profile"
        case .layers: return "layers"
        case .saved: return "saved"
        case .credits: return "credits"
        case .address(let target): return "address-\(target.rawValue)"
        }
    }
}

/// Pantalla principal: mapa vectorial real a pantalla completa, controles flotantes a la derecha
/// y un panel inferior arrastrable (buscador, accesos, recomendaciones, categorías o tarjeta de
/// ruta). Al iniciar la navegación el panel se retira y aparece el HUD sobre el mismo mapa.
struct HomeView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var savedPlaces: [SavedPlace]
    @Query private var settingsRows: [UserSettings]

    @State private var viewModel: HomeViewModel
    @State private var panel: SearchPanelModel
    @State private var navDisplay: NavDisplay = .map
    @State private var showFullRoute = false
    @State private var showPanel = false
    @State private var detent: PresentationDetent = .compactPanel
    @State private var modal: HomeModal?
    @State private var showNavSearch = false
    @State private var showSaveDialog = false
    @State private var mapLoad: MapLoadState = .loading
    @State private var mapToken = 0
    @State private var pendingPlace: Place?
    @State private var failedPersonalAction: PersonalAction?
    @State private var failedFavoriteSave = false
    @State private var showTemporaryStorageNotice = false
    @State private var storeSetAside = false
    @State private var locationNotice: LocationNotice?
    /// Distribución según el espacio real (se actualiza en cada giro o cambio de tamaño).
    @State private var layout = MapScreenLayout(size: CGSize(width: 390, height: 800))
    /// Panel de búsqueda como columna lateral (horizontal) en lugar de hoja inferior. Solo cambia cuando no hay una
    /// ventana abierta encima del panel, para no cerrarla al girar.
    @State private var sidePanel = false
    @State private var temporaryNoticeShown = false
    @State private var map = MapController()
    @State private var miniMap = MapController()
    /// Lleva la ubicación al mapa sin redibujar esta pantalla con cada lectura (ver `HomeLocationFeeder`).
    @State private var feeder = HomeLocationFeeder()
    @AppStorage(SpeedLimitDiagnosticsCard.storageKey) private var limitDiagnostics = false

    let environment: AppEnvironment
    /// false mientras se muestra la animación de inicio: no se pide ningún permiso ni se abre el panel.
    let startupFinished: Bool

    init(environment: AppEnvironment, startupFinished: Bool) {
        self.environment = environment
        self.startupFinished = startupFinished
        _viewModel = State(initialValue: HomeViewModel(
            locationService: environment.locationService,
            routeService: environment.routeService,
            headingUp: true
        ))
        _panel = State(initialValue: SearchPanelModel(search: environment.placeSearch, nearby: environment.nearby))
    }

    private var settings: UserSettings? { settingsRows.first }
    /// La navegación vive en el centro compartido (también la usa CarPlay), no en esta vista.
    private var navigation: ActiveNavigationViewModel? { environment.hub.session }
    private var useMetric: Bool { settings?.useMetricUnits ?? true }
    private var showCompass: Bool { settings?.showCompass ?? true }
    private var speedSign: SpeedSignAppearance { settings?.speedSignAppearance ?? .defaults }
    /// Límite sin ruta: requiere «Mostrar señal» y «También sin ruta».
    private var wantsFreeDriveLimit: Bool { (settings?.showSpeedLimit ?? true) && (settings?.speedLimitWithoutRoute ?? false) }
    /// Comprobación de la vía real durante la navegación.
    private var wantsTraceVerification: Bool { (settings?.showSpeedLimit ?? true) && (settings?.speedLimitVerifyTrace ?? true) }
    private var location: LocationServiceProtocol { environment.locationService }
    private var followMode: FollowMode { viewModel.headingUp ? .headingUp : .northUp }
    /// Columna lateral de búsqueda visible (horizontal, sin navegación).
    private var sidePanelActive: Bool { sidePanel && showPanel && navigation == nil }
    /// Espacio que ocupa la columna lateral a la izquierda, para apartar de ella los demás elementos flotantes.
    private var sideClearance: CGFloat { sidePanelActive ? layout.sidePanelWidth + 12 : 0 }
    /// El control 2D/3D solo existe en estilos con edificios extruidos.
    private var supports3D: Bool { theme.activeCartography.supportsBuildings3D }
    private var view3D: Bool { supports3D && (settings?.view3D ?? false) }
    /// Exploración: cenital (2D) o en perspectiva (3D).
    private var explorePitch: Double { view3D ? 50 : 0 }
    /// Navegación: en estilos con 3D manda la preferencia del usuario (2D = cenital siempre; 3D = perspectiva
    /// moderada, más suave a pie). En el resto de estilos se mantiene el comportamiento anterior.
    private var navigationPitch: Double {
        let mode = navigation?.mode ?? viewModel.mode
        if supports3D { return view3D ? (mode == .driving ? 45 : 30) : 0 }
        return mode == .driving ? theme.activeCartography.navigationPitch : 0
    }

    // MARK: - Cuerpo

    var body: some View {
        mapLayerHandlers(speedLimitHandlers(settingsHandlers(routeHandlers(locationHandlers(screen)))))
    }

    /// Capas del mapa y nombres de lugares: se aplican al momento cambiando solo la visibilidad de capas existentes.
    private func mapLayerHandlers<V: View>(_ view: V) -> some View {
        view
        .onChange(of: settings?.mapLayersRaw) { _, _ in applyMapLayers() }
        .onChange(of: settings?.showPlaceNames) { _, _ in applyMapLayers() }
    }

    private func applyMapLayers() {
        let layers = settings?.mapLayers ?? .defaults
        let names = settings?.showPlaceNames ?? true
        map.setMapLayers(layers)
        map.setPlaceNames(names)
        miniMap.setMapLayers(layers)
        miniMap.setPlaceNames(names)
    }

    /// Ajustes de la señal de límite: se aplican al momento (navegando y sin ruta).
    private func speedLimitHandlers<V: View>(_ view: V) -> some View {
        view
        .onChange(of: settings?.showSpeedLimit) { _, value in
            navigation?.setShowsSpeedLimit(value ?? true)
            environment.hub.setFreeDriveSpeedLimit(wantsFreeDriveLimit)
            environment.hub.setTraceVerification(wantsTraceVerification)
        }
        .onChange(of: settings?.speedLimitWithoutRoute) { _, _ in
            environment.hub.setFreeDriveSpeedLimit(wantsFreeDriveLimit)
        }
        .onChange(of: settings?.speedLimitVerifyTrace) { _, _ in environment.hub.setTraceVerification(wantsTraceVerification) }
    }

    /// Pantalla sin reacciones a cambios de estado (se reparten en tres grupos para que el compilador
    /// pueda comprobar los tipos en un tiempo razonable).
    private var screen: some View {
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
                    music: environment.music,
                    supports3D: supports3D,
                    is3D: view3D,
                    onToggle3D: toggle3D,
                    speedSign: speedSign,
                    layout: layout,
                    onSearch: { showNavSearch = true },
                    onEnd: { navigation.stop() }
                )
                .sheet(isPresented: $showNavSearch) {
                    AddressPickerView(title: "Cambiar destino", prompt: "Buscar destino",
                                      search: environment.placeSearch, near: feeder.searchOrigin) { place in
                        // Cambiar de destino en plena navegación: se cierra la actual y luego se ruta al nuevo.
                        pendingPlace = place
                        navigation.stop()
                    }
                }
            } else {
                browsingOverlay
            }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { updateLayout(proxy) }
                .onChange(of: proxy.size) { _, _ in updateLayout(proxy) }
                .onChange(of: proxy.safeAreaInsets) { _, _ in updateLayout(proxy) }
        })
        .animation(.smooth, value: viewModel.destination != nil)
        // En vertical, hoja inferior; en horizontal, la MISMA vista en una columna lateral (ver `browsingOverlay`).
        .sheet(isPresented: Binding(get: { showPanel && !sidePanel }, set: { if !$0 && !sidePanel { showPanel = false } })) {
            panelSheet
        }
        .onChange(of: layout) { old, new in layoutChanged(from: old, to: new) }
        .onChange(of: modal) { _, open in if open == nil { sidePanel = layout.isSideBySide } }
    }

    private func locationHandlers<V: View>(_ view: V) -> some View {
        view
        .onAppear(perform: setUp)
        .onChange(of: startupFinished) { _, finished in if finished { afterStartup() } }
        .onChange(of: location.authState) { _, state in
            if state.isAuthorized { location.start(mode: navigation == nil ? .idle : .navigating) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Fuera de navegación, el GPS se apaga en segundo plano para ahorrar batería.
            // Navegando, la voz y el GPS siguen en segundo plano; si no, se para todo.
            guard navigation == nil else { return }
            switch phase {
            case .active:
                location.start(mode: .idle)
                location.refreshNow()          // lectura fresca al volver a la app
                environment.music.activate()
                environment.music.refresh()
            case .background:
                location.stop()
                environment.speech.stopImmediately()
                environment.music.deactivate()
            default:
                break                          // .inactive (diálogo del sistema, centro de control): no se para el GPS
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            environment.speech.stopImmediately()
        }
    }

    private func routeHandlers<V: View>(_ view: V) -> some View {
        view
        .onChange(of: environment.hub.startToken) { _, _ in
            if let session = environment.hub.session { presentNavigationUI(session) }
        }
        .onChange(of: environment.hub.endToken) { _, _ in endNavigationUI() }
        .onChange(of: navigation?.route.id) { _, _ in
            guard let navigation else { return }
            map.setRoute(navigation.route.coordinates)
            miniMap.setRoute(navigation.route.coordinates)
        }
        .onChange(of: viewModel.destination) { _, place in
            map.setDestination(place?.coordinate)
            miniMap.setDestination(place?.coordinate)
            if navigation == nil { detent = place == nil && viewModel.selection == nil ? .compactPanel : .medium }
        }
        .onChange(of: viewModel.selection) { _, place in
            map.setSelection(place?.coordinate)
            guard navigation == nil else { return }
            if place != nil { detent = .medium } else if viewModel.destination == nil { detent = .compactPanel }
        }
        .onChange(of: savedSignature) { _, _ in pushSavedPlaces() }
        .onChange(of: viewModel.selectedRouteID) { _, _ in
            guard navigation == nil else { return }
            map.setRoute(viewModel.selectedRoute?.coordinates ?? [])
        }
        .onChange(of: viewModel.routesVersion) { _, _ in fitSelectedRoute() }
        .onChange(of: showFullRoute) { _, full in
            if full, let navigation {
                map.fit(navigation.route.coordinates, insets: layout.fullRouteInsets)
            } else if !full, navigation != nil {
                recenter()
            }
        }
    }

    private func settingsHandlers<V: View>(_ view: V) -> some View {
        view
        .onChange(of: settings?.headingUp) { _, value in
            guard let value else { return }
            viewModel.headingUp = value
            recenter()
        }
        .onChange(of: settings?.mapAvatar) { _, avatar in applyAvatar(avatar) }
        .onChange(of: settings?.showMiniPlayer) { _, _ in applyMusicSettings() }
        .onChange(of: settings?.musicConnectedServicesRaw) { _, _ in applyMusicSettings() }
        .onChange(of: settings?.musicServiceRaw) { _, _ in applyMusicSettings() }
        .onChange(of: supports3D) { _, _ in apply3D(animated: false) }
        .onChange(of: settings?.view3D) { _, _ in apply3D(animated: true) }
        .onChange(of: panel.markers) { _, places in map.setMarkers(places) }
        .onChange(of: navDisplay) { _, _ in
            // El mapa grande se recrea al volver desde el modo HUD: recupera su cámara de seguimiento.
            if navigation != nil { recenter() }
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
                    // Mantener pulsado también solo SELECCIONA: la ruta se calcula al confirmar "Cómo llegar".
                    viewModel.select(.pin(at: coordinate))
                },
                onTap: handleMapTap,
                onStateChange: { mapLoad = $0 }
            )
            .id(mapToken)
            .ignoresSafeArea()
        }
    }

    // MARK: - Capa de exploración (sobre el mapa)

    private var browsingOverlay: some View {
        ZStack {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    LiveGPSIndicator(theme: theme, location: location)
                        .fixedSize()
                    Spacer()
                }
                freeDriveSign
                banners
                Spacer()
            }
            .padding(.leading, 16 + sideClearance)
            .padding(.trailing, sidePanelActive ? 76 : 16)
            .padding(.top, 8)

            if sidePanelActive {
                sideBrowsingExtras
                HStack(alignment: .top) {
                    sidePanelCard
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                bottomBrowsingExtras
            }

            HStack {
                Spacer()
                VStack { Spacer(); sideControls }
            }
            .padding(.trailing, 14)
            .padding(.bottom, sidePanelActive ? 8 : 14 + 118)
            .ignoresSafeArea(.container, edges: sidePanelActive ? [] : .bottom)
        }
    }

    /// Vertical: crédito y reproductor por ENCIMA del panel inferior (siguen su altura).
    private var bottomBrowsingExtras: some View {
        ZStack {
            // Crédito de los datos del mapa: siempre visible, pequeño, a la izquierda y por ENCIMA del panel
            // (sigue a la altura del panel). Al tocarlo se abren los créditos completos.
            GeometryReader { proxy in
                VStack {
                    Spacer()
                    HStack {
                        MapAttributionLabel(text: theme.activeCartography.attribution) { modal = .credits }
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.bottom, attributionBottomInset(screenHeight: proxy.size.height))
                    .opacity(detent == .large ? 0 : 1)
                    .animation(.smooth, value: detent)
                }
            }
            .ignoresSafeArea()

            if environment.music.isVisible && detent != .large {
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        HStack {
                            MiniPlayerCard(model: environment.music)
                                .frame(maxWidth: min(340, proxy.size.width - 100))
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 12)
                        .padding(.bottom, attributionBottomInset(screenHeight: proxy.size.height) + 28)
                    }
                }
                .ignoresSafeArea()
                .animation(.smooth, value: detent)
            }
        }
    }

    /// Horizontal: crédito y reproductor abajo, en la zona del mapa que queda a la derecha de la columna.
    private var sideBrowsingExtras: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
            if environment.music.isVisible {
                MiniPlayerCard(model: environment.music)
                    .frame(maxWidth: max(220, min(340, layout.size.width - sideClearance - 120)))
            }
            MapAttributionLabel(text: theme.activeCartography.attribution) { modal = .credits }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12 + sideClearance)
        .padding(.trailing, 76)
        .padding(.bottom, 6)
    }

    /// Columna lateral con el mismo contenido que la hoja inferior. Sus tres alturas equivalen a las de la hoja
    /// (compacta, media y grande) y se cambian con el asa o, como en la hoja, al escribir o ver resultados.
    private var sidePanelCard: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(spacing: 0) {
            Button(action: cycleSidePanel) {
                Capsule()
                    .fill(AppColor.textSecondary.opacity(0.6))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(detent == .large ? "Reducir el panel" : "Ampliar el panel")
            panelDecorations(panelContent)
        }
        .frame(width: layout.sidePanelWidth, height: layout.sidePanelHeight(for: detent), alignment: .top)
        .background(AppColor.surface, in: shape)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .environment(\.colorScheme, .dark)
        .tint(theme.accent)
        .animation(.smooth, value: detent)
    }

    private func cycleSidePanel() {
        switch detent {
        case .compactPanel: detent = .medium
        case .medium: detent = .large
        default: detent = .compactPanel
        }
    }

    /// Señal sin ruta (si está activada). Va en su propia fila bajo el indicador GPS: nunca encima del buscador, los
    /// botones, el reproductor ni la brújula (a la derecha se baja por debajo de la brújula del mapa).
    @ViewBuilder
    private var freeDriveSign: some View {
        let hub = environment.hub
        if wantsFreeDriveLimit, !SpeedLimitSign.isEmpty(hub.speedLimit, appearance: speedSign) {
            HStack {
                if speedSign.position == .topTrailing { Spacer() }
                VStack(alignment: .leading, spacing: 6) {
                    if limitDiagnostics { SpeedLimitDiagnosticsCard(diagnostic: hub.speedLimitDiagnostic) }
                    SpeedLimitSign(display: hub.speedLimit, metric: useMetric, appearance: speedSign,
                                   countryCode: hub.speedLimitCountry, currentSpeedKmh: hub.currentSpeedKmh)
                }
                if speedSign.position != .topTrailing { Spacer() }
            }
            .padding(.top, speedSign.position == .topTrailing && showCompass ? 52 : 0)
        }
    }

    /// Distancia desde el borde inferior de la pantalla hasta el borde superior del panel.
    private func attributionBottomInset(screenHeight: CGFloat) -> CGFloat {
        let panelHeight: CGFloat = detent == .medium ? screenHeight * 0.5 : 118
        return panelHeight + 6
    }

    // MARK: - Controles flotantes

    private var sideControls: some View {
        VStack(spacing: 12) {
            CircleIconButton(systemImage: "square.3.layers.3d", label: "Capas y estilo del mapa",
                             size: 48, accent: theme.accent, floating: true) { modal = .layers }
            CircleIconButton(systemImage: viewModel.headingUp ? "location.north.line.fill" : "safari",
                             label: viewModel.headingUp ? "Rumbo arriba. Cambiar a norte arriba" : "Norte arriba. Cambiar a rumbo arriba",
                             size: 48, isActive: viewModel.headingUp, accent: theme.accent, floating: true) {
                viewModel.headingUp.toggle()
                settings?.headingUp = viewModel.headingUp
                recenter()
            }
            if supports3D {
                CircleIconButton(systemImage: view3D ? "view.3d" : "view.2d",
                                 label: view3D ? "Vista 3D activa. Cambiar a vista 2D" : "Vista 2D activa. Cambiar a vista 3D con edificios",
                                 size: 48, isActive: view3D, accent: theme.accent, floating: true) { toggle3D() }
            }
            CircleIconButton(systemImage: viewModel.isFollowing ? "location.fill" : "location",
                             label: "Recentrar en mi ubicación",
                             size: 48, isActive: viewModel.isFollowing, accent: theme.accent, floating: true) { locationButtonTapped() }
        }
    }

    // MARK: - Avisos

    @ViewBuilder
    private var banners: some View {
        if environment.network.showsOfflineNotice {
            InlineMessage(kind: .warning, text: environment.network.noticeText)
        }
        if case .failed(let message) = mapLoad {
            InlineMessage(kind: .error, text: message, actionTitle: "Reintentar") { mapToken += 1 }
        }
        if let error = viewModel.errorMessage, navigation == nil, viewModel.destination == nil {
            InlineMessage(kind: .warning, text: error)
        }
        permissionBanner
    }

    /// Aviso que corresponde al estado REAL de la ubicación (nunca "GPS perdido" sin motivo).
    @ViewBuilder
    private var permissionBanner: some View {
        if let notice = locationNotice {
            InlineMessage(kind: .info, text: notice.text, actionTitle: notice.action?.title) { runNoticeAction(notice.action) }
        }
        let status = location.status
        if let text = status.explanation, !(status == .requestingPermission && !startupFinished), shows(status) {
            InlineMessage(kind: status == .acquiring || status == .requestingPermission ? .info : .warning, text: text,
                          actionTitle: bannerAction(for: status)?.title) { runNoticeAction(bannerAction(for: status)) }
        }
    }

    /// Los estados que solo informan (precisión baja) se ven en el indicador, sin banner.
    private func shows(_ status: LocationStatus) -> Bool {
        if case .lowAccuracy = status { return false }
        return true
    }

    private func bannerAction(for status: LocationStatus) -> LocationNotice.Action? {
        switch status {
        case .requestingPermission: return .requestPermission
        case .reducedAccuracy: return .fullAccuracy
        case .lastKnown, .temporaryError: return .refresh
        case .denied, .servicesDisabled: return .settings
        default: return nil
        }
    }

    private func runNoticeAction(_ action: LocationNotice.Action?) {
        switch action {
        case .requestPermission: location.requestWhenInUseAuthorization()
        case .fullAccuracy: location.requestTemporaryFullAccuracy()
        case .refresh: location.refreshNow()
        case .settings: openSettings()
        case nil: break
        }
    }

    /// Botón de ubicación: comprueba permisos, pide/reanuda la lectura y centra si hay posición; si no puede, lo explica.
    private func locationButtonTapped() {
        switch location.status {
        case .requestingPermission:
            location.requestWhenInUseAuthorization()
            showNotice("Acepta el permiso de ubicación en el diálogo de iOS.")
        case .denied:
            showNotice("El permiso de ubicación está denegado para QuestMap IRL.", action: .settings)
        case .servicesDisabled:
            showNotice("Los servicios de localización están desactivados en este iPhone.", action: .settings)
        case .restricted:
            showNotice("La ubicación está restringida en este dispositivo y la app no puede cambiarlo.")
        default:
            location.refreshNow()
            if location.smoothedLocation != nil {
                recenter()
                if location.status == .reducedAccuracy {
                    showNotice("Centrado con ubicación aproximada.", action: .fullAccuracy)
                }
            } else {
                showNotice("Todavía no hay ninguna posición. Seguimos intentando obtenerla; en exteriores suele tardar unos segundos.")
            }
        }
    }

    private func showNotice(_ text: String, action: LocationNotice.Action? = nil) {
        let notice = LocationNotice(text: text, action: action)
        locationNotice = notice
        Task {
            try? await Task.sleep(for: .seconds(8))
            if locationNotice == notice { locationNotice = nil }
        }
    }

    /// Por qué no hay ubicación, para explicarlo en la búsqueda por categorías.
    private var categoryLocationHint: String? {
        switch location.authState {
        case .denied:
            return "Has denegado el permiso de ubicación. Actívalo en Ajustes › QuestMap IRL › Ubicación, o elige una zona."
        case .restricted:
            return "La ubicación está restringida en este iPhone. Elige una zona."
        case .servicesDisabled:
            return "Los servicios de localización están desactivados. Actívalos en Ajustes o elige una zona."
        case .notDetermined:
            return "Aún no has respondido al permiso de ubicación. Permítelo o elige una zona."
        case .authorizedWhenInUse, .authorizedAlways:
            return feeder.searchOrigin == nil ? "Aún no hay señal GPS. Espera unos segundos o elige una zona." : nil
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: - Panel inferior

    /// Hoja inferior (vertical).
    private var panelSheet: some View {
        panelDecorations(
            panelContent
                .presentationDetents([.compactPanel, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(AppColor.surface)
                .interactiveDismissDisabled()
                .preferredColorScheme(.dark)
                .tint(theme.accent)
        )
    }

    /// Contenido del panel: el mismo en la hoja (vertical) y en la columna lateral (horizontal), con el mismo estado.
    private var panelContent: some View {
        Group {
            if viewModel.destination != nil {
                routePanel
            } else if let selection = viewModel.selection {
                PlacePreviewPanel(place: selection, distance: distanceText(to: selection),
                                  replacesRoute: false,
                                  onDirections: { viewModel.confirmSelection() },
                                  onClose: { viewModel.clearSelection() })
            } else {
                SearchPanelView(
                    model: panel,
                    detent: $detent,
                    near: feeder.searchOrigin,
                    accent: theme.accent,
                    locationHint: categoryLocationHint,
                    onSelect: { place in select(place) },
                    onShowOnMap: { place in showOnMap(place) },
                    onProfile: { modal = .profile },
                    onShowSaved: { modal = .saved },
                    onPickAddress: { kind in modal = .address(kind == .home ? .home : .work) },
                    onChooseZone: { modal = .address(.zone) },
                    onDeletePlace: { kind in perform(.delete(kind)) }
                )
            }
        }
    }

    /// Ventanas y avisos que cuelgan del panel, esté donde esté.
    private func panelDecorations<V: View>(_ content: V) -> some View {
        content
        .sheet(item: $modal) { modalView($0) }
        .alert("No se pudo guardar", isPresented: Binding(get: { failedPersonalAction != nil },
                                                          set: { if !$0 { failedPersonalAction = nil } })) {
            Button("Reintentar") { if let action = failedPersonalAction { perform(action) } }
            Button("Cancelar", role: .cancel) { failedPersonalAction = nil }
        } message: {
            Text("El cambio en Casa/Trabajo no se ha guardado y tus datos anteriores siguen intactos. Puedes reintentarlo.")
        }
        .alert("No se pudo guardar el lugar", isPresented: $failedFavoriteSave) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Inténtalo de nuevo en unos segundos.")
        }
        .alert("Almacenamiento temporal", isPresented: $showTemporaryStorageNotice) {
            Button("Entendido", role: .cancel) {}
            Button("Apartar datos y reiniciar", role: .destructive) { setAsideBrokenStore() }
        } message: {
            Text("No se ha podido abrir el almacenamiento de la app. Lo que guardes ahora se perderá al cerrarla. Tus datos antiguos NO se han borrado: hay una copia en la app. Código: \(PersistenceStatus.shared.lastError ?? "desconocido"). «Apartar datos y reiniciar» mueve el archivo antiguo a una carpeta de copias (no lo borra) para empezar limpio al volver a abrir la app.")
        }
        .alert("Datos apartados", isPresented: $storeSetAside) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Cierra la app del todo y vuelve a abrirla.")
        }
        .onAppear {
            if PersistenceStatus.shared.mode == .temporary, !temporaryNoticeShown {
                temporaryNoticeShown = true
                showTemporaryStorageNotice = true
            }
        }
    }

    @ViewBuilder
    private func modalView(_ modal: HomeModal) -> some View {
        switch modal {
        case .profile:
            ProfileSheetView(environment: environment)
                .environment(\.mapTheme, theme)
        case .layers:
            // Un solo botón para capas y estilo (no hay dos controles duplicados): el panel enlaza con «Estilo de mapa».
            MapLayersSheet(onClose: { self.modal = nil })
                .environment(\.mapTheme, theme)
        case .saved:
            SavedPlacesView(onSelect: { select($0) }, onShowOnMap: { showOnMap($0) })
        case .credits:
            MapCreditsView(onClose: { self.modal = nil })
        case .address(let target):
            AddressPickerView(title: addressTitle(target), prompt: "Buscar dirección",
                              search: environment.placeSearch, near: feeder.searchOrigin) { place in
                addressPicked(place, for: target)
            }
        }
    }

    private func addressTitle(_ target: HomeModal.AddressTarget) -> String {
        switch target {
        case .home: return savedPlaces.contains { $0.kindRawValue == PlaceKind.home.rawValue } ? "Editar casa" : "Añadir casa"
        case .work: return savedPlaces.contains { $0.kindRawValue == PlaceKind.work.rawValue } ? "Editar trabajo" : "Añadir trabajo"
        case .zone: return "Elegir zona"
        }
    }

    private func addressPicked(_ place: Place, for target: HomeModal.AddressTarget) {
        switch target {
        case .home: saveSingle(kind: .home, place: place)
        case .work: saveSingle(kind: .work, place: place)
        case .zone: panel.setArea(place, near: location.currentLocation?.coordinate)
        }
    }

    // MARK: - Tarjeta de ruta (dentro del panel)

    private var routePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let pending = viewModel.selection {
                    PlacePreviewPanel(place: pending, distance: distanceText(to: pending), replacesRoute: true,
                                      onDirections: { viewModel.confirmSelection() },
                                      onClose: { viewModel.clearSelection() })
                        .padding(.top, 14)
                }
                if let destination = viewModel.destination {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(destination.name).font(.title2.weight(.bold)).lineLimit(2)
                        if !destination.subtitle.isEmpty {
                            Text(destination.subtitle).font(.subheadline).foregroundStyle(AppColor.textSecondary).lineLimit(2)
                        }
                    }
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 20)
                }

                Picker("Modo", selection: $viewModel.mode) {
                    ForEach(RouteMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.mode) { _, _ in viewModel.loadRoutes() }

                switch viewModel.routeState {
                case .loading:
                    HStack(spacing: 10) { ProgressView(); Text("Calculando rutas…").font(.subheadline) }
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .foregroundStyle(AppColor.textSecondary)
                case .ready where !viewModel.routes.isEmpty:
                    routeAlternatives
                    if let route = viewModel.selectedRoute {
                        Button { startNavigation(route) } label: {
                            Label("Iniciar ruta", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                        .foregroundStyle(.black)
                    }
                case .failed(let message):
                    InlineMessage(kind: .warning, text: message, actionTitle: "Reintentar") { viewModel.loadRoutes() }
                default:
                    EmptyView()
                }

                HStack(spacing: 14) {
                    Button("Cancelar", role: .cancel) { clearRoute() }
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    CircleIconButton(systemImage: "star", label: "Guardar lugar", size: 40) { showSaveDialog = true }
                    if let origin = viewModel.origin, let destination = viewModel.destination,
                       let url = ShareLinkBuilder.routeURL(from: origin, to: destination.coordinate, mode: viewModel.mode) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(AppColor.surfaceRaised, in: .circle)
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("Compartir ruta")
                    }
                }
                .foregroundStyle(AppColor.textPrimary)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .confirmationDialog("Guardar este destino como", isPresented: $showSaveDialog, titleVisibility: .visible) {
            Button("Casa") { save(kind: .home) }
            Button("Trabajo") { save(kind: .work) }
            Button("Favorito") { save(kind: .favorite) }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var routeAlternatives: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.routes) { option in
                    let selected = option.id == viewModel.selectedRoute?.id
                    Button { viewModel.selectedRouteID = option.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(option.etaMinutes) min").font(.title2.weight(.bold))
                            Text(Formatters.distance(option.distanceMeters, metric: useMetric)).font(.caption)
                            Text(option.name).font(.caption2).foregroundStyle(AppColor.textSecondary).lineLimit(1)
                        }
                        .padding(12)
                        .frame(width: 132, alignment: .leading)
                        .background(selected ? theme.accent.opacity(0.22) : AppColor.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selected ? theme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(AppColor.textPrimary)
                    .accessibilityLabel("\(option.name), \(option.etaMinutes) minutos, \(Formatters.distance(option.distanceMeters, metric: useMetric))")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Mapa: cámara y estado

    private func setUp() {
        if let settings {
            viewModel.headingUp = settings.headingUp
            viewModel.mode = settings.defaultMode
        }
        map.onFollowCancelled = { viewModel.isFollowing = false }
        applyAvatar(settings?.mapAvatar)
        let context = modelContext
        environment.music.onConnectedChanged = { service, connected in
            guard let stored = try? context.fetch(FetchDescriptor<UserSettings>()).first else { return }
            var services = stored.connectedMusicServices
            if connected { services.insert(service) } else { services.remove(service) }
            stored.connectedMusicServices = services
            PersistenceCommit.saveQuietly(context, operation: "music-connected")
        }
        applyMusicSettings()
        environment.hub.setFreeDriveSpeedLimit(wantsFreeDriveLimit)
        environment.hub.setTraceVerification(wantsTraceVerification)
        applyMapLayers()
        apply3D(animated: false)
        pushSavedPlaces()
        if let active = environment.hub.session { presentNavigationUI(active) }   // navegación iniciada antes (p. ej. desde CarPlay)
        if startupFinished { afterStartup() } else if environment.hub.session == nil { location.start(mode: .idle) }
        startFeedingMaps()
        pushUser()
        map.setFollow(followMode, zoom: theme.activeCartography.defaultZoom, pitch: explorePitch, insets: layout.browsingFollowInsets)
    }

    /// Después de la animación de inicio: ahora sí se puede pedir el permiso (con contexto) y abrir el panel.
    private func afterStartup() {
        if location.authState == .notDetermined { location.requestWhenInUseAuthorization() }
        location.start(mode: navigation == nil ? .idle : .navigating)
        if navigation == nil { presentPanel() }
    }

    private func presentPanel(after delay: Double = 0.05) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            if navigation == nil, startupFinished { showPanel = true }
        }
    }

    /// Aplica los ajustes de música guardados. No pide permisos ni inicia música.
    private func applyMusicSettings() {
        let service = settings?.musicService ?? .appleMusic
        environment.music.configure(enabled: settings?.showMiniPlayer ?? false, service: service,
                                    connected: settings?.connectedMusicServices.contains(service) ?? false)
        environment.music.activate()
    }

    private func applyAvatar(_ avatar: MapAvatar?) {
        map.setAvatar(avatar ?? .arrow)
        miniMap.setAvatar(avatar ?? .arrow)
    }

    /// Empieza a llevar las lecturas al mapa grande y al minimapa (una sola vez).
    private func startFeedingMaps() {
        let map = self.map
        let miniMap = self.miniMap
        feeder.start(location: location) { reading, heading in
            map.setUser(reading, heading: heading)
            miniMap.setUser(reading, heading: heading)
        }
    }

    private func pushUser() {
        guard let reading = location.smoothedLocation else { return }
        // Solo presentación: los mapas animan la flecha hacia esta lectura. La navegación usa la lectura real
        // (`currentLocation`) en NavigationHub, nunca la posición animada.
        let heading = location.displayHeading
        map.setUser(reading, heading: heading)
        miniMap.setUser(reading, heading: heading)
    }

    private func recenter() {
        showFullRoute = false
        viewModel.isFollowing = true
        let style = theme.activeCartography
        if navigation != nil {
            map.setFollow(followMode, zoom: style.navigationZoom, pitch: navigationPitch, insets: layout.navigationFollowInsets)
            miniMap.setFollow(followMode, zoom: style.minimapZoom, pitch: 0, bottomInset: 0)
        } else {
            map.setFollow(followMode, zoom: style.defaultZoom, pitch: explorePitch, insets: layout.browsingFollowInsets)
        }
    }

    /// Alterna 2D/3D sin mover el centro, la ruta ni el destino; la preferencia se guarda al momento.
    private func toggle3D() {
        guard supports3D, let settings else { return }
        settings.view3D.toggle()
        PersistenceCommit.saveQuietly(modelContext, operation: "view3d")
        apply3D(animated: true)
    }

    /// Edificios y cámara según la preferencia. Durante la navegación usa la inclinación de navegación.
    private func apply3D(animated: Bool) {
        map.setBuildings3D(view3D)
        map.setPerspective(navigation != nil ? navigationPitch : explorePitch, animated: animated)
    }

    private func updateLayout(_ proxy: GeometryProxy) {
        let next = MapScreenLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
        if next != layout { layout = next }
    }

    /// Giro del iPhone o cambio de tamaño. Solo se adaptan la distribución y los márgenes de la cámara: el mapa, el
    /// estilo, la ruta, la navegación, la voz y la música siguen igual (no se recrea ni se recalcula nada).
    private func layoutChanged(from old: MapScreenLayout, to new: MapScreenLayout) {
        if modal == nil, sidePanel != new.isSideBySide { sidePanel = new.isSideBySide }
        if let navigation {
            if showFullRoute {
                map.fit(navigation.route.coordinates, insets: new.fullRouteInsets)
            } else {
                map.updateFollowInsets(new.navigationFollowInsets)     // sin efecto si el usuario explora a mano
            }
        } else if !map.refitWholeRoute(insets: new.previewRouteInsets) {
            map.updateFollowInsets(new.browsingFollowInsets)
        }
    }

    private func fitSelectedRoute() {
        guard navigation == nil, let route = viewModel.selectedRoute else { return }
        map.setRoute(route.coordinates)
        map.fit(route.coordinates, insets: layout.previewRouteInsets)
        viewModel.isFollowing = false
    }

    // MARK: - Acciones

    private func select(_ place: Place) {
        modal = nil
        viewModel.setDestination(place)
    }

    private func showOnMap(_ place: Place) {
        modal = nil
        panel.markers = [place]
        viewModel.isFollowing = false
        detent = .compactPanel
        map.focus(on: place.coordinate)
    }

    // MARK: - Selección en el mapa

    /// Toque sencillo: sobre un icono selecciona ese lugar; sobre una zona vacía quita la selección.
    /// Solo hay una selección. Nunca calcula una ruta ni borra la existente.
    private func handleMapTap(_ tap: MapTap) {
        guard navigation == nil else { return }
        if tap.feature != nil {
            viewModel.select(PoiClassTitles.place(from: tap))
        } else if viewModel.selection != nil {
            viewModel.clearSelection()
        }
    }

    private func distanceText(to place: Place) -> String? {
        guard let here = location.currentLocation else { return nil }
        let meters = here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
        return Formatters.distance(meters, metric: useMetric)
    }

    /// Cambia cuando cambian Casa o Trabajo (para volver a dibujarlos).
    private var savedSignature: String {
        savedPlaces.filter { $0.kindRawValue == PlaceKind.home.rawValue || $0.kindRawValue == PlaceKind.work.rawValue }
            .map { "\($0.kindRawValue):\($0.latitude),\($0.longitude)" }.sorted().joined(separator: "|")
    }

    private func pushSavedPlaces() {
        let items: [(coordinate: CLLocationCoordinate2D, icon: String)] = savedPlaces.compactMap { saved in
            guard let kind = PlaceKind(rawValue: saved.kindRawValue), let icon = GameIcons.savedIconName(for: kind) else { return nil }
            return (saved.coordinate, icon)
        }
        map.setSavedPlaces(items)
    }

    /// Pide al centro de navegación que empiece. La interfaz se prepara al reaccionar a `startToken`.
    private func startNavigation(_ route: Route) {
        guard let destination = viewModel.destination else { return }
        environment.hub.start(route: route, destination: destination, mode: viewModel.mode)
    }

    /// Prepara la pantalla del iPhone para una navegación (iniciada aquí o en CarPlay).
    private func presentNavigationUI(_ session: ActiveNavigationViewModel) {
        let style = theme.activeCartography
        panel.closeCategory()
        panel.clearQuery()
        viewModel.clearSelection()
        showPanel = false
        navDisplay = .map
        showFullRoute = false
        UIApplication.shared.isIdleTimerDisabled = true

        map.setRoute(session.route.coordinates)
        map.setDestination(session.destination)
        miniMap.setRoute(session.route.coordinates)
        miniMap.setDestination(session.destination)
        viewModel.isFollowing = true
        map.setFollow(followMode, zoom: style.navigationZoom, pitch: navigationPitch, insets: layout.navigationFollowInsets)
        miniMap.setFollow(followMode, zoom: style.minimapZoom, pitch: 0, bottomInset: 0)
    }

    /// La navegación ya terminó en el centro (guardado del viaje, voz y GPS incluidos): aquí solo se limpia la pantalla.
    private func endNavigationUI() {
        navDisplay = .map
        showFullRoute = false
        UIApplication.shared.isIdleTimerDisabled = false
        clearRoute()
        detent = .compactPanel
        presentPanel(after: 0.45)
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

    /// Casa y Trabajo: solo uno de cada; la dirección se guarda en la nota.
    private func saveSingle(kind: PlaceKind, place: Place) {
        perform(.set(kind, place))
    }

    /// Guarda o borra Casa/Trabajo AL MOMENTO (no al cerrar la app). Si falla, se avisa y se puede reintentar.
    private func perform(_ action: PersonalAction) {
        do {
            try PersonalPlaceStore(context: modelContext).apply(action)
            failedPersonalAction = nil
        } catch {
            failedPersonalAction = action
        }
    }

    private func setAsideBrokenStore() {
        do {
            _ = try StoreBackup.setAside()
            storeSetAside = true
        } catch {
            StorageDiagnostics.record(operation: "set-aside", outcome: "error", note: StorageErrorInfo.describe(error))
        }
    }

    private func save(kind: PlaceKind) {
        guard let destination = viewModel.destination else { return }
        switch kind {
        case .home, .work:
            saveSingle(kind: kind, place: destination)
        case .favorite, .pin:
            modelContext.insert(SavedPlace(name: destination.name, note: destination.subtitle, iconName: "star.fill",
                                           kind: kind, latitude: destination.latitude, longitude: destination.longitude))
            do { try PersistenceCommit.save(modelContext, operation: "favorite") } catch { failedFavoriteSave = true }
        }
    }
}

extension SavedPlace {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
