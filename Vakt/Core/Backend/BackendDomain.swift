import Foundation

struct BackendUserID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct PrayerSessionID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct PresenceLeaseID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

enum PrayerKey: String, Codable, CaseIterable, Hashable, Sendable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    init(_ prayer: Prayer) {
        switch prayer {
        case .fajr: self = .fajr
        case .dhuhr: self = .dhuhr
        case .asr: self = .asr
        case .maghrib: self = .maghrib
        case .isha: self = .isha
        }
    }
}

struct LocalPrayerDay: Codable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    var databaseValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

struct PrayerSessionScope: Codable, Hashable, Sendable {
    let prayer: PrayerKey
    let localDay: LocalPrayerDay
    let timeZoneIdentifier: String

    init(prayer: Prayer, prayerTime: Date, calendar: Calendar) {
        self.prayer = PrayerKey(prayer)
        localDay = LocalPrayerDay(date: prayerTime, calendar: calendar)
        timeZoneIdentifier = calendar.timeZone.identifier
    }
}

struct PrayerSessionRequest: Codable, Hashable, Sendable {
    let scope: PrayerSessionScope
    let expectedPrayerTime: Date
}

enum PrayerSessionPhase: String, Codable, Hashable, Sendable {
    case upcoming
    case open
    case closed
}

struct BackendPrayerSession: Codable, Identifiable, Hashable, Sendable {
    let id: PrayerSessionID
    let scope: PrayerSessionScope
    let opensAt: Date
    let prayerTime: Date
    let closesAt: Date

    func phase(at serverTime: Date) -> PrayerSessionPhase {
        if serverTime < opensAt { return .upcoming }
        if serverTime >= closesAt { return .closed }
        return .open
    }
}

enum BackendPresenceStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case gettingUp = "getting_up"
    case makingWudu = "making_wudu"
    case joiningSaf = "joining_saf"
    case ready
    case praying

    init(_ status: PrepStatus) {
        switch status {
        case .gettingUp: self = .gettingUp
        case .wudu: self = .makingWudu
        case .findingPlace: self = .joiningSaf
        case .ready: self = .ready
        case .praying: self = .praying
        }
    }
}

struct PresenceCounts: Codable, Equatable, Sendable {
    var gettingUp: Int
    var makingWudu: Int
    var joiningSaf: Int
    var ready: Int
    var praying: Int

    static let zero = PresenceCounts(
        gettingUp: 0,
        makingWudu: 0,
        joiningSaf: 0,
        ready: 0,
        praying: 0
    )

    var total: Int {
        gettingUp + makingWudu + joiningSaf + ready + praying
    }

    subscript(status: BackendPresenceStatus) -> Int {
        get {
            switch status {
            case .gettingUp: gettingUp
            case .makingWudu: makingWudu
            case .joiningSaf: joiningSaf
            case .ready: ready
            case .praying: praying
            }
        }
        set {
            switch status {
            case .gettingUp: gettingUp = max(0, newValue)
            case .makingWudu: makingWudu = max(0, newValue)
            case .joiningSaf: joiningSaf = max(0, newValue)
            case .ready: ready = max(0, newValue)
            case .praying: praying = max(0, newValue)
            }
        }
    }
}

enum PresenceSnapshotSource: String, Codable, Hashable, Sendable {
    case realtime
    case cached
    case localSimulation
}

struct PresenceSnapshot: Codable, Equatable, Sendable {
    let sessionID: PrayerSessionID
    let counts: PresenceCounts
    let observedAt: Date
    let source: PresenceSnapshotSource
    let isStale: Bool

    var participantCount: Int { counts.total }
}

struct PresenceLease: Codable, Equatable, Sendable {
    let id: PresenceLeaseID
    let sessionID: PrayerSessionID
    let status: BackendPresenceStatus
    let expiresAt: Date
}

struct PresenceMutation: Codable, Equatable, Sendable {
    let commandID: UUID
    let sessionID: PrayerSessionID
    let clientInstanceID: UUID
    let status: BackendPresenceStatus
    let createdAt: Date
}

enum BackendConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case offline
    case failed(BackendError)
}

enum BackendError: Error, Equatable, Sendable {
    case notConfigured
    case invalidConfiguration(message: String)
    case unauthenticated
    case forbidden
    case offline
    case rateLimited(retryAfter: TimeInterval?)
    case conflict
    case sessionUnavailable
    case invalidResponse
    case server(message: String)
    case cancelled
}

extension BackendError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Backend is not configured."
        case let .invalidConfiguration(message): message
        case .unauthenticated: "An anonymous session could not be created."
        case .forbidden: "This action is not allowed."
        case .offline: "The network is unavailable."
        case .rateLimited: "Please wait before trying again."
        case .conflict: "The request conflicts with an existing operation."
        case .sessionUnavailable: "The prayer session is not available."
        case .invalidResponse: "The server returned an invalid response."
        case let .server(message): message
        case .cancelled: "The request was cancelled."
        }
    }
}
