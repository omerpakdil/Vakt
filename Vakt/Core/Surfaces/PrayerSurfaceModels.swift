import Foundation

enum PrayerSurfacePrayerID: String, CaseIterable, Codable, Hashable, Sendable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha
}

enum PrayerSurfacePhase: String, Codable, Equatable, Sendable {
    case upcoming
    case approaching
    case entered
    case quiet
    case completed
    case expired
}

enum PrayerSurfaceStatus: String, Codable, Equatable, Sendable {
    case unmarked
    case notYet
    case prayed
    case later
    case missed
    case quiet
}

enum PrayerSurfaceAtmosphere: String, Codable, Equatable, Sendable {
    case night
    case dawn
    case morning
    case midday
    case afternoon
    case sunset
}

struct PrayerSurfacePrayer: Codable, Equatable, Identifiable, Sendable {
    let prayer: PrayerSurfacePrayerID
    let startsAt: Date
    let endsAt: Date?
    let timeZoneIdentifier: String
    let status: PrayerSurfaceStatus

    var id: String {
        "\(prayer.rawValue)-\(startsAt.timeIntervalSince1970)"
    }
}

struct PrayerSurfaceSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let phase: PrayerSurfacePhase
    let currentPrayer: PrayerSurfacePrayer?
    let nextPrayer: PrayerSurfacePrayer?
    let schedule: [PrayerSurfacePrayer]
    let atmosphere: PrayerSurfaceAtmosphere
    let hasPendingActions: Bool

    init(
        generatedAt: Date,
        phase: PrayerSurfacePhase,
        currentPrayer: PrayerSurfacePrayer?,
        nextPrayer: PrayerSurfacePrayer?,
        schedule: [PrayerSurfacePrayer],
        atmosphere: PrayerSurfaceAtmosphere,
        hasPendingActions: Bool = false
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.phase = phase
        self.currentPrayer = currentPrayer
        self.nextPrayer = nextPrayer
        self.schedule = schedule
        self.atmosphere = atmosphere
        self.hasPendingActions = hasPendingActions
    }
}

struct PrayerSurfaceAction: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case markPrayed
        case markNotYet
        case startSalah
    }

    let id: UUID
    let kind: Kind
    let prayer: PrayerSurfacePrayerID
    let prayerDate: Date
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        prayer: PrayerSurfacePrayerID,
        prayerDate: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.prayer = prayer
        self.prayerDate = prayerDate
        self.createdAt = createdAt
    }
}
