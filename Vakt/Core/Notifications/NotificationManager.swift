import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var isReminderEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastDeepLink: NotificationDeepLink?
    @Published private(set) var lastPrayerAction: PrayerNotificationAction?
    @Published private(set) var preferences: NotificationPreferences
    @Published private(set) var pendingPrayerNotificationCount = 0
    @Published private(set) var lastSchedulingError: String?

    var reminderState: ReminderState {
        ReminderState(
            preferenceEnabled: isReminderEnabled,
            authorizationStatus: authorizationStatus
        )
    }

    var areRemindersActive: Bool {
        reminderState == .enabled
    }

    private static let reminderEnabledKey = "vakt.notifications.remindersEnabled.v1"
    private static let preferencesKey = "vakt.notifications.preferences.v2"

    private let center: UNUserNotificationCenter
    private let scheduler = PrayerNotificationScheduler()
    private var schedulingGeneration = 0

    init(
        center: UNUserNotificationCenter = .current(),
        preferences: NotificationPreferences = .default
    ) {
        self.center = center
        let storedPreferences = UserDefaults.standard.data(forKey: Self.preferencesKey)
            .flatMap { try? JSONDecoder().decode(NotificationPreferences.self, from: $0) }
        var resolvedPreferences = storedPreferences ?? preferences
        if resolvedPreferences.checkInMinutesBeforeNextPrayer == 15 {
            resolvedPreferences.checkInMinutesBeforeNextPrayer = 20
        }
        let storedEnabled = UserDefaults.standard.object(forKey: Self.reminderEnabledKey) as? Bool
        let resolvedEnabled = storedEnabled ?? resolvedPreferences.enabled
        resolvedPreferences.enabled = resolvedEnabled
        self.preferences = resolvedPreferences
        self.isReminderEnabled = resolvedEnabled
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

        // Keep the last valid schedule while location and prayer times are loading.
        guard !prayers.isEmpty else { return }

        schedulingGeneration += 1
        let generation = schedulingGeneration

        Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            guard generation == schedulingGeneration else { return }
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

            await replaceScheduledPrayerNotifications(with: requests, generation: generation)
        }
    }

    func enableRemindersAndRequestAuthorization() async -> Bool {
        let authorized = await requestAuthorizationIfNeeded()
        updateReminderPreference(authorized)
        if !authorized {
            removeScheduledPrayerNotifications()
        }
        return authorized
    }

    func setReminderEnabled(_ isEnabled: Bool) {
        if isEnabled {
            Task {
                _ = await enableRemindersAndRequestAuthorization()
            }
        } else {
            updateReminderPreference(false)
            removeScheduledPrayerNotifications()
        }
    }

    func setPrayerOpeningEnabled(_ isEnabled: Bool) {
        updatePreferences { $0.prayerOpeningEnabled = isEnabled }
    }

    func setPrayerTimeEnabled(_ isEnabled: Bool) {
        updatePreferences { $0.prayerTimeEnabled = isEnabled }
    }

    func setFajrWakeEnabled(_ isEnabled: Bool) {
        updatePreferences { $0.fajrWakeEnabled = isEnabled }
    }

    func setCheckInEnabled(_ isEnabled: Bool) {
        updatePreferences { $0.checkInEnabled = isEnabled }
    }

    private func updateReminderPreference(_ isEnabled: Bool) {
        isReminderEnabled = isEnabled
        preferences.enabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.reminderEnabledKey)
        persistPreferences()
    }

    private func updatePreferences(_ update: (inout NotificationPreferences) -> Void) {
        update(&preferences)
        persistPreferences()
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.preferencesKey)
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
                let updatedSettings = await center.notificationSettings()
                authorizationStatus = updatedSettings.authorizationStatus
                return granted
            } catch {
                let updatedSettings = await center.notificationSettings()
                authorizationStatus = updatedSettings.authorizationStatus
                return false
            }
        @unknown default:
            return false
        }
    }

    private func registerNotificationCategories() {
        let openPrayerAction = UNNotificationAction(
            identifier: PrayerNotificationScheduler.openPrayerActionIdentifier,
            title: L10n.string("notification.action.open_prayer"),
            options: [.foreground]
        )

        let prayedAction = UNNotificationAction(
            identifier: PrayerNotificationScheduler.markPrayedActionIdentifier,
            title: L10n.string("notification.action.prayed"),
            options: []
        )

        let missedAction = UNNotificationAction(
            identifier: PrayerNotificationScheduler.markMissedActionIdentifier,
            title: L10n.string("notification.action.missed"),
            options: []
        )

        let prayerCategory = UNNotificationCategory(
            identifier: PrayerNotificationScheduler.categoryIdentifier,
            actions: [openPrayerAction],
            intentIdentifiers: [],
            options: []
        )

        let checkInCategory = UNNotificationCategory(
            identifier: PrayerNotificationScheduler.checkInCategoryIdentifier,
            actions: [prayedAction, missedAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([prayerCategory, checkInCategory])
    }

    private func replaceScheduledPrayerNotifications(
        with requests: [UNNotificationRequest],
        generation: Int
    ) async {
        let pending = await center.pendingNotificationRequests()
        guard generation == schedulingGeneration else { return }
        let existingIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(PrayerNotificationScheduler.identifierPrefix) }

        center.removePendingNotificationRequests(withIdentifiers: existingIdentifiers)

        var scheduledCount = 0
        var schedulingErrors: [String] = []
        for request in requests {
            guard generation == schedulingGeneration else { return }
            do {
                try await center.add(request)
                scheduledCount += 1
            } catch {
                schedulingErrors.append(error.localizedDescription)
            }
        }

        guard generation == schedulingGeneration else { return }
        pendingPrayerNotificationCount = scheduledCount
        lastSchedulingError = schedulingErrors.first
    }

    private func removeScheduledPrayerNotifications() {
        schedulingGeneration += 1
        pendingPrayerNotificationCount = 0
        lastSchedulingError = nil
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

        if userInfo["deep_link"] as? String == "circle" {
            await MainActor.run {
                lastDeepLink = .circle
            }
            return
        }

        if userInfo["deep_link"] as? String == "profile" {
            await MainActor.run {
                lastDeepLink = .profile
            }
            return
        }

        guard
            let rawPrayer = userInfo["prayer"] as? String,
            let prayer = Prayer(rawValue: rawPrayer)
        else {
            return
        }

        let prayerDate = (userInfo["prayerTime"] as? TimeInterval).map {
            Date(timeIntervalSince1970: $0)
        }

        await MainActor.run {
            switch response.actionIdentifier {
            case PrayerNotificationScheduler.markPrayedActionIdentifier:
                lastPrayerAction = PrayerNotificationAction(
                    prayer: prayer,
                    prayerDate: prayerDate,
                    outcome: .prayed
                )
            case PrayerNotificationScheduler.markMissedActionIdentifier:
                lastPrayerAction = PrayerNotificationAction(
                    prayer: prayer,
                    prayerDate: prayerDate,
                    outcome: .missed
                )
            default:
                lastDeepLink = .prayer(prayer)
            }
        }
    }
}

