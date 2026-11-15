import SwiftUI

/// Capa decorativa del tema encima del mapa real.
/// Solo aporta ambiente (viñeta, tinte, brillo); no toca datos ni trazados.
struct MapOverlayView: View {
    let theme: MapTheme

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [.clear, theme.background.opacity(0.6)],
                center: .center,
                startRadius: 180,
                endRadius: 700
            )
            theme.background
                .opacity(theme.overlayOpacity)
                .blendMode(theme.overlayBlend)
        }
        .compositingGroup()
    }
}
