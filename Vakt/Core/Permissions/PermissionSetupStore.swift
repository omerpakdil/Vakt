import Foundation
import UserNotifications

@MainActor
final class PermissionSetupStore: ObservableObject {
    enum Step: Equatable {
        case location
        case notifications
    }

    @Published private(set) var hasMadeNotificationDecision: Bool

    private static let notificationDecisionKey = "vakt.permissions.notificationDecision.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasMadeNotificationDecision = defaults.bool(forKey: Self.notificationDecisionKey)
    }

    func nextStep(
        hasUsablePrayerSchedule: Bool,
        notificationStatus: UNAuthorizationStatus
    ) -> Step? {
        guard hasUsablePrayerSchedule else { return .location }

        if notificationStatus == .notDetermined, !hasMadeNotificationDecision {
            return .notifications
        }

        return nil
    }

    func completeNotificationDecision() {
        hasMadeNotificationDecision = true
        defaults.set(true, forKey: Self.notificationDecisionKey)
    }
}
