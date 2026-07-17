import XCTest
@testable import Vakt

final class SpiritualContentSelectorTests: XCTestCase {
    func testSelectsContentMatchingPrayerAndOutcomeTags() {
        let selector = SpiritualContentSelector(prayerSpecificInterval: 1)
        let request = SpiritualContentRequest(
            prayer: .fajr,
            outcome: .prayed,
            date: fixedDate
        )

        let selected = selector.select(
            from: [
                content(id: "generic", tags: ["salah", "after_salah"], weight: 100),
                content(id: "fajr", tags: ["salah", "after_salah", "fajr", "gratitude"], weight: 80)
            ],
            request: request,
            recentIDs: []
        )

        XCTAssertEqual(selected?.id, "fajr")
    }

    func testSkipsPrayerSpecificContentFromAnotherPrayer() {
        let selector = SpiritualContentSelector(prayerSpecificInterval: 1)
        let request = SpiritualContentRequest(
            prayer: .maghrib,
            outcome: .prayed,
            date: fixedDate
        )

        let selected = selector.select(
            from: [
                content(id: "generic", tags: ["salah", "after_salah", "gratitude"], weight: 80),
                content(id: "fajr", tags: ["salah", "after_salah", "fajr", "gratitude"], weight: 400)
            ],
            request: request,
            recentIDs: []
        )

        XCTAssertEqual(selected?.id, "generic")
    }

    func testPrefersGeneralContentWhenPrayerSpecificRotationIsNotDue() {
        let selector = SpiritualContentSelector(prayerSpecificInterval: UInt64.max)
        let request = SpiritualContentRequest(
            prayer: .isha,
            outcome: .prayed,
            date: fixedDate
        )

        let selected = selector.select(
            from: [
                content(id: "general", tags: ["salah", "after_salah", "gratitude"], weight: 80),
                content(id: "isha", tags: ["salah", "after_salah", "isha", "gratitude"], weight: 400)
            ],
            request: request,
            recentIDs: []
        )

        XCTAssertEqual(selected?.id, "general")
    }

    func testAvoidsRecentlyShownContentWhenPossible() {
        let selector = SpiritualContentSelector(recentWindow: 3)
        let request = SpiritualContentRequest(
            prayer: .isha,
            outcome: .later,
            date: fixedDate
        )

        let selected = selector.select(
            from: [
                content(id: "strong", tags: ["salah", "after_salah", "isha", "returning"], weight: 200),
                content(id: "next", tags: ["salah", "after_salah", "isha", "steadiness"], weight: 120)
            ],
            request: request,
            recentIDs: ["strong"]
        )

        XCTAssertEqual(selected?.id, "next")
    }

    func testFallsBackToRecentContentWhenEverythingWasShown() {
        let selector = SpiritualContentSelector(recentWindow: 3)
        let request = SpiritualContentRequest(
            prayer: .maghrib,
            outcome: .missed,
            date: fixedDate
        )

        let selected = selector.select(
            from: [
                content(id: "one", tags: ["salah", "after_salah", "maghrib"], weight: 100),
                content(id: "two", tags: ["salah", "after_salah", "mercy"], weight: 100)
            ],
            request: request,
            recentIDs: ["one", "two"]
        )

        XCTAssertNotNil(selected)
    }

    func testStableHashIsDeterministic() {
        XCTAssertEqual(
            SpiritualContentSelector.stableHash("asr|prayed|content"),
            SpiritualContentSelector.stableHash("asr|prayed|content")
        )
        XCTAssertNotEqual(
            SpiritualContentSelector.stableHash("asr|prayed|content"),
            SpiritualContentSelector.stableHash("asr|missed|content")
        )
    }

    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_788_537_600)
    }

    private func content(
        id: String,
        tags: Set<String>,
        weight: Int
    ) -> SpiritualContent {
        SpiritualContent(
            id: id,
            kind: .reflection,
            text: "A short reflection after salah.",
            sourceTitle: "Test",
            tags: tags,
            weight: weight
        )
    }
}
