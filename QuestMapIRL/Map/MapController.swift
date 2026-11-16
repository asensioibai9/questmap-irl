import CoreLocation
import MapLibre
import UIKit

enum FollowMode: Equatable {
    case off
    case northUp
    case headingUp
}

/// Controlador del renderizador cartográfico. Guarda el estado de las capas de navegación (ruta,
/// destino, usuario) y lo vuelve a aplicar tras cada carga de estilo, de modo que cambiar de
/// estilo conserva ruta, destino, posición y cámara sin duplicar nada: las fuentes viven en el
/// propio JSON del estilo y aquí solo se actualiza su contenido.
///
/// Debe usarse siempre desde el hilo principal.
final class MapController {
    private weak var mapView: MLNMapView?
    private var styleReady = false

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var destination: CLLocationCoordinate2D?
    private var user: (coordinate: CLLocationCoordinate2D, heading: Double)?
    private var markers: [Place] = []
    private var selection: CLLocationCoordinate2D?
    private var savedMarkers: [(coordinate: CLLocationCoordinate2D, icon: String)] = []
    private var avatar: MapAvatar = .arrow
    private var arrowColorHex: UInt32 = 0xFFFFFF

    private(set) var followMode: FollowMode = .northUp
    private var followZoom: Double = 15.5
    private var followPitch: Double = 0
    private var buildings3D = false
    private var bottomInset: CGFloat = 0
    private var hasCenteredOnUser = false

    /// Se llama cuando el usuario mueve el mapa con un gesto y se deja de seguirle.
    var onFollowCancelled: (() -> Void)?

    // MARK: - Ciclo de vida del mapa

    func attach(_ view: MLNMapView) {
        mapView = view
        styleReady = false
        if let user {
            view.setCenter(user.coordinate, zoomLevel: followZoom, animated: false)
        }
    }

    func detach(_ view: MLNMapView) {
        guard mapView === view else { return }
        mapView = nil
        styleReady = false
    }

    func styleDidLoad(_ style: MLNStyle, arrowHex: UInt32) {
        styleReady = true
        arrowColorHex = arrowHex
        UserArrowImage.register(in: style, avatar: avatar, arrowHex: arrowHex)
        pushRoute()
        pushDestination()
        pushMarkers()
        pushSelection(animated: false)
        pushSaved()
        pushUser()
        applyBuildings()
        applyPitch(animated: false)
        applyFollow(animated: false)
    }

    /// Cambia el avatar de la posición del usuario sin recargar el mapa.
    func setAvatar(_ newAvatar: MapAvatar) {
        guard newAvatar != avatar else { return }
        avatar = newAvatar
        guard styleReady, let style = mapView?.style else { return }
        UserArrowImage.register(in: style, avatar: avatar, arrowHex: arrowColorHex)
    }

    /// Marcadores de resultados de búsqueda (categorías, lugares guardados mostrados en el mapa).
    func setMarkers(_ places: [Place]) {
        markers = places
        pushMarkers()
    }

    /// Punto seleccionado (cuatro flechas alrededor). Solo hay una selección: la nueva sustituye a la anterior;
    /// nil la quita. Las flechas siguen ancladas a la coordenada al mover, rotar o ampliar el mapa.
    func setSelection(_ coordinate: CLLocationCoordinate2D?) {
        let changed = selection?.latitude != coordinate?.latitude || selection?.longitude != coordinate?.longitude
        selection = coordinate
        pushSelection(animated: changed && coordinate != nil)
    }

    /// Casa y Trabajo guardados, dibujados con sus iconos.
    func setSavedPlaces(_ places: [(coordinate: CLLocationCoordinate2D, icon: String)]) {
        savedMarkers = places
        pushSaved()
    }

    /// Edificios 3D encendidos/apagados. Solo cambia la visibilidad de la capa `building-3d` (que ya está en el
    /// estilo): no se reconstruye ni se recarga nada. Se vuelve a aplicar tras cada carga de estilo.
    func setBuildings3D(_ enabled: Bool) {
        buildings3D = enabled
        applyBuildings()
    }

    /// Inclinación de la cámara (0 = cenital). Transición suave; conserva centro, zoom y rumbo, y por tanto
    /// ruta, destino y marcadores. Se recuerda para aplicarla también tras cambiar de estilo.
    func setPerspective(_ pitch: Double, animated: Bool = true) {
        followPitch = pitch
        applyPitch(animated: animated)
    }

    /// Centra el mapa en un punto sin seguir al usuario.
    func focus(on coordinate: CLLocationCoordinate2D, zoom: Double = 16, bottomInset: CGFloat = 0) {
        followMode = .off
        onFollowCancelled?()
        guard let mapView else { return }
        mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        mapView.setCenter(coordinate, zoomLevel: zoom, direction: 0, animated: true)
    }

    func userMovedCamera() {
        guard followMode != .off else { return }
        followMode = .off
        onFollowCancelled?()
    }

