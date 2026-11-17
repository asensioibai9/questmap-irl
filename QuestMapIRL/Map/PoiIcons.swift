import UIKit
import MapLibre

/// Iconos de puntos de interés para el mapa: símbolo claro con contorno oscuro (o al revés en
/// estilos claros). Se dibujan en la app a partir de símbolos del sistema y se registran en el
/// estilo con los nombres `poi-*` que usa el JSON.
enum PoiIcons {
    static let symbols: [String: String] = [
        "poi-fuel": "fuelpump.fill",
        "poi-parking": "parkingsign",
        "poi-health": "cross.case.fill",
        "poi-police": "shield.fill",
        "poi-food": "fork.knife",
        "poi-cafe": "cup.and.saucer.fill",
        "poi-bar": "wineglass.fill",
        "poi-grocery": "basket.fill",
        "poi-shop": "bag.fill",
        "poi-culture": "building.columns.fill",
        "poi-bank": "eurosign",
        "poi-lodging": "bed.double.fill",
        "poi-transit": "bus.fill",
        "poi-bike": "bicycle",
        "poi-bus-stop": "bus",
    ]

    static func image(symbol: String, fill: UIColor, outline: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .heavy)
        guard let base = UIImage(systemName: symbol, withConfiguration: configuration) else { return nil }
        let glyphFill = base.withTintColor(fill, renderingMode: .alwaysOriginal)
        let glyphOutline = base.withTintColor(outline, renderingMode: .alwaysOriginal)
        let pad: CGFloat = 4
        let size = CGSize(width: base.size.width + pad * 2, height: base.size.height + pad * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let origin = CGPoint(x: pad, y: pad)
            // Contorno: el mismo glifo desplazado en 12 direcciones.
            for step in 0..<12 {
                let angle = CGFloat(step) / 12 * 2 * .pi
                glyphOutline.draw(at: CGPoint(x: origin.x + cos(angle) * 2, y: origin.y + sin(angle) * 2))
            }
            glyphFill.draw(at: origin)
        }
    }

    static func register(in style: MLNStyle, fillHex: UInt32, outlineHex: UInt32) {
        let fill = UIColor(hex: fillHex), outline = UIColor(hex: outlineHex)
        for (name, symbol) in symbols {
            if let icon = image(symbol: symbol, fill: fill, outline: outline) {
                style.setImage(icon, forName: name)
            }
        }
        // Semáforo: icono neutro común a todos los estilos (tres luces grises, sin estado en vivo).
        if let signal = GameIcons.image(asset: "signal") { style.setImage(signal, forName: "poi-traffic-signal") }
    }
}
