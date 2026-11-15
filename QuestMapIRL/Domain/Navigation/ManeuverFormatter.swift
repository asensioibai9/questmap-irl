import Foundation

/// Convierte la instrucción de MapKit en texto de voz natural en español
/// y elige el icono de maniobra. MapKit ya devuelve el texto en el idioma del dispositivo.
enum ManeuverFormatter {
    static func spoken(instruction: String, distance: Double, metric: Bool) -> String {
        let text = instruction.isEmpty ? "continúa por la ruta" : lowercasedFirst(instruction)
        guard distance >= 40 else { return capitalized(text) }
        if metric {
            let rounded = Int((distance / 50).rounded() * 50)
            if rounded >= 1000 {
                let km = Double(rounded) / 1000
                let kmText = km == km.rounded() ? "\(Int(km)) kilómetro\(km == 1 ? "" : "s")" : String(format: "%.1f kilómetros", km).replacingOccurrences(of: ".", with: ",")
                return "En \(kmText), \(text)"
            }
            return "En \(rounded) metros, \(text)"
        } else {
            let feet = distance * 3.28084
            if feet >= 1000 { return String(format: "En %.1f millas, %@", feet / 5280, text) }
            return "En \(Int((feet / 100).rounded() * 100)) pies, \(text)"
        }
    }

    /// Icono SF Symbols para la maniobra, deducido del texto (MapKit no expone el tipo).
    static func symbol(for instruction: String) -> String {
        let s = instruction.lowercased()
        if s.contains("llegado") || s.contains("destino") { return "flag.checkered" }
        if s.contains("rotonda") || s.contains("glorieta") { return "arrow.triangle.turn.up.right.circle" }
        if s.contains("cambio de sentido") || s.contains("da la vuelta") { return "arrow.uturn.left" }
        if s.contains("incorpór") || s.contains("incorpora") { return "arrow.merge" }
        if s.contains("salida") || s.contains("sal ") { return "arrow.turn.right.up" }
        if s.contains("ligeramente a la derecha") || s.contains("mantente a la derecha") { return "arrow.up.right" }
        if s.contains("ligeramente a la izquierda") || s.contains("mantente a la izquierda") { return "arrow.up.left" }
        if s.contains("derecha") { return "arrow.turn.up.right" }
        if s.contains("izquierda") { return "arrow.turn.up.left" }
        return "arrow.up"
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
