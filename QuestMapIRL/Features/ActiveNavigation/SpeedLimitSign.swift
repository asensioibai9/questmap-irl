import SwiftUI

/// Señal circular de límite de velocidad: fondo blanco, borde rojo y número negro grande y centrado, sin más texto.
/// Es un elemento distinto de la velocidad ACTUAL del dispositivo (que se muestra como texto «km/h» en el panel).
struct SpeedLimitSign: View {
    let display: SpeedLimitDisplay
    let metric: Bool
    var size: CGFloat = 60

    var body: some View {
        Group {
            switch display {
            case .hidden:
                EmptyView()
            case .limit(let kmh):
                sign(number: SpeedLimitFormatter.signNumber(kmh: kmh, metric: metric))
            case .unavailable:
                unavailable
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpeedLimitFormatter.spokenLabel(display, metric: metric))
    }

    private func sign(number: Int) -> some View {
        let digits = String(number).count
        return ZStack {
            Circle().fill(Color.white)
            Circle().strokeBorder(Color(red: 0.84, green: 0.07, blue: 0.10), lineWidth: size * 0.14)
            Text(String(number))
                .font(.system(size: size * (digits >= 3 ? 0.34 : 0.45), weight: .heavy, design: .default).monospacedDigit())
                .foregroundStyle(Color.black)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    /// Sin dato: círculo gris discreto con un guion. No sugiere ninguna cifra.
    private var unavailable: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.55))
            Circle().strokeBorder(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: size * 0.07, dash: [3, 3]))
            Text("–").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(width: size * 0.78, height: size * 0.78)
    }
}
