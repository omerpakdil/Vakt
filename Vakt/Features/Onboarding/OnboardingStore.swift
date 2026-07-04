import Foundation

@MainActor
final class OnboardingStore: ObservableObject {
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var hasPassedSplash = false
    @Published var currentPage: Int = 0

    private static let completionKey = "vakt.onboarding.completed.v1"

    let pages: [OnboardingPage] = OnboardingPage.all

    init(defaults: UserDefaults = .standard) {
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.completionKey)

        #if DEBUG
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
            eyebrow: "Vakt",
            title: "Keep the next salah close.",
            body: "See the time, notice the Saf gathering, and come to prayer with a little more ease.",
            primaryAction: "Continue",
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .gathering,
            eyebrow: "Before Salah",
            title: "The Saf gathers in its own time.",
            body: "Share where you are as salah draws near, without conversation or interruption.",
            primaryAction: "Continue",
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .placement,
            eyebrow: "Join the Saf",
            title: "Choose where you will join.",
            body: "Select an open place, then continue toward salah.",
            primaryAction: "Continue",
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .anonymousSaf,
            eyebrow: "Saf Privacy",
            title: "Stand together, stay private.",
            body: "You’re here with the Saf, while your name and profile stay with you. Your worship stays between you and Allah.",
            primaryAction: "Continue",
            secondaryAction: nil
        ),
        OnboardingPage(
            id: .location,
            eyebrow: "Local Time",
            title: "Let prayer times meet your day.",
            body: "Approximate location helps Vakt find your local salah times. Your exact location is never shown.",
            primaryAction: "Use Location",
            secondaryAction: "Not Now"
        ),
        OnboardingPage(
            id: .reminders,
            eyebrow: "Prayer reminders",
            title: "A gentle reminder, then quiet.",
            body: "Vakt can remind you before salah and stay silent when it is time to pray. You can pause reminders anytime from My Vakt.",
            primaryAction: "Allow Prayer Reminders",
            secondaryAction: "Continue for now"
        )
    ]
}
