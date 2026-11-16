import SwiftUI

/// Geometría del símbolo de la app. Es la MISMA que usa `tools/make_brand_assets.py` para el
/// icono y la imagen de lanzamiento: chincheta con flecha de navegación recortada, sobre un
/// anillo de ruta. Todas las formas se dibujan en un cuadrado unitario.
enum BrandGeometry {
    static let cx = 0.5, cy = 0.42, radius = 0.215, tipY = 0.80
    static let ringCenter = CGPoint(x: 0.5, y: 0.815)
    static let ringRX = 0.215, ringRY = 0.072, ringWidth = 0.034
    static let arrow: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.285), CGPoint(x: 0.592, y: 0.525),
        CGPoint(x: 0.5, y: 0.462), CGPoint(x: 0.408, y: 0.525),
    ]
    static let magenta = Color(hex: 0xF23FC4)
    static let goldTop = Color(hex: 0xFFDF7A)
    static let goldBottom = Color(hex: 0xF0A22E)
    static let background = Color(hex: 0x0A0A1A)
}

struct BrandPin: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        let r = BrandGeometry.radius
        let d = BrandGeometry.tipY - BrandGeometry.cy
        let theta = acos(r / d)
        let rx = r * sin(theta), ry = r * cos(theta)
        var path = Path()
        path.move(to: point(BrandGeometry.cx - rx, BrandGeometry.cy + ry))
        path.addLine(to: point(BrandGeometry.cx, BrandGeometry.tipY))
        path.addLine(to: point(BrandGeometry.cx + rx, BrandGeometry.cy + ry))
        // Arco por la parte superior, muestreado (evita ambigüedades de sentido en coordenadas con y hacia abajo).
        let a0 = atan2(ry, rx)
        let a1 = Double.pi - a0
        let sweep = (a1 - 2 * Double.pi) - a0
        let samples = 96
        for i in 1..<samples {
            let angle = a0 + sweep * Double(i) / Double(samples)
            path.addLine(to: point(BrandGeometry.cx + r * cos(angle), BrandGeometry.cy + r * sin(angle)))
        }
        path.closeSubpath()
        return path
    }
}

struct BrandArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = BrandGeometry.arrow.map {
            CGPoint(x: rect.minX + rect.width * $0.x, y: rect.minY + rect.height * $0.y)
        }
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

struct BrandRing: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandGeometry.ringCenter
        let box = CGRect(
            x: rect.minX + rect.width * (c.x - BrandGeometry.ringRX),
            y: rect.minY + rect.height * (c.y - BrandGeometry.ringRY),
            width: rect.width * BrandGeometry.ringRX * 2,
            height: rect.height * BrandGeometry.ringRY * 2)
        return Path(ellipseIn: box)
    }
}

/// Símbolo completo, con el anillo dibujable por tramos (`ringProgress` de 0 a 1).
struct BrandMark: View {
    var size: CGFloat = 120
    var ringProgress: CGFloat = 1

    var body: some View {
        ZStack {
            BrandRing()
                .trim(from: 0, to: ringProgress)
                .stroke(BrandGeometry.magenta,
                        style: StrokeStyle(lineWidth: size * BrandGeometry.ringWidth, lineCap: .round))
                .opacity(ringProgress > 0.001 ? 1 : 0)   // un trazo de longitud 0 con punta redonda dibujaría un punto
            BrandPin()
                .fill(LinearGradient(colors: [BrandGeometry.goldTop, BrandGeometry.goldBottom],
                                     startPoint: UnitPoint(x: 0.5, y: BrandGeometry.cy - BrandGeometry.radius),
                                     endPoint: UnitPoint(x: 0.5, y: BrandGeometry.tipY)))
            BrandArrow().fill(BrandGeometry.background)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
