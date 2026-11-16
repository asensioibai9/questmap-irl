import Foundation

/// Convierte la instrucción de un paso en la frase que se dice en voz alta, con la distancia
/// redondeada a un valor natural ("En 200 metros, gira a la derecha").
enum ManeuverFormatter {
    static func spoken(instruction: String, distance: Double, metric: Bool) -> String {
        let text = instruction.isEmpty ? "continúa por la ruta" : lowercasedFirst(instruction)
        guard distance >= 40 else { return capitalized(text) }
        if metric {
            let rounded = Int((distance / 50).rounded() * 50)
            if rounded >= 1000 {
                let km = Double(rounded) / 1000
                let kmText = km == km.rounded()
                    ? "\(Int(km)) kilómetro\(km == 1 ? "" : "s")"
                    : String(format: "%.1f kilómetros", km).replacingOccurrences(of: ".", with: ",")
                return "En \(kmText), \(text)"
            }
            return "En \(rounded) metros, \(text)"
        } else {
            let feet = distance * 3.28084
            if feet >= 1000 { return String(format: "En %.1f millas, %@", feet / 5280, text) }
            return "En \(Int((feet / 100).rounded() * 100)) pies, \(text)"
        }
    }

    private static func lowercasedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }

    private static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
