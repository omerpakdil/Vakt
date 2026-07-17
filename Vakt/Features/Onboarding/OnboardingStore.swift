import Foundation

@MainActor
final class OnboardingStore: ObservableObject {
    static let plannedPageCount = 6

    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var hasPassedSplash = false
    @Published var currentPage: Int = 0

    private static let completionKey = "vakt.onboarding.completed.v1"

    let pages: [OnboardingPage] = OnboardingPage.all

    init(defaults: UserDefaults = .standard) {
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.completionKey)

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--vakt-preview-splash") {
            hasCompletedOnboarding = false
            hasPassedSplash = false
            currentPage = 0
            return
        }

        if let pageArgument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--vakt-onboarding-page=")
        }), let requestedPage = Int(pageArgument.split(separator: "=").last ?? "") {
            hasCompletedOnboarding = false
            hasPassedSplash = true
            currentPage = min(max(0, requestedPage), pages.count - 1)
        }
        #endif
    }

    var isLastPage: Bool {
        currentPage >= pages.count - 1
    }

    func passSplash() {
        hasPassedSplash = true
    }

    func advance() {
        guard !isLastPage else {
            complete()
            return
        }

        currentPage += 1
    }

    func complete(defaults: UserDefaults = .standard) {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.completionKey)
    }

    func reset(defaults: UserDefaults = .standard) {
        hasCompletedOnboarding = false
        hasPassedSplash = false
        currentPage = 0
        defaults.set(false, forKey: Self.completionKey)
    }
}

struct OnboardingPage: Identifiable, Equatable {
    enum Kind {
        case arrival
        case markPrayer
        case friends
        case makeupCalendar
        case closingReminder
        case promise
        case gathering
        case placement
        case anonymousSaf
        case location
        case reminders
    }

    let id: Kind
    let eyebrow: String
    let title: String
    let body: String
    let primaryAction: String
    let secondaryAction: String?

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: .arrival,
            eyebrow: L10n.string("onboarding.arrival.eyebrow"),
            title: L10n.string("onboarding.arrival.title"),
            body: L10n.string("onboarding.arrival.body"),
            primaryAction: L10n.string("action.continue"),
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .markPrayer,
            eyebrow: L10n.string("onboarding.mark_prayer.eyebrow"),
            title: L10n.string("onboarding.mark_prayer.title"),
            body: L10n.string("onboarding.mark_prayer.body"),
            primaryAction: L10n.string("action.continue"),
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .friends,
            eyebrow: L10n.string("onboarding.friends.eyebrow"),
            title: L10n.string("onboarding.friends.title"),
            body: L10n.string("onboarding.friends.body"),
            primaryAction: L10n.string("action.continue"),
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .closingReminder,
            eyebrow: L10n.string("onboarding.closing_reminder.eyebrow"),
            title: L10n.string("onboarding.closing_reminder.title"),
            body: L10n.string("onboarding.closing_reminder.body"),
            primaryAction: L10n.string("action.continue"),
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .makeupCalendar,
            eyebrow: L10n.string("onboarding.makeup_calendar.eyebrow"),
            title: L10n.string("onboarding.makeup_calendar.title"),
            body: L10n.string("onboarding.makeup_calendar.body"),
            primaryAction: L10n.string("action.continue"),
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .promise,
            eyebrow: L10n.string("onboarding.promise.eyebrow"),
            title: L10n.string("onboarding.promise.title"),
            body: L10n.string("onboarding.promise.body"),
            primaryAction: L10n.string("onboarding.promise.action.continue"),
            secondaryAction: nil
        )
    ]
}
