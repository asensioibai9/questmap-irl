import CarPlay
import MapKit
import SwiftData
import SwiftUI
import UIKit

/// Interfaz de navegación de CarPlay con las plantillas públicas (`CPMapTemplate`, `CPNavigationSession`, `CPListTemplate`,
/// `CPSearchTemplate`). NO copia la pantalla del iPhone: el mapa se dibuja en la ventana del coche y todo lo demás son
/// plantillas del sistema. La navegación activa es la del `NavigationHub` (la misma que ve el iPhone).
///
/// Estado: compilado y probado con tests de lógica. NO probado en el simulador de CarPlay ni en un coche, y no funcionará en
/// un dispositivo hasta que Apple conceda el entitlement `com.apple.developer.carplay-maps` (ver docs/21).
@MainActor
final class CarPlayCoordinator: NSObject {
    private let environment: AppEnvironment
    private let interfaceController: CPInterfaceController
    private let window: UIWindow
    private let mapTemplate = CPMapTemplate()
    private let carMap = MapController()
    private var cartography: CartographyStyle
    private var metric = true

    private var navSession: CPNavigationSession?
    private var activeTrip: CPTrip?
    private var shownManeuverIndices: [Int] = []
    private var maneuvers: [CPManeuver] = []
    private var pendingPreview: (place: Place, routes: [Route])?
    private var searchToken = 0
    private var is3D = false
    private var isActive = false

    private var hub: NavigationHub { environment.hub }
    private var location: LocationServiceProtocol { environment.locationService }

    init(environment: AppEnvironment, interfaceController: CPInterfaceController, window: UIWindow) {
        self.environment = environment
        self.interfaceController = interfaceController
        self.window = window
        let stored = try? ContainerFactory.shared.mainContext.fetch(FetchDescriptor<UserSettings>()).first
        let theme = ThemeCatalog.theme(for: stored?.themeID ?? .ciudadNocturna)
        self.cartography = (theme.isCartographyReady ? theme : ThemeCatalog.ciudadNocturna).activeCartography
        self.metric = stored?.useMetricUnits ?? true
        super.init()
    }

    // MARK: - Ciclo de vida

    func start() {
        isActive = true
        carMap.setSimplified(true)          // menos etiquetas y puntos de interés en la pantalla del coche
        // Mismo ajuste que el iPhone para la señal sin ruta (por si CarPlay arranca sin la pantalla del teléfono).
        let stored = try? ContainerFactory.shared.mainContext.fetch(FetchDescriptor<UserSettings>()).first
        hub.setFreeDriveSpeedLimit((stored?.showSpeedLimit ?? true) && (stored?.speedLimitWithoutRoute ?? false))
        hub.setTraceVerification((stored?.showSpeedLimit ?? true) && (stored?.speedLimitVerifyTrace ?? true))
        carMap.setBuildings3D(false)        // 2D por defecto; el botón alterna el 3D
        window.rootViewController = UIHostingController(rootView: CarMapView(
            controller: carMap, style: cartography, hub: hub, metric: metric)
            .modelContainer(ContainerFactory.shared))

        mapTemplate.mapDelegate = self
        mapTemplate.tripEstimateStyle = .dark
        mapTemplate.leadingNavigationBarButtons = [CPBarButton(title: "Destinos") { [weak self] _ in self?.showDestinations() }]
        mapTemplate.trailingNavigationBarButtons = [CPBarButton(title: "Buscar") { [weak self] _ in self?.showSearch() }]
        mapTemplate.mapButtons = mapButtons()
        interfaceController.setRootTemplate(mapTemplate, animated: false, completion: nil)

        followUser()
        observeHub()
        observeLocation()
        // Si el iPhone ya tenía una ruta iniciada, CarPlay se une a LA MISMA sesión (no crea otra).
        hubChanged()
    }

    /// El coche se desconecta: se sueltan los recursos de CarPlay. La navegación NO se cancela ni se borra: sigue en el iPhone.
    func stop() {
        isActive = false
        navSession = nil
        activeTrip = nil
        window.rootViewController = nil
    }

    // MARK: - Botones del mapa

