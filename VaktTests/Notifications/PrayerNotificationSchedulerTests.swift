import XCTest
import UserNotifications
@testable import Vakt

final class PrayerNotificationSchedulerTests: XCTestCase {
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
