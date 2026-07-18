import Foundation
import CoreLocation
import SwiftUI

enum Prayer: String, CaseIterable, Identifiable, Codable {
    case fajr = "Fajr"
    case dhuhr = "Dhuhr"
    case asr = "Asr"
    case maghrib = "Maghrib"
    case isha = "Isha"

    var id: String { rawValue }

    var displayName: String { localizedName }

    var localizedName: String {
        L10n.prayerName(self)
    }
}

enum PrepStatus: String, CaseIterable, Identifiable, Codable {
    case gettingUp = "Getting up"
    case wudu = "Making wudu"
    case findingPlace = "Joining the Saf"
    case ready = "Ready"
    case praying = "In Salah"

    var id: String { rawValue }

    var dotRadius: CGFloat {
        switch self {
        case .gettingUp: 4
        case .wudu: 5
        case .findingPlace: 5
        case .ready: 6
        case .praying: 7
        }
    }

    var dotColor: Color {
        switch self {
        case .gettingUp: .vaktSurface
        case .wudu: .vaktElevated
        case .findingPlace: .vaktElevated
        case .ready: .vaktAccent
        case .praying: .vaktPrimary
        }
    }

    var borderColor: Color? {
        switch self {
        case .gettingUp: .vaktAccent
        case .wudu: .vaktGlow
        case .findingPlace: .vaktGlow
        case .ready: nil
        case .praying: nil
        }
    }

    var shortLabel: String {
        L10n.prepStatusShortLabel(self)
    }

    var localizedTitle: String {
        L10n.prepStatusTitle(self)
    }
}

struct SafMember: Identifiable {
    let id: UUID
    let normalizedPosition: CGFloat
    let status: PrepStatus
    let isCurrentUser: Bool

    var dotRadius: CGFloat {
        isCurrentUser ? 6 : status.dotRadius
    }

    var dotColor: Color {
        isCurrentUser ? .vaktPrimary : status.dotColor
    }

    var borderColor: Color? {
        status.borderColor
    }
}

struct Saf: Identifiable {
    let id: UUID
    let name: String
    let prayer: Prayer
    let members: [SafMember]
    let isSmall: Bool

    var memberCount: Int { members.count }

    var readyCount: Int {
        members.filter { $0.status == .ready || $0.status == .praying }.count
    }
}

@MainActor
final class LiveSafPresenceStore: ObservableObject {
    @Published private(set) var memberCount: Int
    @Published private(set) var ambientMemberCount: Int
    @Published private(set) var lastEvent: LiveSafPresenceEvent?
    @Published private(set) var connectionState: BackendConnectionState = .idle
    @Published private(set) var snapshotSource: PresenceSnapshotSource = .localSimulation

    private let coordinator: PresenceCoordinator
    private var hasStarted = false
    private var joinedStatus: PrepStatus?
    private var eventIndex = 0
    private var eventClearTask: Task<Void, Never>?
    private var ambientTask: Task<Void, Never>?
    private var ambientCountDirection = 1

    convenience init(initialCount: Int) {
        self.init(
            initialCount: initialCount,
            sessions: LocalPrayerSessionRepository(),
            presence: SimulatedPresenceRepository(initialCount: initialCount)
        )
    }

    init(
        initialCount: Int,
        sessions: any PrayerSessionRepository,
        presence: any PresenceRepository,
        minimumInitialCount: Int = PresenceHorizonLayout.minimumDisplayedCount,
        initialSource: PresenceSnapshotSource = .localSimulation
    ) {
        memberCount = max(initialCount, minimumInitialCount)
        ambientMemberCount = SafPresenceDisplayPolicy.initialAmbientCount
        snapshotSource = initialSource
        coordinator = PresenceCoordinator(
            sessions: sessions,
            presence: presence
        )
    }

    var countDirection: Int {
        if memberCount <= SafPresenceDisplayPolicy.realCountThreshold {
            return ambientCountDirection
        }
        guard let lastEvent else { return 1 }
        return lastEvent.direction == .joined ? 1 : -1
    }

    var displayMemberCount: Int {
        SafPresenceDisplayPolicy.displayedCount(
            realCount: memberCount,
            ambientCount: ambientMemberCount
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        coordinator.onSnapshot = { [weak self] snapshot in
            self?.receive(snapshot)
        }
        coordinator.onConnectionStateChange = { [weak self] state in
            self?.connectionState = state
        }
        startAmbientCount()
    }

    func updatePrayerContext(_ prayerTime: PrayerTime) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prayerTime.timeZone
        let scope = PrayerSessionScope(
            prayer: prayerTime.prayer,
            prayerTime: prayerTime.time,
            calendar: calendar
        )
        coordinator.observe(
            PrayerSessionRequest(scope: scope, expectedPrayerTime: prayerTime.time)
        )
        if let joinedStatus {
            coordinator.join(status: BackendPresenceStatus(joinedStatus))
        }
    }

    func join(status: PrepStatus) {
        joinedStatus = status
        coordinator.join(status: BackendPresenceStatus(status))
    }

    func updateStatus(_ status: PrepStatus) {
        guard joinedStatus != nil else { return }
        joinedStatus = status
        coordinator.updateStatus(BackendPresenceStatus(status))
    }

    func leave() {
        joinedStatus = nil
        coordinator.leave()
    }

    func stop() {
        joinedStatus = nil
        ambientTask?.cancel()
        ambientTask = nil
        coordinator.stop()
    }

    private func startAmbientCount() {
        guard ambientTask == nil else { return }

        ambientTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 5.0...13.5)))
                guard !Task.isCancelled, let self else { return }
                guard memberCount <= SafPresenceDisplayPolicy.realCountThreshold else { continue }

                let current = ambientMemberCount
                let next = SafPresenceDisplayPolicy.nextAmbientCount(
                    from: current,
                    roll: Int.random(in: 0..<100)
                )
                ambientCountDirection = next > current ? 1 : -1
                ambientMemberCount = next
            }
        }
    }

    private func receive(_ snapshot: PresenceSnapshot) {
        snapshotSource = snapshot.source
        let observedCount = max(0, snapshot.participantCount)
        let nextCount = snapshot.source == .localSimulation
            ? min(observedCount, SafPresenceDisplayPolicy.realCountThreshold)
            : observedCount
        let resolvedChange = nextCount - memberCount
        guard resolvedChange != 0 else { return }

        eventIndex += 1
        let event = LiveSafPresenceEvent(
            id: UUID(),
            direction: resolvedChange > 0 ? .joined : .left,
            magnitude: abs(resolvedChange),
            anchor: LiveSafPresenceEvent.anchor(for: eventIndex),
            companionIndex: eventIndex,
            createdAt: Date()
        )

        memberCount = nextCount
        lastEvent = event

        eventClearTask?.cancel()
        eventClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard !Task.isCancelled else { return }
            if self?.lastEvent?.id == event.id {
                self?.lastEvent = nil
            }
        }
    }
}

