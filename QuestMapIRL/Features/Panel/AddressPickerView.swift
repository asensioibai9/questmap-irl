import SwiftUI
import SwiftData
import CoreLocation

/// Elegir una dirección real con el buscador: para Casa, Trabajo, una zona de búsqueda o un
/// destino durante la navegación. Descarta respuestas antiguas y no sustituye el lugar elegido.
struct AddressPickerView: View {
    enum Phase: Equatable { case idle, loading, results, empty, failed(SearchError) }

    @Environment(\.dismiss) private var dismiss

    let title: String
    let prompt: String
    let search: PlaceSearchProviding
    let near: CLLocationCoordinate2D?
    let onPick: (Place) -> Void

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var phase: Phase = .idle
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: title) { dismiss() }
            PanelSearchBar(text: $query, focus: $focused, prompt: prompt) { EmptyView() }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 0) {
                    switch phase {
                    case .idle:
                        EmptyStateView(systemImage: "mappin.and.ellipse", title: "Escribe una dirección",
                                       message: "Calle y número, barrio, ciudad o nombre de un lugar.")
                    case .loading:
                        HStack(spacing: 10) { ProgressView(); Text("Buscando…").foregroundStyle(AppColor.textSecondary) }
                            .frame(maxWidth: .infinity, minHeight: 90)
                    case .empty:
                        EmptyStateView(systemImage: "magnifyingglass", title: "Sin resultados",
                                       message: "Prueba con otra dirección.")
                    case .failed(let error):
                        InlineMessage(kind: error.isConnectionProblem ? .error : .warning, text: error.userMessage,
                                      actionTitle: "Reintentar") { run() }
                    case .results:
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, place in
                            if index > 0 { RowDivider() }
                            Button {
                                onPick(place)
                                dismiss()
                            } label: {
                                PlaceRowContent(icon: "mappin.circle.fill", title: place.name, subtitle: place.subtitle)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .background(phase == .results ? AppColor.surface : Color.clear,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in run() }
    }

    private func run() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .idle
            results = []
            return
        }
        phase = .loading
        task = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                let found = try await search.search(text, near: near, category: nil)
                guard !Task.isCancelled, text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                results = found
                phase = found.isEmpty ? .empty : .results
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error as? SearchError ?? .unexpected)
            }
        }
    }
}

/// Lista de lugares guardados: favoritos y pines. Tocar uno traza la ruta; se puede ver en el
/// mapa o eliminar.
struct SavedPlacesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var saved: [SavedPlace]

    let onSelect: (Place) -> Void
    let onShowOnMap: (Place) -> Void
    @State private var deleteFailed = false

    private var favorites: [SavedPlace] {
        saved.filter { $0.kindRawValue == PlaceKind.favorite.rawValue || $0.kindRawValue == PlaceKind.pin.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Guardados") { dismiss() }
            if favorites.isEmpty {
                EmptyStateView(systemImage: "star", title: "Aún no hay lugares guardados",
                               message: "Elige un destino y pulsa la estrella de la tarjeta de ruta para guardarlo aquí.")
                Spacer()
            } else {
                ScrollView {
                    SettingsGroup {
                        ForEach(Array(favorites.enumerated()), id: \.element.persistentModelID) { index, item in
                            if index > 0 { RowDivider() }
                            HStack(spacing: 0) {
                                Button {
                                    onSelect(item.asPlace)
                                    dismiss()
                                } label: {
                                    PlaceRowContent(icon: "star.fill", title: item.name, subtitle: item.kindTitle, showsRoute: true)
                                }
                                .buttonStyle(PressableStyle())
                                Menu {
                                    Button { onShowOnMap(item.asPlace); dismiss() } label: { Label("Ver en el mapa", systemImage: "map") }
                                    Button(role: .destructive) {
                                        context.delete(item)
                                        do { try PersistenceCommit.save(context, operation: "favorite-delete") } catch { deleteFailed = true }
                                    } label: { Label("Eliminar", systemImage: "trash") }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundStyle(AppColor.textSecondary)
                                        .frame(width: 44, height: 56)
                                }
                                .accessibilityLabel("Más acciones para \(item.name)")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .alert("No se pudo eliminar", isPresented: $deleteFailed) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("El lugar sigue guardado. Inténtalo de nuevo.")
        }
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
