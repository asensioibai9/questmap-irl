import SwiftUI
import MapKit
import SwiftData

/// Búsqueda de destino: texto libre, lugares guardados y resultados de Apple Maps.
struct SearchView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]

    let near: CLLocationCoordinate2D?
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    private let service = PlaceSearchService()

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Tus lugares") {
                        if savedPlaces.isEmpty {
                            Text("Guarda Casa, Trabajo o favoritos desde el mapa.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(savedPlaces) { place in
                            Button {
                                select(place.name, CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                            } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(place.name)
                                        if !place.note.isEmpty {
                                            Text(place.note).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: place.iconName).foregroundStyle(theme.accent)
                                }
                            }
                        }
                    }
                } else {
                    Section(isSearching ? "Buscando…" : "Resultados") {
                        ForEach(results, id: \.self) { item in
                            Button {
                                select(item.name ?? "Destino", item.placemark.coordinate)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "Lugar")
                                    if let address = item.placemark.title {
                                        Text(address).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("¿A dónde vamos?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Dirección, lugar, ciudad…")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    isSearching = true
                    results = (try? await service.search(newValue, near: near)) ?? []
                    isSearching = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func select(_ name: String, _ coordinate: CLLocationCoordinate2D) {
        onSelect(name, coordinate)
        dismiss()
    }
}
