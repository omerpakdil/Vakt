import Foundation
import SwiftUI

enum VaktLocalization {
    static let supportedLanguageCodes: [String] = [
        "en", "tr", "ar", "fr", "de", "es", "it", "nl", "pt", "ru", "id", "ur"
    ]

    static var languageCode: String {
        languageCode(for: Locale.autoupdatingCurrent)
    }

    static var appLocale: Locale {
        Locale(identifier: languageCode)
    }

    static var layoutDirection: LayoutDirection {
        isRightToLeft(languageCode) ? .rightToLeft : .leftToRight
    }

    static func languageCode(for locale: Locale) -> String {
        let candidates = Locale.preferredLanguages + [locale.identifier]

        for candidate in candidates {
            let normalized = candidate
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()

            if let exact = supportedLanguageCodes.first(where: { normalized == $0 }) {
                return exact
            }

            if let prefix = normalized.split(separator: "-").first,
               supportedLanguageCodes.contains(String(prefix)) {
                return String(prefix)
            }
        }

        return "en"
    }

    static func isRightToLeft(_ languageCode: String = Self.languageCode) -> Bool {
        ["ar", "ur"].contains(languageCode)
    }
}

enum L10n {
    static func string(_ key: String) -> String {
        value(for: key)
    }

    static func text(_ key: Key) -> String {
        value(for: key.rawValue)
    }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: VaktLocalization.appLocale, arguments: arguments)
    }

    static func formatString(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: VaktLocalization.appLocale, arguments: arguments)
    }

    static func prayerName(_ prayer: Prayer) -> String {
        value(for: "prayer.\(prayer.storageKey)")
    }

    static func prepStatusTitle(_ status: PrepStatus) -> String {
        value(for: "prep.\(status.localizationKey).title")
    }

    static func prepStatusShortLabel(_ status: PrepStatus) -> String {
        value(for: "prep.\(status.localizationKey).short")
    }

    static func prepStatusCategory(_ status: PrepStatus) -> String {
        value(for: "prep.\(status.localizationKey).category")
    }

    static func timeRemaining(minutes: Int) -> String {
        if minutes >= 60 {
            return format(.timeRemainingHoursMinutes, minutes / 60, minutes % 60)
        }

        if minutes == 1 {
            return text(.timeRemainingOneMinute)
        }

        return format(.timeRemainingMinutes, max(1, minutes))
    }

    static func notificationTitle(type: PrayerNotificationKind, prayer: Prayer, minutesBefore: Int) -> String {
        switch type {
        case .prayerOpening:
            return format(.notificationPrayerNearTitle, prayer.localizedName, minutesBefore)
        case .prayerTime:
            return format(.notificationPrayerEnteredTitle, prayer.localizedName)
        case .fajrWake:
            return format(.notificationFajrNearTitle, Prayer.fajr.localizedName, minutesBefore)
        }
    }

    static func notificationBody(
        type: PrayerNotificationKind,
        prayer: Prayer,
        companionCount: Int,
        minutesBefore: Int
    ) -> String {
        switch type {
        case .prayerOpening:
            return format(.notificationSafOpeningBody, prayer.localizedName)
        case .prayerTime:
            return text(.notificationPrayerTimeBody)
        case .fajrWake:
            return format(.notificationFajrWakeBody, Prayer.fajr.localizedName, minutesBefore)
        }
    }

    private static func value(for key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: VaktLocalization.appLocale
        )
    }
}

