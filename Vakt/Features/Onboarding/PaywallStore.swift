import Foundation
import StoreKit

@MainActor
final class PaywallStore: ObservableObject {
    enum Plan: String, CaseIterable, Identifiable {
        case monthly
        case yearly

        var id: String { rawValue }

        var productID: String {
            switch self {
            case .monthly:
                return "com.vakt.plus.monthly"
            case .yearly:
                return "com.vakt.plus.yearly"
            }
        }

        var fallbackDisplayPrice: String {
            switch self {
            case .monthly:
                return "$19.99"
            case .yearly:
                return "$99.99"
            }
        }
    }

    @Published var selectedPlan: Plan = .yearly
    @Published private(set) var productsByPlan: [Plan: Product] = [:]
    @Published private(set) var isPurchasing = false
    @Published private(set) var hasVaktPlus: Bool
    @Published private(set) var statusMessage: String?

    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false
    private let defaults: UserDefaults

    private static let entitlementKey = "vakt.plus.active.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasVaktPlus = defaults.bool(forKey: Self.entitlementKey)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionResult: update)
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func displayPrice(for plan: Plan) -> String {
        productsByPlan[plan]?.displayPrice ?? plan.fallbackDisplayPrice
    }

    func purchaseSelectedPlan() async -> Bool {
        guard !isPurchasing else { return false }

        statusMessage = nil

        if productsByPlan[selectedPlan] == nil {
            await loadProducts()
        }

        guard let product = productsByPlan[selectedPlan] else {
            statusMessage = "Purchases aren\u2019t available right now. You can join Vakt+ later from My Vakt."
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                return await handle(transactionResult: verification)
            case .pending:
                statusMessage = "Your purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            statusMessage = "The purchase could not be completed. Please try again."
            return false
        }
    }

    func restorePurchases() async -> Bool {
        statusMessage = nil

        do {
            try await AppStore.sync()
        } catch {
            statusMessage = "Could not reach the App Store. Please try again."
            return false
        }

        await refreshEntitlement()

        if !hasVaktPlus {
            statusMessage = "No previous Vakt+ purchase was found."
        }

        return hasVaktPlus
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: Plan.allCases.map(\.productID))

            for product in products {
                if let plan = Plan.allCases.first(where: { $0.productID == product.id }) {
                    productsByPlan[plan] = product
                }
            }
        } catch {
            // Keep fallback prices; purchasing surfaces a gentle message instead.
        }
    }

    private func refreshEntitlement() async {
        var isActive = false

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }

            if Plan.allCases.contains(where: { $0.productID == transaction.productID }) {
                isActive = true
            }
        }

        setEntitlement(isActive)
    }

    @discardableResult
    private func handle(transactionResult: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let transaction) = transactionResult else {
            statusMessage = "The purchase could not be verified."
            return false
        }

        if Plan.allCases.contains(where: { $0.productID == transaction.productID }) {
            setEntitlement(transaction.revocationDate == nil)
        }

        await transaction.finish()
        return hasVaktPlus
    }

    private func setEntitlement(_ isActive: Bool) {
        hasVaktPlus = isActive
        defaults.set(isActive, forKey: Self.entitlementKey)
    }
}
