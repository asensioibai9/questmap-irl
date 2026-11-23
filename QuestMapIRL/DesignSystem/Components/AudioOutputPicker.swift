import AVFoundation
import AVKit
import Observation
import SwiftUI

/// Salida de audio actual (la que decide el sistema: altavoz, auriculares, Bluetooth del coche, cable…). Solo informa: la
/// app no fuerza ninguna salida. Se actualiza cuando iOS avisa de un cambio de ruta.
@MainActor
@Observable
final class AudioOutputMonitor {
    private(set) var outputName: String = AudioOutputMonitor.currentOutputName()
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            Task { @MainActor in self?.outputName = AudioOutputMonitor.currentOutputName() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    nonisolated static func currentOutputName() -> String {
        let names = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName)
        return names.isEmpty ? "Sin salida" : names.joined(separator: ", ")
    }
}

/// Botón del sistema para elegir la salida de audio (AirPlay, Bluetooth…): `AVRoutePickerView`, la API oficial.
struct AudioRoutePickerButton: UIViewRepresentable {
    var tint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = tint
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = tint
    }
}

/// Fila de ajustes: «Salida de audio» con la salida actual y el selector del sistema.
struct AudioOutputRow: View {
    let accent: Color
    @State private var monitor = AudioOutputMonitor()

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Salida de audio")
                Text(monitor.outputName)
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            AudioRoutePickerButton(tint: UIColor(accent))
                .frame(width: 44, height: 44)
                .accessibilityLabel("Elegir salida de audio")
        }
        .accessibilityElement(children: .contain)
    }
}
