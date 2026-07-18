import XCTest
@testable import Vakt

final class UsernamePolicyTests: XCTestCase {
    func testSuggestionsTransliterateAndPreserveReadableNameForms() {
        let candidates = UsernamePolicy.candidates(
            displayName: "Ömer Salih Pakdil",
            fallbackSeed: "vakt_111bfb5a"
        )

        XCTAssertEqual(candidates.first, "omer_salih_pakdil")
        XCTAssertTrue(candidates.contains("omersalihpakdil"))
        XCTAssertTrue(candidates.contains("omer_pakdil"))
    }

    func testEverySuggestionMatchesDatabaseFormat() {
        let candidates = UsernamePolicy.candidates(
            displayName: "A Very Long Display Name With Several Parts",
            fallbackSeed: "vakt_12345678"
        )

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy(UsernamePolicy.isValid))
        XCTAssertTrue(candidates.allSatisfy { $0.count <= UsernamePolicy.maximumLength })
        XCTAssertEqual(Set(candidates).count, candidates.count)
    }

    func testValidationRejectsUnsupportedUsernameCharacters() {
        XCTAssertTrue(UsernamePolicy.isValid("omer_salih27"))
        XCTAssertFalse(UsernamePolicy.isValid("Ömer Salih"))
        XCTAssertFalse(UsernamePolicy.isValid("ab"))
        XCTAssertFalse(UsernamePolicy.isValid("user.name"))
    }
}
