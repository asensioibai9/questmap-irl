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
        mapView.logoView.isHidden = !interactive
        mapView.attributionButton.isHidden = !interactive

        controller.attach(mapView)

        if interactive {
            let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
            press.minimumPressDuration = 0.5
            for recognizer in mapView.gestureRecognizers ?? [] where recognizer is UILongPressGestureRecognizer {
                press.require(toFail: recognizer)
            }
            mapView.addGestureRecognizer(press)
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
            for name in parent.style.textures {
                if let image = UIImage(named: name) { style.setImage(image, forName: name) }
            }
            PoiIcons.register(in: style, fillHex: parent.style.poiIconHex, outlineHex: parent.style.poiOutlineHex)
            parent.controller.styleDidLoad(style, arrowHex: parent.style.userArrowHex)
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

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MLNMapView else { return }
            let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress?(coordinate)
        }
    }
}