struct LiveSafPresenceEvent: Equatable {
    enum Direction {
        case joined
        case left
    }

    let id: UUID
    let direction: Direction
    let magnitude: Int
    let anchor: CGFloat
    let companionIndex: Int
    let createdAt: Date

    static func anchor(for index: Int) -> CGFloat {
        let anchors: [CGFloat] = [0.28, 0.72, 0.18, 0.82, 0.38, 0.62]
        return anchors[index % anchors.count]
    }
}

struct PrayerTime: Identifiable, Codable {
    let prayer: Prayer
    let time: Date
    let countdown: TimeInterval
    let timeZoneIdentifier: String?
    let endsAt: Date?

    init(
        prayer: Prayer,
        time: Date,
        countdown: TimeInterval,
        timeZoneIdentifier: String? = nil,
        endsAt: Date? = nil
    ) {
        self.prayer = prayer
        self.time = time
        self.countdown = countdown
        self.timeZoneIdentifier = timeZoneIdentifier
        self.endsAt = endsAt
    }

    var id: Prayer { prayer }

    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }
}

enum PrayerReflectionOutcome: String, CaseIterable, Codable, Identifiable {
    case prayed
    case later
    case missed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prayed:
            return L10n.string("reflection.outcome.prayed")
        case .later:
            return L10n.string("reflection.outcome.later")
        case .missed:
            return L10n.string("reflection.outcome.missed")
        }
    }

    var symbolName: String {
        switch self {
        case .prayed:
            return "circle.fill"
        case .later:
            return "clock"
        case .missed:
            return "minus"
        }
    }

    var contributesToRhythm: Bool {
        switch self {
        case .prayed, .later:
            return true
        case .missed:
            return false
        }
    }
}

enum PrayerCalculationMethodPreference: String, CaseIterable, Codable, Identifiable {
    case automatic
    case muslimWorldLeague
    case ummAlQura
    case egyptian
    case diyanet
    case isna

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return L10n.string("calculation.automatic.title")
        case .muslimWorldLeague:
            return L10n.string("calculation.global.title")
        case .ummAlQura:
            return L10n.string("calculation.saudi.title")
        case .egyptian:
            return L10n.string("calculation.egypt.title")
        case .diyanet:
            return L10n.string("calculation.turkey.title")
        case .isna:
            return L10n.string("calculation.north_america.title")
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return L10n.string("calculation.automatic.detail")
        case .muslimWorldLeague:
            return L10n.string("calculation.global.detail")
        case .ummAlQura:
            return L10n.string("calculation.saudi.detail")
        case .egyptian:
            return L10n.string("calculation.egypt.detail")
        case .diyanet:
            return L10n.string("calculation.turkey.detail")
        case .isna:
            return L10n.string("calculation.north_america.detail")
        }
    }
}

enum AsrJuristicPreference: String, CaseIterable, Codable, Identifiable {
    case standard
    case hanafi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return L10n.string("asr.standard.title")
        case .hanafi:
            return L10n.string("asr.hanafi.title")
        }
    }

    var detail: String {
        switch self {
        case .standard:
            return L10n.string("asr.standard.detail")
        case .hanafi:
            return L10n.string("asr.hanafi.detail")
        }
    }

    var alAdhanSchoolValue: Int {
        switch self {
        case .standard:
            return 0
        case .hanafi:
            return 1
        }
    }
}

struct PrayerCalculationSettings: Equatable {
    let methodPreference: PrayerCalculationMethodPreference
    let asrJuristicPreference: AsrJuristicPreference

    static let `default` = PrayerCalculationSettings(
        methodPreference: .automatic,
        asrJuristicPreference: .standard
    )
}

@MainActor
final class ProfileSettingsStore: ObservableObject {
    @Published var anonymousSafEnabled: Bool {
        didSet { persist() }
    }
    @Published var approximateLocationOnly: Bool {
        didSet { persist() }
    }
    @Published var quietNotificationSoundEnabled: Bool {
        didSet { persist() }
    }
    @Published var prayerCalculationMethod: PrayerCalculationMethodPreference {
        didSet { persist() }
    }
    @Published var asrJuristicMethod: AsrJuristicPreference {
        didSet { persist() }
    }

    private static let storageKey = "vakt.profile.settings.v1"

    init(defaults: UserDefaults = .standard) {
        if
            let data = defaults.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode(ProfileSettingsSnapshot.self, from: data)
        {
            self.anonymousSafEnabled = stored.anonymousSafEnabled
            self.approximateLocationOnly = stored.approximateLocationOnly
            self.quietNotificationSoundEnabled = stored.quietNotificationSoundEnabled
            self.prayerCalculationMethod = stored.prayerCalculationMethod
            self.asrJuristicMethod = stored.asrJuristicMethod
        } else {
            self.anonymousSafEnabled = true
            self.approximateLocationOnly = true
            self.quietNotificationSoundEnabled = true
            self.prayerCalculationMethod = .automatic
            self.asrJuristicMethod = .standard
        }
    }

    var prayerCalculationSettings: PrayerCalculationSettings {
        PrayerCalculationSettings(
            methodPreference: prayerCalculationMethod,
            asrJuristicPreference: asrJuristicMethod
        )
    }

    func resetToDefaults() {
        anonymousSafEnabled = true
        approximateLocationOnly = true
        quietNotificationSoundEnabled = true
        prayerCalculationMethod = .automatic
        asrJuristicMethod = .standard
    }

