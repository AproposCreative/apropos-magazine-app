import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isSubscribed = false
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard FeatureFlags.subscriptionsEnabled else {
            isSubscribed = false
            return
        }

        updatesTask?.cancel()
        updatesTask = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    func refresh() async {
        guard FeatureFlags.subscriptionsEnabled else {
            isSubscribed = false
            products = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: SubscriptionProducts.all)
                .sorted { lhs, rhs in
                    lhs.price < rhs.price
                }
            await updateEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        lastError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        lastError = nil
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await updateEntitlements()
        }
    }

    private func updateEntitlements() async {
        var active = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if SubscriptionProducts.all.contains(transaction.productID) {
                active = true
            }
        }

        isSubscribed = active
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionStoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum SubscriptionStoreError: Error {
    case failedVerification
}
