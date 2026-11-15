import StoreKit
import Observation

/// Compras y suscripciones con StoreKit 2.
/// Para pruebas locales, usar un archivo .storekit en el esquema de Xcode
/// con los mismos identificadores de producto.
@MainActor
@Observable
final class StoreService {
    static let productIDs = ["questmap.premium.monthly", "questmap.premium.yearly"]

    private(set) var products: [Product] = []
    private(set) var isPremium = false
    private(set) var isLoading = false
    var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            errorMessage = "No se pudieron cargar las suscripciones. Inténtalo más tarde."
        }
    }

    func purchase(_ product: Product) async {
        errorMessage = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "La compra no se ha completado."
        }
    }

    /// Restaurar compras: obligatorio en App Store.
    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "No se pudieron restaurar las compras."
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var premium = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                premium = true
            }
        }
        isPremium = premium
    }
}
