import SwiftUI

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

/// Un control del grupo compacto de mapa.
struct MapControlItem: Identifiable {
    let id: String
    let systemImage: String
    let label: String
    var isActive = false
    let action: () -> Void
}

/// Controles de mapa agrupados en una sola pieza vertical (horizontal del iPhone): 44 pt por botón, sin separación extra
/// entre ellos, superficie táctil completa. Ocupa mucho menos alto que botones sueltos con espacio entre medias.
struct MapControlCluster: View {
    let items: [MapControlItem]
    let accent: Color
    var background: Color = AppColor.surface
    var border: Color = AppColor.separator
    var iconWeight: Font.Weight = .semibold
    /// Lado de cada botón (mínimo 44 pt).
    var buttonSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Rectangle().fill(border).frame(width: 28, height: 1) }
                Button(action: item.action) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: buttonSize * 0.41, weight: iconWeight))
                        .foregroundStyle(item.isActive ? Color.black : accent)
                        .frame(width: max(44, buttonSize), height: max(44, buttonSize))
                        .background(item.isActive ? accent : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(item.isActive ? .isSelected : [])
            }
        }
        .padding(3)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

/// Icono de orientación del mapa, distinto del de «recentrar» (antes ambos eran flechas): brújula = el mapa gira con tu
/// rumbo; «N» = norte arriba.
enum MapOrientationIcon {
    static func symbol(headingUp: Bool) -> String { headingUp ? "safari.fill" : "n.circle.fill" }
}

/// Botón circular de mapa (recentrar, orientación, vista).
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
