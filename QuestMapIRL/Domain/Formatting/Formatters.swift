import Foundation

enum Formatters {
    static func distance(_ meters: Double, metric: Bool) -> String {
        if metric {
            if meters >= 10_000 { return String(format: "%.0f km", meters / 1000) }
            if meters >= 1000 { return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",") }
            return "\(Int(max(0, meters).rounded(toNearest: 10))) m"
        }
        let feet = meters * 3.28084
        if feet >= 1000 { return String(format: "%.1f mi", feet / 5280) }
        return "\(Int(max(0, feet).rounded(toNearest: 50))) ft"
    }

    static func speed(_ kmh: Double, metric: Bool) -> String {
        metric ? "\(Int(kmh)) km/h" : "\(Int(kmh * 0.621371)) mph"
    }
}

private extension Double {
    func rounded(toNearest step: Double) -> Double { (self / step).rounded() * step }
}
