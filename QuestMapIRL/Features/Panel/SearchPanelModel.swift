import Foundation
import CoreLocation
import Observation

/// Estado del panel inferior de búsqueda: texto, resultados del buscador, categoría abierta y
/// marcadores del mapa. Vive en la pantalla principal, así que el texto no se pierde al cambiar
/// de altura el panel. Descarta respuestas antiguas y nunca sustituye el lugar elegido.
@MainActor
@Observable
final class SearchPanelModel {
    enum Phase: Equatable { case idle, loading, results, empty, needsLocation, failed(String) }

    // Buscador de texto
    var query = ""
    private(set) var phase: Phase = .idle
    private(set) var results: [Place] = []

    // Categoría
    private(set) var activeCategory: PlaceCategory?
    private(set) var categoryPhase: Phase = .idle
    private(set) var categoryResults: [Place] = []
    /// Zona elegida por el usuario cuando no hay ubicación (o quiere buscar en otro sitio).
    private(set) var area: Place?

    /// Marcadores que debe dibujar el mapa.
    var markers: [Place] = []

    private let search: PlaceSearchProviding
    private let nearby: NearbySearchProviding
    private var searchTask: Task<Void, Never>?
    private var categoryTask: Task<Void, Never>?

    init(search: PlaceSearchProviding, nearby: NearbySearchProviding) {
        self.search = search
        self.nearby = nearby
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Buscador

    func queryChanged(near: CLLocationCoordinate2D?) {
        searchTask?.cancel()
        let text = trimmedQuery
        guard !text.isEmpty else {
            phase = .idle
            results = []
            if activeCategory == nil { markers = [] }
            return
        }
        // Escribir cierra la categoría abierta: el texto manda.
        if activeCategory != nil { closeCategory() }
        phase = .loading
        searchTask = Task { [search, self] in
            try? await Task.sleep(for: .milliseconds(350))   // espera a que el usuario termine de escribir
            guard !Task.isCancelled else { return }
            do {
                let found = try await search.search(text, near: near, category: nil)
                // Descarta respuestas antiguas: solo vale la de la consulta actual.
                guard !Task.isCancelled, text == self.trimmedQuery else { return }
                results = found
                phase = found.isEmpty ? .empty : .results
                markers = found
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                phase = .failed((error as? LocalizedError)?.errorDescription ?? "No se pudo buscar")
            }
        }
    }

    func clearQuery() {
        searchTask?.cancel()
        query = ""
        phase = .idle
        results = []
        markers = []
    }

    // MARK: - Categorías

    func openCategory(_ category: PlaceCategory, near: CLLocationCoordinate2D?) {
        searchTask?.cancel()
        query = ""
        phase = .idle
        results = []
        activeCategory = category
        loadCategory(near: near)
    }

    func setArea(_ place: Place?, near: CLLocationCoordinate2D?) {
        area = place
        if activeCategory != nil { loadCategory(near: near) }
    }

    func reloadCategory(near: CLLocationCoordinate2D?) {
        loadCategory(near: near)
    }

    func closeCategory() {
        categoryTask?.cancel()
        activeCategory = nil
        categoryPhase = .idle
        categoryResults = []
        markers = []
    }

    /// Centro de la búsqueda: la zona elegida, o si no, la ubicación real del usuario.
    private func center(near: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        area?.coordinate ?? near
    }

    private func loadCategory(near: CLLocationCoordinate2D?) {
        categoryTask?.cancel()
        guard let category = activeCategory else { return }
        guard let center = center(near: near) else {
            categoryResults = []
            categoryPhase = .needsLocation
            markers = []
            return
        }
        categoryPhase = .loading
        categoryResults = []
        markers = []
        categoryTask = Task { [nearby, self] in
            do {
                var found = try await nearby.nearby(category, around: center, radiusMeters: 2500)
                if found.isEmpty {
                    found = try await nearby.nearby(category, around: center, radiusMeters: 7000)
                }
                guard !Task.isCancelled, self.activeCategory == category else { return }
                categoryResults = found
                categoryPhase = found.isEmpty ? .empty : .results
                markers = found
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.activeCategory == category else { return }
                categoryResults = []
                categoryPhase = .failed((error as? LocalizedError)?.errorDescription ?? "No se pudo buscar")
            }
        }
    }
}
