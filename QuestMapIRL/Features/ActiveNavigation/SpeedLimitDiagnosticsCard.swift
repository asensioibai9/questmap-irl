import SwiftUI

/// Modo diagnóstico del límite (SOLO desarrollo, oculto por defecto). Muestra en pantalla de dónde sale la cifra y por qué se
/// enseña u oculta. No muestra coordenadas ni recorridos y no registra nada. Se activa tocando 7 veces la vista previa en
/// Ajustes › Señal de límite de velocidad. Para mirarlo con el coche parado o un acompañante.
struct SpeedLimitDiagnosticsCard: View {
    static let storageKey = "questmap.speedLimitDiagnostics"
    let diagnostic: SpeedLimitDiagnostic?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DIAGNÓSTICO LÍMITE").font(.system(size: 9, weight: .heavy))
            if let d = diagnostic {
                line("fuente", d.source)
                line("vía", [d.wayID.map { "#\($0)" }, d.roadName].compactMap { $0 }.joined(separator: " · ").ifEmpty("—"))
                line("dato", d.raw ?? "—")
                line("muestra", d.interpreted)
                line("antig.", d.dataAgeSeconds.map { "\($0) s" } ?? "—")
                line("precisión", d.accuracy.map { "±\($0) m" } ?? "—")
                line("motivo", d.reason)
                if let change = d.change { line("cambio", change) }
            } else {
                Text("sin datos todavía").font(.system(size: 9, design: .monospaced))
            }
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(maxWidth: 230, alignment: .leading)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func line(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(.system(size: 9, design: .monospaced))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
