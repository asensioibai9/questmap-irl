import SwiftUI

/// Minimapa compacto: segunda vista de mapa real, recortada con la forma del estilo, con zoom
/// independiente, flecha del usuario y ruta. El recorte es real (clipShape), no una máscara pintada.
struct MinimapView: View {
    @Environment(\.mapTheme) private var theme
    let controller: MapController
    let size: CGFloat
    let onTap: () -> Void

    var body: some View {
        let style = theme.activeCartography
        let faded = style.minimapShape == .fadedRectangle
        let width = faded ? size * 1.5 : size
        let shape = shape(for: style.minimapShape)

        QuestMapView(controller: controller, style: style, interactive: false)
            .frame(width: width, height: size)
            .clipShape(shape)
            // Radar rectangular: el mapa se desvanece hacia los bordes en vez de acabar en un marco.
            .mask {
                if faded {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.black).padding(7).blur(radius: 7)
                } else {
                    Rectangle()
                }
            }
            .overlay {
                if !faded { shape.stroke(Color(hex: style.minimapBorderHex), lineWidth: 4) }
            }
            .shadow(color: .black.opacity(faded ? 0 : 0.35), radius: 8, y: 3)
            .contentShape(shape)
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Minimapa")
            .accessibilityHint("Toca dos veces para abrir el mapa completo")
            .accessibilityAddTraits(.isButton)
    }

    private func shape(for kind: MinimapShape) -> AnyShape {
        switch kind {
        case .circle: AnyShape(Circle())
        case .roundedSquare: AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .fadedRectangle: AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
