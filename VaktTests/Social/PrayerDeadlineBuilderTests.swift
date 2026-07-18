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

    func testFajrUsesSunriseAsDeadline() {
        let fajr = date(2026, 7, 12, 4, 41)
        let sunrise = date(2026, 7, 12, 5, 42)
        let dhuhr = date(2026, 7, 12, 13, 10)
        let prayers = [
            PrayerTime(
                prayer: .fajr,
                time: fajr,
                countdown: 0,
                timeZoneIdentifier: "Europe/Istanbul",
                endsAt: sunrise
            ),
            PrayerTime(prayer: .dhuhr, time: dhuhr, countdown: 0, timeZoneIdentifier: "Europe/Istanbul")
        ]

        let deadline = PrayerDeadlineBuilder.build(
            from: prayers,
            now: date(2026, 7, 12, 5, 0)
        ).first

        XCTAssertEqual(deadline?.prayer, .fajr)
        XCTAssertEqual(deadline?.closesAt, sunrise)
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

final class ActivePrayerWindowTests: XCTestCase {
    private let zone = "Europe/Istanbul"

    func testDhuhrWindowEndsAtAsr() throws {
        let dhuhr = prayer(.dhuhr, at: date(2026, 7, 18, 13, 0))
        let asr = prayer(.asr, at: date(2026, 7, 18, 17, 0))
        let window = try XCTUnwrap(ActivePrayerWindow.resolve(
            from: [dhuhr, asr],
            at: date(2026, 7, 18, 14, 0)
        ))

        XCTAssertEqual(window.prayerTime.prayer, .dhuhr)
        XCTAssertEqual(window.endsAt, asr.time)
        XCTAssertEqual(window.endingPrayer, .asr)
        XCTAssertEqual(window.progress(at: date(2026, 7, 18, 14, 0)), 0.25, accuracy: 0.001)
    }

    func testFajrWindowEndsAtSunrise() {
        let sunrise = date(2026, 7, 18, 5, 42)
        let fajr = PrayerTime(
            prayer: .fajr,
            time: date(2026, 7, 18, 3, 48),
            countdown: 0,
            timeZoneIdentifier: zone,
            endsAt: sunrise
        )
        let dhuhr = prayer(.dhuhr, at: date(2026, 7, 18, 13, 8))

        let beforeSunrise = ActivePrayerWindow.resolve(
            from: [fajr, dhuhr],
            at: date(2026, 7, 18, 5, 30)
        )
        let afterSunrise = ActivePrayerWindow.resolve(
            from: [fajr, dhuhr],
            at: date(2026, 7, 18, 8, 0)
        )

        XCTAssertEqual(beforeSunrise?.prayerTime.prayer, .fajr)
        XCTAssertEqual(beforeSunrise?.endsAt, sunrise)
        XCTAssertNil(beforeSunrise?.endingPrayer)
        XCTAssertNil(afterSunrise)
    }

    func testIshaWindowEndsAtNextDaysFajr() {
        let isha = prayer(.isha, at: date(2026, 7, 18, 22, 12))
        let fajr = prayer(.fajr, at: date(2026, 7, 19, 3, 49))
        let window = ActivePrayerWindow.resolve(
            from: [isha, fajr],
            at: date(2026, 7, 19, 0, 30)
        )

        XCTAssertEqual(window?.prayerTime.prayer, .isha)
        XCTAssertEqual(window?.endsAt, fajr.time)
        XCTAssertEqual(window?.endingPrayer, .fajr)
    }

    private func prayer(_ prayer: Prayer, at time: Date) -> PrayerTime {
        PrayerTime(
            prayer: prayer,
            time: time,
            countdown: 0,
            timeZoneIdentifier: zone
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
