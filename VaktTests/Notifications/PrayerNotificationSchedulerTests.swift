import XCTest
import CoreLocation
import UserNotifications
@testable import Vakt

final class PrayerNotificationSchedulerTests: XCTestCase {
    func testReminderStateRequiresSystemPermissionBeforeBecomingEnabled() {
        XCTAssertEqual(
            ReminderState(preferenceEnabled: true, authorizationStatus: .notDetermined),
            .notRequested
        )
        XCTAssertEqual(
            ReminderState(preferenceEnabled: true, authorizationStatus: .denied),
            .denied
        )
        XCTAssertEqual(
            ReminderState(preferenceEnabled: true, authorizationStatus: .authorized),
            .enabled
        )
        XCTAssertEqual(
            ReminderState(preferenceEnabled: false, authorizationStatus: .authorized),
            .paused
        )
    }

    @MainActor
    func testPermissionSetupRequiresScheduleThenNotificationDecision() {
        let suiteName = "PermissionSetupStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PermissionSetupStore(defaults: defaults)

        XCTAssertEqual(
            store.nextStep(
                hasUsablePrayerSchedule: false,
                locationStatus: .authorizedWhenInUse,
                notificationStatus: .notDetermined
            ),
            .location
        )
        XCTAssertEqual(
            store.nextStep(
                hasUsablePrayerSchedule: true,
                locationStatus: .notDetermined,
                notificationStatus: .notDetermined
            ),
            .location
        )
        XCTAssertEqual(
            store.nextStep(
                hasUsablePrayerSchedule: true,
                locationStatus: .authorizedWhenInUse,
                notificationStatus: .notDetermined
            ),
            .notifications
        )

        store.completeNotificationDecision()

        XCTAssertNil(
            store.nextStep(
                hasUsablePrayerSchedule: true,
                locationStatus: .authorizedWhenInUse,
                notificationStatus: .notDetermined
            )
        )
    }

    func testSchedulesCheckInForPrayerAlreadyInProgress() {
        let now = date(2026, 7, 12, 14, 0)
        let prayers = [
            prayer(.dhuhr, at: date(2026, 7, 12, 13, 10)),
            prayer(.asr, at: date(2026, 7, 12, 17, 5)),
            prayer(.maghrib, at: date(2026, 7, 12, 20, 35))
        ]
        var preferences = NotificationPreferences.default
        preferences.prayerOpeningEnabled = false
        preferences.prayerTimeEnabled = false
        preferences.fajrWakeEnabled = false
        preferences.checkInEnabled = true
        preferences.checkInMinutesBeforeNextPrayer = 15

        let requests = PrayerNotificationScheduler().requests(
            prayers: prayers,
            now: now,
            liveMemberCount: 0,
            preferences: preferences,
            quietSoundEnabled: false
        )

        let dhuhrCheckIn = requests.first {
            $0.content.userInfo["type"] as? String == "prayerCheckIn" &&
            $0.content.userInfo["prayer"] as? String == Prayer.dhuhr.rawValue
        }
        XCTAssertNotNil(dhuhrCheckIn)
    }

