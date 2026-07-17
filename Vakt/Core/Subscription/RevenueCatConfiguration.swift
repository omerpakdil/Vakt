import Foundation
import RevenueCat

enum RevenueCatConfiguration {
    static let apiKey = "appl_JGCrKLkgrwrIqVbwhAzIeykeXXH"
    static let entitlementID = "premium"
    static let offeringID = "default"
    static let monthlyProductID = "vakt_premium_monthly"
    static let yearlyProductID = "vakt_premium_yearly"
    static let monthlyReferralOfferID = "vakt_referral_monthly_1m"
    static let yearlyReferralOfferID = "vakt_referral_yearly_1m"

    static func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: apiKey)
    }
}
