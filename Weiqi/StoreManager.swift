import Foundation
import StoreKit

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    let productID = "com.cwave.weiqi.unlock_levels"
    
    @Published var product: Product?
    @Published var isPurchased: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var errorMessage: String?
    
    private var transactionListener: Task<Void, Error>?
    
    init() {
        // Start listening for transaction updates in the background
        transactionListener = Task {
            for await result in Transaction.updates {
                await handle(transactionResult: result)
            }
        }
        
        // Asynchronously check current purchase status and load products
        Task {
            await updatePurchaseStatus()
            await loadProducts()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    func loadProducts() async {
        do {
            let products = try await Product.products(for: [productID])
            self.product = products.first
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    func purchase() async {
        guard let product = product else { return }
        isPurchasing = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }
    
    func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await updatePurchaseStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }
    
    private func handle(transactionResult result: VerificationResult<Transaction>) async {
        switch result {
        case .unverified(_, let error):
            print("Transaction verification failed: \(error)")
        case .verified(let transaction):
            await transaction.finish()
            await updatePurchaseStatus()
        }
    }
    
    func updatePurchaseStatus() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == productID {
                    purchased = true
                    break
                }
            }
        }
        self.isPurchased = purchased
    }
}
