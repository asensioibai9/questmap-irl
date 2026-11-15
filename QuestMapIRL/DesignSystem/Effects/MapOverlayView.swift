import SwiftUI

/// Capa decorativa del tema encima del mapa real.
/// Solo aporta ambiente; nunca tapa el HUD ni altera datos. Se dibuja con Canvas
/// (barato en GPU) y se desactiva automáticamente si el usuario reduce transparencias.
struct MapOverlayView: View {
    let theme: MapTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency || theme.overlay == .none {
                Color.clear
            } else {
                effect
            }
        }
    }

    @ViewBuilder
    private var effect: some View {
        switch theme.overlay {
        case .none:
            Color.clear
        case .vignette:
            vignette(strength: theme.overlayOpacity)
        case .neonGrid:
            ZStack {
                vignette(strength: 0.5)
                Canvas { context, size in
                    drawPerspectiveGrid(context: &context, size: size, color: theme.routeGlow)
                }
                .opacity(theme.overlayOpacity)
                .blendMode(.plusLighter)
            }
        case .parchment:
            ZStack {
                theme.background.opacity(theme.overlayOpacity).blendMode(.multiply)
                vignette(strength: 0.35, color: theme.accent)
            }
        case .voxelGrid:
            Canvas { context, size in
                drawSquareGrid(context: &context, size: size, step: 28, color: theme.routeBorder)
            }
            .opacity(theme.overlayOpacity)
        case .scanlines:
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black))
                    y += 3
                }
            }
            .opacity(theme.overlayOpacity)
        }
    }

    private func vignette(strength: Double, color: Color? = nil) -> some View {
        RadialGradient(
            colors: [.clear, (color ?? theme.background).opacity(strength)],
            center: .center,
            startRadius: 160,
            endRadius: 760
        )
    }

    private func drawPerspectiveGrid(context: inout GraphicsContext, size: CGSize, color: Color) {
        let horizon = size.height * 0.55
        var path = Path()
        // Líneas horizontales cada vez más separadas hacia abajo.
        var y = horizon
        var gap: CGFloat = 6
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += gap
            gap *= 1.22
        }
        // Líneas que convergen en el punto de fuga.
        let vanishing = CGPoint(x: size.width / 2, y: horizon)
        let count = 14
        for i in 0...count {
            let x = size.width * CGFloat(i) / CGFloat(count) * 1.6 - size.width * 0.3
            path.move(to: vanishing)
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(path, with: .color(color), lineWidth: 1)
    }

    private func drawSquareGrid(context: inout GraphicsContext, size: CGSize, step: CGFloat, color: Color) {
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
        var y: CGFloat = 0
        while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
        context.stroke(path, with: .color(color), lineWidth: 1)
    }
}
