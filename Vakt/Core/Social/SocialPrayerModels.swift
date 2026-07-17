import Foundation

struct VaktUserID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct SocialProfile: Identifiable, Codable, Equatable, Sendable {
    let id: VaktUserID
    var displayName: String
    var username: String
    var avatarURL: URL?
    var isPrayerStatusVisible: Bool
}

enum FriendshipStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case accepted
    case blocked
}

struct Friendship: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let requesterID: VaktUserID
    let receiverID: VaktUserID
    var status: FriendshipStatus
    let createdAt: Date
    var updatedAt: Date
}

struct PendingFriendRequest: Identifiable, Equatable, Sendable {
    let friendship: Friendship
    let requester: SocialProfile

    var id: UUID { friendship.id }
}

enum SocialPrayerStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case preparing
    case prayedOnTime = "prayed_on_time"
    case prayedLater = "prayed_later"
    case notMarked = "not_marked"
    case madeUp = "made_up"

    var isVisibleToFriends: Bool {
        switch self {
        case .preparing, .prayedOnTime, .prayedLater, .notMarked:
            true
        case .madeUp:
            false
        }
    }
}

struct SocialPrayerStatusEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let userID: VaktUserID
    let localDay: LocalPrayerDay
    let prayer: PrayerKey
    let timeZoneIdentifier: String
    var status: SocialPrayerStatus
    var markedAt: Date
}

enum MakeupPrayerStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case open
    case completed
}

struct MakeupPrayer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let userID: VaktUserID
    let originalLocalDay: LocalPrayerDay
    let prayer: PrayerKey
    let timeZoneIdentifier: String
    var status: MakeupPrayerStatus
    let createdAt: Date
    var completedAt: Date?
}

struct MakeupPrayerMonth: Hashable, Sendable {
    let year: Int
    let month: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
    }

    var firstDay: LocalPrayerDay {
        LocalPrayerDay(year: year, month: month, day: 1)
    }

    var nextMonthFirstDay: LocalPrayerDay {
        month == 12
            ? LocalPrayerDay(year: year + 1, month: 1, day: 1)
            : LocalPrayerDay(year: year, month: month + 1, day: 1)
    }
}

struct MakeupPrayerDaySummary: Identifiable, Equatable, Sendable {
    let day: LocalPrayerDay
    let prayers: [PrayerKey]

    var id: LocalPrayerDay { day }
    var count: Int { prayers.count }
}

struct PrayerDeadline: Equatable, Sendable {
    let localDay: LocalPrayerDay
    let prayer: PrayerKey
    let timeZoneIdentifier: String
    let prayerAt: Date
    let closesAt: Date
}

enum PrayerDeadlineBuilder {
    static func build(from prayers: [PrayerTime], now: Date) -> [PrayerDeadline] {
        let sorted = prayers.sorted { $0.time < $1.time }
        return zip(sorted, sorted.dropFirst()).compactMap { prayerTime, nextPrayerTime in
            guard nextPrayerTime.time > prayerTime.time, nextPrayerTime.time > now else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = prayerTime.timeZone
            return PrayerDeadline(
                localDay: LocalPrayerDay(date: prayerTime.time, calendar: calendar),
                prayer: PrayerKey(prayerTime.prayer),
                timeZoneIdentifier: prayerTime.timeZone.identifier,
                prayerAt: prayerTime.time,
                closesAt: nextPrayerTime.time
            )
        }
    }
}

struct PrayerNudge: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let fromUserID: VaktUserID
    let toUserID: VaktUserID
    let localDay: LocalPrayerDay
    let prayer: PrayerKey
    let createdAt: Date
}

struct FriendPrayerSummary: Identifiable, Equatable, Sendable {
    let id: VaktUserID
    let profile: SocialProfile
    let statuses: [PrayerKey: SocialPrayerStatus]
    let lastMarkedAt: Date?
}
