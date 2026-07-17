import XCTest
@testable import Vakt

final class ReviewPromptPolicyTests: XCTestCase {
    func testDoesNotPromptBeforeFirstThreshold() {
        let policy = ReviewPromptPolicy(firstPromptDelay: 0)
        let now = Date(timeIntervalSince1970: 10_000)
        let state = ReviewPromptState.fresh(now: now.addingTimeInterval(-1_000))

        XCTAssertFalse(
            policy.shouldPresent(
                completionCount: 1,
                state: state,
                now: now
            )
        )
    }

    func testPromptsAtFirstThresholdAfterDelay() {
        let policy = ReviewPromptPolicy(firstPromptDelay: 60)
        let now = Date(timeIntervalSince1970: 10_000)
        let state = ReviewPromptState.fresh(now: now.addingTimeInterval(-120))

        XCTAssertTrue(
            policy.shouldPresent(
                completionCount: 2,
                state: state,
                now: now
            )
        )
    }

    func testDoesNotPromptAgainForSameThreshold() {
        let policy = ReviewPromptPolicy(firstPromptDelay: 0)
        let now = Date(timeIntervalSince1970: 10_000)
        let state = ReviewPromptState(
            installedAt: now.addingTimeInterval(-1_000),
            lastPromptedAt: now.addingTimeInterval(-900),
            lastNativeRequestAt: nil,
            lastPromptedCompletionCount: 2,
            dismissalCount: 1
        )

        XCTAssertFalse(
            policy.shouldPresent(
                completionCount: 3,
                state: state,
                now: now
            )
        )
    }

    func testWaitsForCooldownBeforeNextThreshold() {
        let policy = ReviewPromptPolicy(
            firstPromptDelay: 0,
            dismissalCooldown: 100,
            nativeRequestCooldown: 1_000
        )
        let now = Date(timeIntervalSince1970: 10_000)
        let state = ReviewPromptState(
            installedAt: now.addingTimeInterval(-2_000),
            lastPromptedAt: now.addingTimeInterval(-40),
            lastNativeRequestAt: nil,
            lastPromptedCompletionCount: 2,
            dismissalCount: 1
        )

        XCTAssertFalse(
            policy.shouldPresent(
                completionCount: 4,
                state: state,
                now: now
            )
        )
    }

    func testAllowsNextThresholdAfterCooldown() {
        let policy = ReviewPromptPolicy(
            firstPromptDelay: 0,
            dismissalCooldown: 100,
            nativeRequestCooldown: 1_000
        )
        let now = Date(timeIntervalSince1970: 10_000)
        let state = ReviewPromptState(
            installedAt: now.addingTimeInterval(-2_000),
            lastPromptedAt: now.addingTimeInterval(-140),
            lastNativeRequestAt: nil,
            lastPromptedCompletionCount: 2,
            dismissalCount: 1
        )

        XCTAssertTrue(
            policy.shouldPresent(
                completionCount: 4,
                state: state,
                now: now
            )
        )
    }

    func testWaitsLongerAfterNativeReviewRequest() {
        let policy = ReviewPromptPolicy(
            firstPromptDelay: 0,
            dismissalCooldown: 100,
            nativeRequestCooldown: 1_000
        )
        let now = Date(timeIntervalSince1970: 10_000)
        let state = ReviewPromptState(
            installedAt: now.addingTimeInterval(-2_000),
            lastPromptedAt: now.addingTimeInterval(-500),
            lastNativeRequestAt: now.addingTimeInterval(-500),
            lastPromptedCompletionCount: 4,
            dismissalCount: 0
        )

        XCTAssertFalse(
            policy.shouldPresent(
                completionCount: 7,
                state: state,
                now: now
            )
        )
    }
}
