import SwiftUI
import MapKit
import SwiftData

/// Pantalla principal: mapa a pantalla completa, búsqueda, accesos rápidos y vista previa de ruta.
struct HomeView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query private var savedPlaces: [SavedPlace]
    @State private var viewModel: HomeViewModel
    @State private var showSearch = false
    @State private var navigation: ActiveNavigationViewModel?
    @State private var savePlaceKind: PlaceKind?

    let environment: AppEnvironment
    let useMetric: Bool

    init(environment: AppEnvironment, useMetric: Bool) {
        self.environment = environment
        self.useMetric = useMetric
        _viewModel = State(initialValue: HomeViewModel(
            locationService: environment.locationService,
            routeService: environment.routeService
        ))
    }

    private var home: SavedPlace? { savedPlaces.first { $0.kindRawValue == PlaceKind.home.rawValue } }
    private var work: SavedPlace? { savedPlaces.first { $0.kindRawValue == PlaceKind.work.rawValue } }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            MapOverlayView(theme: theme)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                searchBar
                if viewModel.destination == nil { quickAccess }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote.weight(.semibold))
                        .padding(10)
                        .background(theme.panel, in: .rect(cornerRadius: 12))
                        .foregroundStyle(theme.textPrimary)
                }
                if environment.locationService.authState == .denied { permissionBanner }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.destination == nil {
                RecenterButton(theme: theme) { viewModel.recenter() }
                    .padding(20)
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.destination != nil {
                routeCard.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: viewModel.destination != nil)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onAppear {
            if environment.locationService.authState == .notDetermined {
                environment.locationService.requestWhenInUseAuthorization()
            }
            environment.locationService.startUpdating()
        }
        .sheet(isPresented: $showSearch) {
            SearchView(near: viewModel.origin) { name, coordinate in
                viewModel.setDestination(coordinate, name: name)
            }
        }
        .fullScreenCover(item: $navigation) { nav in
            ActiveNavigationView(viewModel: nav,
                                 locationService: environment.locationService,
                                 speech: environment.speech,
                                 useMetric: useMetric)
                .onDisappear { viewModel.clearRoute() }
        }
        .alert("Guardar como", isPresented: Binding(
            get: { savePlaceKind != nil },
            set: { if !$0 { savePlaceKind = nil } }
        )) {
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
                UserAnnotation()

                ForEach(savedPlaces) { place in
                    Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
                        Image(systemName: place.iconName)
                            .font(.caption.weight(.bold))
                            .padding(6)
                            .background(theme.panel, in: .circle)
                            .foregroundStyle(theme.accent)
                    }
                }

                if let destination = viewModel.destination {
                    Annotation(viewModel.destinationName, coordinate: destination) {
                        DestinationPin(color: theme.accent)
                    }
                }

                if let route = viewModel.selectedRoute {
                    MapPolyline(route.route.polyline)
                        .stroke(theme.routeGlow, lineWidth: theme.routeGlowWidth)
                    MapPolyline(route.route.polyline)
                        .stroke(theme.routeCore, lineWidth: theme.routeCoreWidth)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        if case .second(true, let drag?) = value,
                           let coordinate = proxy.convert(drag.location, from: .local) {
                            viewModel.setDestination(coordinate, name: "Punto del mapa")
                        }
                    }
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Piezas de UI

    private var searchBar: some View {
        Button { showSearch = true } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text(viewModel.destination == nil ? "¿A dónde vamos?" : viewModel.destinationName)
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(viewModel.destination == nil ? theme.textSecondary : theme.textPrimary)
            .font(.body.weight(.medium))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(theme.panel, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.6), lineWidth: 1))
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
                viewModel.setDestination(CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude), name: place.name)
            } else {
                showSearch = true
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(theme.panel, in: .capsule)
                .foregroundStyle(place == nil ? theme.textSecondary : theme.accent)
        }
    }

    private var permissionBanner: some View {
        VStack(spacing: 8) {
            Text("Sin acceso a la ubicación no podemos guiarte.")
                .font(.footnote.weight(.semibold))
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.footnote.weight(.bold))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(theme.panel, in: .rect(cornerRadius: 12))
        .foregroundStyle(theme.textPrimary)
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Modo", selection: $viewModel.mode) {
                ForEach(RouteMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.mode) { _, _ in Task { await viewModel.loadRoutes() } }

            if viewModel.isLoadingRoutes {
                ProgressView().frame(maxWidth: .infinity)
            } else if !viewModel.routes.isEmpty {
                routeAlternatives
                if let route = viewModel.selectedRoute {
                    Button { startNavigation(route) } label: {
                        Label("Iniciar misión", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                }
            }

            HStack {
                Button("Cancelar", role: .cancel) { viewModel.clearRoute() }
                Spacer()
                Button { savePlaceKind = .favorite } label: { Image(systemName: "star") }
                    .accessibilityLabel("Guardar lugar")
                if let origin = viewModel.origin, let destination = viewModel.destination,
                   let url = ShareLinkBuilder.routeURL(from: origin, to: destination, mode: viewModel.mode) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
            .font(.subheadline)
            .foregroundStyle(theme.textPrimary)
        }
        .padding(18)
        .background(theme.panel, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.accent.opacity(0.5), lineWidth: 1))
        .padding(16)
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
                            Text(Formatters.distance(option.route.distance, metric: useMetric))
                                .font(.caption)
                            Text(option.name).font(.caption2).lineLimit(1)
                        }
                        .padding(12)
                        .frame(width: 130, alignment: .leading)
                        .background(selected ? theme.accent.opacity(0.25) : theme.background.opacity(0.5), in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? theme.accent : .clear, lineWidth: 2))
                    }
                    .foregroundStyle(theme.textPrimary)
                }
            }
        }
    }

    // MARK: - Acciones

    private func startNavigation(_ route: RouteOption) {
        guard let destination = viewModel.destination else { return }
        navigation = ActiveNavigationViewModel(
            route: route,
            destinationName: viewModel.destinationName,
            destination: destination,
            mode: viewModel.mode,
            routeService: environment.routeService,
            speech: environment.speech
        )
    }

    private func save(kind: PlaceKind) {
        guard let destination = viewModel.destination else { return }
        // Casa y Trabajo son únicos: se sustituye el anterior.
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
        savePlaceKind = nil
    }
}

extension ActiveNavigationViewModel: Identifiable {}

// MARK: - Componentes

private struct DestinationPin: View {
    let color: Color
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 34))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.7), radius: 8)
    }
}

private struct RecenterButton: View {
    let theme: MapTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .font(.title2)
                .frame(width: 56, height: 56)
                .foregroundStyle(theme.accent)
                .background(theme.panel, in: .circle)
                .overlay(Circle().stroke(theme.accent, lineWidth: 2))
        }
        .accessibilityLabel("Recentrar en mi ubicación")
    }
}
