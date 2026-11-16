import SwiftUI
import SwiftData
import CoreLocation

/// Búsqueda de destino: autocompletado, lugares guardados y accesos por categoría.
/// Gestiona consulta vacía, carga, sin resultados, error y sin conexión; descarta respuestas
/// antiguas que llegan tarde y no sustituye nunca el resultado elegido por otro parecido.
struct SearchView: View {
    enum Phase: Equatable { case idle, loading, results, empty, failed(String) }

    @Environment(\.mapTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]

    let search: PlaceSearchProviding
    let near: CLLocationCoordinate2D?
    let onSelect: (Place) -> Void

    @SwiftUI.State private var query = ""
    @SwiftUI.State private var results: [Place] = []
    @SwiftUI.State private var phase: Phase = .idle
    @SwiftUI.State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions
                } else {
                    resultsSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("¿A dónde vamos?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Dirección, calle, ciudad, restaurante…")
            .autocorrectionDisabled()
            .onChange(of: query) { _, newValue in runSearch(newValue) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
        .tint(theme.accent)
    }

    // MARK: - Sugerencias

    @ViewBuilder
    private var suggestions: some View {
        Section("Cerca de ti") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlaceCategory.allCases) { category in
                        Button { query = category.title } label: {
                            Label(category.title, systemImage: theme.icon(for: category.poiKind))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).frame(minHeight: 36)
                                .background(theme.accent.opacity(0.15), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }

        Section("Tus lugares") {
            if savedPlaces.isEmpty {
                Text("Guarda Casa, Trabajo o favoritos desde la tarjeta de ruta.").foregroundStyle(.secondary)
            }
            ForEach(savedPlaces) { saved in
                let place = Place(id: "saved-\(saved.createdAt.timeIntervalSince1970)", name: saved.name,
                                  subtitle: saved.note.isEmpty ? saved.kindTitle : saved.note,
                                  latitude: saved.latitude, longitude: saved.longitude)
                Button { select(place) } label: { row(icon: saved.iconName, place: place) }
            }
        }
    }

    // MARK: - Resultados

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            switch phase {
            case .loading, .idle:
                HStack { ProgressView(); Text("Buscando…") }.foregroundStyle(.secondary)
            case .empty:
                ContentUnavailableView.search(text: query)
            case .failed(let message):
                ContentUnavailableView(message, systemImage: "wifi.exclamationmark",
                                       description: Text("Comprueba la conexión e inténtalo de nuevo."))
            case .results:
                ForEach(results) { place in
                    Button { select(place) } label: { row(icon: "mappin.circle.fill", place: place) }
                }
            }
        } header: {
            Text(phase == .results ? "\(results.count) resultados" : "Resultados")
        }
    }

    private func row(icon: String, place: Place) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: theme.iconWeight))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if let distance = distance(to: place.coordinate) {
                Text(distance).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                .font(.title3)
                .foregroundStyle(theme.accent)
                .accessibilityLabel("Iniciar ruta")
        }
        .contentShape(Rectangle())
    }

    private func distance(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let near else { return nil }
        let meters = CLLocation(latitude: near.latitude, longitude: near.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        return Formatters.distance(meters, metric: true)
    }

    // MARK: - Búsqueda

    private func runSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            phase = .idle
            results = []
            return
        }
        phase = .loading
        // Si el texto coincide con un acceso por categoría, se filtra por esa categoría.
        let category = PlaceCategory.allCases.first { $0.title == trimmed }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))   // espera a que el usuario termine de escribir
            guard !Task.isCancelled else { return }
            do {
                let found = try await search.search(trimmed, near: near, category: category)
                // Descarta respuestas antiguas: solo vale la de la consulta actual.
                guard !Task.isCancelled, trimmed == query.trimmingCharacters(in: .whitespaces) else { return }
                results = found
                phase = found.isEmpty ? .empty : .results
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                phase = .failed((error as? LocalizedError)?.errorDescription ?? "No se pudo buscar")
            }
        }
    }

    private func select(_ place: Place) {
        onSelect(place)
        dismiss()
    }
}

extension SavedPlace {
    var kindTitle: String {
        switch PlaceKind(rawValue: kindRawValue) {
        case .home: return "Casa"
        case .work: return "Trabajo"
        case .favorite: return "Favorito"
        default: return "Pin"
        }
    }
}
