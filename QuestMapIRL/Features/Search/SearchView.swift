import SwiftUI
import MapKit
import SwiftData

/// Búsqueda de destino: texto libre (MKLocalSearch), lugares guardados y accesos por categoría.
/// Estados: inicial, cargando, sin resultados, error / sin conexión.
struct SearchView: View {
    enum State: Equatable { case idle, loading, results, empty, failed(String) }

    @Environment(\.mapTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]

    let near: CLLocationCoordinate2D?
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    @SwiftUI.State private var query = ""
    @SwiftUI.State private var results: [MKMapItem] = []
    @SwiftUI.State private var state: State = .idle
    @SwiftUI.State private var searchTask: Task<Void, Never>?
    private let service = PlaceSearchService()

    private let categories: [(String, POIKind)] = [
        ("Gasolinera", .fuel), ("Restaurante", .food), ("Parking", .parking),
        ("Hospital", .hospital), ("Policía", .police), ("Centro comercial", .shop)
    ]

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.0) { title, kind in
                                    Button { query = title } label: {
                                        Label(title, systemImage: theme.icon(for: kind))
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
                    } header: { Text("Cerca de ti") }

                    Section("Tus lugares") {
                        if savedPlaces.isEmpty {
                            Text("Guarda Casa, Trabajo o favoritos desde la tarjeta de ruta.").foregroundStyle(.secondary)
                        }
                        ForEach(savedPlaces) { place in
                            Button { select(place.name, place.coordinate) } label: {
                                row(icon: place.iconName, title: place.name, subtitle: place.note.isEmpty ? place.kindTitle : place.note,
                                    distance: distance(to: place.coordinate))
                            }
                        }
                    }
                } else {
                    Section {
                        switch state {
                        case .loading:
                            HStack { ProgressView(); Text("Buscando…") }.foregroundStyle(.secondary)
                        case .empty:
                            ContentUnavailableView.search(text: query)
                        case .failed(let message):
                            ContentUnavailableView(message, systemImage: "wifi.exclamationmark",
                                                   description: Text("Comprueba la conexión e inténtalo de nuevo."))
                        case .results, .idle:
                            ForEach(results, id: \.self) { item in
                                Button { select(item.name ?? "Destino", item.placemark.coordinate) } label: {
                                    row(icon: "mappin.circle.fill", title: item.name ?? "Lugar",
                                        subtitle: item.placemark.title ?? "", distance: distance(to: item.placemark.coordinate))
                                }
                            }
                        }
                    } header: { Text(state == .results ? "\(results.count) resultados" : "Resultados") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("¿A dónde vamos?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Dirección, calle, ciudad, restaurante…")
            .autocorrectionDisabled()
            .onChange(of: query) { _, newValue in search(newValue) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
        .tint(theme.accent)
    }

    // MARK: - Filas

    private func row(icon: String, title: String, subtitle: String, distance: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: theme.iconWeight))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if let distance {
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

    private func search(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { state = .idle; results = []; return }
        state = .loading
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))   // debounce
            guard !Task.isCancelled else { return }
            do {
                let found = try await service.search(trimmed, near: near)
                guard !Task.isCancelled else { return }
                results = found
                state = found.isEmpty ? .empty : .results
            } catch is CancellationError {
            } catch {
                let ns = error as NSError
                let offline = ns.domain == NSURLErrorDomain || (error as? MKError)?.code == .serverFailure
                results = []
                state = offline ? .failed("Sin conexión") : .failed("No se pudo buscar")
            }
        }
    }

    private func select(_ name: String, _ coordinate: CLLocationCoordinate2D) {
        onSelect(name, coordinate)
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
