import XCTest
@testable import Vakt

final class MakeupPrayerCalendarTests: XCTestCase {
    func testMonthBuildsBoundedDatabaseRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!

        let month = MakeupPrayerMonth(date: date, calendar: calendar)

        XCTAssertEqual(month.firstDay.databaseValue, "2026-07-01")
        XCTAssertEqual(month.nextMonthFirstDay.databaseValue, "2026-08-01")
    }

    func testDecemberRangeContinuesIntoNextYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!

        let month = MakeupPrayerMonth(date: date, calendar: calendar)

        XCTAssertEqual(month.firstDay.databaseValue, "2026-12-01")
        XCTAssertEqual(month.nextMonthFirstDay.databaseValue, "2027-01-01")
    }

    func testDaySummaryUsesPrayerCount() {
        let summary = MakeupPrayerDaySummary(
            day: LocalPrayerDay(year: 2026, month: 7, day: 12),
            prayers: [.fajr, .asr, .isha]
        )

        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.id.databaseValue, "2026-07-12")
    }
}
