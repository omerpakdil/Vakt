import XCTest
@testable import Vakt

final class UsernamePolicyTests: XCTestCase {
    func testSuggestionsTransliterateAndPreserveReadableNameForms() {
        let candidates = UsernamePolicy.candidates(
            displayName: "Ömer Salih Pakdil",
            fallbackSeed: "vakt_111bfb5a"
        )

        XCTAssertEqual(candidates.first, "omer_salih_pakdil")
        XCTAssertTrue(candidates.contains("omersalihpakdil"))
        XCTAssertTrue(candidates.contains("omer_pakdil"))
    }

    func testEverySuggestionMatchesDatabaseFormat() {
        let candidates = UsernamePolicy.candidates(
            displayName: "A Very Long Display Name With Several Parts",
            fallbackSeed: "vakt_12345678"
        )

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy(UsernamePolicy.isValid))
        XCTAssertTrue(candidates.allSatisfy { $0.count <= UsernamePolicy.maximumLength })
        XCTAssertEqual(Set(candidates).count, candidates.count)
    }

    func testValidationRejectsUnsupportedUsernameCharacters() {
        XCTAssertTrue(UsernamePolicy.isValid("omer_salih27"))
        XCTAssertFalse(UsernamePolicy.isValid("Ömer Salih"))
        XCTAssertFalse(UsernamePolicy.isValid("ab"))
        XCTAssertFalse(UsernamePolicy.isValid("user.name"))
    }
}

final class FriendshipRequestClassifierTests: XCTestCase {
    private let currentUserID = VaktUserID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
    private let otherUserID = VaktUserID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    )

    func testPendingRequestFromCurrentUserIsAlreadySent() throws {
        let friendship = makeFriendship(requesterID: currentUserID, status: .pending)

        XCTAssertEqual(
            try FriendshipRequestClassifier.classify(friendship, currentUserID: currentUserID),
            .alreadyPending(friendship)
        )
    }

    func testPendingRequestFromOtherUserIsIncoming() throws {
        let friendship = makeFriendship(requesterID: otherUserID, status: .pending)

        XCTAssertEqual(
            try FriendshipRequestClassifier.classify(friendship, currentUserID: currentUserID),
            .incomingRequest(friendship)
        )
    }

    func testAcceptedRelationshipIsAlreadyFriends() throws {
        let friendship = makeFriendship(requesterID: currentUserID, status: .accepted)

        XCTAssertEqual(
            try FriendshipRequestClassifier.classify(friendship, currentUserID: currentUserID),
            .alreadyFriends(friendship)
        )
    }

    func testBlockedRelationshipCannotBeRequested() {
        let friendship = makeFriendship(requesterID: otherUserID, status: .blocked)

        XCTAssertThrowsError(
            try FriendshipRequestClassifier.classify(friendship, currentUserID: currentUserID)
        ) { error in
            XCTAssertEqual(error as? BackendError, .forbidden)
        }
    }

    private func makeFriendship(
        requesterID: VaktUserID,
        status: FriendshipStatus
    ) -> Friendship {
        Friendship(
            id: UUID(),
            requesterID: requesterID,
            receiverID: requesterID == currentUserID ? otherUserID : currentUserID,
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
