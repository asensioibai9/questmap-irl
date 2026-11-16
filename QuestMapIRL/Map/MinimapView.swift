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
        let shape = style.minimapShape == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        QuestMapView(controller: controller, style: style, interactive: false)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.stroke(Color(hex: style.minimapBorderHex), lineWidth: 4))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .contentShape(shape)
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Minimapa")
            .accessibilityHint("Toca dos veces para abrir el mapa completo")
            .accessibilityAddTraits(.isButton)
    }
}
