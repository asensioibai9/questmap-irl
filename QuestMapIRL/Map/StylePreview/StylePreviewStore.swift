import Foundation
import ImageIO
import Observation
import UIKit

/// Previews reales del selector de estilos. Primero se leen de la caché (sin renderizar nada); solo se genera lo que falta
/// o ha cambiado, de UNO en UNO (nunca varios mapas a la vez) y en segundo plano de la pantalla. Si una preview falla se
/// muestra el error de ESE estilo: nunca la imagen de otro.
///
/// Rendimiento:
/// - La huella de cada estilo (lectura del JSON + SHA-256) se calcula UNA vez por ejecución: el estilo va dentro de la app y
///   no cambia mientras está abierta.
/// - Las imágenes de la caché se decodifican FUERA del hilo principal y ya reducidas al tamaño de la tarjeta en pantalla
///   (antes se decodificaban a 1920×1200 en el hilo principal al dibujarlas, durante el scroll).
@MainActor
@Observable
final class StylePreviewStore {
    static let shared = StylePreviewStore()

    enum State {
        case idle
        case loading
        case ready(UIImage)
        case failed(String)
    }

    private(set) var states: [MapThemeID: State] = [:]
    /// Cuántas previews se han generado con el motor (no leídas de la caché). Sirve para comprobar que la caché funciona.
    @ObservationIgnored private(set) var renderedCount = 0

    @ObservationIgnored private let cache: StylePreviewCache
    @ObservationIgnored private let renderer: StylePreviewRendering
    @ObservationIgnored private let scale: CGFloat
    @ObservationIgnored private let build: String
    @ObservationIgnored private let loadStyleData: (CartographyStyle) -> Data?
    /// Lado mayor (px) con el que se decodifican las previews de la caché: el ancho de la tarjeta en pantalla.
    @ObservationIgnored private let displayMaxPixel: CGFloat
    @ObservationIgnored private var fingerprints: [String: String] = [:]
    @ObservationIgnored private var generationQueue: [MapTheme] = []
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var decodeTask: Task<Void, Never>?

    init(cache: StylePreviewCache = StylePreviewCache(), renderer: StylePreviewRendering? = nil,
         scale: CGFloat = UIScreen.main.scale, build: String = AppConfig.build,
         displayMaxPixel: CGFloat = UIScreen.main.bounds.width * UIScreen.main.scale,
         loadStyleData: @escaping (CartographyStyle) -> Data? = { style in
             Bundle.main.url(forResource: style.resourceName, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
         }) {
        self.cache = cache
        self.renderer = renderer ?? StylePreviewRenderer()
        self.scale = scale
        self.build = build
        self.displayMaxPixel = max(200, displayMaxPixel)
        self.loadStyleData = loadStyleData
    }

    func state(for id: MapThemeID) -> State { states[id] ?? .idle }

    private func fingerprint(for style: CartographyStyle) -> String? {
        if let known = fingerprints[style.resourceName] { return known }
        guard let data = PerformanceTrace.measure("preview-fingerprint", { loadStyleData(style) }) else { return nil }
        let value = StylePreviewCache.fingerprint(styleData: data, appBuild: build, scale: scale)
        fingerprints[style.resourceName] = value
        return value
    }

    /// Lee la caché (en segundo plano) y genera lo que falte, empezando por el estilo elegido.
    func prepare(themes: [MapTheme], selected: MapThemeID?) {
        let ordered = themes.filter(\.isCartographyReady).sorted { $0.id == selected && $1.id != selected }
        var cached: [(theme: MapTheme, url: URL)] = []
        var missing: [MapTheme] = []
        for theme in ordered {
            switch state(for: theme.id) {
            case .ready, .loading: continue
            case .idle, .failed: break
            }
            guard let style = theme.cartography, let fingerprint = fingerprint(for: style) else {
                states[theme.id] = .failed("No se encuentra el estilo en la app.")
                continue
            }
            states[theme.id] = .loading
            if let url = cache.existingURL(styleID: theme.id.rawValue, fingerprint: fingerprint) {
                cached.append((theme, url))
            } else {
                missing.append(theme)
            }
        }
        enqueueGeneration(missing)
        guard !cached.isEmpty else { return }
        let maxPixel = displayMaxPixel
        let previous = decodeTask
        decodeTask = Task { [weak self] in
            await previous?.value
            for item in cached {
                let image = await Self.decodeForDisplay(url: item.url, maxPixel: maxPixel)
                guard let self else { return }
                if let image {
                    self.states[item.theme.id] = .ready(image)
                } else {
                    self.enqueueGeneration([item.theme])     // archivo de caché dañado: se vuelve a generar
                }
            }
        }
    }

    /// Reintenta una preview fallida.
    func retry(_ theme: MapTheme, themes: [MapTheme], selected: MapThemeID?) {
        if case .failed = state(for: theme.id) { states[theme.id] = .idle }
        prepare(themes: themes, selected: selected)
    }

    private func enqueueGeneration(_ themes: [MapTheme]) {
        generationQueue.append(contentsOf: themes)
        guard generationTask == nil, !generationQueue.isEmpty else { return }
        generationTask = Task { [weak self] in
            while let self, !self.generationQueue.isEmpty {
                let theme = self.generationQueue.removeFirst()
                await self.generate(theme)
            }
            self?.generationTask = nil
        }
    }

    private func generate(_ theme: MapTheme) async {
        guard let style = theme.cartography, let fingerprint = fingerprint(for: style) else { return }
        states[theme.id] = .loading
        do {
            let image = try await renderer.render(style: style)
            renderedCount += 1
            do {
                try cache.store(image, styleID: theme.id.rawValue, fingerprint: fingerprint)
            } catch {
                // Sin caché la preview se ve igual; la próxima vez se regenerará.
                StorageDiagnostics.record(operation: "preview-cache-store", outcome: "error", note: StorageErrorInfo.describe(error))
            }
            states[theme.id] = .ready(image)
        } catch {
            states[theme.id] = .failed((error as? LocalizedError)?.errorDescription ?? "No se pudo generar la vista previa.")
        }
    }

    /// Decodifica y reduce una imagen de la caché sin pasar por el hilo principal (función asíncrona no aislada: se ejecuta
    /// en el ejecutor global). Devuelve nil si el archivo está dañado.
    nonisolated static func decodeForDisplay(url: URL, maxPixel: CGFloat) async -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,          // decodifica aquí, no al dibujar
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Lo que necesita el almacén de un generador de previews (permite probarlo sin renderizar).
@MainActor
protocol StylePreviewRendering {
    func render(style: CartographyStyle) async throws -> UIImage
}

extension StylePreviewRenderer: StylePreviewRendering {
    func render(style: CartographyStyle) async throws -> UIImage {
        try await render(style: style, provider: .openFreeMap, timeout: 30)
    }
}
