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
