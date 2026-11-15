import SwiftUI
import StoreKit

/// Paywall de QuestMap Premium. Cumple con App Store: precio visible,
/// restaurar compras y enlaces legales.
struct PaywallView: View {
    @Environment(\.mapTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: StoreService

    private let perks: [(String, String)] = [
        ("paintpalette.fill", "Los 6 temas de mapa"),
        ("waveform", "Voces premium"),
        ("cloud.fog.fill", "Niebla de guerra avanzada"),
        ("chart.bar.fill", "Estadísticas e historial ampliados"),
        ("car.fill", "CarPlay (cuando esté disponible)")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("QuestMap Premium")
                        .font(.system(.largeTitle, design: theme.titleDesign).weight(.heavy))
                        .foregroundStyle(theme.accent)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(perks, id: \.1) { icon, text in
                            Label(text, systemImage: icon)
                                .font(.body.weight(.medium))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(theme.panel, in: .rect(cornerRadius: 20))

                    if store.isLoading {
                        ProgressView()
                    } else if store.products.isEmpty {
                        Text("No hay productos disponibles ahora mismo.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                Task {
                                    await store.purchase(product)
                                    if store.isPremium { dismiss() }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName).font(.headline)
                                        if let period = product.subscription?.subscriptionPeriod {
                                            Text(periodText(period)).font(.caption)
                                        }
                                    }
                                    Spacer()
                                    Text(product.displayPrice).font(.title3.weight(.bold))
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.accent)
                        }
                    }

                    if let error = store.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    Button("Restaurar compras") { Task { await store.restorePurchases() } }
                        .font(.subheadline)

                    VStack(spacing: 4) {
                        Text("La suscripción se renueva automáticamente salvo que se cancele al menos 24 h antes del final del periodo. Se gestiona desde los ajustes de tu ID de Apple.")
                        HStack {
                            Link("Política de privacidad", destination: URL(string: "https://example.com/privacidad")!)
                            Text("·")
                            Link("Términos de uso", destination: URL(string: "https://example.com/terminos")!)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Ahora no") { dismiss() } }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .month: return period.value == 1 ? "al mes" : "cada \(period.value) meses"
        case .year: return "al año"
        case .week: return "a la semana"
        case .day: return "al día"
        @unknown default: return ""
        }
    }
}
