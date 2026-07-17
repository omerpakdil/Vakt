import Foundation

struct ReferralCampaign: Codable, Equatable, Sendable {
    let id: UUID
    let code: String
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, code
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

enum ReferralRewardStatus: String, Codable, Equatable, Sendable {
    case pending
    case earned
    case redeeming
    case redeemed
    case rejected
    case expired
}

struct ReferralReward: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let inviteeID: UUID
    let status: ReferralRewardStatus
    let eligibleAt: Date
    let expiresAt: Date
    let promotionalOfferID: String?
    let redeemedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case inviteeID = "invitee_id"
        case eligibleAt = "eligible_at"
        case expiresAt = "expires_at"
        case promotionalOfferID = "promotional_offer_id"
        case redeemedAt = "redeemed_at"
        case createdAt = "created_at"
    }
}

struct ReferralDashboard: Codable, Equatable, Sendable {
    let campaign: ReferralCampaign?
    let yearCount: Int
    let claimsWaiting: Int
    let rewards: [ReferralReward]

    static let empty = ReferralDashboard(campaign: nil, yearCount: 0, claimsWaiting: 0, rewards: [])

    enum CodingKeys: String, CodingKey {
        case campaign, rewards
        case yearCount = "year_count"
        case claimsWaiting = "claims_waiting"
    }

    var readyRewards: [ReferralReward] { rewards.filter { $0.status == .earned } }
    var pendingCount: Int { rewards.filter { $0.status == .pending }.count + claimsWaiting }
}

struct ReferralClaimResult: Codable, Equatable, Sendable {
    let claimID: UUID
    let inviterID: UUID
    let inviterName: String
    let inviterUsername: String
    let qualifiesForReward: Bool
    let friendshipID: UUID

    enum CodingKeys: String, CodingKey {
        case claimID = "claim_id"
        case inviterID = "inviter_id"
        case inviterName = "inviter_name"
        case inviterUsername = "inviter_username"
        case qualifiesForReward = "qualifies_for_reward"
        case friendshipID = "friendship_id"
    }
}

struct ReferralRedemption: Codable, Equatable, Sendable {
    let id: UUID
    let productID: String
    let promotionalOfferID: String

    enum CodingKeys: String, CodingKey {
        case id
        case productID = "product_id"
        case promotionalOfferID = "promotional_offer_id"
    }
}
