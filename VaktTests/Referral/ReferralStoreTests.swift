import XCTest
@testable import Vakt

@MainActor
final class ReferralStoreTests: XCTestCase {
    func testClaimNormalizesCodeBeforeRepositoryCall() async {
        let repository = ReferralRepositorySpy()
        let store = ReferralStore(repository: repository)

        let claimed = await store.claim(code: "ab-cd 2345")
        let claimedCodes = await repository.claimedCodes

        XCTAssertTrue(claimed)
        XCTAssertEqual(claimedCodes, ["ABCD2345"])
    }

    func testClaimRejectsInvalidLengthWithoutRepositoryCall() async {
        let repository = ReferralRepositorySpy()
        let store = ReferralStore(repository: repository)

        let claimed = await store.claim(code: "ABC")
        let claimedCodes = await repository.claimedCodes

        XCTAssertFalse(claimed)
        XCTAssertEqual(store.message, "Davet kodu 8 karakter olmalı.")
        XCTAssertTrue(claimedCodes.isEmpty)
    }

    func testCreateCampaignKeepsExistingDashboardCounters() async {
        let repository = ReferralRepositorySpy()
        let store = ReferralStore(repository: repository)
        await store.refresh()

        await store.createCampaign()

        XCTAssertEqual(store.dashboard.campaign?.code, "VAKT2345")
        XCTAssertEqual(store.dashboard.yearCount, 2)
        XCTAssertEqual(store.dashboard.claimsWaiting, 1)
    }
}

private actor ReferralRepositorySpy: ReferralRepository {
    private(set) var claimedCodes: [String] = []

    func synchronizeSubscription() async throws {}

    func dashboard() async throws -> ReferralDashboard {
        ReferralDashboard(campaign: nil, yearCount: 2, claimsWaiting: 1, rewards: [])
    }

    func createCampaign() async throws -> ReferralCampaign {
        ReferralCampaign(
            id: UUID(),
            code: "VAKT2345",
            expiresAt: Date().addingTimeInterval(2_592_000),
            createdAt: Date()
        )
    }

    func claim(code: String) async throws -> ReferralClaimResult {
        claimedCodes.append(code)
        return ReferralClaimResult(
            claimID: UUID(),
            inviterID: UUID(),
            inviterName: "Ayse",
            inviterUsername: "ayse",
            qualifiesForReward: true,
            friendshipID: UUID()
        )
    }

    func beginRedemption(rewardID: UUID) async throws -> ReferralRedemption {
        ReferralRedemption(
            id: rewardID,
            productID: SubscriptionStore.monthlyProductID,
            promotionalOfferID: RevenueCatConfiguration.monthlyReferralOfferID
        )
    }

    func cancelRedemption(rewardID: UUID) async {}
}
