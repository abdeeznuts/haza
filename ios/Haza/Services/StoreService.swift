import Foundation
import StoreKit
import Observation

/// StoreKit 2 subscriptions. Pro is decided server-side (`my_pro()`), so after any transaction the app
/// sends the signed JWS to `iap/verify-transaction`; App Store Server Notifications keep it current after that.
@Observable @MainActor
final class StoreService {
    static let shared = StoreService()

    private(set) var products: [Product] = []
    private(set) var busy = false
    private(set) var message: String?
    private var updates: Task<Void, Never>?

    func start() async {
        if updates == nil {
            updates = Task.detached { [weak self] in
                for await result in Transaction.updates {
                    await self?.handle(result)
                }
            }
        }
        do {
            products = try await Product.products(for: HazaBrand.Products.all).sorted { $0.price < $1.price }
        } catch { message = "Store unavailable: \(error.localizedDescription)" }
        await syncCurrentEntitlements()
    }

    var monthly: Product? { products.first { $0.id == HazaBrand.Products.monthly } }
    var yearly: Product? { products.first { $0.id == HazaBrand.Products.yearly } }

    func purchase(_ product: Product) async {
        guard let uid = SupabaseService.shared.userID else { message = "Sign in first."; return }
        busy = true; defer { busy = false }
        do {
            // appAccountToken ties the Apple transaction to the Supabase user for the server webhook.
            let result = try await product.purchase(options: [.appAccountToken(uid)])
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled: break
            case .pending: message = "Waiting for approval (Ask to Buy)."
            @unknown default: break
            }
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        busy = true; defer { busy = false }
        try? await AppStore.sync()
        await syncCurrentEntitlements()
    }

    private func syncCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements { await handle(result) }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = result else { return }
        guard HazaBrand.Products.all.contains(tx.productID) else { return }
        _ = try? await SupabaseService.shared.verifyTransaction(jws: result.jwsRepresentation)
        await tx.finish()
    }
}