enum ReminderState: Equatable {
    case notRequested
    case enabled
    case paused
    case denied

    init(preferenceEnabled: Bool, authorizationStatus: UNAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            self = .notRequested
        case .denied:
            self = .denied
        case .authorized, .provisional, .ephemeral:
            self = preferenceEnabled ? .enabled : .paused
        @unknown default:
            self = .denied
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
    case prayer(Prayer)
    case circle
    case profile
}

struct PrayerNotificationAction: Equatable {
    let id = UUID()
    let prayer: Prayer
    let prayerDate: Date?
    let outcome: PrayerReflectionOutcome
}

struct NotificationPreferences: Codable, Equatable {
    var enabled: Bool
    var prayerOpeningEnabled: Bool
    var prayerTimeEnabled: Bool
    var fajrWakeEnabled: Bool
    var checkInEnabled: Bool
    var minutesBeforePrayer: Int
    var fajrWakeMinutesBefore: Int
    var checkInMinutesBeforeNextPrayer: Int
    var enabledPrayers: Set<Prayer>

    static let `default` = NotificationPreferences(
        enabled: true,
        prayerOpeningEnabled: true,
        prayerTimeEnabled: true,
        fajrWakeEnabled: true,
        checkInEnabled: true,
        minutesBeforePrayer: 10,
        fajrWakeMinutesBefore: 30,
        checkInMinutesBeforeNextPrayer: 20,
        enabledPrayers: Set(Prayer.allCases)
    )
}

struct PrayerNotificationScheduler {
    static let identifierPrefix = "vakt.prayer."
    static let categoryIdentifier = "VAKT_PRAYER"
    static let checkInCategoryIdentifier = "VAKT_PRAYER_CHECK_IN"
    static let openPrayerActionIdentifier = "VAKT_OPEN_PRAYER"
    static let markPrayedActionIdentifier = "VAKT_MARK_PRAYED"
    static let markMissedActionIdentifier = "VAKT_MARK_MISSED"

