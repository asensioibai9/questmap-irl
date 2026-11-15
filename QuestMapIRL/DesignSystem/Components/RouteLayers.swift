import SwiftUI
import MapKit

/// Ruta en tres capas (resplandor, borde, núcleo) con el mismo trazado de Apple Maps.
/// Si el tema lo pide, el núcleo lleva un trazo discontinuo animado ("recorrido").
@MapContentBuilder
func routeLayers(_ polyline: MKPolyline, theme: MapTheme, phase: CGFloat = 0) -> some MapContent {
    MapPolyline(polyline)
        .stroke(theme.routeGlow, lineWidth: theme.routeGlowWidth)
    MapPolyline(polyline)
        .stroke(theme.routeBorder, style: StrokeStyle(lineWidth: theme.routeBorderWidth, lineCap: .round, lineJoin: .round))
    MapPolyline(polyline)
        .stroke(theme.routeCore, style: StrokeStyle(lineWidth: theme.routeCoreWidth, lineCap: .round, lineJoin: .round))
    if theme.routeAnimated {
        MapPolyline(polyline)
            .stroke(theme.routeBorder.opacity(0.9),
                    style: StrokeStyle(lineWidth: max(2, theme.routeCoreWidth - 3), lineCap: .round,
                                       dash: [10, 22], dashPhase: phase))
    }
}

/// Panel HUD reutilizable: fondo, borde y radio del tema.
struct QuestPanel<Content: View>: View {
    let theme: MapTheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous).stroke(theme.panelBorder, lineWidth: 1))
    }
}

/// Botón circular de mapa (recentrar, brújula, orientación).
struct MapRoundButton: View {
    let theme: MapTheme
    let systemImage: String
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: theme.iconWeight))
                .frame(width: 50, height: 50)
                .foregroundStyle(isActive ? theme.background : theme.accent)
                .background(isActive ? theme.accent : theme.panel, in: .circle)
                .overlay(Circle().stroke(theme.panelBorder, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }
}

/// Marcador del jugador: flecha orientada con el rumbo real.
struct PlayerMarker: View {
    let theme: MapTheme
    let heading: Double

    var body: some View {
        ZStack {
            Circle().fill(theme.player.opacity(0.18)).frame(width: 46, height: 46)
            Image(systemName: "location.north.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(theme.player)
                .shadow(color: theme.background.opacity(0.8), radius: 2)
                .rotationEffect(.degrees(heading))
        }
        .animation(.smooth(duration: 0.4), value: heading)
        .accessibilityHidden(true)
    }
}