    private func persist(defaults: UserDefaults = .standard) {
        let snapshot = ProfileSettingsSnapshot(
            anonymousSafEnabled: anonymousSafEnabled,
            approximateLocationOnly: approximateLocationOnly,
            quietNotificationSoundEnabled: quietNotificationSoundEnabled,
            prayerCalculationMethod: prayerCalculationMethod,
            asrJuristicMethod: asrJuristicMethod
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

private struct ProfileSettingsSnapshot: Codable {
    let anonymousSafEnabled: Bool
    let approximateLocationOnly: Bool
    let quietNotificationSoundEnabled: Bool
    let prayerCalculationMethod: PrayerCalculationMethodPreference
    let asrJuristicMethod: AsrJuristicPreference

    enum CodingKeys: String, CodingKey {
        case anonymousSafEnabled
        case approximateLocationOnly
        case quietNotificationSoundEnabled
        case prayerCalculationMethod
        case asrJuristicMethod
    }

    init(
        anonymousSafEnabled: Bool,
        approximateLocationOnly: Bool,
        quietNotificationSoundEnabled: Bool,
        prayerCalculationMethod: PrayerCalculationMethodPreference,
        asrJuristicMethod: AsrJuristicPreference
    ) {
        self.anonymousSafEnabled = anonymousSafEnabled
        self.approximateLocationOnly = approximateLocationOnly
        self.quietNotificationSoundEnabled = quietNotificationSoundEnabled
        self.prayerCalculationMethod = prayerCalculationMethod
        self.asrJuristicMethod = asrJuristicMethod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.anonymousSafEnabled = try container.decodeIfPresent(Bool.self, forKey: .anonymousSafEnabled) ?? true
        self.approximateLocationOnly = try container.decodeIfPresent(Bool.self, forKey: .approximateLocationOnly) ?? true
        self.quietNotificationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietNotificationSoundEnabled) ?? true
        self.prayerCalculationMethod = try container.decodeIfPresent(PrayerCalculationMethodPreference.self, forKey: .prayerCalculationMethod) ?? .automatic
        self.asrJuristicMethod = try container.decodeIfPresent(AsrJuristicPreference.self, forKey: .asrJuristicMethod) ?? .standard
    }
}

struct PrayerReflectionEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let prayer: Prayer
    let prayerDate: Date
    let checkedInAt: Date
    let quietStartedAt: Date
    let quietEndedAt: Date
    let companionCount: Int
    let outcome: PrayerReflectionOutcome

    init(
        id: UUID = UUID(),
        prayer: Prayer,
        prayerDate: Date,
        checkedInAt: Date,
        quietStartedAt: Date,
        quietEndedAt: Date,
        companionCount: Int,
        outcome: PrayerReflectionOutcome
    ) {
        self.id = id
        self.prayer = prayer
        self.prayerDate = prayerDate
        self.checkedInAt = checkedInAt
        self.quietStartedAt = quietStartedAt
        self.quietEndedAt = quietEndedAt
        self.companionCount = max(0, companionCount)
        self.outcome = outcome
    }
}

enum PrayerSessionRole: String, Codable, Equatable {
    case primary
    case additional
}

enum PrayerSessionReflectionState: String, Codable, Equatable {
    case pending
    case recorded
    case skipped
    case notNeeded
}

struct PrayerQuietSession: Identifiable, Codable, Equatable {
    let id: UUID
    let prayer: Prayer
    let prayerDate: Date
    let startedAt: Date
    var endedAt: Date?
    var companionCount: Int
    let role: PrayerSessionRole
    var reflectionState: PrayerSessionReflectionState

    init(
        id: UUID = UUID(),
        prayer: Prayer,
        prayerDate: Date,
        startedAt: Date,
        endedAt: Date? = nil,
        companionCount: Int,
        role: PrayerSessionRole,
        reflectionState: PrayerSessionReflectionState? = nil
    ) {
        self.id = id
        self.prayer = prayer
        self.prayerDate = prayerDate
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.companionCount = max(0, companionCount)
        self.role = role
        self.reflectionState = reflectionState ?? (role == .primary ? .pending : .notNeeded)
    }

    var isOpen: Bool {
        endedAt == nil
    }
}

enum PrayerSessionStatus: Equatable {
    case ready
    case inProgress(startedAt: Date)
    case primaryCompleted(additionalCount: Int)
}

enum PrayerTrackingStatus: Equatable {
    case ready
    case inProgress(startedAt: Date)
    case prayed
    case later
    case missed
}

@MainActor
final class PrayerSessionStore: ObservableObject {
    @Published private(set) var sessions: [PrayerQuietSession] = []

    private static let storageKey = "vakt.prayer.sessions.v1"
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        restore()
    }

    func status(for prayerTime: PrayerTime) -> PrayerSessionStatus {
        let key = occurrenceKey(for: prayerTime.prayer, on: prayerTime.time)

        if let openSession = sessions.last(where: { session in
            occurrenceKey(for: session.prayer, on: session.prayerDate) == key && session.isOpen
        }) {
            return .inProgress(startedAt: openSession.startedAt)
        }

        guard hasCompletedPrimarySession(for: key) else {
            return .ready
        }

        let additionalCount = sessions.filter { session in
            occurrenceKey(for: session.prayer, on: session.prayerDate) == key &&
            session.role == .additional &&
            session.endedAt != nil
        }.count

        return .primaryCompleted(additionalCount: additionalCount)
    }

    func beginSession(
        for prayerTime: PrayerTime,
        companionCount: Int,
        startedAt: Date = Date()
    ) -> PrayerQuietSession {
        let key = occurrenceKey(for: prayerTime.prayer, on: prayerTime.time)

        if let openSession = sessions.last(where: { session in
            occurrenceKey(for: session.prayer, on: session.prayerDate) == key && session.isOpen
        }) {
            return openSession
        }

        let role: PrayerSessionRole = hasAnyPrimarySession(for: key) ? .additional : .primary
        let session = PrayerQuietSession(
            prayer: prayerTime.prayer,
            prayerDate: prayerTime.time,
            startedAt: startedAt,
            companionCount: companionCount,
            role: role
        )

        var updatedSessions = sessions
        updatedSessions.append(session)
        updatedSessions.sort { $0.startedAt < $1.startedAt }
        sessions = updatedSessions
        persist()
        return session
    }