    func requests(
        prayers: [PrayerTime],
        now: Date,
        liveMemberCount: Int,
        preferences: NotificationPreferences,
        quietSoundEnabled: Bool
    ) -> [UNNotificationRequest] {
        let sortedPrayers = prayers.sorted { $0.time < $1.time }
        let firstFutureIndex = sortedPrayers.firstIndex { $0.time > now } ?? sortedPrayers.endIndex
        let startIndex = firstFutureIndex > sortedPrayers.startIndex
            ? sortedPrayers.index(before: firstFutureIndex)
            : firstFutureIndex
        let futurePrayers = Array(sortedPrayers[startIndex...].prefix(7))

        return futurePrayers.enumerated().flatMap { index, prayerTime in
            requests(
                for: prayerTime,
                nextPrayerTime: futurePrayers.indices.contains(index + 1) ? futurePrayers[index + 1] : nil,
                now: now,
                liveMemberCount: liveMemberCount,
                preferences: preferences,
                quietSoundEnabled: quietSoundEnabled
            )
        }
    }

    private func requests(
        for prayerTime: PrayerTime,
        nextPrayerTime: PrayerTime?,
        now: Date,
        liveMemberCount: Int,
        preferences: NotificationPreferences,
        quietSoundEnabled: Bool
    ) -> [UNNotificationRequest] {
        guard preferences.enabledPrayers.contains(prayerTime.prayer) else { return [] }

        var requests: [UNNotificationRequest] = []

        if preferences.prayerOpeningEnabled {
            let openDate = prayerTime.time.addingTimeInterval(TimeInterval(-preferences.minutesBeforePrayer * 60))
            if let request = request(
                type: .prayerOpening,
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

        if preferences.checkInEnabled,
           let closesAt = prayerTime.endsAt ?? nextPrayerTime?.time {
            let checkInDate = closesAt.addingTimeInterval(TimeInterval(-preferences.checkInMinutesBeforeNextPrayer * 60))
            if checkInDate > prayerTime.time,
               let request = request(
                type: .prayerCheckIn,
                prayerTime: prayerTime,
                fireDate: checkInDate,
                now: now,
                liveMemberCount: liveMemberCount,
                minutesBefore: preferences.checkInMinutesBeforeNextPrayer,
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
        content.categoryIdentifier = type == .prayerCheckIn
            ? Self.checkInCategoryIdentifier
            : Self.categoryIdentifier
        content.threadIdentifier = "vakt.prayer.\(prayerTime.prayer.rawValue)"
        content.userInfo = [
            "deepLink": "prayer",
            "type": type.rawValue,
            "prayer": prayerTime.prayer.rawValue,
            "prayerTime": prayerTime.time.timeIntervalSince1970,
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
    case prayerOpening
    case prayerTime
    case fajrWake
    case prayerCheckIn

    func title(for prayer: Prayer, minutesBefore: Int) -> String {
        switch self {
        case .prayerOpening:
            return L10n.notificationTitle(type: .prayerOpening, prayer: prayer, minutesBefore: minutesBefore)
        case .prayerTime:
            return L10n.notificationTitle(type: .prayerTime, prayer: prayer, minutesBefore: minutesBefore)
        case .fajrWake:
            return L10n.notificationTitle(type: .fajrWake, prayer: prayer, minutesBefore: minutesBefore)
        case .prayerCheckIn:
            return L10n.formatString("notification.checkin.title", prayer.localizedName)
        }
    }

    func body(for prayer: Prayer, liveMemberCount: Int, minutesBefore: Int) -> String {
        let companionCount = max(liveMemberCount - 1, 6)

        switch self {
        case .prayerOpening:
            return L10n.notificationBody(
                type: .prayerOpening,
                prayer: prayer,
                companionCount: companionCount,
                minutesBefore: minutesBefore
            )
        case .prayerTime:
            return L10n.notificationBody(
                type: .prayerTime,
                prayer: prayer,
                companionCount: companionCount,
                minutesBefore: minutesBefore
            )
        case .fajrWake:
            return L10n.notificationBody(
                type: .fajrWake,
                prayer: prayer,
                companionCount: companionCount,
                minutesBefore: minutesBefore
            )
        case .prayerCheckIn:
            return L10n.formatString("notification.checkin.body", prayer.localizedName)
        }
    }

    func sound(quietSoundEnabled: Bool) -> UNNotificationSound? {
        guard quietSoundEnabled else { return nil }

        switch self {
        case .prayerOpening, .fajrWake:
            return .default
        case .prayerTime, .prayerCheckIn:
            return nil
        }
    }
}
