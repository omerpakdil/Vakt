import XCTest
@testable import Vakt

final class VaktTimeFormatterTests: XCTestCase {
    func testSanFranciscoUsesLocalPrayerClockAndUSDayPeriod() throws {
        let date = try makeDate(year: 2026, month: 7, day: 4, hour: 20, minute: 14)
        let output = VaktTimeFormatter.string(
            from: date,
            locale: Locale(identifier: "en_US"),
            timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        )

        XCTAssertTrue(output.contains("1:14"))
        XCTAssertTrue(output.uppercased().contains("PM"))
    }

    func testLegacyPrayerTimeCacheDecodesWithoutTimeZone() throws {
        let data = try XCTUnwrap(
            #"{"prayer":"Dhuhr","time":804888840,"countdown":0}"#.data(using: .utf8)
        )

        let prayerTime = try JSONDecoder().decode(PrayerTime.self, from: data)

        XCTAssertEqual(prayerTime.prayer, .dhuhr)
        XCTAssertNil(prayerTime.timeZoneIdentifier)
    }

    func testBritishLocaleUsesTwentyFourHourClock() throws {
        let date = try makeDate(year: 2026, month: 7, day: 4, hour: 20, minute: 14)
        let output = VaktTimeFormatter.string(
            from: date,
            locale: Locale(identifier: "en_GB"),
            timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        )

        XCTAssertEqual(output, "23:14")
    }

    func testSameInstantFollowsProvidedDisplayTimeZone() throws {
        let date = try makeDate(year: 2026, month: 7, day: 4, hour: 20, minute: 14)
        let locale = Locale(identifier: "en_GB")

        let istanbul = VaktTimeFormatter.string(
            from: date,
            locale: locale,
            timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        )
        let london = VaktTimeFormatter.string(
            from: date,
            locale: locale,
            timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        )

        XCTAssertEqual(istanbul, "23:14")
        XCTAssertEqual(london, "21:14")
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}
