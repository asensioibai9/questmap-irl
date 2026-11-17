import SwiftUI

/// Señal de límite de velocidad de la VÍA (no es la cobertura GPS). Es el ÚNICO componente que la dibuja: lo usan el mapa
/// del iPhone, la vista previa de Ajustes y CarPlay, así que no hay diferencias entre lo que se configura y lo que se ve.
///
/// - Con límite: la señal del diseño elegido y, debajo, la unidad («km/h» o «≈ mph», porque en mph es una conversión).
/// - Sin dato / ubicación insuficiente: un indicador neutro gris con «—» (no se parece a ninguna señal oficial, tampoco a
///   la de fin de limitación) o nada, según el ajuste.
/// - Velocidad actual (opcional): un elemento APARTE, con su etiqueta, para no confundirla con el límite.
struct SpeedLimitSign: View {
    let display: SpeedLimitDisplay
    let metric: Bool
    var appearance: SpeedSignAppearance = .defaults
    var countryCode: String?
    var currentSpeedKmh: Double?
    /// Lado fijo (CarPlay). Nil = el del ajuste de tamaño, adaptado al tamaño de texto del sistema.
    var fixedSide: CGFloat?

    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    private var side: CGFloat {
        if let fixedSide { return fixedSide }
        return appearance.size.side * min(max(textScale, 1), 1.3)
    }

    private var style: SpeedSignStyle { appearance.style.resolved(countryCode: countryCode) }

    /// true si no hay nada que dibujar (para que el contenedor no reserve hueco).
    static func isEmpty(_ display: SpeedLimitDisplay, appearance: SpeedSignAppearance) -> Bool {
        switch display {
        case .hidden: return true
        case .limit: return false
        case .unavailable, .insufficientLocation: return appearance.noData == .hide
        }
    }

    var body: some View {
        if !Self.isEmpty(display, appearance: appearance) {
            HStack(alignment: .center, spacing: 8) {
                VStack(spacing: 3) {
                    signBody
                    if case .limit = display { unitCaption }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SpeedLimitFormatter.spokenLabel(display, metric: metric))
                if appearance.showsCurrentSpeed { currentSpeed }
            }
            .animation(.easeInOut(duration: 0.2), value: display)
            .transition(.opacity)
        }
    }

    // MARK: Señal

    @ViewBuilder
    private var signBody: some View {
        switch display {
        case .limit(let kmh):
            let number = SpeedLimitFormatter.signNumber(kmh: kmh, metric: metric)
            switch style {
            case .unitedStates: unitedStates(number)
            case .minimal: minimal(number)
            case .european, .automatic: european(number)
            }
        case .unavailable, .insufficientLocation:
            neutral
        case .hidden:
            EmptyView()
        }
    }

    private func european(_ number: Int) -> some View {
        let digits = String(number).count
        return ZStack {
            Circle().fill(Color.white)
            Circle().strokeBorder(Color(red: 0.84, green: 0.07, blue: 0.10), lineWidth: side * 0.13)
            Text(String(number))
                .font(.system(size: side * (digits >= 3 ? 0.34 : 0.44), weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.black)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(side * 0.18)
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private func unitedStates(_ number: Int) -> some View {
        let width = side * 0.82
        let height = side * 1.04
        return VStack(spacing: 0) {
            Text("SPEED")
                .font(.system(size: height * 0.15, weight: .bold))
            Text("LIMIT")
                .font(.system(size: height * 0.15, weight: .bold))
            Text(String(number))
                .font(.system(size: height * 0.42, weight: .heavy).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, width * 0.08)
        .padding(.vertical, height * 0.06)
        .frame(width: width, height: height)
        .background(Color.white, in: RoundedRectangle(cornerRadius: side * 0.1, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: side * 0.1, style: .continuous)
            .inset(by: side * 0.04)
            .strokeBorder(Color.black, lineWidth: side * 0.035))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    /// Compacta y claramente identificada: rótulo «LÍMITE» encima del número.
    private func minimal(_ number: Int) -> some View {
        VStack(spacing: 0) {
            Text("LÍMITE")
                .font(.system(size: side * 0.16, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
            Text(String(number))
                .font(.system(size: side * 0.44, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: side * 0.92, height: side * 0.86)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: side * 0.2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
            .strokeBorder(Color(red: 0.84, green: 0.07, blue: 0.10), lineWidth: side * 0.05))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    /// Sin dato: gris, con borde discontinuo y un guion. No sugiere ninguna cifra ni «sin límite».
    private var neutral: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous).fill(Color.black.opacity(0.6))
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: max(1.5, side * 0.05), dash: [3, 3]))
            Text("—").font(.system(size: side * 0.36, weight: .bold)).foregroundStyle(Color.white.opacity(0.8))
        }
        .frame(width: side * 0.78, height: side * 0.78)
    }

    private var unitCaption: some View {
        Text(SpeedLimitFormatter.unitCaption(metric: metric))
            .font(.system(size: max(10, side * 0.18), weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.black.opacity(0.6), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Velocidad actual (elemento aparte)

    private var currentSpeed: some View {
        let value = currentSpeedKmh.map { metric ? $0 : $0 * 0.621371 }
        return VStack(spacing: 0) {
            Text(value.map { String(Int($0.rounded())) } ?? "—")
                .font(.system(size: side * 0.4, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(metric ? "km/h · tú" : "mph · tú")
                .font(.system(size: max(9, side * 0.15), weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, side * 0.14)
        .frame(minWidth: side * 0.9, minHeight: side * 0.78)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: side * 0.2, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "Tu velocidad actual: \(Int($0.rounded())) \(metric ? "kilómetros" : "millas") por hora" }
                            ?? "Tu velocidad actual no está disponible")
    }
}
