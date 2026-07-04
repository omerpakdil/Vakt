import XCTest
@testable import Vakt

final class InMemoryPresenceRepositoryTests: XCTestCase {
    func testRepeatedUpsertForSameClientDoesNotDuplicatePresence() async throws {
        let repository = InMemoryPresenceRepository()
        let sessionID = PrayerSessionID(rawValue: UUID())
        let clientID = UUID()
        let stream = await repository.snapshots(for: sessionID)
        var iterator = stream.makeAsyncIterator()

        let initial = try await iterator.next()
        XCTAssertEqual(initial?.participantCount, 0)

        let firstLease = try await repository.upsertPresence(
            mutation(sessionID: sessionID, clientID: clientID, status: .makingWudu)
        )
        let joined = try await iterator.next()
        XCTAssertEqual(joined?.participantCount, 1)
        XCTAssertEqual(joined?.counts.makingWudu, 1)

        let retriedLease = try await repository.upsertPresence(
            mutation(sessionID: sessionID, clientID: clientID, status: .ready)
        )
        let updated = try await iterator.next()

        XCTAssertEqual(firstLease.id, retriedLease.id)
        XCTAssertEqual(updated?.participantCount, 1)
        XCTAssertEqual(updated?.counts.makingWudu, 0)
        XCTAssertEqual(updated?.counts.ready, 1)
    }

    func testRefreshMovesStatusWithoutChangingTotal() async throws {
        let repository = InMemoryPresenceRepository()
        let sessionID = PrayerSessionID(rawValue: UUID())
        let stream = await repository.snapshots(for: sessionID)
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()

        let lease = try await repository.upsertPresence(
            mutation(sessionID: sessionID, clientID: UUID(), status: .joiningSaf)
        )
        _ = try await iterator.next()

        _ = try await repository.refreshPresence(
            leaseID: lease.id,
            status: .praying,
            at: Date()
        )
        let snapshot = try await iterator.next()

        XCTAssertEqual(snapshot?.participantCount, 1)
        XCTAssertEqual(snapshot?.counts.joiningSaf, 0)
        XCTAssertEqual(snapshot?.counts.praying, 1)
    }

    func testLeaveRemovesPresence() async throws {
        let repository = InMemoryPresenceRepository()
        let sessionID = PrayerSessionID(rawValue: UUID())
        let stream = await repository.snapshots(for: sessionID)
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()

        let lease = try await repository.upsertPresence(
            mutation(sessionID: sessionID, clientID: UUID(), status: .ready)
        )
        _ = try await iterator.next()

        await repository.leave(leaseID: lease.id)
        let snapshot = try await iterator.next()
        XCTAssertEqual(snapshot?.participantCount, 0)
    }

    func testExpiredLeaseCannotBeRefreshed() async throws {
        let repository = InMemoryPresenceRepository(leaseDuration: 1)
        let sessionID = PrayerSessionID(rawValue: UUID())
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let lease = try await repository.upsertPresence(
            mutation(
                sessionID: sessionID,
                clientID: UUID(),
                status: .ready,
                createdAt: createdAt
            )
        )

        do {
            _ = try await repository.refreshPresence(
                leaseID: lease.id,
                status: .praying,
                at: createdAt.addingTimeInterval(2)
            )
            XCTFail("Refreshing an expired lease should fail")
        } catch let error as BackendError {
            XCTAssertEqual(error, .sessionUnavailable)
        }
    }

    private func mutation(
        sessionID: PrayerSessionID,
        clientID: UUID,
        status: BackendPresenceStatus,
        createdAt: Date = Date()
    ) -> PresenceMutation {
        PresenceMutation(
            commandID: UUID(),
            sessionID: sessionID,
            clientInstanceID: clientID,
            status: status,
            createdAt: createdAt
        )
    }
}
