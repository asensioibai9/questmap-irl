import Foundation
import Observation
import UIKit

/// Previews reales del selector de estilos. Primero se leen de la caché (sin renderizar nada); solo se genera lo que falta
/// o ha cambiado, de UNO en UNO (nunca varios mapas a la vez) y en segundo plano de la pantalla. Si una preview falla se
/// muestra el error de ESE estilo: nunca la imagen de otro.
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
    @ObservationIgnored private var task: Task<Void, Never>?

    init(cache: StylePreviewCache = StylePreviewCache(), renderer: StylePreviewRendering? = nil,
         scale: CGFloat = UIScreen.main.scale, build: String = AppConfig.build,
         loadStyleData: @escaping (CartographyStyle) -> Data? = { style in
             Bundle.main.url(forResource: style.resourceName, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
         }) {
        self.cache = cache
        self.renderer = renderer ?? StylePreviewRenderer()
        self.scale = scale
        self.build = build
        self.loadStyleData = loadStyleData
    }

    func state(for id: MapThemeID) -> State { states[id] ?? .idle }

    private func fingerprint(for style: CartographyStyle) -> String? {
        guard let data = loadStyleData(style) else { return nil }
        return StylePreviewCache.fingerprint(styleData: data, appBuild: build, scale: scale)
    }

    /// Lee la caché y genera lo que falte, empezando por el estilo elegido. No hace nada si ya hay un trabajo en marcha.
    func prepare(themes: [MapTheme], selected: MapThemeID?) {
        let ordered = themes.filter(\.isCartographyReady).sorted { $0.id == selected && $1.id != selected }
        var pending: [MapTheme] = []
        for theme in ordered {
            guard let style = theme.cartography, let fingerprint = fingerprint(for: style) else {
                states[theme.id] = .failed("No se encuentra el estilo en la app.")
                continue
            }
            if case .ready = state(for: theme.id) { continue }
            if let image = cache.load(styleID: theme.id.rawValue, fingerprint: fingerprint) {
                states[theme.id] = .ready(image)
            } else {
                states[theme.id] = .loading
                pending.append(theme)
            }
        }
        guard task == nil, !pending.isEmpty else { return }
        task = Task { [weak self] in
            for theme in pending {
                await self?.generate(theme)
            }
            self?.task = nil
        }
    }

    /// Reintenta una preview fallida.
    func retry(_ theme: MapTheme, themes: [MapTheme], selected: MapThemeID?) {
        if case .failed = state(for: theme.id) { states[theme.id] = .idle }
        prepare(themes: themes, selected: selected)
    }

    private func generate(_ theme: MapTheme) async {
        guard let style = theme.cartography, let fingerprint = fingerprint(for: style) else { return }
        states[theme.id] = .loading
        do {
            let image = try await renderer.render(style: style)
            renderedCount += 1
            try? cache.store(image, styleID: theme.id.rawValue, fingerprint: fingerprint)
            states[theme.id] = .ready(image)
        } catch {
            states[theme.id] = .failed((error as? LocalizedError)?.errorDescription ?? "No se pudo generar la vista previa.")
        }
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
