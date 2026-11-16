import SwiftUI

/// Aviso que se muestra al pulsar el botón de ubicación cuando no se puede centrar el mapa.
struct LocationNotice: Equatable {
    enum Action: Equatable {
        case requestPermission, fullAccuracy, refresh, settings

        var title: String {
            switch self {
            case .requestPermission: return "Permitir"
            case .fullAccuracy: return "Activar precisa"
            case .refresh: return "Reintentar"
            case .settings: return "Abrir Ajustes"
            }
        }
    }

    let text: String
    var action: Action?
}

/// Crédito de los datos del mapa. Texto corto SIEMPRE visible (no queda escondido tras un botón),
/// en dos líneas pequeñas; al tocarlo se abren los créditos completos con sus enlaces.
struct MapAttributionLabel: View {
    /// Texto completo del estilo ("© OpenStreetMap contributors · © OpenMapTiles · OpenFreeMap").
    let text: String
    let onTap: () -> Void

    private var lines: [String] {
        text.components(separatedBy: " · ").enumerated().map { $0.element }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 5) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(lines.first ?? text)
                    if lines.count > 1 { Text(lines.dropFirst().joined(separator: " · ")) }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Créditos del mapa: \(text). Toca para ver los créditos completos.")
    }
}

/// Créditos y licencias completos de los datos y servicios cartográficos que usa la app.
struct MapCreditsView: View {
    var onClose: (() -> Void)?

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let onClose { PanelHeader(title: "Créditos del mapa", onClose: onClose).padding(.horizontal, -20) }

                credit("Datos del mapa",
                       "© colaboradores de OpenStreetMap. Los datos están disponibles bajo la licencia abierta ODbL.",
                       "Copyright de OpenStreetMap", "https://www.openstreetmap.org/copyright")
                credit("Teselas del mapa",
                       "OpenFreeMap · © OpenMapTiles · Data from OpenStreetMap.",
                       "openfreemap.org", "https://openfreemap.org")
                credit("OpenMapTiles", "Esquema de las teselas vectoriales.", "openmaptiles.org", "https://www.openmaptiles.org/")
                credit("Rutas", "Cálculo con OSRM sobre datos de OpenStreetMap.", "project-osrm.org", "https://project-osrm.org")
                credit("Búsqueda de direcciones", "Photon (komoot) sobre datos de OpenStreetMap.", "photon.komoot.io", "https://photon.komoot.io")
                Text("Los estilos visuales son creaciones propias; no están afiliados a ningún videojuego.")
                    .font(.footnote).foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppColor.background.ignoresSafeArea())

        if onClose != nil {
            content.preferredColorScheme(.dark)
        } else {
            content.navigationTitle("Créditos del mapa").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func credit(_ title: String, _ text: String, _ linkTitle: String, _ url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(AppColor.textPrimary)
            Text(text).font(.subheadline).foregroundStyle(AppColor.textSecondary)
            if let destination = URL(string: url) {
                Link(linkTitle, destination: destination).font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
