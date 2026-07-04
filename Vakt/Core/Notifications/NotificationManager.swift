import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var isReminderEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastDeepLink: NotificationDeepLink?

    private static let reminderEnabledKey = "vakt.notifications.remindersEnabled.v1"

    private let center: UNUserNotificationCenter
    private var preferences: NotificationPreferences
    private let scheduler = PrayerNotificationScheduler()

    init(
        center: UNUserNotificationCenter = .current(),
        preferences: NotificationPreferences = .default
    ) {
        self.center = center
        let storedEnabled = UserDefaults.standard.object(forKey: Self.reminderEnabledKey) as? Bool
        self.isReminderEnabled = storedEnabled ?? preferences.enabled
        self.preferences = preferences
        self.preferences.enabled = storedEnabled ?? preferences.enabled
        super.init()
    }

    func start() {
        center.delegate = self
        registerNotificationCategories()
        refreshAuthorizationStatus()
    }

    func schedulePrayerNotifications(
        prayers: [PrayerTime],
        now: Date,
        liveMemberCount: Int,
        quietSoundEnabled: Bool
    ) {
        guard isReminderEnabled else {
            removeScheduledPrayerNotifications()
            return
        }

        Task {
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus

            if !settings.authorizationStatus.allowsPrayerNotifications {
                removeScheduledPrayerNotifications()
                return
            }

            let requests = scheduler.requests(
                prayers: prayers,
                now: now,
                liveMemberCount: liveMemberCount,
                preferences: preferences,
                quietSoundEnabled: quietSoundEnabled
            )

            await replaceScheduledPrayerNotifications(with: requests)
        }
    }

    func requestAuthorization() {
        Task {
            _ = await requestAuthorizationIfNeeded()
        }
    }

    func enableRemindersAndRequestAuthorization() async -> Bool {
        updateReminderPreference(true)
        return await requestAuthorizationIfNeeded()
    }

    func setReminderEnabled(_ isEnabled: Bool) {
        updateReminderPreference(isEnabled)

        if isEnabled {
            requestAuthorization()
        } else {
            removeScheduledPrayerNotifications()
        }
    }

    private func updateReminderPreference(_ isEnabled: Bool) {
        isReminderEnabled = isEnabled
        preferences.enabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.reminderEnabledKey)
    }

    func refreshAuthorizationStatus() {
        Task {
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                refreshAuthorizationStatus()
                return granted
            } catch {
                refreshAuthorizationStatus()
                return false
            }
        @unknown default:
            return false
        }
    }

    private func registerNotificationCategories() {
        let joinSafAction = UNNotificationAction(
            identifier: PrayerNotificationScheduler.joinSafActionIdentifier,
            title: "Join the Saf",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: PrayerNotificationScheduler.categoryIdentifier,
            actions: [joinSafAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }

    private func replaceScheduledPrayerNotifications(with requests: [UNNotificationRequest]) async {
        let pending = await center.pendingNotificationRequests()
        let existingIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(PrayerNotificationScheduler.identifierPrefix) }

        center.removePendingNotificationRequests(withIdentifiers: existingIdentifiers)

        for request in requests {
            do {
                try await center.add(request)
            } catch {
                continue
            }
        }
    }

    private func removeScheduledPrayerNotifications() {
        Task {
            let pending = await center.pendingNotificationRequests()
            let pendingIdentifiers = pending
                .map(\.identifier)
                .filter { $0.hasPrefix(PrayerNotificationScheduler.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)

            let delivered = await center.deliveredNotifications()
            let deliveredIdentifiers = delivered
                .map(\.request.identifier)
                .filter { $0.hasPrefix(PrayerNotificationScheduler.identifierPrefix) }
            center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let shouldPlaySound = (userInfo["playsSound"] as? Bool) ?? false
        return shouldPlaySound ? [.banner, .sound] : [.banner]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard
            let rawPrayer = userInfo["prayer"] as? String,
            let prayer = Prayer(rawValue: rawPrayer)
        else {
            return
        }

        await MainActor.run {
            lastDeepLink = .saf(prayer)
        }
    }
}

extension UNAuthorizationStatus {
    var allowsPrayerNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}

enum NotificationDeepLink: Equatable {
    case saf(Prayer)
}

struct NotificationPreferences {
    var enabled: Bool
    var safOpeningEnabled: Bool
    var prayerTimeEnabled: Bool
    var fajrWakeEnabled: Bool
    var minutesBeforePrayer: Int
    var fajrWakeMinutesBefore: Int
    var enabledPrayers: Set<Prayer>

    static let `default` = NotificationPreferences(
        enabled: true,
        safOpeningEnabled: true,
        prayerTimeEnabled: true,
        fajrWakeEnabled: true,
        minutesBeforePrayer: 10,
        fajrWakeMinutesBefore: 30,
        enabledPrayers: Set(Prayer.allCases)
    )
}

struct PrayerNotificationScheduler {
    static let identifierPrefix = "vakt.prayer."
    static let categoryIdentifier = "VAKT_PRAYER"
    static let joinSafActionIdentifier = "VAKT_JOIN_SAF"

    func requests(
        prayers: [PrayerTime],
        now: Date,
        liveMemberCount: Int,
        preferences: NotificationPreferences,
        quietSoundEnabled: Bool
    ) -> [UNNotificationRequest] {
        let futurePrayers = prayers
            .filter { $0.time > now }
            .sorted { $0.time < $1.time }
            .prefix(5)

        return futurePrayers.flatMap { prayerTime in
            requests(
                for: prayerTime,
                now: now,
                liveMemberCount: liveMemberCount,
                preferences: preferences,
                quietSoundEnabled: quietSoundEnabled
            )
        }
    }

    private func requests(
        for prayerTime: PrayerTime,
        now: Date,
        liveMemberCount: Int,
        preferences: NotificationPreferences,
        quietSoundEnabled: Bool
    ) -> [UNNotificationRequest] {
        guard preferences.enabledPrayers.contains(prayerTime.prayer) else { return [] }

        var requests: [UNNotificationRequest] = []

        if preferences.safOpeningEnabled {
            let openDate = prayerTime.time.addingTimeInterval(TimeInterval(-preferences.minutesBeforePrayer * 60))
            if let request = request(
                type: .safOpening,
                prayerTime: prayerTime,
                fireDate: openDate,
                now: now,
                liveMemberCount: liveMemberCount,
                minutesBefore: preferences.minutesBeforePrayer,
                quietSoundEnabled: quietSoundEnabled
            ) {
                requests.append(request)
            }
        }

        if preferences.prayerTimeEnabled {
            if let request = request(
                type: .prayerTime,
                prayerTime: prayerTime,
                fireDate: prayerTime.time,
                now: now,
                liveMemberCount: liveMemberCount,
                minutesBefore: 0,
                quietSoundEnabled: quietSoundEnabled
            ) {
                requests.append(request)
            }
        }

        if prayerTime.prayer == .fajr, preferences.fajrWakeEnabled {
            let wakeDate = prayerTime.time.addingTimeInterval(TimeInterval(-preferences.fajrWakeMinutesBefore * 60))
            if let request = request(
                type: .fajrWake,
                prayerTime: prayerTime,
                fireDate: wakeDate,
                now: now,
                liveMemberCount: liveMemberCount,
                minutesBefore: preferences.fajrWakeMinutesBefore,
                quietSoundEnabled: quietSoundEnabled
            ) {
                requests.append(request)
            }
        }

        return requests
    }

    private func request(
        type: PrayerNotificationType,
        prayerTime: PrayerTime,
        fireDate: Date,
        now: Date,
        liveMemberCount: Int,
        minutesBefore: Int,
        quietSoundEnabled: Bool
    ) -> UNNotificationRequest? {
        guard fireDate.timeIntervalSince(now) > 5 else { return nil }

        let content = UNMutableNotificationContent()
        content.title = type.title(for: prayerTime.prayer, minutesBefore: minutesBefore)
        content.body = type.body(for: prayerTime.prayer, liveMemberCount: liveMemberCount, minutesBefore: minutesBefore)
        let sound = type.sound(quietSoundEnabled: quietSoundEnabled)
        content.sound = sound
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "vakt.prayer.\(prayerTime.prayer.rawValue)"
        content.userInfo = [
            "deepLink": "saf",
            "type": type.rawValue,
            "prayer": prayerTime.prayer.rawValue,
            "fireDate": fireDate.timeIntervalSince1970,
            "playsSound": sound != nil
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prayerTime.timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        components.timeZone = prayerTime.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = Self.identifier(type: type, prayerTime: prayerTime, fireDate: fireDate)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private static func identifier(
        type: PrayerNotificationType,
        prayerTime: PrayerTime,
        fireDate: Date
    ) -> String {
        let timestamp = Int(fireDate.timeIntervalSince1970)
        return "\(identifierPrefix)\(type.rawValue).\(prayerTime.prayer.rawValue).\(timestamp)"
    }
}

private enum PrayerNotificationType: String {
    case safOpening
    case prayerTime
    case fajrWake

    func title(for prayer: Prayer, minutesBefore: Int) -> String {
        switch self {
        case .safOpening:
            return "\(prayer.displayName) is near"
        case .prayerTime:
            return "\(prayer.displayName) has entered"
        case .fajrWake:
            return "Fajr is near"
        }
    }

    func body(for prayer: Prayer, liveMemberCount: Int, minutesBefore: Int) -> String {
        let companionCount = max(liveMemberCount - 1, 6)

        switch self {
        case .safOpening:
            return "\(companionCount) others are preparing for \(prayer.displayName). Join the Saf when you are ready."
        case .prayerTime:
            return "It is time for salah. Put the phone away when you are ready."
        case .fajrWake:
            return "\(companionCount) others are waking for Fajr. The Saf gathers in \(minutesBefore) minutes."
        }
    }

    func sound(quietSoundEnabled: Bool) -> UNNotificationSound? {
        guard quietSoundEnabled else { return nil }

        switch self {
        case .safOpening, .fajrWake:
            return .default
        case .prayerTime:
            return nil
        }
    }
}
