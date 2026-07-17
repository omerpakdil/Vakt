import Foundation

struct ReviewPromptState: Codable, Equatable {
    var installedAt: Date
    var lastPromptedAt: Date?
    var lastNativeRequestAt: Date?
    var lastPromptedCompletionCount: Int
    var dismissalCount: Int

    static func fresh(now: Date) -> ReviewPromptState {
        ReviewPromptState(
            installedAt: now,
            lastPromptedAt: nil,
            lastNativeRequestAt: nil,
            lastPromptedCompletionCount: 0,
            dismissalCount: 0
        )
    }
}

struct ReviewPromptPolicy {
    let thresholds: [Int]
    let firstPromptDelay: TimeInterval
    let dismissalCooldown: TimeInterval
    let nativeRequestCooldown: TimeInterval

    init(
        thresholds: [Int] = [2, 4, 7, 12, 20, 35, 60, 100],
        firstPromptDelay: TimeInterval = 6 * 60 * 60,
        dismissalCooldown: TimeInterval = 14 * 24 * 60 * 60,
        nativeRequestCooldown: TimeInterval = 120 * 24 * 60 * 60
    ) {
        self.thresholds = thresholds.sorted()
        self.firstPromptDelay = firstPromptDelay
        self.dismissalCooldown = dismissalCooldown
        self.nativeRequestCooldown = nativeRequestCooldown
    }

    func eligibleThreshold(for completionCount: Int) -> Int? {
        thresholds.last { completionCount >= $0 }
    }

    func shouldPresent(
        completionCount: Int,
        state: ReviewPromptState,
        now: Date
    ) -> Bool {
        guard let threshold = eligibleThreshold(for: completionCount) else { return false }
        guard threshold > state.lastPromptedCompletionCount else { return false }
        guard now.timeIntervalSince(state.installedAt) >= firstPromptDelay else { return false }

        if let lastPromptedAt = state.lastPromptedAt,
           now.timeIntervalSince(lastPromptedAt) < dismissalCooldown {
            return false
        }

        if let lastNativeRequestAt = state.lastNativeRequestAt,
           now.timeIntervalSince(lastNativeRequestAt) < nativeRequestCooldown {
            return false
        }

        return true
    }
}

@MainActor
final class ReviewPromptStore: ObservableObject {
    @Published private(set) var isPromptPresented = false

    private static let storageKey = "vakt.review.prompt.state.v1"
    private let defaults: UserDefaults
    private let policy: ReviewPromptPolicy
    private var state: ReviewPromptState

    init(
        defaults: UserDefaults = .standard,
        policy: ReviewPromptPolicy = ReviewPromptPolicy(),
        now: Date = Date()
    ) {
        self.defaults = defaults
        self.policy = policy

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ReviewPromptState.self, from: data) {
            self.state = decoded
        } else {
            self.state = .fresh(now: now)
            Self.persist(self.state, defaults: defaults)
        }
    }

    func considerPrompt(completedPrayerCount: Int, now: Date = Date()) {
        guard !isPromptPresented else { return }
        guard policy.shouldPresent(completionCount: completedPrayerCount, state: state, now: now) else { return }

        isPromptPresented = true
        state.lastPromptedAt = now
        state.lastPromptedCompletionCount = policy.eligibleThreshold(for: completedPrayerCount) ?? completedPrayerCount
        persist()
    }

    func markNativeReviewRequested(now: Date = Date()) {
        state.lastNativeRequestAt = now
        persist()
        isPromptPresented = false
    }

    func dismissPrompt() {
        state.dismissalCount += 1
        persist()
        isPromptPresented = false
    }

    #if DEBUG
    func presentForDebug() {
        isPromptPresented = true
    }

    func resetForDebug(now: Date = Date()) {
        state = .fresh(now: now)
        persist()
        isPromptPresented = false
    }
    #endif

    private func persist() {
        Self.persist(state, defaults: defaults)
    }

    private static func persist(_ state: ReviewPromptState, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