    @discardableResult
    func markPrayerCompleted(
        for prayerTime: PrayerTime,
        at date: Date = Date()
    ) -> PrayerQuietSession {
        let key = occurrenceKey(for: prayerTime.prayer, on: prayerTime.time)
        var updatedSessions = sessions

        if let completedPrimaryIndex = updatedSessions.lastIndex(where: { session in
            occurrenceKey(for: session.prayer, on: session.prayerDate) == key &&
            session.role == .primary &&
            session.endedAt != nil
        }) {
            return updatedSessions[completedPrimaryIndex]
        }

        if let openPrimaryIndex = updatedSessions.lastIndex(where: { session in
            occurrenceKey(for: session.prayer, on: session.prayerDate) == key &&
            session.role == .primary &&
            session.isOpen
        }) {
            updatedSessions[openPrimaryIndex].endedAt = date
            updatedSessions[openPrimaryIndex].companionCount = 0
            updatedSessions[openPrimaryIndex].reflectionState = .skipped
            sessions = updatedSessions
            persist()
            return updatedSessions[openPrimaryIndex]
        }

        let session = PrayerQuietSession(
            prayer: prayerTime.prayer,
            prayerDate: prayerTime.time,
            startedAt: date,
            endedAt: date,
            companionCount: 0,
            role: .primary,
            reflectionState: .skipped
        )

        updatedSessions.append(session)
        updatedSessions.sort { $0.startedAt < $1.startedAt }
        sessions = updatedSessions
        persist()
        return session
    }

    @discardableResult
    func completeSession(
        id: PrayerQuietSession.ID,
        endedAt: Date = Date(),
        companionCount: Int
    ) -> PrayerQuietSession? {
        var updatedSessions = sessions
        guard let index = updatedSessions.firstIndex(where: { $0.id == id }) else { return nil }

        updatedSessions[index].endedAt = endedAt
        updatedSessions[index].companionCount = max(0, companionCount)
        sessions = updatedSessions
        persist()
        return sessions[index]
    }

    func session(with id: PrayerQuietSession.ID) -> PrayerQuietSession? {
        sessions.first { $0.id == id }
    }

    func shouldRequestReflection(for id: PrayerQuietSession.ID) -> Bool {
        guard let session = session(with: id) else { return false }
        return session.role == .primary &&
        session.endedAt != nil &&
        session.reflectionState == .pending
    }

    func markReflectionRecorded(for id: PrayerQuietSession.ID) {
        updateReflectionState(.recorded, for: id)
    }

    func markReflectionSkipped(for id: PrayerQuietSession.ID) {
        updateReflectionState(.skipped, for: id)
    }

    func clear() {
        sessions.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func updateReflectionState(_ state: PrayerSessionReflectionState, for id: PrayerQuietSession.ID) {
        var updatedSessions = sessions
        guard let index = updatedSessions.firstIndex(where: { $0.id == id }) else { return }
        updatedSessions[index].reflectionState = state
        sessions = updatedSessions
        persist()
    }

    private func hasAnyPrimarySession(for key: String) -> Bool {
        sessions.contains { session in
            occurrenceKey(for: session.prayer, on: session.prayerDate) == key &&
            session.role == .primary
        }
    }

    private func hasCompletedPrimarySession(for key: String) -> Bool {
        sessions.contains { session in
            occurrenceKey(for: session.prayer, on: session.prayerDate) == key &&
            session.role == .primary &&
            session.endedAt != nil
        }
    }

    private func restore() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode([PrayerQuietSession].self, from: data)
        else {
            return
        }

        sessions = decoded.sorted { $0.startedAt < $1.startedAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func occurrenceKey(for prayer: Prayer, on date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(prayer.rawValue)"
    }
}

enum ReflectionPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week:
            return L10n.string("period.week")
        case .month:
            return L10n.string("period.month")
        case .year:
            return L10n.string("period.year")
        }
    }
}

struct ReflectionPeriodBucket: Identifiable {
    let id: Date
    let date: Date
    let label: String
    let rhythmCount: Int
    let totalCount: Int
    let maxPossible: Int

    var fillRatio: CGFloat {
        guard maxPossible > 0 else { return 0 }
        return CGFloat(min(rhythmCount, maxPossible)) / CGFloat(maxPossible)
    }
}

struct ReflectionPeriodSummary {
    let period: ReflectionPeriod
    let buckets: [ReflectionPeriodBucket]
    let entries: [PrayerReflectionEntry]
    let startsAt: Date
    let endsAt: Date

    var startedTogetherCount: Int {
        entries.filter { $0.outcome == .prayed }.count
    }

    var reflectedCount: Int {
        entries.count
    }

    var laterCount: Int {
        entries.filter { $0.outcome == .later }.count
    }

    var rhythmCount: Int {
        entries.filter(\.outcome.contributesToRhythm).count
    }

    var missedCount: Int {
        entries.filter { $0.outcome == .missed }.count
    }

    var largestHorizonCount: Int? {
        entries.map(\.companionCount).max()
    }

    var averageCompanionCount: Int? {
        guard !entries.isEmpty else { return nil }
        let total = entries.map(\.companionCount).reduce(0, +)
        return Int((Double(total) / Double(entries.count)).rounded())
    }

    var mostGatheredPrayer: Prayer? {
        let grouped = Dictionary(grouping: entries, by: \.prayer)
        return grouped.max { lhs, rhs in
            lhs.value.map(\.companionCount).reduce(0, +) < rhs.value.map(\.companionCount).reduce(0, +)
        }?.key
    }

    var completionRatio: Double {
        let possible = buckets.map(\.maxPossible).reduce(0, +)
        guard possible > 0 else { return 0 }
        return Double(rhythmCount) / Double(possible)
    }
}

@MainActor
final class PrayerReflectionStore: ObservableObject {
    @Published private(set) var entries: [PrayerReflectionEntry] = []