    // MARK: - Capas de navegación

    func setRoute(_ coordinates: [CLLocationCoordinate2D]) {
        routeCoordinates = coordinates
        pushRoute()
    }

    func setDestination(_ coordinate: CLLocationCoordinate2D?) {
        destination = coordinate
        pushDestination()
    }

    /// Posición MOSTRADA (ya suavizada por el servicio de ubicación). Nunca se inventa una posición.
    func setUser(_ coordinate: CLLocationCoordinate2D, heading: Double) {
        user = (coordinate, heading)
        pushUser()
        applyFollow(animated: hasCenteredOnUser)
    }

    // MARK: - Cámara

    func setFollow(_ mode: FollowMode, zoom: Double, pitch: Double, bottomInset: CGFloat) {
        followMode = mode
        followZoom = zoom
        followPitch = pitch
        self.bottomInset = bottomInset
        guard let mapView else { return }
        if mode != .off {
            let camera = mapView.camera
            if abs(Double(camera.pitch) - pitch) > 0.5 {
                camera.pitch = CGFloat(pitch)
                mapView.setCamera(camera, animated: false)
            }
        }
        applyFollow(animated: true)
    }

    /// Encuadra una ruta completa (vista previa).
    func fit(_ coordinates: [CLLocationCoordinate2D], insets: UIEdgeInsets) {
        followMode = .off
        guard let mapView, !coordinates.isEmpty else { return }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }
        mapView.contentInset = .zero
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        )
        mapView.setDirection(0, animated: false)
        mapView.setVisibleCoordinateBounds(bounds, edgePadding: insets, animated: true)
    }

    // MARK: - Privado

    private func applyBuildings() {
        guard styleReady, let layer = mapView?.style?.layer(withIdentifier: "building-3d") else { return }
        layer.isVisible = buildings3D
    }

    private func applyPitch(animated: Bool) {
        guard let mapView, styleReady else { return }
        let camera = mapView.camera
        guard abs(Double(camera.pitch) - followPitch) > 0.5 else { return }
        camera.pitch = CGFloat(followPitch)
        mapView.setCamera(camera, withDuration: animated ? 0.6 : 0, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
    }

    private func applyFollow(animated: Bool) {
        guard let mapView, let user, followMode != .off else { return }
        mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        let direction = followMode == .headingUp ? user.heading : 0
        mapView.setCenter(user.coordinate, zoomLevel: followZoom, direction: direction, animated: animated)
        hasCenteredOnUser = true
    }

    private func shapeSource(_ identifier: String) -> MLNShapeSource? {
        guard styleReady, let style = mapView?.style else { return nil }
        return style.source(withIdentifier: identifier) as? MLNShapeSource
    }

    private func pushRoute() {
        guard let source = shapeSource("route") else { return }
        if routeCoordinates.count >= 2 {
            let coordinates = routeCoordinates
            source.shape = MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
        } else {
            source.shape = nil
        }
    }

    private func pushDestination() {
        guard let source = shapeSource("destination") else { return }
        if let destination {
            let feature = MLNPointFeature()
            feature.coordinate = destination
            source.shape = feature
        } else {
            source.shape = nil
        }
    }

    private func pushSelection(animated: Bool) {
        guard let source = shapeSource("selection") else { return }
        guard let selection else {
            source.shape = nil
            return
        }
        let feature = MLNPointFeature()
        feature.coordinate = selection
        source.shape = feature
        // Aparición breve y suave (sin parpadeo continuo); con "Reducir movimiento" aparece directamente.
        guard animated, !UIAccessibility.isReduceMotionEnabled,
              let layer = mapView?.style?.layer(withIdentifier: "selection-arrows") as? MLNSymbolStyleLayer else { return }
        layer.iconOpacityTransition = MLNTransition(duration: 0.22, delay: 0)
        layer.iconOpacity = NSExpression(forConstantValue: 0)
        DispatchQueue.main.async { layer.iconOpacity = NSExpression(forConstantValue: 1) }
    }

    private func pushSaved() {
        guard let source = shapeSource("saved") else { return }
        if savedMarkers.isEmpty {
            source.shape = nil
            return
        }
        let features: [MLNPointFeature] = savedMarkers.map { item in
            let feature = MLNPointFeature()
            feature.coordinate = item.coordinate
            feature.attributes = ["icon": item.icon]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func pushMarkers() {
        guard let source = shapeSource("results") else { return }
        if markers.isEmpty {
            source.shape = nil
            return
        }
        let features: [MLNPointFeature] = markers.map { place in
            let feature = MLNPointFeature()
            feature.coordinate = place.coordinate
            feature.attributes = ["name": place.name]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func pushUser() {
        guard let source = shapeSource("user") else { return }
        if let user {
            let feature = MLNPointFeature()
            feature.coordinate = user.coordinate
            feature.attributes = ["heading": user.heading]
            source.shape = feature
        } else {
            source.shape = nil
        }
    }
}
