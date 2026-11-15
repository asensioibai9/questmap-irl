import SwiftUI

/// Chip de calidad de señal GPS: 4 barras + texto. Accesible por VoiceOver.
struct GPSIndicator: View {
    let theme: MapTheme
    let quality: GPSQuality
    let signalLost: Bool

    private var color: Color {
        switch quality {
        case .none, .poor: return .red
        case .fair: return .orange
        case .good, .excellent: return .green
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1...4, id: \.self) { bar in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(bar <= quality.bars ? color : theme.textSecondary.opacity(0.3))
                        .frame(width: 4, height: CGFloat(4 + bar * 3))
                }
            }
            Text(signalLost ? "GPS perdido" : "GPS \(quality.title.lowercased())")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(signalLost ? Color.red : theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(theme.panel, in: .capsule)
        .overlay(Capsule().stroke(theme.panelBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signalLost ? "Señal GPS perdida" : "Señal GPS \(quality.title)")
    }
}
