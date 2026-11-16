import SwiftUI

/// Ficha del lugar seleccionado en el mapa. Primero se muestra el lugar; la ruta solo se calcula al
/// confirmar «Cómo llegar». Si ya hay una ruta, se presenta como NUEVO destino por confirmar y la ruta
/// actual no se toca hasta entonces.
struct PlacePreviewPanel: View {
    let place: Place
    let distance: String?
    let replacesRoute: Bool
    let onDirections: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if replacesRoute {
                Label("Nuevo destino (la ruta actual se mantiene hasta que confirmes)", systemImage: "arrow.triangle.swap")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name).font(.title2.weight(.bold)).foregroundStyle(AppColor.textPrimary).lineLimit(2)
                    HStack(spacing: 8) {
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.subheadline).foregroundStyle(AppColor.textSecondary)
                        }
                        if let distance {
                            Text("· \(distance)").font(.subheadline.monospacedDigit()).foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                CircleIconButton(systemImage: "xmark", label: "Cerrar selección", size: 36, action: onClose)
            }
            Button(action: onDirections) {
                Label(replacesRoute ? "Cómo llegar aquí (sustituye el destino)" : "Cómo llegar", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0xA855E8))
            .foregroundStyle(.white)
            .accessibilityHint("Calcula la ruta hasta este lugar")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
