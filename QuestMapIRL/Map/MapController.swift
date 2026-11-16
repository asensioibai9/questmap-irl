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

    private(set) var followMode: FollowMode = .northUp
    private var followZoom: Double = 15.5
    private var followPitch: Double = 0
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

    func styleDidLoad() {
        styleReady = true
        pushRoute()
        pushDestination()
        pushUser()
        applyFollow(animated: false)
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
