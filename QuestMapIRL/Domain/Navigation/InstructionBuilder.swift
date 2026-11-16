import Foundation

/// Construye la instrucción en español a partir de datos reales de maniobra
/// (tipo y modificador de OSRM). No se inventa nada: si falta información, la frase es genérica.
enum InstructionBuilder {
    struct Result: Equatable {
        let text: String
        let symbol: String
    }

    static func build(type: String, modifier: String?, name: String?, exit: Int?, exits: String?) -> Result {
        let street = (name ?? "").trimmingCharacters(in: .whitespaces)
        let onto = street.isEmpty ? "" : " en \(street)"
        let along = street.isEmpty ? "" : " por \(street)"
        let m = modifier ?? ""

        switch type {
        case "depart":
            return Result(text: street.isEmpty ? "Empieza la ruta" : "Empieza por \(street)", symbol: "arrow.up")

        case "arrive":
            var text = "Has llegado a tu destino"
            if m == "left" { text += ", a la izquierda" } else if m == "right" { text += ", a la derecha" }
            return Result(text: text, symbol: "flag.checkered")

        case "turn":
            return turn(modifier: m, onto: onto, along: along)

        case "end of road":
            if let side = direction(m) {
                return Result(text: "Al final de la calle, gira \(side)\(onto)", symbol: turnSymbol(m))
            }
            return Result(text: "Al final de la calle, continúa\(along)", symbol: "arrow.up")

        case "continue":
            switch m {
            case "", "straight": return Result(text: "Continúa recto\(along)", symbol: "arrow.up")
            case "uturn": return Result(text: "Haz un cambio de sentido\(onto)", symbol: "arrow.uturn.left")
            default:
                let side = direction(m) ?? ""
                return Result(text: "Sigue \(side)\(onto)", symbol: turnSymbol(m))
            }

        case "new name":
            return Result(text: street.isEmpty ? "Continúa recto" : "Continúa por \(street)", symbol: "arrow.up")

        case "merge":
            var text = "Incorpórate"
            if m.contains("left") { text += " por la izquierda" } else if m.contains("right") { text += " por la derecha" }
            if !street.isEmpty { text += " a \(street)" }
            return Result(text: text, symbol: "arrow.merge")

        case "on ramp", "ramp":
            var text = "Toma la incorporación"
            if let side = sideOnly(m) { text += " \(side)" }
            if !street.isEmpty { text += " a \(street)" }
            return Result(text: text, symbol: m.contains("left") ? "arrow.up.left" : "arrow.up.right")

        case "off ramp":
            var text = "Toma la salida"
            if let exits, !exits.isEmpty { text += " \(exits)" }
            if let side = sideOnly(m) { text += " \(side)" }
            if !street.isEmpty { text += " hacia \(street)" }
            return Result(text: text, symbol: m.contains("left") ? "arrow.up.left" : "arrow.up.right")

        case "fork":
            let text: String
            if m.contains("left") { text = "Mantente a la izquierda en la bifurcación" }
            else if m.contains("right") { text = "Mantente a la derecha en la bifurcación" }
            else { text = "Sigue recto en la bifurcación" }
            let suffix = street.isEmpty ? "" : " hacia \(street)"
            return Result(text: text + suffix, symbol: m.contains("left") ? "arrow.up.left" : (m.contains("right") ? "arrow.up.right" : "arrow.up"))

        case "roundabout", "rotary":
            if let exit {
                let suffix = street.isEmpty ? "" : " hacia \(street)"
                return Result(text: "En la rotonda, toma la \(ordinal(exit)) salida\(suffix)",
                              symbol: "arrow.triangle.turn.up.right.circle")
            }
            return Result(text: "Entra en la rotonda", symbol: "arrow.triangle.turn.up.right.circle")

        case "roundabout turn":
            let side = direction(m) ?? "recto"
            return Result(text: "En la rotonda, gira \(side)\(onto)", symbol: "arrow.triangle.turn.up.right.circle")

        case "exit roundabout", "exit rotary":
            return Result(text: "Sal de la rotonda\(onto)", symbol: "arrow.triangle.turn.up.right.circle")

        case "notification":
            return Result(text: "Continúa recto\(along)", symbol: "arrow.up")

        default:
            return Result(text: "Continúa\(along)", symbol: "arrow.up")
        }
    }

    // MARK: - Piezas

    private static func turn(modifier m: String, onto: String, along: String) -> Result {
        switch m {
        case "straight": return Result(text: "Continúa recto\(along)", symbol: "arrow.up")
        case "uturn": return Result(text: "Haz un cambio de sentido\(onto)", symbol: "arrow.uturn.left")
        default:
            guard let side = direction(m) else { return Result(text: "Continúa\(along)", symbol: "arrow.up") }
            return Result(text: "Gira \(side)\(onto)", symbol: turnSymbol(m))
        }
    }

    private static func direction(_ m: String) -> String? {
        switch m {
        case "right": return "a la derecha"
        case "left": return "a la izquierda"
        case "slight right": return "ligeramente a la derecha"
        case "slight left": return "ligeramente a la izquierda"
        case "sharp right": return "de forma cerrada a la derecha"
        case "sharp left": return "de forma cerrada a la izquierda"
        default: return nil
        }
    }

    private static func sideOnly(_ m: String) -> String? {
        if m.contains("left") { return "a la izquierda" }
        if m.contains("right") { return "a la derecha" }
        return nil
    }

    private static func turnSymbol(_ m: String) -> String {
        switch m {
        case "right": return "arrow.turn.up.right"
        case "left": return "arrow.turn.up.left"
        case "slight right": return "arrow.up.right"
        case "slight left": return "arrow.up.left"
        case "sharp right": return "arrow.turn.down.right"
        case "sharp left": return "arrow.turn.down.left"
        case "uturn": return "arrow.uturn.left"
        default: return "arrow.up"
        }
    }

    static func ordinal(_ n: Int) -> String {
        let words = [1: "primera", 2: "segunda", 3: "tercera", 4: "cuarta", 5: "quinta",
                     6: "sexta", 7: "séptima", 8: "octava", 9: "novena", 10: "décima"]
        return words[n] ?? "\(n)ª"
    }
}
