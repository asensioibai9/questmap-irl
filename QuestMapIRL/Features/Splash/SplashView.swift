import SwiftUI

/// Animación de inicio dentro de la app (≈ 1,9 s). Continúa la pantalla de lanzamiento del
/// sistema: el símbolo arranca en el mismo sitio y tamaño que la imagen de lanzamiento.
/// Se muestra una vez por arranque, se puede saltar con un toque, respeta "Reducir movimiento"
/// y nunca espera al GPS ni a la red (la app ya está montada debajo).
struct SplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var streets: CGFloat = 0
    @State private var lift: CGFloat = 0
    @State private var nameOpacity = 0.0
    @State private var creditOpacity = 0.0
    @State private var finished = false

    private let markSize: CGFloat = 120

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()

            StreetLines(progress: streets)
                .stroke(.white.opacity(0.07), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .ignoresSafeArea()

            BrandMark(size: markSize, ringProgress: ring)
                .offset(y: -lift)

            VStack(spacing: 6) {
                Text(AppConfig.appName)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(nameOpacity)
                    .offset(y: reduceMotion ? 0 : (1 - nameOpacity) * 8)
                Text(AppConfig.creditLine)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(creditOpacity)
            }
            .offset(y: markSize / 2 + 44)
            .accessibilityElement(children: .combine)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            // Sin movimiento: solo aparece el texto con un fundido suave.
            ring = 1
            withAnimation(.easeOut(duration: 0.4)) { nameOpacity = 1 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.4)) { creditOpacity = 1 }
            try? await Task.sleep(for: .milliseconds(1000))
            finish()
            return
        }
        withAnimation(.easeInOut(duration: 0.9)) { streets = 1 }
        withAnimation(.easeInOut(duration: 0.65)) { ring = 1 }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { lift = 30 }
        withAnimation(.easeOut(duration: 0.45).delay(0.1)) { nameOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeOut(duration: 0.45)) { creditOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(950))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// Líneas sutiles que recuerdan calles y una ruta; se trazan con `progress`.
struct StreetLines: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var full = Path()
        full.move(to: CGPoint(x: -20, y: h * 0.22)); full.addLine(to: CGPoint(x: w * 0.55, y: h * 0.30))
        full.addLine(to: CGPoint(x: w + 20, y: h * 0.18))
        full.move(to: CGPoint(x: -20, y: h * 0.78)); full.addLine(to: CGPoint(x: w * 0.4, y: h * 0.70))
        full.addLine(to: CGPoint(x: w + 20, y: h * 0.84))
        full.move(to: CGPoint(x: w * 0.18, y: -20)); full.addLine(to: CGPoint(x: w * 0.30, y: h * 0.5))
        full.addLine(to: CGPoint(x: w * 0.12, y: h + 20))
        full.move(to: CGPoint(x: w * 0.82, y: -20)); full.addLine(to: CGPoint(x: w * 0.70, y: h * 0.52))
        full.addLine(to: CGPoint(x: w * 0.88, y: h + 20))
        return full.trimmedPath(from: 0, to: progress)
    }
}
