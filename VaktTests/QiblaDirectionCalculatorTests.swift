import XCTest
@testable import Vakt

final class QiblaDirectionCalculatorTests: XCTestCase {
    private let calculator = QiblaDirectionCalculator()

    func testBearingFromSanFrancisco() {
        let bearing = calculator.bearingTowardQibla(
            from: Coordinate(latitude: 37.7749, longitude: -122.4194)
        )

        XCTAssertEqual(bearing, 18.8, accuracy: 0.4)
    }

    func testBearingFromIstanbul() {
        let bearing = calculator.bearingTowardQibla(
            from: Coordinate(latitude: 41.0082, longitude: 28.9784)
        )

        XCTAssertEqual(bearing, 151.9, accuracy: 0.4)
    }

    func testSignedAngleUsesShortestTurn() {
        XCTAssertEqual(
            calculator.signedAngleToQibla(qiblaBearing: 10, deviceHeading: 350),
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            calculator.signedAngleToQibla(qiblaBearing: 350, deviceHeading: 10),
            -20,
            accuracy: 0.001
        )
    }

    func testSignedAngleNormalizesOppositeDirection() {
        XCTAssertEqual(
            calculator.signedAngleToQibla(qiblaBearing: 180, deviceHeading: 0),
            180,
            accuracy: 0.001
        )
    }
}