    private func mapButtons() -> [CPMapButton] {
        let recenter = CPMapButton { [weak self] _ in self?.followUser() }
        recenter.image = UIImage(systemName: "location.fill")
        var buttons = [recenter]
        if cartography.supportsBuildings3D {
            let toggle = CPMapButton { [weak self] button in
                guard let self else { return }
                self.is3D.toggle()
                self.carMap.setBuildings3D(self.is3D)
                self.carMap.setPerspective(self.is3D ? 40 : 0)
                button.image = UIImage(systemName: self.is3D ? "view.3d" : "view.2d")
            }
            toggle.image = UIImage(systemName: "view.2d")
            buttons.append(toggle)
        }
        return buttons
    }

    private func followUser() {
        let inset = max(0, window.bounds.height * 0.18)
        let zoom = hub.isNavigating ? cartography.navigationZoom : cartography.defaultZoom
        carMap.setFollow(.headingUp, zoom: zoom, pitch: is3D ? 40 : 0, bottomInset: inset)
    }

    // MARK: - Observación del estado compartido

    private func observeHub() {
        withObservationTracking {
            _ = hub.session
            _ = hub.session?.snapshot
            _ = hub.startToken
            _ = hub.endToken
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.hubChanged()
                self.observeHub()
            }
        }
    }

    private func observeLocation() {
        withObservationTracking {
            _ = location.smoothedLocation
            _ = location.displayHeading
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                if let reading = self.location.smoothedLocation {
                    self.carMap.setUser(reading, heading: self.location.displayHeading)
                }
                self.observeLocation()
            }
        }
    }

    private func hubChanged() {
        if let session = hub.session {
            if navSession == nil { beginCarNavigation(session) }
            syncNavigation(session)
        } else if navSession != nil {
            endCarNavigation()
        }
    }

    // MARK: - Navegación activa

    private func beginCarNavigation(_ session: ActiveNavigationViewModel) {
        let place = hub.destination ?? Place.pin(at: session.destination, name: session.destinationName)
        let trip = makeTrip(destination: place, routes: [session.route])
        activeTrip = trip
        shownManeuverIndices = []
        mapTemplate.hideTripPreviews()
        navSession = mapTemplate.startNavigationSession(for: trip)
        carMap.setRoute(session.route.coordinates)
        carMap.setDestination(session.destination)
        followUser()
    }

    /// Maniobra próxima, siguiente, distancias y tiempos reales del motor de navegación (no una línea dibujada).
    private func syncNavigation(_ session: ActiveNavigationViewModel) {
        guard let navSession, let trip = activeTrip else { return }
        let snapshot = session.snapshot
        let route = session.route
        let indices = CarPlayPresentation.upcomingIndices(snapshot: snapshot, stepCount: route.steps.count)
        if indices != shownManeuverIndices {
            shownManeuverIndices = indices
            maneuvers = indices.map { index in
                let step = route.steps[index]
                let maneuver = CPManeuver()
                maneuver.instructionVariants = CarPlayPresentation.maneuverVariants(step)
                maneuver.symbolImage = UIImage(systemName: step.symbol)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                return maneuver
            }
            navSession.upcomingManeuvers = maneuvers
        }
        if let first = maneuvers.first {
            let meters = max(0, snapshot.distanceToManeuver)
            navSession.updateEstimates(
                CPTravelEstimates(distanceRemaining: Measurement(value: meters, unit: UnitLength.meters),
                                  timeRemaining: CarPlayPresentation.seconds(forMeters: meters, route: route)),
                for: first)
        }
        mapTemplate.updateEstimates(
            CPTravelEstimates(distanceRemaining: Measurement(value: max(0, snapshot.remainingMeters), unit: UnitLength.meters),
                              timeRemaining: max(0, snapshot.remainingSeconds)),
            for: trip)
    }

    private func endCarNavigation() {
        if hub.lastEndWasArrival { navSession?.finishTrip() } else { navSession?.cancelTrip() }
        navSession = nil
        activeTrip = nil
        shownManeuverIndices = []
        maneuvers = []
        carMap.setRoute([])
        carMap.setDestination(nil)
        followUser()
    }

    // MARK: - Destinos

    private func showDestinations() {
        let home = savedPlace(.home)
        let work = savedPlace(.work)
        var items: [CPListItem] = [
            placeItem(title: "Casa", place: home, missing: "Añádela desde el iPhone"),
            placeItem(title: "Trabajo", place: work, missing: "Añádelo desde el iPhone"),
        ]
        items.append(listItem("Favoritos", detail: "Lugares guardados") { [weak self] in self?.showList("Favoritos", self?.favorites() ?? []) })
        items.append(listItem("Recientes", detail: "Últimas búsquedas") { [weak self] in self?.showList("Recientes", self?.recents() ?? []) })
        items.append(listItem("Cerca de ti", detail: "Gasolineras, aparcamientos…") { [weak self] in self?.showCategories() })
        let template = CPListTemplate(title: "Destinos", sections: [CPListSection(items: items)])
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func placeItem(title: String, place: Place?, missing: String) -> CPListItem {
        let item = CPListItem(text: title, detailText: place.map { CarPlayPresentation.detail(for: $0, distanceMeters: nil, metric: metric) } ?? missing)
        if let place {
            item.handler = { [weak self] _, completion in
                self?.preview(place)
                completion()
            }
        } else {
            item.isEnabled = false
        }
        return item
    }

    private func listItem(_ title: String, detail: String, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail)
        item.accessoryType = .disclosureIndicator
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    private func showList(_ title: String, _ places: [Place]) {
        guard !places.isEmpty else { return showMessage("Sin lugares", detail: "No hay \(title.lowercased()) todavía.") }
        let items = CarPlayPresentation.limited(places, max: CPListTemplate.maximumItemCount).map { place in
            let item = CPListItem(text: place.name, detailText: CarPlayPresentation.detail(for: place, distanceMeters: distance(to: place), metric: metric))
            item.handler = { [weak self] _, completion in
                self?.preview(place)
                completion()
            }
            return item
        }
        interfaceController.pushTemplate(CPListTemplate(title: title, sections: [CPListSection(items: items)]), animated: true, completion: nil)
    }

    private func showCategories() {
        let items = PlaceCategory.grid.map { category in
            listItem(category.title, detail: "Cerca de tu posición") { [weak self] in self?.loadNearby(category) }
        }
        interfaceController.pushTemplate(CPListTemplate(title: "Cerca de ti", sections: [CPListSection(items: items)]),
                                         animated: true, completion: nil)
    }

    private func loadNearby(_ category: PlaceCategory) {
        guard let here = location.currentLocation?.coordinate else {
            return showMessage("Sin ubicación", detail: "Esperando una lectura fiable de GPS.")
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let places = try await self.environment.nearby.nearby(category, around: here, radiusMeters: 3000)
                self.showList(category.title, places)
            } catch {
                self.showMessage("No se pudo buscar", detail: "Comprueba la conexión del iPhone.")
            }
        }
    }

    // MARK: - Búsqueda

    private func showSearch() {
        let template = CPSearchTemplate()
        template.delegate = self
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Vista previa e inicio

    private func preview(_ place: Place) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let routes = try await self.hub.previewRoutes(to: place)
                guard !routes.isEmpty else { return self.showMessage("Sin ruta", detail: "No hay ruta hasta ese destino.") }
                self.pendingPreview = (place, routes)
                self.interfaceController.popToRootTemplate(animated: true, completion: nil)
                let configuration = CPTripPreviewTextConfiguration(startButtonTitle: "Iniciar",
                                                                    additionalRoutesButtonTitle: "Más rutas",
                                                                    overviewButtonTitle: "Resumen")
                self.mapTemplate.showTripPreviews([self.makeTrip(destination: place, routes: routes)], textConfiguration: configuration)
                self.showRouteOnMap(routes[0])
            } catch {
                let message = (error as? RoutingError)?.errorDescription ?? "No se pudo calcular la ruta."
                self.showMessage("Sin ruta", detail: self.location.currentLocation == nil ? "Esperando ubicación." : message)
            }
        }
    }

    private func makeTrip(destination place: Place, routes: [Route]) -> CPTrip {
        let origin = location.currentLocation.map { MKMapItem(placemark: MKPlacemark(coordinate: $0.coordinate)) } ?? MKMapItem.forCurrentLocation()
        let target = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        target.name = place.name
        let choices = routes.enumerated().map { index, route -> CPRouteChoice in
            let summary = CarPlayPresentation.routeSummary(route, metric: metric)
            let choice = CPRouteChoice(summaryVariants: summary,
                                       additionalInformationVariants: CarPlayPresentation.routeInformation(route, index: index, count: routes.count),
                                       selectionSummaryVariants: summary)
            choice.userInfo = index
            return choice
        }
        return CPTrip(origin: origin, destination: target, routeChoices: choices)
    }

    private func showRouteOnMap(_ route: Route) {
        carMap.setRoute(route.coordinates)
        let inset = UIEdgeInsets(top: 80, left: 120, bottom: 80, right: 60)
        carMap.fit(route.coordinates, insets: inset)
    }

    fileprivate func startTrip(using choice: CPRouteChoice) {
        guard let preview = pendingPreview, let index = choice.userInfo as? Int, preview.routes.indices.contains(index) else { return }
        pendingPreview = nil
        hub.start(route: preview.routes[index], destination: preview.place, mode: .driving)
        hubChanged()
    }

    fileprivate func selectedPreview(using choice: CPRouteChoice) {
        guard let preview = pendingPreview, let index = choice.userInfo as? Int, preview.routes.indices.contains(index) else { return }
        showRouteOnMap(preview.routes[index])
    }

    fileprivate func cancelNavigation() {
        pendingPreview = nil
        mapTemplate.hideTripPreviews()
        if hub.isNavigating { hub.stop() } else { carMap.setRoute([]); followUser() }
    }

    // MARK: - Datos del usuario (solo lectura; no se registran)

    private func savedPlace(_ kind: PlaceKind) -> Place? {
        let all = (try? ContainerFactory.shared.mainContext.fetch(FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return all.first { $0.kindRawValue == kind.rawValue }?.asPlace
    }

    private func favorites() -> [Place] {
        let all = (try? ContainerFactory.shared.mainContext.fetch(FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return all.filter { $0.kindRawValue == PlaceKind.favorite.rawValue || $0.kindRawValue == PlaceKind.pin.rawValue }.map(\.asPlace)
    }

    private func recents() -> [Place] {
        var descriptor = FetchDescriptor<RecentSearch>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 12
        return ((try? ContainerFactory.shared.mainContext.fetch(descriptor)) ?? []).map(\.place)
    }

    private func distance(to place: Place) -> Double? {
        location.currentLocation?.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    }

    private func showMessage(_ title: String, detail: String) {
        let alert = CPAlertTemplate(titleVariants: ["\(title). \(detail)", title], actions: [
            CPAlertAction(title: "Aceptar", style: .default) { [weak self] _ in
                self?.interfaceController.dismissTemplate(animated: true, completion: nil)
            }
        ])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }
}

// MARK: - Delegado del mapa

extension CarPlayCoordinator: CPMapTemplateDelegate {
    nonisolated func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        MainActor.assumeIsolated { startTrip(using: routeChoice) }
    }

    nonisolated func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
        MainActor.assumeIsolated { selectedPreview(using: routeChoice) }
    }

    nonisolated func mapTemplateDidCancelNavigation(_ mapTemplate: CPMapTemplate) {
        MainActor.assumeIsolated { cancelNavigation() }
    }
}

// MARK: - Delegado de búsqueda

extension CarPlayCoordinator: CPSearchTemplateDelegate {
    nonisolated func searchTemplate(_ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String,
                                    completionHandler: @escaping ([CPListItem]) -> Void) {
        MainActor.assumeIsolated {
            let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else { return completionHandler([]) }
            searchToken += 1
            let token = searchToken
            Task { [weak self] in
                guard let self else { return completionHandler([]) }
                let places = (try? await self.environment.placeSearch.search(text, near: self.location.currentLocation?.coordinate, category: nil)) ?? []
                guard token == self.searchToken else { return completionHandler([]) }
                let items = CarPlayPresentation.limited(places, max: CPListTemplate.maximumItemCount).map { place -> CPListItem in
                    let item = CPListItem(text: place.name, detailText: CarPlayPresentation.detail(for: place, distanceMeters: self.distance(to: place), metric: self.metric))
                    item.userInfo = place
                    return item
                }
                completionHandler(items)
            }
        }
    }

    nonisolated func searchTemplate(_ searchTemplate: CPSearchTemplate, selectedResult item: CPListItem, completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            if let place = item.userInfo as? Place { preview(place) }
            completionHandler()
        }
    }
}
