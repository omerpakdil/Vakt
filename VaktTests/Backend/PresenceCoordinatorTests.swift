import XCTest
@testable import Vakt

@MainActor
final class PresenceCoordinatorTests: XCTestCase {
    func testDisplayMemberCountUsesAmbientValueWhenObservedCountIsLow() {
        let store = LiveSafPresenceStore(
            initialCount: 0,
            sessions: LocalPrayerSessionRepository(),
            presence: InMemoryPresenceRepository(),
            minimumInitialCount: 0
        )

        XCTAssertEqual(store.memberCount, 0)
        XCTAssertEqual(store.displayMemberCount, 7)
    }

    func testDisplayMemberCountKeepsObservedCountsAboveFloor() {
        let store = LiveSafPresenceStore(
            initialCount: 12,
            sessions: LocalPrayerSessionRepository(),
            presence: InMemoryPresenceRepository(),
            minimumInitialCount: 0
        )

        XCTAssertEqual(store.memberCount, 12)
        XCTAssertEqual(store.displayMemberCount, 12)
    }

    func testObservedCountAboveThresholdOverridesAmbientValue() {
        XCTAssertEqual(
            SafPresenceDisplayPolicy.displayedCount(realCount: 8, ambientCount: 5),
            8
        )
        XCTAssertEqual(
            SafPresenceDisplayPolicy.displayedCount(realCount: 7, ambientCount: 10),
            10
        )
    }

    func testLocalSimulationSnapshotsDoNotPromoteHighMockCountsToRealPresence() async throws {
        let store = LiveSafPresenceStore(
            initialCount: 0,
            sessions: LocalPrayerSessionRepository(),
            presence: FixedSnapshotPresenceRepository(count: 90, source: .localSimulation),
            minimumInitialCount: 0
        )

        store.start()
        store.updatePrayerContext(prayerTime(prayer: .dhuhr))

        try await waitUntil("local simulation snapshot is clamped") {
            store.memberCount == SafPresenceDisplayPolicy.realCountThreshold
        }
        XCTAssertEqual(store.displayMemberCount, SafPresenceDisplayPolicy.initialAmbientCount)
        store.stop()
    }

    func testRealtimeSnapshotsKeepHighObservedPresenceCounts() async throws {
        let store = LiveSafPresenceStore(
            initialCount: 0,
            sessions: LocalPrayerSessionRepository(),
            presence: FixedSnapshotPresenceRepository(count: 90, source: .realtime),
            minimumInitialCount: 0
        )

        store.start()
        store.updatePrayerContext(prayerTime(prayer: .dhuhr))

        try await waitUntil("realtime snapshot is applied") {
            store.memberCount == 90
        }
        XCTAssertEqual(store.displayMemberCount, 90)
        store.stop()
    }

    func testAmbientRandomWalkRemainsWithinRange() {
        var count = SafPresenceDisplayPolicy.initialAmbientCount

        for roll in 0..<500 {
            count = SafPresenceDisplayPolicy.nextAmbientCount(from: count, roll: roll % 100)
            XCTAssertTrue(SafPresenceDisplayPolicy.ambientRange.contains(count))
        }
    }

    func testObserveDoesNotJoinUntilExplicitJoin() async throws {
        let repository = InMemoryPresenceRepository()
        let sessions = LocalPrayerSessionRepository()
        let coordinator = PresenceCoordinator(sessions: sessions, presence: repository)
        let observed = expectation(description: "Observed empty session")
        let joined = expectation(description: "Joined session")
        var didObserve = false
        var didJoin = false

        coordinator.onSnapshot = { snapshot in
            if snapshot.participantCount == 0, !didObserve {
                didObserve = true
                observed.fulfill()
            } else if snapshot.participantCount == 1, !didJoin {
                didJoin = true
                joined.fulfill()
            }
        }

        coordinator.observe(request(prayer: .dhuhr))
        await fulfillment(of: [observed], timeout: 1)

        coordinator.join(status: .makingWudu)
        await fulfillment(of: [joined], timeout: 1)
        coordinator.stop()
    }

