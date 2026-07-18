import XCTest
@testable import Vakt

final class VaktTimeFormatterTests: XCTestCase {
    func testAutomaticCalculationPolicyUsesRegionalMethods() {
        XCTAssertEqual(policy(latitude: 39.9334, longitude: 32.8597).method, .diyanet)
        XCTAssertEqual(policy(latitude: 40.7128, longitude: -74.0060).method, .isna)
        XCTAssertEqual(policy(latitude: 51.5074, longitude: -0.1278).method, .muslimWorldLeague)
        XCTAssertEqual(policy(latitude: 48.8566, longitude: 2.3522).method, .muslimWorldLeague)
    }

    func testHighLatitudePolicyUsesOneSeventhRule() {
        XCTAssertEqual(policy(latitude: 59.3293, longitude: 18.0686).latitudeAdjustment, .oneSeventh)
        XCTAssertEqual(policy(latitude: 43.6532, longitude: -79.3832).latitudeAdjustment, .angleBased)
    }

    func testManualMethodStillOverridesRegionalSelection() {
        let policy = PrayerCalculationPolicy.resolve(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            preference: .diyanet
        )

        XCTAssertEqual(policy.method, .diyanet)
    }

    func testPolarReferenceLatitudePreservesHemisphereAndLongitude() {
        let northern = policy(latitude: 69.6492, longitude: 18.9553)
            .referenceCoordinate(for: Coordinate(latitude: 69.6492, longitude: 18.9553))
        let southern = policy(latitude: -69.0, longitude: 18.9553)
            .referenceCoordinate(for: Coordinate(latitude: -69.0, longitude: 18.9553))

        XCTAssertEqual(northern, Coordinate(latitude: 48.5, longitude: 18.9553))
        XCTAssertEqual(southern, Coordinate(latitude: -48.5, longitude: 18.9553))
    }

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

    private func policy(latitude: Double, longitude: Double) -> PrayerCalculationPolicy {
        PrayerCalculationPolicy.resolve(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            preference: .automatic
        )
    }
}
