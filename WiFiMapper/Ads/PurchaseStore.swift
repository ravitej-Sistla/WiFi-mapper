import Observation
import StoreKit

/// The one-time "Remove ads" purchase.
@MainActor
@Observable
final class PurchaseStore {
    private(set) var removeAdsProduct: Product?
    private(set) var adsRemoved = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        // Purchases can complete outside the app (Ask to Buy, another device, refunds).
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    func load() async {
        removeAdsProduct = try? await Product.products(for: [AdConfig.removeAdsProductID]).first
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == AdConfig.removeAdsProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        adsRemoved = owned
    }

    func purchaseRemoveAds() async {
        guard let product = removeAdsProduct, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                adsRemoved = true
            case .success(.unverified):
                errorMessage = "The App Store couldn't verify this purchase."
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }
}
