import SwiftUI

/// Contenido de la ventana de CarPlay: el mapa (solo lectura, sin gestos) y, dentro del área segura que deja el sistema,
/// la señal de límite de velocidad y el crédito del mapa. No dibuja botones propios: los controles son las plantillas de CarPlay.
struct CarMapView: View {
    let controller: MapController
    let style: CartographyStyle
    let hub: NavigationHub
    let metric: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            QuestMapView(controller: controller, style: style, interactive: false)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                if let session = hub.session, session.speedLimit != .hidden {
                    SpeedLimitSign(display: session.speedLimit, metric: metric, size: 64)
                }
                Text(style.attribution)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(12)
        }
    }
}
