import Foundation
import RevenueCat
import Supabase

protocol ReferralRepository: Sendable {
    func synchronizeSubscription() async throws
    func dashboard() async throws -> ReferralDashboard
    func createCampaign() async throws -> ReferralCampaign
    func claim(code: String) async throws -> ReferralClaimResult
    func beginRedemption(rewardID: UUID) async throws -> ReferralRedemption
    func cancelRedemption(rewardID: UUID) async
}

actor SupabaseReferralRepository: ReferralRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func synchronizeSubscription() async throws {
        do {
            let session = try await client.auth.session
            _ = try await Purchases.shared.logIn(session.user.id.uuidString)
            try await client.functions.invoke("sync-referral-subscription")
        } catch {
            throw mapReferralError(error)
        }
    }

    func dashboard() async throws -> ReferralDashboard {
        do {
            return try await client.rpc("referral_dashboard").execute().value
        } catch {
            throw mapReferralError(error)
        }
    }

    func createCampaign() async throws -> ReferralCampaign {
        do {
            try await synchronizeSubscription()
            let rows: [ReferralCampaign] = try await client
                .rpc("create_referral_campaign")
                .execute()
                .value
            guard let campaign = rows.first else { throw BackendError.invalidResponse }
            return campaign
        } catch {
            throw mapReferralError(error)
        }
    }

    func claim(code: String) async throws -> ReferralClaimResult {
        struct Parameters: Encodable, Sendable { let inputCode: String
            enum CodingKeys: String, CodingKey { case inputCode = "input_code" }
        }

        do {
            try await synchronizeSubscription()
            let rows: [ReferralClaimResult] = try await client
                .rpc("claim_referral_code", params: Parameters(inputCode: code))
                .execute()
                .value
            guard let claim = rows.first else { throw BackendError.invalidResponse }
            return claim
        } catch {
            throw mapReferralError(error)
        }
    }

    func beginRedemption(rewardID: UUID) async throws -> ReferralRedemption {
        struct Parameters: Encodable, Sendable { let rewardID: UUID
            enum CodingKeys: String, CodingKey { case rewardID = "reward_id" }
        }

        do {
            try await synchronizeSubscription()
            let rows: [ReferralRedemption] = try await client
                .rpc("begin_referral_redemption", params: Parameters(rewardID: rewardID))
                .execute()
                .value
            guard let redemption = rows.first else { throw BackendError.invalidResponse }
            return redemption
        } catch {
            throw mapReferralError(error)
        }
    }

    func cancelRedemption(rewardID: UUID) async {
        struct Parameters: Encodable, Sendable { let rewardID: UUID
            enum CodingKeys: String, CodingKey { case rewardID = "reward_id" }
        }
        _ = try? await client.rpc(
            "cancel_referral_redemption",
            params: Parameters(rewardID: rewardID)
        ).execute()
    }

    private func mapReferralError(_ error: Error) -> BackendError {
        if let postgrestError = error as? PostgrestError {
            let message = postgrestError.message.lowercased()
            let referralReasons = [
                "active_subscription_required",
                "invalid_or_expired_code",
                "self_referral",
                "already_claimed",
                "reward_not_redeemable"
            ]
            if referralReasons.contains(where: message.contains) {
                return .server(message: postgrestError.message)
            }
        }
        return SupabaseBackendErrorMapper.map(error)
    }
}
