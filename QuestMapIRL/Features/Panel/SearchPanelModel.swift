import Foundation
import CoreLocation
import Observation

/// Estado del panel inferior de búsqueda: texto, resultados del buscador, categoría abierta y
/// marcadores del mapa. Vive en la pantalla principal, así que el texto no se pierde al cambiar
/// de altura el panel.
///
/// Reglas que cumple:
/// - Una respuesta antigua nunca pisa a una búsqueda más reciente (token de generación, además de
///   la cancelación de la tarea).
/// - Una cancelación normal (el usuario cambia de categoría o escribe otra cosa) no es un error.
/// - Una búsqueda correcta sin resultados es `.empty`, no un error.
/// - Cada fallo conserva su causa (`SearchError`) para mostrar el mensaje que le corresponde.
@MainActor
@Observable
final class SearchPanelModel {
    enum Phase: Equatable { case idle, loading, results, empty, needsLocation, failed(SearchError) }

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

    /// Radios de búsqueda de menor a mayor: si el primero no da resultados se amplía una vez.
    static let radii = [2000, 5000]

    private let search: PlaceSearchProviding
    private let nearby: NearbySearchProviding
    private var searchTask: Task<Void, Never>?
    private var categoryTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var categoryGeneration = 0
    /// Retraso antes de buscar mientras se escribe (ajustable en pruebas).
    var typingDelay: Duration = .milliseconds(350)

    init(search: PlaceSearchProviding, nearby: NearbySearchProviding) {
        self.search = search
        self.nearby = nearby
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Buscador

    func queryChanged(near: CLLocationCoordinate2D?) {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
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
            try? await Task.sleep(for: typingDelay)   // espera a que el usuario termine de escribir
            guard !Task.isCancelled, generation == searchGeneration else { return }
            do {
                let found = try await search.search(text, near: near, category: nil)
                // Respuesta antigua: solo vale la de la consulta actual.
                guard !Task.isCancelled, generation == searchGeneration else { return }
                results = found
                phase = found.isEmpty ? .empty : .results
                markers = found
            } catch is CancellationError {
                // Cancelación normal: la búsqueda nueva ya se ocupa del estado.
            } catch {
                guard !Task.isCancelled, generation == searchGeneration else { return }
                results = []
                phase = .failed(error as? SearchError ?? .unexpected)
            }
        }
    }

    func clearQuery() {
        searchTask?.cancel()
        searchGeneration += 1
        query = ""
        phase = .idle
        results = []
        markers = []
    }

    // MARK: - Categorías

    func openCategory(_ category: PlaceCategory, near: CLLocationCoordinate2D?) {
        searchTask?.cancel()
        searchGeneration += 1
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

    /// "Reintentar": lanza una búsqueda nueva y sale del estado de error.
    func reloadCategory(near: CLLocationCoordinate2D?) {
        loadCategory(near: near)
    }

    func closeCategory() {
        categoryTask?.cancel()
        categoryGeneration += 1
        activeCategory = nil
        categoryPhase = .idle
        categoryResults = []
        markers = []
    }

    /// Centro de la búsqueda: la zona elegida, o si no, la ubicación real del usuario.
    private func center(near: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        if let area { return area.coordinate }
        guard let near, CLLocationCoordinate2DIsValid(near) else { return nil }
        return near
    }

    private func loadCategory(near: CLLocationCoordinate2D?) {
        categoryTask?.cancel()
        categoryGeneration += 1
        let generation = categoryGeneration
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
                var found: [Place] = []
                for radius in Self.radii {
                    found = try await nearby.nearby(category, around: center, radiusMeters: radius)
                    if found.count >= 3 { break }       // suficientes resultados: no se amplía
                }
                guard !Task.isCancelled, generation == categoryGeneration else { return }
                categoryResults = found
                categoryPhase = found.isEmpty ? .empty : .results
                markers = found
            } catch is CancellationError {
                // El usuario cambió de categoría o buscó otra cosa: no es un fallo.
            } catch {
                guard !Task.isCancelled, generation == categoryGeneration else { return }
                categoryResults = []
                categoryPhase = .failed(error as? SearchError ?? .unexpected)
            }
        }
    }
}
