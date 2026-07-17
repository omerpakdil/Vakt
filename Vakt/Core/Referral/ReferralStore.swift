import Foundation

@MainActor
final class ReferralStore: ObservableObject {
    enum Activity: Equatable {
        case idle
        case loading
        case claiming
        case redeeming(UUID)
    }

    @Published private(set) var dashboard: ReferralDashboard = .empty
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var claimedInvitation: ReferralClaimResult?
    @Published private(set) var message: String?
    @Published private(set) var dashboardLoadError: String?
    @Published private(set) var hasLoadedDashboard = false

    private let repository: (any ReferralRepository)?

    init(repository: (any ReferralRepository)?) {
        self.repository = repository
    }

    var isConfigured: Bool { repository != nil }

    func refresh() async {
        guard let repository else { return }
        message = nil
        dashboardLoadError = nil
        activity = .loading
        defer { activity = .idle }
        do {
            dashboard = try await repository.dashboard()
            hasLoadedDashboard = true
        } catch {
            dashboardLoadError = friendlyMessage(for: error)
        }
    }

    func createCampaign(allowDeveloperPreview: Bool = false) async {
        #if DEBUG
        if allowDeveloperPreview {
            dashboard = ReferralDashboard(
                campaign: ReferralCampaign(
                    id: UUID(uuidString: "00000000-0000-4000-8000-000000000204")!,
                    code: "VAKT2026",
                    expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60),
                    createdAt: Date()
                ),
                yearCount: dashboard.yearCount,
                claimsWaiting: dashboard.claimsWaiting,
                rewards: dashboard.rewards
            )
            message = nil
            return
        }
        #endif

        guard let repository else { return }
        activity = .loading
        defer { activity = .idle }
        do {
            let campaign = try await repository.createCampaign()
            dashboard = ReferralDashboard(
                campaign: campaign,
                yearCount: dashboard.yearCount,
                claimsWaiting: dashboard.claimsWaiting,
                rewards: dashboard.rewards
            )
            message = nil
        } catch {
            message = friendlyMessage(for: error)
        }
    }

    func claim(code: String) async -> Bool {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.count == 8 else {
            message = L10n.string("referral.message.code_length")
            return false
        }

        #if DEBUG
        if normalized == "VAKT2026" {
            claimedInvitation = ReferralClaimResult(
                claimID: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
                inviterID: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!,
                inviterName: "Yusuf",
                inviterUsername: "yusuf",
                qualifiesForReward: true,
                friendshipID: UUID(uuidString: "00000000-0000-4000-8000-000000000203")!
            )
            message = nil
            return true
        }
        #endif

        guard let repository else { return false }
        activity = .claiming
        defer { activity = .idle }
        do {
            claimedInvitation = try await repository.claim(code: normalized)
            message = nil
            return true
        } catch {
            message = friendlyMessage(for: error)
            return false
        }
    }

    func redeem(_ reward: ReferralReward, using subscriptionStore: SubscriptionStore) async {
        guard let repository else { return }
        activity = .redeeming(reward.id)
        defer { activity = .idle }
        do {
            let redemption = try await repository.beginRedemption(rewardID: reward.id)
            try await subscriptionStore.redeemReferralReward(
                productID: redemption.productID,
                offerID: redemption.promotionalOfferID
            )
            await refresh()
            message = L10n.string("referral.message.reward_added")
        } catch {
            await repository.cancelRedemption(rewardID: reward.id)
            message = friendlyMessage(for: error)
        }
    }

    func clearMessage() { message = nil }

    private func friendlyMessage(for error: Error) -> String {
        let value = error.localizedDescription.lowercased()
        if value.contains("active_subscription_required") {
            return L10n.string("referral.message.active_subscription_required")
        }
        if value.contains("invalid_or_expired_code") {
            return L10n.string("referral.message.invalid_or_expired_code")
        }
        if value.contains("self_referral") {
            return L10n.string("referral.message.self_referral")
        }
        if value.contains("already_claimed") {
            return L10n.string("referral.message.already_claimed")
        }
        if value.contains("reward_not_redeemable") {
            return L10n.string("referral.message.reward_not_redeemable")
        }
        return L10n.string("referral.message.generic_error")
    }
}
