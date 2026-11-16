import SwiftUI

/// Cambia el icono real de la aplicación. Los iconos alternativos están en el catálogo de recursos
/// (`AppIconLight`, `AppIconMono`) y se declaran con `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
struct AppIconPickerView: View {
    private struct Option: Identifiable {
        let id: String
        let name: String?          // nil = icono principal
        let title: String
        let preview: String
    }

    private let options = [
        Option(id: "default", name: nil, title: "Noche", preview: "IconPreviewDefault"),
        Option(id: "light", name: "AppIconLight", title: "Día", preview: "IconPreviewLight"),
        Option(id: "mono", name: "AppIconMono", title: "Monocromo", preview: "IconPreviewMono"),
    ]

    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !UIApplication.shared.supportsAlternateIcons {
                    InlineMessage(kind: .warning, text: "Este dispositivo no permite cambiar el icono de la app.")
                }
                ForEach(options) { option in
                    let selected = current == option.name
                    Button { select(option) } label: {
                        HStack(spacing: 16) {
                            Image(option.preview)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            Text(option.title).font(.headline).foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                            }
                        }
                        .padding(14)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Icono \(option.title)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                if let errorMessage { InlineMessage(kind: .error, text: errorMessage) }
            }
            .padding(16)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Icono de la app")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ option: Option) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(option.name)
                current = option.name
                errorMessage = nil
            } catch {
                errorMessage = "No se pudo cambiar el icono: \(error.localizedDescription)"
            }
        }
    }
}
