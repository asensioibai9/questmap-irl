import SwiftData
import SwiftUI

/// Contenido de la ventana de CarPlay: el mapa (solo lectura, sin gestos) y, dentro del área segura que deja el sistema,
/// la señal de límite de velocidad y el crédito del mapa. No dibuja botones propios: los controles son las plantillas de CarPlay.
///
/// La señal sale de la MISMA fuente que el iPhone (`NavigationHub.speedLimit`): no hay una segunda detección. En CarPlay se
/// aplican «Mostrar señal», el diseño y «cuando no hay dato»; el tamaño es fijo y la posición es siempre abajo a la
/// izquierda dentro del área segura (CarPlay no permite colocar elementos libremente). La velocidad actual no se muestra.
struct CarMapView: View {
    let controller: MapController
    let style: CartographyStyle
    let hub: NavigationHub
    let metric: Bool

    @Query private var settingsRows: [UserSettings]

    private var appearance: SpeedSignAppearance {
        var value = settingsRows.first?.speedSignAppearance ?? .defaults
        value.showsCurrentSpeed = false
        return value
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            QuestMapView(controller: controller, style: style, interactive: false)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                SpeedLimitSign(display: hub.speedLimit, metric: metric, appearance: appearance,
                               countryCode: hub.speedLimitCountry, fixedSide: 64)
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
