import SwiftData
import SwiftUI

/// «Capas del mapa»: elementos visibles SOBRE el estilo elegido. El estilo (GTA, Fortnite…) se elige en «Estilo de mapa»,
/// al que se llega desde aquí. Cada interruptor solo cambia la visibilidad de capas que ya están en el mapa: se aplica al
/// momento, sin recargar el estilo, sin mover la cámara y sin tocar la ruta. Las capas sin fuente real no se pueden
/// activar y dicen por qué.
struct MapLayersSheet: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.mapTheme) private var theme
    @Query private var settingsRows: [UserSettings]
    @State private var confirmReset = false

    private var settings: UserSettings? { settingsRows.first }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MapStyleGalleryView()
                    } label: {
                        HStack {
                            Label("Estilo de mapa", systemImage: "paintpalette.fill")
                            Spacer()
                            Text(theme.name).foregroundStyle(AppColor.textSecondary).lineLimit(1)
                        }
                    }
                } footer: {
                    Text("El estilo cambia el aspecto del mapa. Las capas de abajo se mantienen al cambiar de estilo.")
                }

                if let settings {
                    Section {
                        Toggle(isOn: Binding(get: { settings.showPlaceNames }, set: { setPlaceNames($0) })) {
                            Label("Mostrar nombres de los lugares", systemImage: "textformat")
                        }
                    } footer: {
                        Text("Nombre breve bajo cada icono, según el zoom y sin tapar otros elementos. El nombre completo aparece al tocar el lugar.")
                    }

                    ForEach(MapLayerGroup.allCases) { group in
                        Section(group.title) {
                            ForEach(MapLayerID.allCases.filter { $0.group == group }) { layer in
                                row(layer, preferences: settings.mapLayers)
                            }
                        }
                    }

                    Section {
                        Button("Restablecer capas", role: .destructive) { confirmReset = true }
                    } footer: {
                        Text("Vuelve a las capas y nombres predeterminados. No borra Casa, Trabajo, favoritos ni perfiles de voz. Los resultados de una búsqueda, el destino, el lugar seleccionado y tus lugares guardados se ven siempre, aunque su categoría esté oculta. Ocultar una capa no cambia cómo se calculan las rutas.")
                    }

                    Section {
                        EmptyView()
                    } footer: {
                        Text("Datos: OpenStreetMap vía OpenMapTiles / OpenFreeMap (© colaboradores de OpenStreetMap). Son datos estáticos: no hay horarios, plazas libres, bicicletas disponibles ni estado de semáforos en directo.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Capas del mapa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { onClose() } }
            }
            .confirmationDialog("¿Restablecer las capas del mapa?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Restablecer", role: .destructive) {
                    settings?.resetMapLayers()
                    PersistenceCommit.saveQuietly(context, operation: "map-layers-reset")
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .tint(theme.accent)
    }

    @ViewBuilder
    private func row(_ layer: MapLayerID, preferences: MapLayerPreferences) -> some View {
        let available = layer.availability.canEnable
        Toggle(isOn: Binding(get: { preferences.isEnabled(layer) }, set: { set(layer, $0) })) {
            HStack(spacing: 12) {
                Image(systemName: layer.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(available ? theme.accent : AppColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.title).foregroundStyle(available ? AppColor.textPrimary : AppColor.textSecondary)
                    if !available {
                        Text("No disponible").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                    if let detail = layer.detail {
                        Text(detail).font(.caption).foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        .disabled(!available)
        .accessibilityHint(available ? "" : (layer.availability.unavailableReason ?? ""))
    }

    private func set(_ layer: MapLayerID, _ on: Bool) {
        guard let settings else { return }
        var preferences = settings.mapLayers
        preferences.set(layer, on)
        guard preferences != settings.mapLayers else { return }
        settings.mapLayers = preferences
        PersistenceCommit.saveQuietly(context, operation: "map-layers")
    }

    private func setPlaceNames(_ show: Bool) {
        guard let settings, settings.showPlaceNames != show else { return }
        settings.showPlaceNames = show
        PersistenceCommit.saveQuietly(context, operation: "place-names")
    }
}