    private static let storageKey = "vakt.prayer.reflections.v1"
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        restore()
    }

    func record(
        prayer: Prayer,
        prayerDate: Date,
        outcome: PrayerReflectionOutcome,
        companionCount: Int,
        quietStartedAt: Date,
        quietEndedAt: Date,
        checkedInAt: Date = Date()
    ) {
        let entry = PrayerReflectionEntry(
            prayer: prayer,
            prayerDate: prayerDate,
            checkedInAt: checkedInAt,
            quietStartedAt: quietStartedAt,
            quietEndedAt: quietEndedAt,
            companionCount: companionCount,
            outcome: outcome
        )
        let key = occurrenceKey(for: prayer, on: prayerDate)

        entries.removeAll { existing in
            occurrenceKey(for: existing.prayer, on: existing.prayerDate) == key
        }
        entries.append(entry)
        entries.sort { $0.prayerDate < $1.prayerDate }
        persist()
    }

    func mark(
        prayer: Prayer,
        prayerDate: Date,
        outcome: PrayerReflectionOutcome,
        markedAt: Date = Date()
    ) {
        record(
            prayer: prayer,
            prayerDate: prayerDate,
            outcome: outcome,
            companionCount: 0,
            quietStartedAt: markedAt,
            quietEndedAt: markedAt,
            checkedInAt: markedAt
        )
    }

    func outcome(for prayerTime: PrayerTime) -> PrayerReflectionOutcome? {
        let key = occurrenceKey(for: prayerTime.prayer, on: prayerTime.time)
        return entries.last { entry in
            occurrenceKey(for: entry.prayer, on: entry.prayerDate) == key
        }?.outcome
    }

    func trackingStatus(
        for prayerTime: PrayerTime,
        sessionStatus: PrayerSessionStatus
    ) -> PrayerTrackingStatus {
        if let outcome = outcome(for: prayerTime) {
            switch outcome {
            case .prayed:
                return .prayed
            case .later:
                return .later
            case .missed:
                return .missed
            }
        }

        switch sessionStatus {
        case .ready:
            return .ready
        case .inProgress(let startedAt):
            return .inProgress(startedAt: startedAt)
        case .primaryCompleted:
            return .prayed
        }
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    var startedTogetherCount: Int {
        entries.filter { $0.outcome == .prayed }.count
    }

    var largestHorizonCount: Int? {
        entries.map(\.companionCount).max()
    }

    var mostGatheredPrayer: Prayer? {
        let grouped = Dictionary(grouping: entries, by: \.prayer)
        return grouped.max { lhs, rhs in
            lhs.value.map(\.companionCount).reduce(0, +) < rhs.value.map(\.companionCount).reduce(0, +)
        }?.key
    }

    var latestEntry: PrayerReflectionEntry? {
        entries.max { $0.checkedInAt < $1.checkedInAt }
    }

    func summary(for period: ReflectionPeriod, endingAt date: Date = Date()) -> ReflectionPeriodSummary {
        let buckets = periodBuckets(for: period, endingAt: date)
        guard let firstDate = buckets.first?.date, let lastDate = buckets.last?.date else {
            return ReflectionPeriodSummary(period: period, buckets: [], entries: [], startsAt: date, endsAt: date)
        }
        let periodEnd = nextBucketBoundary(after: lastDate, period: period)

        let entriesInPeriod = entries.filter { entry in
            entry.prayerDate >= firstDate && entry.prayerDate < periodEnd
        }

        let resolvedBuckets = buckets.map { bucket in
            let nextDate = nextBucketBoundary(after: bucket.date, period: period)
            let bucketEntries = entriesInPeriod.filter { entry in
                entry.prayerDate >= bucket.date && entry.prayerDate < nextDate
            }
            let rhythmCount = bucketEntries.filter(\.outcome.contributesToRhythm).count

            return ReflectionPeriodBucket(
                id: bucket.date,
                date: bucket.date,
                label: bucket.label,
                rhythmCount: rhythmCount,
                totalCount: bucketEntries.count,
                maxPossible: bucket.maxPossible
            )
        }

        return ReflectionPeriodSummary(
            period: period,
            buckets: resolvedBuckets,
            entries: entriesInPeriod,
            startsAt: firstDate,
            endsAt: periodEnd
        )
    }

    private func restore() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode([PrayerReflectionEntry].self, from: data)
        else {
            return
        }

        entries = decoded.sorted { $0.prayerDate < $1.prayerDate }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func occurrenceKey(for prayer: Prayer, on date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(prayer.rawValue)"
    }

    private func periodBuckets(for period: ReflectionPeriod, endingAt date: Date) -> [ReflectionPeriodBucket] {
        switch period {
        case .week:
            return weekBuckets(containing: date)
        case .month:
            return monthDayBuckets(containing: date)
        case .year:
            return yearMonthBuckets(containing: date)
        }
    }

    private func weekBuckets(containing date: Date) -> [ReflectionPeriodBucket] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        let start = interval?.start ?? calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.locale = VaktLocalization.appLocale
        formatter.dateFormat = "EEE"

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let possible = day <= today ? Prayer.allCases.count : 0

            return ReflectionPeriodBucket(
                id: day,
                date: day,
                label: formatter.string(from: day),
                rhythmCount: 0,
                totalCount: 0,
                maxPossible: possible
            )
        }
    }

    private func monthDayBuckets(containing date: Date) -> [ReflectionPeriodBucket] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: date)
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30

        return (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let possible = day <= today ? Prayer.allCases.count : 0

            return ReflectionPeriodBucket(
                id: day,
                date: day,
                label: (offset + 1).formatted(.number.locale(VaktLocalization.appLocale)),
                rhythmCount: 0,
                totalCount: 0,
                maxPossible: possible
            )
        }
    }

    private func yearMonthBuckets(containing date: Date) -> [ReflectionPeriodBucket] {
        let start = calendar.date(from: calendar.dateComponents([.year], from: date)) ?? calendar.startOfDay(for: date)
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
        let currentDay = calendar.component(.day, from: date)
        let formatter = DateFormatter()
        formatter.locale = VaktLocalization.appLocale
        formatter.dateFormat = "MMM"

        return (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
            let range = calendar.range(of: .day, in: .month, for: month)
            let possibleDays: Int
            if month < currentMonth {
                possibleDays = range?.count ?? 30
            } else if calendar.isDate(month, equalTo: currentMonth, toGranularity: .month) {
                possibleDays = currentDay
            } else {
                possibleDays = 0
            }
            let possible = possibleDays * Prayer.allCases.count

            return ReflectionPeriodBucket(
                id: month,
                date: month,
                label: formatter.string(from: month),
                rhythmCount: 0,
                totalCount: 0,
                maxPossible: possible
            )
        }
    }

    private func nextBucketBoundary(after date: Date, period: ReflectionPeriod) -> Date {
        switch period {
        case .week, .month:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .year:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(31 * 86_400)
        }
    }
}

struct DailyPrayerTimes {
    let date: Date
    let times: [PrayerTime]
}

struct Coordinate: Equatable, Codable {
    let latitude: Double
    let longitude: Double
}

enum PrayerScheduleStatus: Equatable {
    case locating
    case loading
    case ready
    case usingSavedTimes
    case denied
    case failed(String)

