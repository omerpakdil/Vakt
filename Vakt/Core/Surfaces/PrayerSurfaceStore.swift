import Foundation

struct PrayerSurfaceStore {
    static let appGroupIdentifier = "group.com.callousity.vakt"
    static let shared = PrayerSurfaceStore(
        defaults: UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    )

    private enum Key {
        static let snapshot = "vakt.surface.snapshot.v1"
        static let pendingActions = "vakt.surface.pending-actions.v1"
        static let access = "vakt.surface.access.v1"
    }

    private struct AccessState: Codable {
        let isActive: Bool
        let expirationDate: Date?
        let validatedAt: Date
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maximumPendingActionCount = 50

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func loadSnapshot() -> PrayerSurfaceSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshot),
              let snapshot = try? decoder.decode(PrayerSurfaceSnapshot.self, from: data),
              snapshot.schemaVersion == PrayerSurfaceSnapshot.currentSchemaVersion else {
            return nil
        }
        return snapshot
    }

    @discardableResult
    func saveSnapshot(_ snapshot: PrayerSurfaceSnapshot) -> Bool {
        guard let data = try? encoder.encode(snapshot) else { return false }
        defaults.set(data, forKey: Key.snapshot)
        return true
    }

    @discardableResult
    func markPrayerPrayed(
        prayer: PrayerSurfacePrayerID,
        prayerDate: Date
    ) -> Bool {
        markPrayer(prayer: prayer, prayerDate: prayerDate, status: .prayed)
    }

    @discardableResult
    func markPrayerNotYet(
        prayer: PrayerSurfacePrayerID,
        prayerDate: Date
    ) -> Bool {
        markPrayer(prayer: prayer, prayerDate: prayerDate, status: .notYet)
    }

    private func markPrayer(
        prayer: PrayerSurfacePrayerID,
        prayerDate: Date,
        status: PrayerSurfaceStatus
    ) -> Bool {
        guard let snapshot = loadSnapshot() else { return false }

        func updated(_ item: PrayerSurfacePrayer?) -> PrayerSurfacePrayer? {
            guard let item else { return nil }
            guard item.prayer == prayer,
                  abs(item.startsAt.timeIntervalSince(prayerDate)) < 1 else {
                return item
            }
            return PrayerSurfacePrayer(
                prayer: item.prayer,
                startsAt: item.startsAt,
                endsAt: item.endsAt,
                timeZoneIdentifier: item.timeZoneIdentifier,
                status: status
            )
        }

        let marksCurrent = snapshot.currentPrayer.map {
            $0.prayer == prayer && abs($0.startsAt.timeIntervalSince(prayerDate)) < 1
        } ?? false
        let schedule = snapshot.schedule.map { updated($0) ?? $0 }
        let result = PrayerSurfaceSnapshot(
            generatedAt: snapshot.generatedAt,
            phase: marksCurrent && status == .prayed && snapshot.phase != .quiet
                ? .completed
                : snapshot.phase,
            currentPrayer: updated(snapshot.currentPrayer),
            nextPrayer: updated(snapshot.nextPrayer),
            schedule: schedule,
            atmosphere: snapshot.atmosphere,
            hasPendingActions: true
        )
        return saveSnapshot(result)
    }

    func clearSnapshot() {
        defaults.removeObject(forKey: Key.snapshot)
    }

    func updateAccess(
        isActive: Bool,
        expirationDate: Date?,
        validatedAt: Date = Date()
    ) {
        let state = AccessState(
            isActive: isActive,
            expirationDate: expirationDate,
            validatedAt: validatedAt
        )
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: Key.access)
    }

    func hasActiveAccess(at date: Date = Date()) -> Bool {
        guard let data = defaults.data(forKey: Key.access),
              let state = try? decoder.decode(AccessState.self, from: data),
              state.isActive else {
            return false
        }
        return state.expirationDate.map { date < $0 } ?? true
    }

    func pendingActions() -> [PrayerSurfaceAction] {
        guard let data = defaults.data(forKey: Key.pendingActions),
              let actions = try? decoder.decode([PrayerSurfaceAction].self, from: data) else {
            return []
        }
        return actions.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func enqueue(_ action: PrayerSurfaceAction) -> Bool {
        var actions = pendingActions()
        guard !actions.contains(where: {
            $0.id == action.id ||
                ($0.kind == action.kind &&
                    $0.prayer == action.prayer &&
                    abs($0.prayerDate.timeIntervalSince(action.prayerDate)) < 1)
        }) else { return false }

        actions.append(action)
        actions.sort { $0.createdAt < $1.createdAt }
        if actions.count > maximumPendingActionCount {
            actions.removeFirst(actions.count - maximumPendingActionCount)
        }
        return save(actions: actions)
    }

    @discardableResult
    func removePendingAction(id: UUID) -> Bool {
        var actions = pendingActions()
        let originalCount = actions.count
        actions.removeAll { $0.id == id }
        guard actions.count != originalCount else { return false }
        return save(actions: actions)
    }

    private func save(actions: [PrayerSurfaceAction]) -> Bool {
        guard let data = try? encoder.encode(actions) else { return false }
        defaults.set(data, forKey: Key.pendingActions)
        return true
    }
}
