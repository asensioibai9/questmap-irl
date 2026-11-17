import SwiftData
import SwiftUI

/// Ajustes de navegación › Señal de límite de velocidad. Cada cambio se aplica al momento (mapa, navegación y CarPlay
/// leen el mismo `UserSettings`) y se guarda en el acto. La vista previa usa el MISMO componente que el mapa con un
/// valor de demostración: no toca el límite real de la navegación.
struct SpeedSignSettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var settings: UserSettings
    @State private var previewHasData = true
    @State private var confirmReset = false

    /// Valor de demostración de la vista previa (no es un dato real).
    private static let previewLimitKmh = 50
    private static let previewSpeedKmh = 47.0

    private var appearance: SpeedSignAppearance { settings.speedSignAppearance }

    private func update(_ change: (inout SpeedSignAppearance) -> Void, operation: String) {
        var value = settings.speedSignAppearance
        change(&value)
        guard value != settings.speedSignAppearance else { return }     // misma opción: ni escritura ni guardado
        settings.speedSignAppearance = value
        save(operation)
    }

    private func save(_ operation: String) {
        PersistenceCommit.saveQuietly(context, operation: operation)
    }

    var body: some View {
        Form {
            previewSection

            Section {
                Toggle("Mostrar señal", isOn: Binding(
                    get: { settings.showSpeedLimit },
                    set: { settings.showSpeedLimit = $0; save("speed-limit-setting") }))
                Toggle("También sin ruta", isOn: Binding(
                    get: { settings.speedLimitWithoutRoute },
                    set: { settings.speedLimitWithoutRoute = $0; save("speed-limit-free-drive") }))
                    .disabled(!settings.showSpeedLimit)
            } header: {
                Text("Mostrar")
            } footer: {
                Text("Los límites vienen de OpenStreetMap a través del servidor público de demostración de Valhalla (gratuito, sin garantías). Navegando se envía la geometría de la ruta. «También sin ruta» (desactivado por defecto) envía tus últimos ~400 m recorridos mientras te mueves, nunca puntos a menos de 300 m de Casa o Trabajo. Con «Mostrar señal» desactivado no se hace ninguna consulta. La señalización real siempre prevalece.")
            }

            Section {
                Picker("Diseño", selection: Binding(
                    get: { appearance.style },
                    set: { style in update({ $0.style = style }, operation: "speed-sign-style") })) {
                    ForEach(SpeedSignStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Tamaño", selection: Binding(
                    get: { appearance.size },
                    set: { size in update({ $0.size = size }, operation: "speed-sign-size") })) {
                    ForEach(SpeedSignSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Posición en el iPhone", selection: Binding(
                    get: { appearance.position },
                    set: { position in update({ $0.position = position }, operation: "speed-sign-position") })) {
                    ForEach(SpeedSignPosition.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Diseño")
            } footer: {
                Text("El diseño solo cambia el dibujo: no cambia el límite, la vía ni las unidades. «Automático» usa la señal rectangular en Estados Unidos y sus territorios cuando el proveedor indica el país; en el resto, o si no se sabe el país, la circular europea. Las posiciones son huecos reservados: la señal nunca tapa la maniobra, los botones, la brújula, el buscador ni el reproductor. «Automática»: navegando, abajo a la izquierda; sin ruta, arriba a la izquierda.")
            }

            Section {
                Picker("Sin dato", selection: Binding(
                    get: { appearance.noData },
                    set: { noData in update({ $0.noData = noData }, operation: "speed-sign-nodata") })) {
                    ForEach(SpeedSignNoData.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Mostrar mi velocidad junto a la señal", isOn: Binding(
                    get: { appearance.showsCurrentSpeed },
                    set: { shows in update({ $0.showsCurrentSpeed = shows }, operation: "speed-sign-current") }))
            } header: {
                Text("Cuando no hay dato y velocidad actual")
            } footer: {
                Text("«—» significa que no hay límite conocido para ese tramo o que la ubicación no permite identificar la vía; NO significa «sin límite». Tu velocidad va en un recuadro aparte con el rótulo «tú»; si el GPS no da una velocidad válida aparece «—».")
            }

            Section {
                LabeledContent("Unidades", value: settings.useMetricUnits ? "km/h" : "mph (convertido)")
            } footer: {
                Text("Se usa el ajuste general de unidades (Ajustes de navegación › Rutas). Los límites llegan en km/h; en mph la cifra es una conversión redondeada y debajo de la señal pone «≈ mph».")
            }

            Section {
                Button("Restablecer esta sección", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Vuelve a los valores predeterminados de la señal. No borra Casa, Trabajo, favoritos ni otros ajustes.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("Señal de límite")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Restablecer la señal de límite?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Restablecer", role: .destructive) {
                settings.resetSpeedSignSettings()
                save("speed-sign-reset")
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var previewSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                    let display: SpeedLimitDisplay = previewHasData ? .limit(kmh: Self.previewLimitKmh) : .unavailable
                    if settings.showSpeedLimit, !SpeedLimitSign.isEmpty(display, appearance: appearance) {
                        SpeedLimitSign(display: display, metric: settings.useMetricUnits, appearance: appearance,
                                       countryCode: nil, currentSpeedKmh: Self.previewSpeedKmh)
                    } else {
                        Text(settings.showSpeedLimit ? "Sin dato: la señal se oculta" : "Señal desactivada")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(height: 150)
                .overlay(alignment: .topLeading) {
                    Text("Vista previa")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Vista previa de la señal, valor de demostración")

                Picker("Estado de la vista previa", selection: $previewHasData) {
                    Text("Con límite").tag(true)
                    Text("Sin dato").tag(false)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
        } footer: {
            Text("Vista previa con un valor de DEMOSTRACIÓN (\(Self.previewLimitKmh) km/h, tu velocidad \(Int(Self.previewSpeedKmh)) km/h). No cambia el límite que se muestra navegando. Con «Automático» y sin país conocido se ve la circular.")
        }
    }
}
