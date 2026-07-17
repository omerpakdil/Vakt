import XCTest
@testable import Vakt

final class PrayerDeadlineBuilderTests: XCTestCase {
    func testEachPrayerClosesWhenNextPrayerBegins() {
        let zone = "Europe/Istanbul"
        let dhuhr = date(2026, 7, 12, 13, 10)
        let asr = date(2026, 7, 12, 17, 5)
        let maghrib = date(2026, 7, 12, 20, 35)
        let prayers = [
            PrayerTime(prayer: .dhuhr, time: dhuhr, countdown: 0, timeZoneIdentifier: zone),
            PrayerTime(prayer: .asr, time: asr, countdown: 0, timeZoneIdentifier: zone),
            PrayerTime(prayer: .maghrib, time: maghrib, countdown: 0, timeZoneIdentifier: zone)
        ]

        let deadlines = PrayerDeadlineBuilder.build(
            from: prayers,
            now: date(2026, 7, 12, 14, 0)
        )

        XCTAssertEqual(deadlines.map(\.prayer), [.dhuhr, .asr])
        XCTAssertEqual(deadlines[0].closesAt, asr)
        XCTAssertEqual(deadlines[1].closesAt, maghrib)
    }

    func testIshaUsesNextDaysFajrAsDeadline() {
        let zone = "Europe/Istanbul"
        let isha = date(2026, 7, 12, 22, 10)
        let fajr = date(2026, 7, 13, 3, 48)
        let prayers = [
            PrayerTime(prayer: .isha, time: isha, countdown: 0, timeZoneIdentifier: zone),
            PrayerTime(prayer: .fajr, time: fajr, countdown: 0, timeZoneIdentifier: zone)
        ]

        let deadline = PrayerDeadlineBuilder.build(
            from: prayers,
            now: date(2026, 7, 12, 23, 0)
        ).first

        XCTAssertEqual(deadline?.prayer, .isha)
        XCTAssertEqual(deadline?.localDay.databaseValue, "2026-07-12")
        XCTAssertEqual(deadline?.closesAt, fajr)
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
