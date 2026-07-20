import Foundation

enum PrayerSurfaceSnapshotBuilder {
    @MainActor
    static func make(
        prayers: [PrayerTime],
        now: Date,
        reflectionStore: PrayerReflectionStore,
        sessionStore: PrayerSessionStore,
        surfaceStore: PrayerSurfaceStore = .shared
    ) -> PrayerSurfaceSnapshot {
        let sorted = prayers.sorted { $0.time < $1.time }
        let activeWindow = ActivePrayerWindow.resolve(from: sorted, at: now)
        let current = activeWindow?.prayerTime
        let next = sorted.first { $0.time > now }
        let mappedSchedule = sorted.map {
            map($0, reflectionStore: reflectionStore, sessionStore: sessionStore)
        }
        let mappedCurrent = current.map {
            map($0, reflectionStore: reflectionStore, sessionStore: sessionStore)
        }
        let mappedNext = next.map {
            map($0, reflectionStore: reflectionStore, sessionStore: sessionStore)
        }

        return PrayerSurfaceSnapshot(
            generatedAt: now,
            phase: phase(current: mappedCurrent, next: mappedNext, now: now),
            currentPrayer: mappedCurrent,
            nextPrayer: mappedNext,
            schedule: mappedSchedule,
            atmosphere: atmosphere(at: now, timeZone: current?.timeZone ?? next?.timeZone ?? .autoupdatingCurrent),
            hasPendingActions: !surfaceStore.pendingActions().isEmpty
        )
    }

    @MainActor
    private static func map(
        _ prayerTime: PrayerTime,
        reflectionStore: PrayerReflectionStore,
        sessionStore: PrayerSessionStore
    ) -> PrayerSurfacePrayer {
        let trackingStatus = reflectionStore.trackingStatus(
            for: prayerTime,
            sessionStatus: sessionStore.status(for: prayerTime)
        )

        return PrayerSurfacePrayer(
            prayer: PrayerSurfacePrayerID(prayerTime.prayer),
            startsAt: prayerTime.time,
            endsAt: prayerTime.endsAt,
            timeZoneIdentifier: prayerTime.timeZone.identifier,
            status: PrayerSurfaceStatus(trackingStatus)
        )
    }

    private static func phase(
        current: PrayerSurfacePrayer?,
        next: PrayerSurfacePrayer?,
        now: Date
    ) -> PrayerSurfacePhase {
        if let current {
            switch current.status {
            case .quiet:
                return .quiet
            case .prayed:
                return .completed
            case .unmarked, .notYet, .later, .missed:
                return .entered
            }
        }

        guard let next else { return .expired }
        return next.startsAt.timeIntervalSince(now) <= 30 * 60 ? .approaching : .upcoming
    }

    private static func atmosphere(at date: Date, timeZone: TimeZone) -> PrayerSurfaceAtmosphere {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch calendar.component(.hour, from: date) {
        case 0..<5, 21..<24:
            return .night
        case 5..<7:
            return .dawn
        case 7..<11:
            return .morning
        case 11..<15:
            return .midday
        case 15..<18:
            return .afternoon
        case 18..<21:
            return .sunset
        default:
            return .night
        }
    }
}

extension PrayerSurfacePrayerID {
    init(_ prayer: Prayer) {
        switch prayer {
        case .fajr: self = .fajr
        case .dhuhr: self = .dhuhr
        case .asr: self = .asr
        case .maghrib: self = .maghrib
        case .isha: self = .isha
        }
    }

    var prayer: Prayer {
        switch self {
        case .fajr: return .fajr
        case .dhuhr: return .dhuhr
        case .asr: return .asr
        case .maghrib: return .maghrib
        case .isha: return .isha
        }
    }
}

private extension PrayerSurfaceStatus {
    init(_ status: PrayerTrackingStatus) {
        switch status {
        case .ready: self = .unmarked
        case .inProgress: self = .quiet
        case .prayed: self = .prayed
        case .later: self = .later
        case .missed: self = .missed
        }
    }
}
