import SwiftUI
import MapLibre

enum MapLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

/// Mapa vectorial interactivo (MapLibre Native). Renderiza el estilo JSON del tema con datos
/// cartográficos reales. Es el único tipo de la app que conoce MapLibre, junto con `MapController`.
struct QuestMapView: UIViewRepresentable {
    let controller: MapController
    let style: CartographyStyle
    var provider: MapProviderConfig = .openFreeMap
    var interactive = true
    var showsCompass = false
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    /// Toque sencillo: devuelve el punto y, si hay un icono bajo el dedo, sus datos.
    var onTap: ((MapTap) -> Void)?
    var onStateChange: ((MapLoadState) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.backgroundColor = UIColor(hex: style.backgroundHex)
        mapView.automaticallyAdjustsContentInset = false
        mapView.showsUserLocation = false          // la posición la dibuja la app con su propio servicio
        mapView.compassView.isHidden = !showsCompass
        mapView.minimumZoomLevel = 2
        mapView.maximumZoomLevel = 20
        mapView.isUserInteractionEnabled = interactive
        // El minimapa no muestra ornamentos; la atribución va en el pie del HUD.
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true   // la atribución la dibuja la app (MapAttributionLabel)

        controller.attach(mapView)

        if interactive {
            let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
            press.minimumPressDuration = 0.5
            for recognizer in mapView.gestureRecognizers ?? [] where recognizer is UILongPressGestureRecognizer {
                press.require(toFail: recognizer)
            }
            mapView.addGestureRecognizer(press)

            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            for recognizer in mapView.gestureRecognizers ?? [] {
                if let other = recognizer as? UITapGestureRecognizer, other.numberOfTapsRequired > 1 { tap.require(toFail: other) }
            }
            mapView.addGestureRecognizer(tap)
        }

        context.coordinator.load(style, into: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        mapView.compassView.isHidden = !showsCompass
        if context.coordinator.loadedStyleName != style.resourceName {
            context.coordinator.load(style, into: mapView)
        }
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: Coordinator) {
        coordinator.cancelTimeout()
        coordinator.parent.controller.detach(mapView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: QuestMapView
        private(set) var loadedStyleName: String?
        private var timeout: DispatchWorkItem?

        private static let userGestureReasons: MLNCameraChangeReason = [
            .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn,
            .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt
        ]

        init(_ parent: QuestMapView) { self.parent = parent }

        func load(_ style: CartographyStyle, into mapView: MLNMapView) {
            loadedStyleName = style.resourceName
            mapView.backgroundColor = UIColor(hex: style.backgroundHex)
            report(.loading)
            do {
                mapView.styleURL = try StyleManager(provider: parent.provider).styleURL(for: style)
                scheduleTimeout()
            } catch {
                report(.failed(error.localizedDescription))
            }
        }

        func cancelTimeout() {
            timeout?.cancel()
            timeout = nil
        }

        private func scheduleTimeout() {
            cancelTimeout()
            let work = DispatchWorkItem { [weak self] in
                self?.report(.failed("El mapa tarda demasiado en cargar. Comprueba tu conexión."))
            }
            timeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        }

        private func report(_ state: MapLoadState) {
            let callback = parent.onStateChange
            DispatchQueue.main.async { callback?(state) }
        }

        // MARK: MLNMapViewDelegate

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            cancelTimeout()
            PerformanceTrace.measure("map-style-images", thresholdMs: 30) {
                for name in parent.style.textures {
                    if let image = UIImage(named: name) { style.setImage(image, forName: name) }
                }
                switch parent.style.poiIconSet {
                case .systemSymbols:
                    PoiIcons.register(in: style, fillHex: parent.style.poiIconHex, outlineHex: parent.style.poiOutlineHex)
                case .gameBadges:
                    GameIcons.register(in: style)
                }
                parent.controller.styleDidLoad(style, arrowHex: parent.style.userArrowHex)
            }
            report(.ready)
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            cancelTimeout()
            report(.failed("No se pudo cargar el mapa. \(error.localizedDescription)"))
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            if !reason.isDisjoint(with: Self.userGestureReasons) {
                parent.controller.userMovedCamera()
            }
        }

        // MARK: Gestos

        /// Toque sencillo: busca iconos propios (POI, Casa/Trabajo) en un área de 44 pt alrededor del dedo.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let ids = Set((mapView.style?.layers ?? []).map(\.identifier)
                .filter { $0.hasPrefix("poi-icon") || $0 == "saved-places" })
            var feature: MapTappedFeature?
            var tapped = coordinate
            if !ids.isEmpty {
                let area = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
                let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let nearest = mapView.visibleFeatures(in: area, styleLayerIdentifiers: ids)
                    .compactMap { $0 as? MLNPointFeature }
                    .min { a, b in
                        here.distance(from: CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude))
                            < here.distance(from: CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude))
                    }
                if let nearest {
                    tapped = nearest.coordinate
                    let attributes = nearest.attributes
                    let name = (attributes["name:es"] as? String) ?? (attributes["name"] as? String)
                    if let icon = attributes["icon"] as? String {
                        feature = MapTappedFeature(name: name, kind: icon, isSavedPlace: true)
                    } else {
                        feature = MapTappedFeature(name: name, kind: attributes["class"] as? String)
                    }
                }
            }
            parent.onTap?(MapTap(coordinate: tapped, feature: feature))
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MLNMapView else { return }
            let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress?(coordinate)
        }
    }
}