extension L10n {
    enum Key: String {
        case joinSaf = "join_saf"
        case yourStatus = "your_status"
        case setStatusAccessibility = "set_status_accessibility"
        case noOneHereYet = "no_one_here_yet"
        case horizonEmptyBody = "horizon_empty_body"
        case horizonEmptyAccessibility = "horizon_empty_accessibility"
        case horizonLegendPreparing = "horizon.legend.preparing"
        case horizonLegendReady = "horizon.legend.ready"
        case horizonLegendYou = "horizon.legend.you"
        case horizonPresenceAccessibility = "horizon.presence.accessibility"
        case tabHome = "tab.home"
        case tabPrayer = "tab.prayer"
        case tabCircle = "tab.circle"
        case tabMoments = "tab.moments"
        case tabProfile = "tab.profile"
        case loading = "loading"
        case offlineSafPresence = "offline_saf_presence"
        case offlineSafPresenceAccessibility = "offline_saf_presence_accessibility"
        case timeRemainingHourUnit = "time_remaining_hour_unit"
        case timeRemainingMinuteRemainingUnit = "time_remaining_minute_remaining_unit"
        case minuteRemainingSuffix = "minute_remaining_suffix"
        case minutesRemainingSuffix = "minutes_remaining_suffix"
        case timeRemainingOneMinute = "time_remaining_one_minute"
        case timeRemainingMinutes = "time_remaining_minutes"
        case timeRemainingHoursMinutes = "time_remaining_hours_minutes"
        case timeRemainingAccessibility = "time_remaining_accessibility"
        case notificationPrayerNearTitle = "notification.prayer_near.title"
        case notificationPrayerEnteredTitle = "notification.prayer_entered.title"
        case notificationFajrNearTitle = "notification.fajr_near.title"
        case notificationSafOpeningBody = "notification.saf_opening.body"
        case notificationPrayerTimeBody = "notification.prayer_time.body"
        case notificationFajrWakeBody = "notification.fajr_wake.body"
        case qibla = "qibla"
        case qiblaFaceDirectionTitle = "qibla_face_direction_title"
        case qiblaAhead = "qibla_ahead"
        case qiblaTurnRight = "qibla_turn_right"
        case qiblaTurnLeft = "qibla_turn_left"
        case qiblaDegreesRight = "qibla_degrees_right"
        case qiblaDegreesLeft = "qibla_degrees_left"
        case qiblaFacingSteady = "qibla_facing_steady"
        case qiblaIsDegreesRight = "qibla_is_degrees_right"
        case qiblaIsDegreesLeft = "qibla_is_degrees_left"
        case qiblaFindTitle = "qibla_find_title"
        case qiblaFindingTitle = "qibla_finding_title"
        case qiblaCalibratingTitle = "qibla_calibrating_title"
        case qiblaLocationOffTitle = "qibla_location_off_title"
        case qiblaUnavailableTitle = "qibla_unavailable_title"
        case qiblaFailedTitle = "qibla_failed_title"
        case qiblaPreparingTitle = "qibla_preparing_title"
        case qiblaReadyTitle = "qibla_ready_title"
        case qiblaPermissionMessage = "qibla_permission_message"
        case qiblaLocatingMessage = "qibla_locating_message"
        case qiblaCalibratingMessage = "qibla_calibrating_message"
        case qiblaDeniedMessage = "qibla_denied_message"
        case qiblaUnavailableMessage = "qibla_unavailable_message"
        case qiblaIdleMessage = "qibla_idle_message"
        case qiblaReadyMessage = "qibla_ready_message"
        case qiblaDialSteady = "qibla.dial.steady"
        case qiblaDialToQibla = "qibla.dial.to_qibla"
        case qiblaMetricBearing = "qibla.metric.bearing"
        case qiblaMetricDistance = "qibla.metric.distance"
        case qiblaMetricSignal = "qibla.metric.signal"
        case qiblaDistanceThousandsKm = "qibla.distance.thousands_km"
        case qiblaDistanceKm = "qibla.distance.km"
        case qiblaSignalGood = "qibla.signal.good"
        case qiblaSignalFair = "qibla.signal.fair"
        case qiblaSignalLow = "qibla.signal.low"
        case qiblaSignalCalm = "qibla.signal.calm"
        case qiblaSavedLocationHelper = "qibla.helper.saved_location"
        case qiblaPoorSignalHelper = "qibla.helper.poor_signal"
        case qiblaDefaultHelper = "qibla.helper.default"
        case useLocation = "use_location"
        case openSettings = "open_settings"
        case closeQiblaFinder = "close_qibla_finder"
        case moveAwayFromMetal = "move_away_from_metal"
        case locationPermissionUsage = "location_permission_usage"
        case appStoreSubtitle = "app_store.subtitle"
        case appStoreKeywords = "app_store.keywords"
        case preparingVakt = "preparing_vakt"
    }
}

enum PrayerNotificationKind {
    case prayerOpening
    case prayerTime
    case fajrWake
}

private extension Prayer {
    var storageKey: String {
        rawValue.lowercased()
    }
}

extension PrepStatus {
    var localizationKey: String {
        switch self {
        case .gettingUp: "getting_up"
        case .wudu: "wudu"
        case .findingPlace: "joining_saf"
        case .ready: "ready"
        case .praying: "in_salah"
        }
    }
}