    func testSchedulesCheckInForAllFivePrayersIncludingIsha() throws {
        let now = date(2026, 7, 12, 4, 0)
        let sunrise = date(2026, 7, 12, 5, 42)
        let nextFajr = date(2026, 7, 13, 4, 42)
        let prayers = [
            prayer(.fajr, at: date(2026, 7, 12, 4, 41), endsAt: sunrise),
            prayer(.dhuhr, at: date(2026, 7, 12, 13, 10)),
            prayer(.asr, at: date(2026, 7, 12, 17, 5)),
            prayer(.maghrib, at: date(2026, 7, 12, 20, 35)),
            prayer(.isha, at: date(2026, 7, 12, 22, 8)),
            prayer(.fajr, at: nextFajr)
        ]
        var preferences = NotificationPreferences.default
        preferences.prayerOpeningEnabled = false
        preferences.prayerTimeEnabled = false
        preferences.fajrWakeEnabled = false
        preferences.checkInEnabled = true

        let requests = PrayerNotificationScheduler().requests(
            prayers: prayers,
            now: now,
            liveMemberCount: 0,
            preferences: preferences,
            quietSoundEnabled: false
        )
        let checkIns = requests.filter {
            $0.content.userInfo["type"] as? String == "prayerCheckIn"
        }

        XCTAssertEqual(checkIns.count, 5)
        XCTAssertEqual(
            Set(checkIns.compactMap { $0.content.userInfo["prayer"] as? String }),
            Set(Prayer.allCases.map(\.rawValue))
        )

        let ishaCheckIn = try XCTUnwrap(checkIns.first {
            $0.content.userInfo["prayer"] as? String == Prayer.isha.rawValue
        })
        let expectedFireDate = nextFajr.addingTimeInterval(-20 * 60)
        let trigger = try XCTUnwrap(ishaCheckIn.trigger as? UNCalendarNotificationTrigger)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let actualFireDate = try XCTUnwrap(calendar.date(from: trigger.dateComponents))
        XCTAssertEqual(actualFireDate.timeIntervalSince1970, expectedFireDate.timeIntervalSince1970, accuracy: 1)

        let fajrCheckIn = try XCTUnwrap(checkIns.first {
            $0.content.userInfo["prayer"] as? String == Prayer.fajr.rawValue
        })
        let fajrTrigger = try XCTUnwrap(fajrCheckIn.trigger as? UNCalendarNotificationTrigger)
        let fajrFireDate = try XCTUnwrap(calendar.date(from: fajrTrigger.dateComponents))
        XCTAssertEqual(
            fajrFireDate.timeIntervalSince1970,
            sunrise.addingTimeInterval(-20 * 60).timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testSchedulesPreparationOpeningPrayerTimeAndCheckIn() throws {
        let now = date(2026, 7, 12, 12, 0)
        let dhuhr = prayer(.dhuhr, at: date(2026, 7, 12, 13, 10))
        let asr = prayer(.asr, at: date(2026, 7, 12, 17, 5))

        let requests = PrayerNotificationScheduler().requests(
            prayers: [dhuhr, asr],
            now: now,
            liveMemberCount: 0,
            preferences: .default,
            quietSoundEnabled: true
        ).filter {
            $0.content.userInfo["prayer"] as? String == Prayer.dhuhr.rawValue
        }

        XCTAssertEqual(
            Set(requests.compactMap { $0.content.userInfo["type"] as? String }),
            ["prayerPreparation", "prayerOpening", "prayerTime", "prayerCheckIn"]
        )

        let prayerTimeRequest = try XCTUnwrap(requests.first {
            $0.content.userInfo["type"] as? String == "prayerTime"
        })
        XCTAssertNotNil(prayerTimeRequest.content.sound)

        let preparationRequest = try XCTUnwrap(requests.first {
            $0.content.userInfo["type"] as? String == "prayerPreparation"
        })
        XCTAssertNil(preparationRequest.content.sound)
        XCTAssertEqual(
            try fireDate(for: preparationRequest).timeIntervalSince1970,
            dhuhr.time.addingTimeInterval(-30 * 60).timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testFajrWakeReplacesDuplicateThirtyMinutePreparation() {
        let now = date(2026, 7, 12, 3, 0)
        let fajr = prayer(.fajr, at: date(2026, 7, 12, 4, 41))
        var preferences = NotificationPreferences.default
        preferences.checkInEnabled = false
        preferences.enabledPrayers = [.fajr]

        let requests = PrayerNotificationScheduler().requests(
            prayers: [fajr],
            now: now,
            liveMemberCount: 0,
            preferences: preferences,
            quietSoundEnabled: true
        )
        let types = requests.compactMap { $0.content.userInfo["type"] as? String }

        XCTAssertFalse(types.contains("prayerPreparation"))
        XCTAssertEqual(types.filter { $0 == "fajrWake" }.count, 1)
        XCTAssertTrue(types.contains("prayerOpening"))
        XCTAssertTrue(types.contains("prayerTime"))
    }

    func testDecodingLegacyPreferencesPreservesExistingChoices() throws {
        let legacyJSON = """
        {
          "enabled": true,
          "prayerOpeningEnabled": false,
          "prayerTimeEnabled": true,
          "fajrWakeEnabled": false,
          "checkInEnabled": true,
          "minutesBeforePrayer": 10,
          "fajrWakeMinutesBefore": 30,
          "checkInMinutesBeforeNextPrayer": 20,
          "enabledPrayers": ["dhuhr", "asr"]
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(NotificationPreferences.self, from: legacyJSON)

        XCTAssertFalse(preferences.prayerOpeningEnabled)
        XCTAssertFalse(preferences.fajrWakeEnabled)
        XCTAssertTrue(preferences.prayerPreparationEnabled)
        XCTAssertEqual(preferences.preparationMinutesBeforePrayer, 30)
        XCTAssertEqual(preferences.enabledPrayers, [.dhuhr, .asr])
    }

    private func fireDate(for request: UNNotificationRequest) throws -> Date {
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return try XCTUnwrap(calendar.date(from: trigger.dateComponents))
    }

    private func prayer(_ prayer: Prayer, at time: Date, endsAt: Date? = nil) -> PrayerTime {
        PrayerTime(
            prayer: prayer,
            time: time,
            countdown: 0,
            timeZoneIdentifier: "Europe/Istanbul",
            endsAt: endsAt
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
