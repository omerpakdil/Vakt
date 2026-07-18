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
    var profileCompletedAt: Date?

    var isComplete: Bool { profileCompletedAt != nil }
}

enum UsernamePolicy {
    static let minimumLength = 3
    static let maximumLength = 24

    static func normalizedInput(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func isValid(_ value: String) -> Bool {
        normalizedInput(value).range(
            of: "^[a-z0-9_]{3,24}$",
            options: .regularExpression
        ) != nil
    }

    static func candidates(displayName: String, fallbackSeed: String) -> [String] {
        let latinName = displayName
            .applyingTransform(.toLatin, reverse: false)?
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased() ?? displayName.lowercased()
        let tokens = latinName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let joined = String(tokens.joined().prefix(20))
        let underscored = String(tokens.joined(separator: "_").prefix(maximumLength))
        let firstLast = tokens.count > 1
            ? String("\(tokens[0])_\(tokens[tokens.count - 1])".prefix(maximumLength))
            : joined
        let base = joined.count >= minimumLength ? joined : "vaktfriend"
        let digits = fallbackSeed.filter(\.isNumber)
        let suffix = String((digits.isEmpty ? fallbackSeed.unicodeScalars.map { Int($0.value) }.reduce(0, +).description : digits).suffix(2))

        return [
            underscored,
            joined,
            firstLast,
            String("\(base.prefix(21))\(suffix)"),
            String("\(base.prefix(20))_\(suffix)")
        ]
        .map(normalizedInput)
        .filter(isValid)
        .uniqued()
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
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

enum FriendshipRequestResult: Equatable, Sendable {
    case sent(Friendship)
    case alreadyPending(Friendship)
    case alreadyFriends(Friendship)
    case incomingRequest(Friendship)
}

enum FriendshipRequestClassifier {
    static func classify(
        _ friendship: Friendship,
        currentUserID: VaktUserID
    ) throws -> FriendshipRequestResult {
        switch friendship.status {
        case .accepted:
            return .alreadyFriends(friendship)
        case .pending where friendship.requesterID == currentUserID:
            return .alreadyPending(friendship)
        case .pending:
            return .incomingRequest(friendship)
        case .blocked:
            throw BackendError.forbidden
        }
    }
}

enum FriendshipRequestFeedback: Equatable {
    case sent(SocialProfile)
    case alreadyPending(SocialProfile)
    case alreadyFriends(SocialProfile)
    case incomingRequest(SocialProfile)

    var profile: SocialProfile {
        switch self {
        case .sent(let profile),
             .alreadyPending(let profile),
             .alreadyFriends(let profile),
             .incomingRequest(let profile):
            profile
        }
    }
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
            let closesAt = prayerTime.endsAt ?? nextPrayerTime.time
            guard closesAt > prayerTime.time, closesAt > now else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = prayerTime.timeZone
            return PrayerDeadline(
                localDay: LocalPrayerDay(date: prayerTime.time, calendar: calendar),
                prayer: PrayerKey(prayerTime.prayer),
                timeZoneIdentifier: prayerTime.timeZone.identifier,
                prayerAt: prayerTime.time,
                closesAt: closesAt
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
