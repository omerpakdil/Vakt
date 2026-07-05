import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    enum Entitlement: Equatable {
        case checking
        case active
        case inactive
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case pending
        case failed(String)
    }

    struct Plan: Identifiable, Equatable {
        enum Cadence: Int, Comparable {
            case monthly
            case yearly

            static func < (lhs: Cadence, rhs: Cadence) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        let id: String
        let cadence: Cadence
        let displayPrice: String
        let billingDescription: String

        var title: String {
            switch cadence {
            case .monthly: "Monthly"
            case .yearly: "Yearly"
            }
        }
    }

    static let monthlyProductID = "com.vakt.app.subscription.monthly"
    static let yearlyProductID = "com.vakt.app.subscription.yearly"

    @Published private(set) var entitlement: Entitlement = .checking
    @Published private(set) var plans: [Plan] = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var isLoadingProducts = false
    /// True when there are no real StoreKit products to sell (e.g. no StoreKit
    /// Configuration attached to the run scheme) and the store has fallen back
    /// to local plans so the purchase flow can still be exercised in DEBUG.
    /// Always false in release builds.
    @Published private(set) var isUsingDeveloperFallback = false

    private let productIDs: Set<String>
    private let isPreviewMode: Bool
    private var productsByID: [String: Product] = [:]
    private var transactionListener: Task<Void, Never>?
    private var hasPrepared = false

    init(productIDs: Set<String>? = nil) {
        self.productIDs = productIDs ?? [Self.monthlyProductID, Self.yearlyProductID]

        #if DEBUG
        isPreviewMode = ProcessInfo.processInfo.arguments.contains("--vakt-paywall-preview")
        #else
        isPreviewMode = false
        #endif

        if isPreviewMode {
            plans = Self.developerFallbackPlans
            isUsingDeveloperFallback = true
            entitlement = .inactive
            hasPrepared = true
            return
        }

        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    func prepare() async {
        guard !isPreviewMode, !hasPrepared else { return }
        hasPrepared = true

        await refreshEntitlement()
        await loadProducts()
    }

    func retryLoadingProducts() async {
        purchaseState = .idle
        await loadProducts()
    }

    func purchase(planID: String) async {
        guard !isUsingDeveloperFallback else {
            await simulateDeveloperPurchase()
            return
        }

        guard let product = productsByID[planID] else {
            purchaseState = .failed("The App Store could not load this plan. Please try again.")
            return
        }

        purchaseState = .purchasing

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlement()
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .failed("The purchase could not be completed.")
            }
        } catch {
            purchaseState = .failed("The purchase could not be completed. Please try again.")
        }
    }

    func restorePurchases() async {
        guard !isUsingDeveloperFallback else {
            await simulateDeveloperPurchase()
            return
        }

        purchaseState = .purchasing

        do {
            try await AppStore.sync()
            await refreshEntitlement()
            purchaseState = entitlement == .active
                ? .idle
                : .failed("No active subscription was found for this Apple ID.")
        } catch {
            purchaseState = .failed("Purchases could not be restored. Please try again.")
        }
    }

    func dismissMessage() {
        guard purchaseState != .purchasing else { return }
        purchaseState = .idle
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: productIDs)
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            plans = products.compactMap(makePlan).sorted { $0.cadence < $1.cadence }
        } catch {
            productsByID = [:]
            plans = []
        }

        guard !plans.isEmpty else {
            #if DEBUG
            isUsingDeveloperFallback = true
            plans = Self.developerFallbackPlans
            purchaseState = .idle
            print("⚠️ SubscriptionStore: the App Store returned no products, so local developer plans are being used. Attach a StoreKit Configuration file to the scheme (Product > Scheme > Edit Scheme > Run > Options) to test the real purchase flow.")
            #else
            purchaseState = .failed("Subscriptions are not available from the App Store right now.")
            #endif
            return
        }

        isUsingDeveloperFallback = false
        purchaseState = .idle
    }

    /// Skips real StoreKit entirely and simulates a successful purchase.
    /// Only ever reachable when `isUsingDeveloperFallback` is true, which is
    /// itself only ever set to true in DEBUG builds — so this can't run in
    /// production regardless of build configuration.
    private func simulateDeveloperPurchase() async {
        purchaseState = .purchasing
        try? await Task.sleep(for: .seconds(0.6))
        entitlement = .active
        purchaseState = .idle
    }

    private func refreshEntitlement() async {
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else {
                continue
            }

            if let expirationDate = transaction.expirationDate,
               expirationDate <= Date() {
                continue
            }

            hasActiveSubscription = true
            break
        }

        entitlement = hasActiveSubscription ? .active : .inactive
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }

                if case .verified(let transaction) = result {
                    await transaction.finish()
                }

                await self.refreshEntitlement()
            }
        }
    }

    private func makePlan(product: Product) -> Plan? {
        guard let subscription = product.subscription else { return nil }

        let cadence: Plan.Cadence
        switch subscription.subscriptionPeriod.unit {
        case .month where subscription.subscriptionPeriod.value == 1:
            cadence = .monthly
        case .year where subscription.subscriptionPeriod.value == 1:
            cadence = .yearly
        default:
            return nil
        }

        return Plan(
            id: product.id,
            cadence: cadence,
            displayPrice: product.displayPrice,
            billingDescription: billingDescription(for: cadence)
        )
    }

    private func billingDescription(for cadence: Plan.Cadence) -> String {
        switch cadence {
        case .monthly: "billed each month"
        case .yearly: "billed once a year"
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private static let developerFallbackPlans: [Plan] = [
        Plan(
            id: SubscriptionStore.monthlyProductID,
            cadence: .monthly,
            displayPrice: "$19.99",
            billingDescription: "billed each month"
        ),
        Plan(
            id: SubscriptionStore.yearlyProductID,
            cadence: .yearly,
            displayPrice: "$99.99",
            billingDescription: "billed once a year"
        )
    ]
}

private enum StoreError: Error {
    case failedVerification
}