    var message: String? {
        switch self {
        case .locating:
            return L10n.string("schedule.finding")
        case .loading:
            return L10n.string("schedule.refreshing")
        case .ready:
            return nil
        case .usingSavedTimes:
            return L10n.string("schedule.saved")
        case .denied:
            return L10n.string("schedule.location_needed")
        case .failed:
            return L10n.string("schedule.failed")
        }
    }
}

private struct CachedPrayerSchedule: Codable {
    let coordinate: Coordinate?
    let prayers: [PrayerTime]
    let savedAt: Date
}

protocol PrayerTimeProviding {
    func prayerTimes(
        for date: Date,
        coordinate: Coordinate,
        calculationSettings: PrayerCalculationSettings
    ) async throws -> [PrayerTime]
}

struct AlAdhanPrayerTimeProvider: PrayerTimeProviding {
    func prayerTimes(
        for date: Date,
        coordinate: Coordinate,
        calculationSettings: PrayerCalculationSettings
    ) async throws -> [PrayerTime] {
        let policy = PrayerCalculationPolicy.resolve(
            coordinate: coordinate,
            preference: calculationSettings.methodPreference
        )
        var response = try await request(
            dateString: Self.requestDateString(from: date, timeZone: .autoupdatingCurrent),
            coordinate: coordinate,
            calculationSettings: calculationSettings,
            policy: policy
        )
        let targetTimeZone = TimeZone(identifier: response.data.meta.timezone) ?? .autoupdatingCurrent
        let targetDateString = Self.requestDateString(from: date, timeZone: targetTimeZone)

        if targetDateString != response.data.date.gregorian.date {
            response = try await request(
                dateString: targetDateString,
                coordinate: coordinate,
                calculationSettings: calculationSettings,
                policy: policy,
                timeZoneIdentifier: targetTimeZone.identifier
            )
        }

        if response.data.timings.requiresReferenceLatitude {
            guard abs(coordinate.latitude) >= 48 else {
                throw URLError(.cannotParseResponse)
            }
            response = try await request(
                dateString: targetDateString,
                coordinate: policy.referenceCoordinate(for: coordinate),
                calculationSettings: calculationSettings,
                policy: policy,
                timeZoneIdentifier: targetTimeZone.identifier
            )
            guard !response.data.timings.requiresReferenceLatitude else {
                throw URLError(.cannotParseResponse)
            }
        }

        let timeZone = TimeZone(identifier: response.data.meta.timezone) ?? targetTimeZone
        return try response.data.timings.prayerTimes(for: date, timeZone: timeZone)
    }

    private func request(
        dateString: String,
        coordinate: Coordinate,
        calculationSettings: PrayerCalculationSettings,
        policy: PrayerCalculationPolicy,
        timeZoneIdentifier: String? = nil
    ) async throws -> AlAdhanTimingsResponse {
        var components = URLComponents(string: "https://api.aladhan.com/v1/timings/\(dateString)")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "method", value: String(policy.method.rawValue)),
            URLQueryItem(name: "school", value: String(calculationSettings.asrJuristicPreference.alAdhanSchoolValue)),
            URLQueryItem(name: "latitudeAdjustmentMethod", value: String(policy.latitudeAdjustment.rawValue))
        ]
        if let timeZoneIdentifier {
            components.queryItems?.append(URLQueryItem(name: "timezonestring", value: timeZoneIdentifier))
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(AlAdhanTimingsResponse.self, from: data)
    }

    private static func requestDateString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }
}

enum AlAdhanCalculationMethod: Int {
    case muslimWorldLeague = 3
    case ummAlQura = 4
    case egyptian = 5
    case diyanet = 13
    case isna = 2

    static func method(
        for coordinate: Coordinate,
        preference: PrayerCalculationMethodPreference
    ) -> AlAdhanCalculationMethod {
        switch preference {
        case .automatic:
            break
        case .muslimWorldLeague:
            return .muslimWorldLeague
        case .ummAlQura:
            return .ummAlQura
        case .egyptian:
            return .egyptian
        case .diyanet:
            return .diyanet
        case .isna:
            return .isna
        }

        switch (coordinate.latitude, coordinate.longitude) {
        case (35.8...42.2, 25.6...45.1):
            return .diyanet
        case (16.0...32.5, 34.0...56.0):
            return .ummAlQura
        case (21.0...32.5, 24.0...37.5):
            return .egyptian
        case (24.0...72.0, -170.0 ... -50.0):
            return .isna
        default:
            return .muslimWorldLeague
        }
    }
}

enum AlAdhanLatitudeAdjustmentMethod: Int {
    case middleOfTheNight = 1
    case oneSeventh = 2
    case angleBased = 3
}

struct PrayerCalculationPolicy: Equatable {
    let method: AlAdhanCalculationMethod
    let latitudeAdjustment: AlAdhanLatitudeAdjustmentMethod

    static func resolve(
        coordinate: Coordinate,
        preference: PrayerCalculationMethodPreference
    ) -> PrayerCalculationPolicy {
        PrayerCalculationPolicy(
            method: AlAdhanCalculationMethod.method(for: coordinate, preference: preference),
            latitudeAdjustment: abs(coordinate.latitude) >= 48 ? .oneSeventh : .angleBased
        )
    }

    func referenceCoordinate(for coordinate: Coordinate) -> Coordinate {
        let referenceLatitude = coordinate.latitude < 0 ? -48.5 : 48.5
        return Coordinate(latitude: referenceLatitude, longitude: coordinate.longitude)
    }
}

private struct AlAdhanTimingsResponse: Decodable {
    let data: AlAdhanTimingsData
}

private struct AlAdhanTimingsData: Decodable {
    let timings: AlAdhanTimings
    let date: AlAdhanDate
    let meta: AlAdhanMeta
}

private struct AlAdhanDate: Decodable {
    let gregorian: AlAdhanGregorianDate
}

private struct AlAdhanGregorianDate: Decodable {
    let date: String
}

private struct AlAdhanMeta: Decodable {
    let timezone: String
}

private struct AlAdhanTimings: Decodable {
    let Fajr: String
    let Sunrise: String
    let Dhuhr: String
    let Asr: String
    let Maghrib: String
    let Isha: String

