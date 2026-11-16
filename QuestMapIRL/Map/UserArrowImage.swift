import UIKit
import MapLibre

/// Flecha del usuario dibujada por la app (asset propio, sin imágenes de terceros).
/// Se registra en el estilo con el nombre que usa la capa `user-arrow` del JSON.
enum UserArrowImage {
    static let name = "user-arrow"

    static func make(color: UIColor, border: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44))
        return renderer.image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 22, y: 4))
            path.addLine(to: CGPoint(x: 36, y: 38))
            path.addLine(to: CGPoint(x: 22, y: 30))
            path.addLine(to: CGPoint(x: 8, y: 38))
            path.close()
            path.lineWidth = 3
            path.lineJoinStyle = .round
            border.setStroke()
            path.stroke()
            color.setFill()
            path.fill()
        }
    }

    static func register(in style: MLNStyle, arrowHex: UInt32) {
        let image = make(color: UIColor(hex: arrowHex), border: UIColor(hex: 0xFFFFFF))
        style.setImage(image, forName: name)
    }
}
