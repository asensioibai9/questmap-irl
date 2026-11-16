import SwiftUI
import SwiftData
import CoreLocation

extension SavedPlace {
    /// Lugar listo para usar como destino.
    var asPlace: Place {
        Place(id: "saved-\(createdAt.timeIntervalSince1970)", name: note.isEmpty ? name : note,
              subtitle: kindTitle, latitude: latitude, longitude: longitude)
    }
}

/// Contenido del panel inferior: buscador, accesos rápidos, recientes, recomendaciones y
/// categorías. Se reparte en tres alturas (compacto, medio, expandido) que decide el sistema
/// con los detents de la hoja; aquí solo se reacciona a la altura y al foco del teclado.
struct SearchPanelView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecentSearch.date, order: .reverse) private var recents: [RecentSearch]
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var settingsRows: [UserSettings]

    @Bindable var model: SearchPanelModel
    @Binding var detent: PresentationDetent
    let near: CLLocationCoordinate2D?
    let accent: Color
    /// Por qué no hay ubicación (permiso denegado, GPS sin señal…), si se sabe.
    var locationHint: String?

    var onSelect: (Place) -> Void
    var onShowOnMap: (Place) -> Void
    var onProfile: () -> Void
    var onShowSaved: () -> Void
    var onPickAddress: (PlaceKind) -> Void
    var onChooseZone: () -> Void
    /// Borra solo Casa o solo Trabajo (la persistencia la hace quien llama, con guardado explícito).
    var onDeletePlace: (PlaceKind) -> Void = { _ in }

    @FocusState private var focused: Bool
    @State private var pendingDelete: PlaceKind?
    @State private var confirmClear = false
    @State private var showAllRecents = false

    private var settings: UserSettings? { settingsRows.first }
    private var metric: Bool { settings?.useMetricUnits ?? true }
    private var isCompact: Bool { detent == .compactPanel }

    var body: some View {
        VStack(spacing: 0) {
            PanelSearchBar(text: $model.query, focus: $focused, prompt: "Buscar") {
                CircleIconButton(systemImage: "person.fill", label: "Perfil", size: 48, action: onProfile)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) { content }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(isCompact)
            .scrollIndicators(.hidden)
        }
        .background(AppColor.surface)
        .onChange(of: focused) { _, isFocused in
            if isFocused { detent = .large }
        }
        .onChange(of: model.query) { _, _ in model.queryChanged(near: near) }
        .onChange(of: model.categoryPhase) { _, phase in
            if phase == .results || phase == .empty || phase == .needsLocation { focused = false; detent = .medium }
        }
        .confirmationDialog("¿Borrar el historial de búsquedas?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Borrar historial", role: .destructive) {
                recents.forEach(context.delete)
                PersistenceCommit.saveQuietly(context, operation: "recents-clear")
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Solo se borra el historial de este dispositivo.")
        }
        .confirmationDialog(pendingDelete == .home ? "¿Eliminar Casa?" : "¿Eliminar Trabajo?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(pendingDelete == .home ? "Eliminar Casa" : "Eliminar Trabajo", role: .destructive) {
                if let kind = pendingDelete { onDeletePlace(kind) }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Solo se elimina este acceso; no afecta a tu otra ubicación guardada.")
        }
    }

    // MARK: - Contenido según estado

    @ViewBuilder
    private var content: some View {
        if let category = model.activeCategory {
            categoryContent(category)
        } else if !model.trimmedQuery.isEmpty {
            queryContent
        } else {
            browseContent
        }
    }

    // MARK: Inicio (accesos, recientes, recomendaciones, categorías)

    @ViewBuilder
    private var browseContent: some View {
        quickAccess
        if !recents.isEmpty { recentSection }
        recommendations
        categories
    }

    private var quickAccess: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                placeChip(.home, icon: "house", set: "Casa", unset: "Añadir casa")
                placeChip(.work, icon: "briefcase", set: "Trabajo", unset: "Añadir trabajo")
                QuickAccessChip(systemImage: "bookmark", title: "Guardados",
                                subtitle: favoriteCount == 0 ? nil : "\(favoriteCount)") { onShowSaved() }
            }
            .padding(.vertical, 2)
        }
    }

    private var favoriteCount: Int {
        saved.filter { $0.kindRawValue == PlaceKind.favorite.rawValue || $0.kindRawValue == PlaceKind.pin.rawValue }.count
    }

    private func placeChip(_ kind: PlaceKind, icon: String, set: String, unset: String) -> some View {
        let item = saved.first { $0.kindRawValue == kind.rawValue }
        return QuickAccessChip(systemImage: icon, title: item == nil ? unset : set,
                               subtitle: item.flatMap { $0.note.isEmpty ? nil : $0.note },
                               isSet: item != nil) {
            if let item { onSelect(item.asPlace) } else { onPickAddress(kind) }
        }
        .contextMenu {
            if let item {
                Button { onSelect(item.asPlace) } label: { Label("Ir ahora", systemImage: "arrow.triangle.turn.up.right.circle") }
                Button { onShowOnMap(item.asPlace) } label: { Label("Ver en el mapa", systemImage: "map") }
                Button { onPickAddress(kind) } label: { Label("Editar dirección", systemImage: "pencil") }
                Button(role: .destructive) { pendingDelete = kind } label: { Label("Eliminar", systemImage: "trash") }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { withAnimation(.smooth) { showAllRecents.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text("Búsquedas recientes").font(.title3.weight(.bold))
                        Image(systemName: showAllRecents ? "chevron.down" : "chevron.right").font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(AppColor.textPrimary)
                }
                .accessibilityLabel(showAllRecents ? "Mostrar menos búsquedas recientes" : "Mostrar todas las búsquedas recientes")
                Spacer()
                Button("Borrar") { confirmClear = true }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(recents.prefix(showAllRecents ? 30 : 3).enumerated()), id: \.element.persistentModelID) { index, item in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 0) {
                        Button { open(item.place) } label: {
                            PlaceRowContent(icon: "clock.arrow.circlepath", title: item.name, subtitle: item.subtitle,
                                            distance: distance(to: item.place.coordinate))
                        }
                        .buttonStyle(PressableStyle())
                        Button {
                            context.delete(item)
                            PersistenceCommit.saveQuietly(context, operation: "recent-delete")
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(width: 44, height: 56)
                        }
                        .accessibilityLabel("Quitar \(item.name) del historial")
                    }
                }
            }
            .background(AppColor.surfaceRaised.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Recomendaciones")
            HStack(alignment: .top, spacing: 10) {
                RecommendationCard(title: "Restaurantes cercanos", systemImage: PlaceCategory.food.symbol,
                                   tint: Color(hex: 0xC2410C), tall: true) { openCategory(.food) }
                VStack(spacing: 10) {
                    RecommendationCard(title: "Cafeterías", systemImage: PlaceCategory.cafe.symbol,
                                       tint: Color(hex: 0x7C4A21)) { openCategory(.cafe) }
                    RecommendationCard(title: "Compras cercanas", systemImage: PlaceCategory.shop.symbol,
                                       tint: Color(hex: 0x6D28D9)) { openCategory(.shop) }
                }
            }
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Categorías")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(PlaceCategory.grid) { category in
                    CategoryTile(systemImage: category.symbol, title: category.title,
                                 isBusy: model.activeCategory == category && model.categoryPhase == .loading) {
                        openCategory(category)
                    }
                }
            }
        }
    }

    // MARK: Resultados del buscador

    @ViewBuilder
    private var queryContent: some View {
        switch model.phase {
        case .idle, .loading:
            HStack(spacing: 10) { ProgressView(); Text("Buscando…").foregroundStyle(AppColor.textSecondary) }
                .frame(maxWidth: .infinity, minHeight: 80)
        case .empty:
            EmptyStateView(systemImage: "magnifyingglass", title: "Sin resultados",
                           message: "Prueba con otra dirección, calle o nombre de lugar.")
        case .needsLocation:
            EmptyView()
        case .failed(let error):
            InlineMessage(kind: error.isConnectionProblem ? .error : .warning, text: error.userMessage,
                          actionTitle: "Reintentar") { model.queryChanged(near: near) }
        case .results:
            resultList(model.results, icon: "mappin.circle.fill")
        }
    }

    // MARK: Categoría abierta

    @ViewBuilder
    private func categoryContent(_ category: PlaceCategory) -> some View {
        HStack(spacing: 10) {
            CircleIconButton(systemImage: "chevron.left", label: "Volver", size: 40) { model.closeCategory() }
            Text(category.title).font(.title2.weight(.bold)).foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
        if let area = model.area {
            HStack {
                Label("Zona: \(area.name)", systemImage: "scope")
                    .font(.footnote.weight(.semibold)).foregroundStyle(AppColor.textSecondary).lineLimit(1)
                Spacer()
                Button("Cambiar", action: onChooseZone).font(.footnote.weight(.bold))
                Button("Quitar") { model.setArea(nil, near: near) }.font(.footnote.weight(.bold))
            }
        }
        switch model.categoryPhase {
        case .idle, .loading:
            HStack(spacing: 10) { ProgressView(); Text("Buscando \(category.title.lowercased())…").foregroundStyle(AppColor.textSecondary) }
                .frame(maxWidth: .infinity, minHeight: 100)
        case .needsLocation:
            EmptyStateView(systemImage: "location.slash",
                           title: "No tenemos tu ubicación",
                           message: locationHint ?? "Elige una zona para buscar a su alrededor.",
                           actionTitle: "Elegir zona", action: onChooseZone)
        case .empty:
            EmptyStateView(systemImage: category.symbol, title: "No hemos encontrado \(category.title.lowercased()) cerca",
                           message: "Prueba a elegir otra zona.", actionTitle: "Elegir zona", action: onChooseZone)
        case .failed(let error):
            InlineMessage(kind: error.isConnectionProblem ? .error : .warning, text: error.userMessage,
                          actionTitle: "Reintentar") {
                model.reloadCategory(near: near)
            }
        case .results:
            Text("\(model.categoryResults.count) resultados, del más cercano al más lejano")
                .font(.footnote).foregroundStyle(AppColor.textSecondary)
            resultList(model.categoryResults, icon: category.symbol)
        }
    }

    private func resultList(_ places: [Place], icon: String) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                if index > 0 { RowDivider() }
                Button { open(place) } label: {
                    PlaceRowContent(icon: icon, title: place.name, subtitle: place.subtitle,
                                    distance: distance(to: place.coordinate), showsRoute: true)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .background(AppColor.surfaceRaised.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Acciones

    private func openCategory(_ category: PlaceCategory) {
        focused = false
        model.openCategory(category, near: near)
    }

    private func open(_ place: Place) {
        focused = false
        if settings?.saveSearchHistory ?? true, model.activeCategory == nil { remember(place) }
        onSelect(place)
    }

    /// Guarda el lugar en el historial real (sin duplicados, máximo 30).
    private func remember(_ place: Place) {
        recents.filter { $0.placeID == place.id }.forEach(context.delete)
        context.insert(RecentSearch(place: place))
        for old in recents.dropFirst(29) { context.delete(old) }
        PersistenceCommit.saveQuietly(context, operation: "recent-add")
    }

    private func distance(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let near else { return nil }
        let meters = CLLocation(latitude: near.latitude, longitude: near.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        return Formatters.distance(meters, metric: metric)
    }
}

/// Fila de lugar: icono en círculo, nombre, dirección y distancia.
struct PlaceRowContent: View {
    let icon: String
    let title: String
    let subtitle: String
    var distance: String?
    var showsRoute = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(AppColor.surfaceRaised, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(AppColor.textPrimary).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(AppColor.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let distance {
                Text(distance).font(.caption.monospacedDigit()).foregroundStyle(AppColor.textSecondary)
            }
            if showsRoute {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.title3).foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension PresentationDetent {
    /// Solo la barra de búsqueda y el indicador de arrastre.
    static let compactPanel = PresentationDetent.height(118)
}