    func testStatusUpdateKeepsSingleLease() async throws {
        let repository = InMemoryPresenceRepository()
        let sessions = LocalPrayerSessionRepository()
        let coordinator = PresenceCoordinator(sessions: sessions, presence: repository)
        let joined = expectation(description: "Joined")
        let praying = expectation(description: "Status updated")

        coordinator.onSnapshot = { snapshot in
            if snapshot.counts.makingWudu == 1 {
                joined.fulfill()
            }
            if snapshot.counts.praying == 1 {
                XCTAssertEqual(snapshot.participantCount, 1)
                praying.fulfill()
            }
        }

        coordinator.observe(request(prayer: .asr))
        coordinator.join(status: .makingWudu)
        await fulfillment(of: [joined], timeout: 1)

        coordinator.updateStatus(.praying)
        await fulfillment(of: [praying], timeout: 1)
        coordinator.stop()
    }

    func testLeaveRemovesActiveLeaseButKeepsObservation() async throws {
        let repository = InMemoryPresenceRepository()
        let sessions = LocalPrayerSessionRepository()
        let coordinator = PresenceCoordinator(sessions: sessions, presence: repository)
        let joined = expectation(description: "Joined")
        let left = expectation(description: "Left")
        var hasJoined = false

        coordinator.onSnapshot = { snapshot in
            if snapshot.participantCount == 1 {
                hasJoined = true
                joined.fulfill()
            } else if hasJoined, snapshot.participantCount == 0 {
                left.fulfill()
            }
        }

        coordinator.observe(request(prayer: .maghrib))
        coordinator.join(status: .ready)
        await fulfillment(of: [joined], timeout: 1)

        coordinator.leave()
        await fulfillment(of: [left], timeout: 1)
        coordinator.stop()
    }

    private func request(prayer: Prayer) -> PrayerSessionRequest {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let prayerTime = Date(timeIntervalSince1970: 1_750_000_000)
        return PrayerSessionRequest(
            scope: PrayerSessionScope(
                prayer: prayer,
                prayerTime: prayerTime,
                calendar: calendar
            ),
            expectedPrayerTime: prayerTime
        )
    }

    private func prayerTime(prayer: Prayer) -> PrayerTime {
        PrayerTime(
            prayer: prayer,
            time: Date(timeIntervalSince1970: 1_750_000_000),
            countdown: 600,
            timeZoneIdentifier: "UTC"
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTFail("Timed out waiting for \(description)")
    }
}

private actor FixedSnapshotPresenceRepository: PresenceRepository {
    let count: Int
    let source: PresenceSnapshotSource

    init(count: Int, source: PresenceSnapshotSource) {
        self.count = count
        self.source = source
    }

    nonisolated func snapshots(
        for sessionID: PrayerSessionID
    ) async -> AsyncThrowingStream<PresenceSnapshot, Error> {
        let count = count
        let source = source

        return AsyncThrowingStream { continuation in
            continuation.yield(
                PresenceSnapshot(
                    sessionID: sessionID,
                    counts: PresenceCounts(
                        gettingUp: 0,
                        makingWudu: 0,
                        joiningSaf: 0,
                        ready: count,
                        praying: 0
                    ),
                    observedAt: Date(),
                    source: source,
                    isStale: false
                )
            )
        }
    }

    func upsertPresence(_ mutation: PresenceMutation) async throws -> PresenceLease {
        PresenceLease(
            id: PresenceLeaseID(rawValue: UUID()),
            sessionID: mutation.sessionID,
            status: mutation.status,
            expiresAt: mutation.createdAt.addingTimeInterval(900)
        )
    }

    func refreshPresence(
        leaseID: PresenceLeaseID,
        status: BackendPresenceStatus,
        at date: Date
    ) async throws -> PresenceLease {
        PresenceLease(
            id: leaseID,
            sessionID: PrayerSessionID(rawValue: UUID()),
            status: status,
            expiresAt: date.addingTimeInterval(900)
        )
    }

    func leave(leaseID _: PresenceLeaseID) async {}
}
