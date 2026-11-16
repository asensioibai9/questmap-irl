import MapLibre
import UIKit

enum StylePreviewError: LocalizedError, Equatable {
    case timedOut
    case failed(String)
    case noImage

    var errorDescription: String? {
        switch self {
        case .timedOut: return "Tardó demasiado en cargar el mapa. Comprueba la conexión."
        case .failed: return "No se pudo cargar la cartografía de esta zona."
        case .noImage: return "El mapa no devolvió ninguna imagen."
        }
    }
}

/// Genera UNA preview con `MLNMapSnapshotter` (misma biblioteca y mismo JSON de estilo que el mapa principal). Al cargar el
/// estilo registra EXACTAMENTE las mismas imágenes que el mapa principal (iconos, texturas, flecha del usuario) y rellena las
/// capas de navegación (ruta, destino, usuario) con la ruta de ejemplo: así la preview enseña lo que el estilo dibuja de verdad
/// y no depende de que el snapshotter las incluya por su cuenta. Los edificios 3D no se capturan (vista cenital, 2D).
@MainActor
final class StylePreviewRenderer: NSObject, MLNMapSnapshotterDelegate {
    private var snapshotter: MLNMapSnapshotter?
    private var cartography: CartographyStyle?
    private(set) var failure: String?

    /// Renderiza el estilo. Solo debe haber una llamada a la vez (la cola la garantiza el almacén).
    func render(style cartography: CartographyStyle, provider: MapProviderConfig = .openFreeMap,
                timeout: TimeInterval = 30) async throws -> UIImage {
        self.cartography = cartography
        failure = nil
        let styleURL = try StyleManager(provider: provider).styleURL(for: cartography)
        let camera = MLNMapCamera(lookingAtCenter: StylePreviewSpec.center, altitude: 1, pitch: StylePreviewSpec.pitch,
                                  heading: StylePreviewSpec.bearing)
        let options = MLNMapSnapshotOptions(styleURL: styleURL, camera: camera, size: StylePreviewSpec.size)
        options.zoomLevel = StylePreviewSpec.zoom
        let snapshotter = MLNMapSnapshotter(options: options)
        snapshotter.delegate = self
        self.snapshotter = snapshotter
        defer { self.snapshotter = nil }

        return try await withCheckedThrowingContinuation { continuation in
            let gate = OneShot()
            let finish: (Result<UIImage, Error>) -> Void = { result in
                guard gate.take() else { return }
                continuation.resume(with: result)
            }
            // Si el servidor no responde, la espera termina con un error claro (no se queda cargando para siempre).
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                snapshotter.cancel()
                finish(.failure(StylePreviewError.timedOut))
            }
            snapshotter.start { snapshot, error in
                timeoutTask.cancel()
                if let image = snapshot?.image {
                    finish(.success(image))
                } else if let error {
                    finish(.failure(StylePreviewError.failed(error.localizedDescription)))
                } else {
                    finish(.failure(StylePreviewError.noImage))
                }
            }
        }
    }

    func cancel() {
        snapshotter?.cancel()
        snapshotter = nil
    }

    // MARK: - MLNMapSnapshotterDelegate

    nonisolated func mapSnapshotter(_ snapshotter: MLNMapSnapshotter, didFinishLoading style: MLNStyle) {
        MainActor.assumeIsolated { prepare(style) }
    }

    nonisolated func mapSnapshotterDidFail(_ snapshotter: MLNMapSnapshotter, withError error: Error) {
        MainActor.assumeIsolated { failure = error.localizedDescription }
    }

    private func prepare(_ style: MLNStyle) {
        guard let cartography else { return }
        // Las mismas imágenes que registra el mapa principal (QuestMapView).
        for name in cartography.textures {
            if let image = UIImage(named: name) { style.setImage(image, forName: name) }
        }
        switch cartography.poiIconSet {
        case .systemSymbols:
            PoiIcons.register(in: style, fillHex: cartography.poiIconHex, outlineHex: cartography.poiOutlineHex)
        case .gameBadges:
            GameIcons.register(in: style)
        }
        UserArrowImage.register(in: style, avatar: .arrow, arrowHex: cartography.userArrowHex)

        // Capas de navegación: las mismas fuentes que alimenta MapController en el mapa principal.
        let route = StylePreviewSpec.route
        if let source = style.source(withIdentifier: "route") as? MLNShapeSource {
            source.shape = MLNPolylineFeature(coordinates: route, count: UInt(route.count))
        }
        if let source = style.source(withIdentifier: "destination") as? MLNShapeSource {
            let feature = MLNPointFeature()
            feature.coordinate = StylePreviewSpec.destination
            source.shape = feature
        }
        if let source = style.source(withIdentifier: "user") as? MLNShapeSource {
            let feature = MLNPointFeature()
            feature.coordinate = StylePreviewSpec.user.coordinate
            feature.attributes = ["heading": StylePreviewSpec.user.heading]
            source.shape = feature
        }
    }
}

/// Permite reanudar una continuación una sola vez.
private final class OneShot {
    private var used = false
    func take() -> Bool {
        if used { return false }
        used = true
        return true
    }
}