    var requiresReferenceLatitude: Bool {
        guard
            let fajr = clockMinutes(Fajr),
            let sunrise = clockMinutes(Sunrise),
            let dhuhr = clockMinutes(Dhuhr),
            let asr = clockMinutes(Asr),
            let maghrib = clockMinutes(Maghrib)
        else {
            return true
        }

        return !(fajr < sunrise && sunrise < dhuhr && dhuhr < asr && asr < maghrib)
    }

    func prayerTimes(for date: Date, timeZone: TimeZone) throws -> [PrayerTime] {
        let sunrise = try dateTime(value: Sunrise, date: date, timeZone: timeZone)
        var prayers = [
            try prayerTime(.fajr, value: Fajr, date: date, timeZone: timeZone, endsAt: sunrise),
            try prayerTime(.dhuhr, value: Dhuhr, date: date, timeZone: timeZone),
            try prayerTime(.asr, value: Asr, date: date, timeZone: timeZone),
            try prayerTime(.maghrib, value: Maghrib, date: date, timeZone: timeZone),
            try prayerTime(.isha, value: Isha, date: date, timeZone: timeZone)
        ]

        if prayers[4].time <= prayers[3].time {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: prayers[4].time) else {
                throw URLError(.cannotParseResponse)
            }
            prayers[4] = PrayerTime(
                prayer: .isha,
                time: nextDay,
                countdown: max(0, nextDay.timeIntervalSince(Date())),
                timeZoneIdentifier: timeZone.identifier
            )
        }

        return prayers
    }

    private func prayerTime(
        _ prayer: Prayer,
        value: String,
        date: Date,
        timeZone: TimeZone,
        endsAt: Date? = nil
    ) throws -> PrayerTime {
        let time = try dateTime(value: value, date: date, timeZone: timeZone)
        return PrayerTime(
            prayer: prayer,
            time: time,
            countdown: max(0, time.timeIntervalSince(Date())),
            timeZoneIdentifier: timeZone.identifier,
            endsAt: endsAt
        )
    }

    private func dateTime(value: String, date: Date, timeZone: TimeZone) throws -> Date {
        let clock = value.split(separator: " ").first.map(String.init) ?? value
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else {
            throw URLError(.cannotParseResponse)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = 0

        guard let time = components.date else {
            throw URLError(.cannotParseResponse)
        }

        return time
    }

    private func clockMinutes(_ value: String) -> Int? {
        let clock = value.split(separator: " ").first.map(String.init) ?? value
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

struct ActivePrayerWindow {
    let prayerTime: PrayerTime
    let endsAt: Date
    let endingPrayer: Prayer?

    func progress(at date: Date) -> Double {
        let duration = endsAt.timeIntervalSince(prayerTime.time)
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(prayerTime.time) / duration))
    }

    func remaining(at date: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(date))
    }

    static func resolve(from prayers: [PrayerTime], at date: Date) -> ActivePrayerWindow? {
        let sorted = prayers.sorted { $0.time < $1.time }
        guard let index = sorted.lastIndex(where: { $0.time <= date }) else {
            return nil
        }

        let prayer = sorted[index]
        let nextPrayer = sorted.indices.contains(index + 1) ? sorted[index + 1] : nil
        let endsAt = prayer.endsAt ?? nextPrayer?.time
        guard let endsAt, date < endsAt else { return nil }

        return ActivePrayerWindow(
            prayerTime: prayer,
            endsAt: endsAt,
            endingPrayer: prayer.endsAt == nil ? nextPrayer?.prayer : nil
        )
    }
}

