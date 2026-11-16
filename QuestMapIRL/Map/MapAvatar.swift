import UIKit

/// Avatares de la posición del usuario. Todos son dibujos propios (código, sin imágenes de
/// terceros). Posición y orientación son cosas distintas: el punto no tiene orientación y el
/// resto solo giran cuando hay un rumbo válido.
enum MapAvatar: String, CaseIterable, Identifiable {
    case arrow, dot, car, pixel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: return "Flecha clásica"
        case .dot: return "Punto de ubicación"
        case .car: return "Coche"
        case .pixel: return "Avatar pixelado"
        }
    }

    var detail: String {
        switch self {
        case .arrow: return "Indica hacia dónde avanzas."
        case .dot: return "Solo tu posición, sin orientación."
        case .car: return "Vista cenital, gira con el rumbo."
        case .pixel: return "Flecha de píxeles, gira con el rumbo."
        }
    }

    var isDirectional: Bool { self != .dot }

    /// Imagen que se registra en el estilo con el nombre `user-arrow`.
    func image(fill: UIColor, border: UIColor) -> UIImage {
        let size = CGSize(width: 48, height: 48)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            switch self {
            case .arrow:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 24, y: 5))
                path.addLine(to: CGPoint(x: 39, y: 41))
                path.addLine(to: CGPoint(x: 24, y: 32))
                path.addLine(to: CGPoint(x: 9, y: 41))
                path.close()
                path.lineWidth = 3
                path.lineJoinStyle = .round
                border.setStroke(); path.stroke()
                fill.setFill(); path.fill()

            case .dot:
                let rect = CGRect(x: 10, y: 10, width: 28, height: 28)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: rect).fill()
                fill.setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()

            case .car:
                // Coche en vista cenital, con el morro hacia arriba.
                let body = UIBezierPath(roundedRect: CGRect(x: 14, y: 4, width: 20, height: 40), cornerRadius: 8)
                body.lineWidth = 2.5
                border.setStroke(); body.stroke()
                fill.setFill(); body.fill()
                let windshield = UIBezierPath(roundedRect: CGRect(x: 17.5, y: 12, width: 13, height: 8), cornerRadius: 2)
                UIColor(white: 0.08, alpha: 0.85).setFill(); windshield.fill()
                let rear = UIBezierPath(roundedRect: CGRect(x: 18, y: 31, width: 12, height: 6), cornerRadius: 2)
                UIColor(white: 0.08, alpha: 0.85).setFill(); rear.fill()
                cg.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
                for y in [9.0, 31.0] {
                    cg.fill(CGRect(x: 11.5, y: y, width: 3, height: 8))
                    cg.fill(CGRect(x: 33.5, y: y, width: 3, height: 8))
                }

            case .pixel:
                // Flecha de 8 x 8 "píxeles" de 5 puntos cada uno.
                let rows = [
                    "...XX...",
                    "..XXXX..",
                    "..XXXX..",
                    ".XXXXXX.",
                    ".XXXXXX.",
                    "XXX..XXX",
                    "XX....XX",
                    "X......X",
                ]
                let cell: CGFloat = 5
                let origin = CGPoint(x: 4, y: 4)
                for (row, line) in rows.enumerated() {
                    for (column, character) in line.enumerated() where character == "X" {
                        let rect = CGRect(x: origin.x + CGFloat(column) * cell, y: origin.y + CGFloat(row) * cell,
                                          width: cell, height: cell)
                        border.setFill(); cg.fill(rect.insetBy(dx: -1, dy: -1))
                    }
                }
                for (row, line) in rows.enumerated() {
                    for (column, character) in line.enumerated() where character == "X" {
                        let rect = CGRect(x: origin.x + CGFloat(column) * cell, y: origin.y + CGFloat(row) * cell,
                                          width: cell, height: cell)
                        fill.setFill(); cg.fill(rect)
                    }
                }
            }
        }
    }
}
