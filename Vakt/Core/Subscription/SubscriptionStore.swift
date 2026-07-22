import Foundation
import RevenueCat

@MainActor
final class SubscriptionStore: ObservableObject {
    struct Summary: Equatable {
        enum Period: Equatable { case normal, trial, introductory, prepaid, unknown }

        let productID: String
        let cadence: Plan.Cadence
        let expirationDate: Date?
        let willRenew: Bool
        let period: Period
        let billingIssueDetectedAt: Date?
        let managementURL: URL?
        let isSandbox: Bool
    }
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
        let displayPrice: String?
        let billingDescription: String

        var title: String {
            switch cadence {
            case .monthly: L10n.string("paywall.plan.monthly")
            case .yearly: L10n.string("paywall.plan.yearly")
            }
        }
    }

    static let monthlyProductID = RevenueCatConfiguration.monthlyProductID
    static let yearlyProductID = RevenueCatConfiguration.yearlyProductID

    @Published private(set) var entitlement: Entitlement = .checking
    @Published private(set) var plans: [Plan] = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var completedPurchaseID: UUID?
    @Published private(set) var isLoadingProducts = false
    /// True when RevenueCat cannot return live Offering packages in DEBUG and
    /// the store falls back to local plans so the paywall can still be previewed.
    /// This path is never enabled in release builds.
    @Published private(set) var isUsingDeveloperFallback = false
    @Published private(set) var summary: Summary?

    private let entitlementID: String
    private let offeringID: String
    private let isPreviewMode: Bool
    private var packagesByPlanID: [String: RevenueCat.Package] = [:]
    private var hasPrepared = false

    init(
        entitlementID: String = RevenueCatConfiguration.entitlementID,
        offeringID: String = RevenueCatConfiguration.offeringID
    ) {
        self.entitlementID = entitlementID
        self.offeringID = offeringID

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
        }
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

    func refreshSubscription() async {
        guard !isPreviewMode else { return }
        await refreshEntitlement()
        if plans.isEmpty { await loadProducts() }
    }

    func purchase(planID: String) async {
        #if DEBUG
        if Self.shouldBypassPurchasesBeforeStoreSheet {
            await simulateDeveloperPurchase()
            return
        }
        #endif

        guard !isUsingDeveloperFallback else {
            await simulateDeveloperPurchase()
            return
        }

        guard let package = packagesByPlanID[planID] else {
            purchaseState = .failed(L10n.string("paywall.error.plan_unavailable"))
            return
        }

        purchaseState = .purchasing

        do {
            let customerInfo = try await purchase(package: package)
            if customerInfo.entitlements[entitlementID]?.isActive == true {
                completedPurchaseID = UUID()
            }
            apply(customerInfo: customerInfo)
            if entitlement == .active {
                purchaseState = .idle
            } else {
                purchaseState = .failed(L10n.string("paywall.error.activation_failed"))
            }
        } catch RevenueCatPurchaseError.cancelled {
            purchaseState = .idle
        } catch {
            #if DEBUG
            if Self.allowsDeveloperPurchaseBypass {
                await simulateDeveloperPurchase()
                return
            }
            #endif

            purchaseState = .failed(L10n.string("paywall.error.purchase_failed"))
        }
    }

    func restorePurchases() async {
        guard !isUsingDeveloperFallback else {
            purchaseState = entitlement == .active
                ? .idle
                : .failed(L10n.string("paywall.error.no_active_subscription"))
            return
        }

        purchaseState = .purchasing

        do {
            let customerInfo = try await restoreCustomerInfo()
            apply(customerInfo: customerInfo)
            purchaseState = entitlement == .active
                ? .idle
                : .failed(L10n.string("paywall.error.no_active_subscription"))
        } catch {
            purchaseState = .failed(L10n.string("paywall.error.restore_failed"))
        }
    }

    func dismissMessage() {
        guard purchaseState != .purchasing else { return }
        purchaseState = .idle
    }

    func consumeCompletedPurchase() {
        completedPurchaseID = nil
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let offerings = try await fetchOfferings()
            let offering = offerings.offering(identifier: offeringID) ?? offerings.current
            let packages = offering?.availablePackages ?? []

            packagesByPlanID = Dictionary(uniqueKeysWithValues: packages.compactMap { package in
                guard let plan = makePlan(package: package) else { return nil }
                return (plan.id, package)
            })
            plans = packages.compactMap(makePlan).sorted { $0.cadence < $1.cadence }
        } catch {
            packagesByPlanID = [:]
            plans = []
        }

        guard !plans.isEmpty else {
            #if DEBUG
            isUsingDeveloperFallback = true
            plans = Self.developerFallbackPlans
            purchaseState = .idle
            print("⚠️ SubscriptionStore: RevenueCat returned no Offering packages, so local developer plans are being used. Check the RevenueCat Offering, App Store products, bundle ID, and sandbox configuration.")
            #else
            purchaseState = .failed(L10n.string("paywall.error.subscriptions_unavailable"))
            #endif
            return
        }

        isUsingDeveloperFallback = false
        purchaseState = .idle
    }

    private func simulateDeveloperPurchase() async {
        purchaseState = .purchasing
        try? await Task.sleep(for: .seconds(0.6))
        completedPurchaseID = UUID()
        entitlement = .active
        purchaseState = .idle
    }

    private func refreshEntitlement() async {
        do {
            let customerInfo = try await fetchCustomerInfo()
            apply(customerInfo: customerInfo)
        } catch {
            entitlement = .inactive
        }
    }

    private func apply(customerInfo: CustomerInfo) {
        guard let info = customerInfo.entitlements[entitlementID] else {
            entitlement = .inactive
            summary = nil
            return
        }
        entitlement = info.isActive ? .active : .inactive
        let cadence: Plan.Cadence = info.productIdentifier == Self.yearlyProductID ? .yearly : .monthly
        let period: Summary.Period = switch info.periodType {
        case .normal: .normal
        case .trial: .trial
        case .intro: .introductory
        case .prepaid: .prepaid
        @unknown default: .unknown
        }
        summary = Summary(
            productID: info.productIdentifier,
            cadence: cadence,
            expirationDate: info.expirationDate,
            willRenew: info.willRenew,
            period: period,
            billingIssueDetectedAt: info.billingIssueDetectedAt,
            managementURL: customerInfo.managementURL,
            isSandbox: info.isSandbox
        )
    }

    func redeemReferralReward(productID: String, offerID: String) async throws {
        guard let package = packagesByPlanID[productID] else {
            throw ReferralPurchaseError.productUnavailable
        }
        guard let discount = package.storeProduct.discounts.first(where: {
            $0.offerIdentifier == offerID && $0.type == .promotional
        }) else {
            throw ReferralPurchaseError.offerUnavailable
        }

        let offer = try await Purchases.shared.promotionalOffer(
            forProductDiscount: discount,
            product: package.storeProduct
        )
        let result = try await Purchases.shared.purchase(package: package, promotionalOffer: offer)
        apply(customerInfo: result.customerInfo)
    }

    private func makePlan(package: RevenueCat.Package) -> Plan? {
        let productID = package.storeProduct.productIdentifier

        let cadence: Plan.Cadence
        switch productID {
        case Self.monthlyProductID:
            cadence = .monthly
        case Self.yearlyProductID:
            cadence = .yearly
        default:
            switch package.packageType {
            case .monthly:
                cadence = .monthly
            case .annual:
                cadence = .yearly
            default:
                return nil
            }
        }

        return Plan(
            id: productID,
            cadence: cadence,
            displayPrice: package.storeProduct.localizedPriceString,
            billingDescription: billingDescription(for: cadence)
        )
    }

    private func billingDescription(for cadence: Plan.Cadence) -> String {
        switch cadence {
        case .monthly: L10n.string("paywall.billing.monthly")
        case .yearly: L10n.string("paywall.billing.yearly")
        }
    }

    private func fetchOfferings() async throws -> Offerings {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getOfferings { offerings, error in
                if let offerings {
                    continuation.resume(returning: offerings)
                } else {
                    continuation.resume(throwing: error ?? RevenueCatStoreError.missingOfferings)
                }
            }
        }
    }

    private func fetchCustomerInfo() async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getCustomerInfo { customerInfo, error in
                if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: error ?? RevenueCatStoreError.missingCustomerInfo)
                }
            }
        }
    }

    private func purchase(package: RevenueCat.Package) async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.purchase(package: package) { _, customerInfo, error, userCancelled in
                if userCancelled {
                    continuation.resume(throwing: RevenueCatPurchaseError.cancelled)
                } else if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: error ?? RevenueCatStoreError.missingCustomerInfo)
                }
            }
        }
    }

    private func restoreCustomerInfo() async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.restorePurchases { customerInfo, error in
                if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: error ?? RevenueCatStoreError.missingCustomerInfo)
                }
            }
        }
    }

    private static let developerFallbackPlans: [Plan] = [
        Plan(
            id: SubscriptionStore.monthlyProductID,
            cadence: .monthly,
            displayPrice: nil,
            billingDescription: L10n.string("paywall.billing.monthly")
        ),
        Plan(
            id: SubscriptionStore.yearlyProductID,
            cadence: .yearly,
            displayPrice: nil,
            billingDescription: L10n.string("paywall.billing.yearly")
        )
    ]

    #if DEBUG
    private static var allowsDeveloperPurchaseBypass: Bool {
        ProcessInfo.processInfo.environment["VAKT_DISABLE_PURCHASE_BYPASS"] != "1"
    }

    private static var shouldBypassPurchasesBeforeStoreSheet: Bool {
        #if targetEnvironment(simulator)
        return allowsDeveloperPurchaseBypass
        #else
        return false
        #endif
    }
    #endif
}

private enum RevenueCatStoreError: Error {
    case missingOfferings
    case missingCustomerInfo
}

private enum RevenueCatPurchaseError: Error {
    case cancelled
}

private enum ReferralPurchaseError: LocalizedError {
    case productUnavailable
    case offerUnavailable

    var errorDescription: String? {
        switch self {
        case .productUnavailable: L10n.string("paywall.error.referral_product_unavailable")
        case .offerUnavailable: L10n.string("paywall.error.referral_offer_unavailable")
        }
    }
}