@MainActor
final class PrayerScheduleStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var now: Date
    @Published private(set) var status: PrayerScheduleStatus = .locating
    @Published private(set) var scheduleVersion = 0

    private static let cacheKey = "vakt.cachedPrayerSchedule.v1"
    private static let locationPermissionRequestedKey = "vakt.location.permissionRequested.v1"

    private let provider: any PrayerTimeProviding
    private let locationManager = CLLocationManager()
    private var coordinate: Coordinate?
    private var loadedPrayers: [PrayerTime] = []
    private var clockTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var hasRequestedLocationPermission: Bool
    private var calculationSettings: PrayerCalculationSettings

    init(now: Date = Date(), provider: any PrayerTimeProviding = AlAdhanPrayerTimeProvider()) {
        self.now = now
        self.provider = provider
        self.hasRequestedLocationPermission = UserDefaults.standard.bool(forKey: Self.locationPermissionRequestedKey)
        self.calculationSettings = .default
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeConfigurationDidChange),
            name: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeConfigurationDidChange),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
        restoreCachedPrayerTimes()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var upcomingPrayers: [PrayerTime] {
        loadedPrayers
            .filter { $0.time > now }
            .prefix(5)
            .map { prayerTime in
                PrayerTime(
                    prayer: prayerTime.prayer,
                    time: prayerTime.time,
                    countdown: max(0, prayerTime.time.timeIntervalSince(now)),
                    timeZoneIdentifier: prayerTime.timeZoneIdentifier,
                    endsAt: prayerTime.endsAt
                )
            }
    }

    var prayersForDeadlineSync: [PrayerTime] {
        loadedPrayers.sorted { $0.time < $1.time }
    }

    var nextPrayer: PrayerTime {
        upcomingPrayers.first ?? fallbackPrayerTime
    }

    var hasUsablePrayerSchedule: Bool {
        loadedPrayers.contains { $0.time > now }
    }

    var locationAccessNeedsSettings: Bool {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    var activePrayerWindow: ActivePrayerWindow? {
        ActivePrayerWindow.resolve(from: loadedPrayers, at: now)
    }

    var activePrayer: PrayerTime? {
        activePrayerWindow?.prayerTime
    }

    var nextCountdown: TimeInterval {
        max(0, nextPrayer.time.timeIntervalSince(now))
    }

    func prayerTime(for prayer: Prayer, on date: Date = Date()) -> PrayerTime? {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = loadedPrayers.first?.timeZone ?? .autoupdatingCurrent
        return loadedPrayers.first {
            $0.prayer == prayer && calendar.isDate($0.time, inSameDayAs: date)
        }
    }

    var statusMessage: String? {
        status.message
    }

    func start() {
        startClock()
        requestLocationIfAllowed()
    }

    func requestLocationPermission() {
        hasRequestedLocationPermission = true
        UserDefaults.standard.set(true, forKey: Self.locationPermissionRequestedKey)
        startClock()
        requestLocationIfNeeded(allowPrompt: true)
    }

    func updateCalculationSettings(_ settings: PrayerCalculationSettings) {
        guard calculationSettings != settings else { return }
        calculationSettings = settings

        if let coordinate {
            refreshPrayerTimes(for: coordinate)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.requestLocationIfNeeded(allowPrompt: false)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let nextCoordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            let coordinateChanged = nextCoordinate != self.coordinate
            let needsTimeZoneMetadata = self.loadedPrayers.contains { $0.timeZoneIdentifier == nil }
            let needsSavedScheduleRefresh = self.status == .usingSavedTimes
            guard coordinateChanged || needsTimeZoneMetadata || needsSavedScheduleRefresh || self.loadedPrayers.isEmpty else { return }
            self.coordinate = nextCoordinate
            self.refreshPrayerTimes(for: nextCoordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.status = .failed(message)
        }
    }

    private func requestLocationIfAllowed() {
        requestLocationIfNeeded(allowPrompt: false)
    }

    private func requestLocationIfNeeded(allowPrompt: Bool) {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            if allowPrompt {
                status = .locating
                locationManager.requestWhenInUseAuthorization()
            } else {
                status = loadedPrayers.isEmpty ? .locating : .usingSavedTimes
                refreshSavedCoordinateIfAvailable()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            status = loadedPrayers.isEmpty ? .loading : .usingSavedTimes
            locationManager.requestLocation()
        case .denied, .restricted:
            status = loadedPrayers.isEmpty ? .denied : .usingSavedTimes
            refreshSavedCoordinateIfAvailable()
        @unknown default:
            status = .failed("Unknown location authorization status")
        }
    }

    private func startClock() {
        guard clockTask == nil else { return }

        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.now = Date()
                    self?.refreshIfNeeded()
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @objc private func systemTimeConfigurationDidChange() {
        now = Date()
        scheduleVersion += 1

        if let coordinate {
            refreshPrayerTimes(for: coordinate)
        }
    }

    private func refreshIfNeeded() {
        guard let coordinate, status != .loading else { return }
        if loadedPrayers.filter({ $0.time > now }).count < 2 {
            refreshPrayerTimes(for: coordinate)
        }
    }

    private func refreshSavedCoordinateIfAvailable() {
        guard let coordinate, !loadedPrayers.isEmpty, status == .usingSavedTimes else { return }
        refreshPrayerTimes(for: coordinate)
    }

    private func refreshPrayerTimes(for coordinate: Coordinate) {
        refreshTask?.cancel()
        status = .loading

        refreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let calendar = Calendar.autoupdatingCurrent
                let settings = self.calculationSettings
                let today = try await provider.prayerTimes(
                    for: now,
                    coordinate: coordinate,
                    calculationSettings: settings
                )
                var previousPrayerTimes: [PrayerTime] = []
                if (today.first?.time ?? .distantFuture) > now {
                    let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now)
                        ?? now.addingTimeInterval(-24 * 60 * 60)
                    previousPrayerTimes = try await provider.prayerTimes(
                        for: yesterdayDate,
                        coordinate: coordinate,
                        calculationSettings: settings
                    )
                }
                let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
                let tomorrow = try await provider.prayerTimes(
                    for: tomorrowDate,
                    coordinate: coordinate,
                    calculationSettings: settings
                )
                let merged = (previousPrayerTimes + today + tomorrow).sorted { $0.time < $1.time }

                await MainActor.run {
                    self.loadedPrayers = merged
                    self.scheduleVersion += 1
                    self.saveCachedPrayerTimes(merged, coordinate: coordinate)
                    self.status = .ready
                }
            } catch {
                await MainActor.run {
                    if self.loadedPrayers.isEmpty {
                        self.restoreCachedPrayerTimes()
                    }

                    self.status = self.loadedPrayers.isEmpty
                        ? .failed(error.localizedDescription)
                        : .usingSavedTimes
                }
            }
        }
    }

    private var fallbackPrayerTime: PrayerTime {
        PrayerTime(prayer: .fajr, time: now.addingTimeInterval(60 * 60), countdown: 60 * 60)
    }

    private func restoreCachedPrayerTimes() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.cacheKey),
            let cached = try? JSONDecoder().decode(CachedPrayerSchedule.self, from: data),
            cached.prayers.allSatisfy({ $0.timeZoneIdentifier != nil })
        else {
            return
        }

        let futurePrayers = cached.prayers.filter { $0.time > now }
        guard !futurePrayers.isEmpty else { return }

        coordinate = cached.coordinate
        loadedPrayers = cached.prayers.sorted { $0.time < $1.time }
        scheduleVersion += 1
        status = .usingSavedTimes
    }

    private func saveCachedPrayerTimes(_ prayers: [PrayerTime], coordinate: Coordinate) {
        let cache = CachedPrayerSchedule(
            coordinate: coordinate,
            prayers: prayers,
            savedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

enum VaktMockData {
    static let nextPrayer = PrayerTime(
        prayer: .asr,
        time: Date().addingTimeInterval(12 * 60),
        countdown: 12 * 60
    )

    static let globalSaf = Saf(
        id: UUID(),
        name: "Saf",
        prayer: .asr,
        members: makeSafMembers(count: 85),
        isSmall: false
    )

    static let upcomingPrayers: [PrayerTime] = [
        PrayerTime(prayer: .asr, time: Date().addingTimeInterval(12 * 60), countdown: 12 * 60),
        PrayerTime(prayer: .maghrib, time: Date().addingTimeInterval(114 * 60), countdown: 114 * 60),
        PrayerTime(prayer: .isha, time: Date().addingTimeInterval(208 * 60), countdown: 208 * 60),
        PrayerTime(prayer: .fajr, time: Date().addingTimeInterval(610 * 60), countdown: 610 * 60)
    ]

    private static func makeSafMembers(count: Int) -> [SafMember] {
        let clampedCount = max(1, count)
        let currentUserIndex = min(clampedCount - 1, clampedCount / 2)
        let statuses: [PrepStatus] = [.gettingUp, .wudu, .wudu, .findingPlace, .ready, .ready]

        return (0..<clampedCount).map { index in
            let position = clampedCount == 1
                ? 0.5
                : 0.06 + (0.88 * CGFloat(index) / CGFloat(clampedCount - 1))

            return SafMember(
                id: UUID(),
                normalizedPosition: position,
                status: index == currentUserIndex ? .ready : statuses[index % statuses.count],
                isCurrentUser: index == currentUserIndex
            )
        }
    }
}
