import SwiftUI

/// Indicador de ubicación. Muestra el ESTADO real (obteniendo, disponible, aproximada, sin confirmar…)
/// y, cuando hay lectura reciente, una valoración basada únicamente en la precisión horizontal de esa
/// lectura. No es un porcentaje de señal GPS: iOS no lo proporciona.
struct GPSIndicator: View {
    let theme: MapTheme
    let status: LocationStatus
    let accuracy: Double?

    private var quality: GPSQuality {
        guard let accuracy, accuracy >= 0 else { return .none }
        return LocationService.quality(for: accuracy)
    }

    private var color: Color {
        switch status {
        case .available:
            switch quality {
            case .none, .poor: return .orange
            case .fair: return .yellow
            case .good, .excellent: return .green
            }
        case .acquiring, .requestingPermission: return theme.textSecondary
        case .reducedAccuracy, .lowAccuracy, .lastKnown, .temporaryError: return .orange
        case .denied, .restricted, .servicesDisabled: return .red
        }
    }

    private var label: String {
        if case .available = status, let accuracy, accuracy >= 0 { return "Precisión ±\(Int(accuracy)) m" }
        return status.title
    }

    var body: some View {
        HStack(spacing: 6) {
            if case .available = status {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(1...4, id: \.self) { bar in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(bar <= quality.bars ? color : theme.textSecondary.opacity(0.3))
                            .frame(width: 4, height: CGFloat(4 + bar * 3))
                    }
                }
            } else if case .acquiring = status {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(color)
            }
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(status.needsAttention ? color : theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(theme.panel, in: .capsule)
        .overlay(Capsule().stroke(theme.panelBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var symbol: String {
        switch status {
        case .reducedAccuracy: return "location.circle"
        case .lowAccuracy: return "scope"
        case .lastKnown: return "clock.arrow.circlepath"
        case .temporaryError: return "exclamationmark.triangle.fill"
        case .denied, .restricted: return "location.slash.fill"
        case .servicesDisabled: return "location.slash"
        case .requestingPermission: return "location"
        default: return "location"
        }
    }
}
