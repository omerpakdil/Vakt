import XCTest
@testable import Vakt

final class PrayerSurfaceFoundationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PrayerSurfaceFoundationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSnapshotRoundTripPreservesVersionedPayload() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let prayer = PrayerSurfacePrayer(
            prayer: .asr,
            startsAt: now,
            endsAt: now.addingTimeInterval(3_600),
            timeZoneIdentifier: "Europe/Istanbul",
            status: .quiet
        )
        let snapshot = PrayerSurfaceSnapshot(
            generatedAt: now,
            phase: .quiet,
            currentPrayer: prayer,
            nextPrayer: nil,
            schedule: [prayer],
            atmosphere: .afternoon
        )
        let store = PrayerSurfaceStore(defaults: defaults)

        XCTAssertTrue(store.saveSnapshot(snapshot))
        XCTAssertEqual(store.loadSnapshot(), snapshot)
    }

    func testPendingActionQueueIsIdempotentAndOrdered() {
        let store = PrayerSurfaceStore(defaults: defaults)
        let first = PrayerSurfaceAction(
            kind: .markPrayed,
            prayer: .dhuhr,
            prayerDate: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let second = PrayerSurfaceAction(
            kind: .startSalah,
            prayer: .asr,
            prayerDate: Date(timeIntervalSince1970: 300),
            createdAt: Date(timeIntervalSince1970: 400)
        )

        XCTAssertTrue(store.enqueue(second))
        XCTAssertTrue(store.enqueue(first))
        XCTAssertFalse(store.enqueue(first))
        XCTAssertFalse(store.enqueue(PrayerSurfaceAction(
            kind: .markPrayed,
            prayer: .dhuhr,
            prayerDate: first.prayerDate,
            createdAt: first.createdAt.addingTimeInterval(1)
        )))
        XCTAssertEqual(store.pendingActions(), [first, second])
        XCTAssertTrue(store.removePendingAction(id: first.id))
        XCTAssertEqual(store.pendingActions(), [second])
    }

    func testSurfaceAccessHonorsEntitlementExpiration() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = PrayerSurfaceStore(defaults: defaults)

        XCTAssertFalse(store.hasActiveAccess(at: now))
        store.updateAccess(isActive: true, expirationDate: now.addingTimeInterval(60), validatedAt: now)
        XCTAssertTrue(store.hasActiveAccess(at: now))
        XCTAssertFalse(store.hasActiveAccess(at: now.addingTimeInterval(61)))
        store.updateAccess(isActive: false, expirationDate: nil, validatedAt: now)
        XCTAssertFalse(store.hasActiveAccess(at: now))
    }

    func testStartPrayerDeepLinkRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_123.5)
        let deepLink = VaktDeepLink.startPrayer(prayer: .maghrib, prayerDate: date)
        let url = try XCTUnwrap(deepLink.url)

        XCTAssertEqual(VaktDeepLink(url: url), deepLink)
    }

    func testOpenPrayerDeepLinkRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_456.5)
        let deepLink = VaktDeepLink.openPrayer(prayer: .asr, prayerDate: date)
        let url = try XCTUnwrap(deepLink.url)

        XCTAssertEqual(VaktDeepLink(url: url), deepLink)
    }

    func testWidgetMarkPrayedUpdatesSnapshotAndQueuesReconciliation() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prayer = PrayerSurfacePrayer(
            prayer: .dhuhr,
            startsAt: date,
            endsAt: date.addingTimeInterval(3_600),
            timeZoneIdentifier: "Europe/Istanbul",
            status: .unmarked
        )
        let store = PrayerSurfaceStore(defaults: defaults)
        XCTAssertTrue(store.saveSnapshot(PrayerSurfaceSnapshot(
            generatedAt: date,
            phase: .entered,
            currentPrayer: prayer,
            nextPrayer: nil,
            schedule: [prayer],
            atmosphere: .midday
        )))

        XCTAssertTrue(store.markPrayerPrayed(prayer: .dhuhr, prayerDate: date))
        XCTAssertEqual(store.loadSnapshot()?.currentPrayer?.status, .prayed)
        XCTAssertEqual(store.loadSnapshot()?.schedule.first?.status, .prayed)
        XCTAssertEqual(store.loadSnapshot()?.phase, .completed)
        XCTAssertEqual(store.loadSnapshot()?.hasPendingActions, true)
    }

    func testWidgetNotYetCanLaterBeReplacedByPrayed() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prayer = PrayerSurfacePrayer(
            prayer: .asr,
            startsAt: date,
            endsAt: date.addingTimeInterval(3_600),
            timeZoneIdentifier: "Europe/Istanbul",
            status: .unmarked
        )
        let store = PrayerSurfaceStore(defaults: defaults)
        XCTAssertTrue(store.saveSnapshot(PrayerSurfaceSnapshot(
            generatedAt: date,
            phase: .entered,
            currentPrayer: prayer,
            nextPrayer: nil,
            schedule: [prayer],
            atmosphere: .afternoon
        )))

        XCTAssertTrue(store.markPrayerNotYet(prayer: .asr, prayerDate: date))
        XCTAssertEqual(store.loadSnapshot()?.currentPrayer?.status, .notYet)
        XCTAssertEqual(store.loadSnapshot()?.schedule.first?.status, .notYet)
        XCTAssertEqual(store.loadSnapshot()?.phase, .entered)

        XCTAssertTrue(store.markPrayerPrayed(prayer: .asr, prayerDate: date))
        XCTAssertEqual(store.loadSnapshot()?.currentPrayer?.status, .prayed)
        XCTAssertEqual(store.loadSnapshot()?.phase, .completed)
    }

    func testInvalidDeepLinkIsRejected() {
        XCTAssertNil(VaktDeepLink(url: URL(string: "vakt://prayer/start?prayer=fajr")!))
        XCTAssertNil(VaktDeepLink(url: URL(string: "https://example.com")!))
    }

    func testLiveActivityQuietStateRoundTrip() throws {
        let state = PrayerLiveActivityAttributes.ContentState.quiet
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            PrayerLiveActivityAttributes.ContentState.self,
            from: data
        )

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.phase, .quiet)
        XCTAssertNil(decoded.completedAt)
    }

    func testLiveActivityCompletedStatePreservesCompletionDate() throws {
        let completedAt = Date(timeIntervalSince1970: 1_800_000_999)
        let state = PrayerLiveActivityAttributes.ContentState.completed(at: completedAt)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            PrayerLiveActivityAttributes.ContentState.self,
            from: data
        )

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.phase, .completed)
        XCTAssertEqual(decoded.completedAt, completedAt)
    }
}
