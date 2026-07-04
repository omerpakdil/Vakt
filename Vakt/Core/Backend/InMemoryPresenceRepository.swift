import Foundation

actor InMemoryPresenceRepository: PresenceRepository {
    private struct Record {
        let leaseID: PresenceLeaseID
        let clientInstanceID: UUID
        var status: BackendPresenceStatus
        var expiresAt: Date
    }

    private let leaseDuration: TimeInterval
    private var records: [PrayerSessionID: [UUID: Record]] = [:]
    private var continuations: [PrayerSessionID: [UUID: AsyncThrowingStream<PresenceSnapshot, Error>.Continuation]] = [:]

    init(leaseDuration: TimeInterval = 15 * 60) {
        self.leaseDuration = leaseDuration
    }

    nonisolated func snapshots(
        for sessionID: PrayerSessionID
    ) async -> AsyncThrowingStream<PresenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let subscriberID = UUID()

            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(subscriberID, from: sessionID)
                }
            }

            Task {
                await self.addContinuation(continuation, id: subscriberID, for: sessionID)
            }
        }
    }

    func upsertPresence(_ mutation: PresenceMutation) async throws -> PresenceLease {
        removeExpiredRecords(at: mutation.createdAt, sessionID: mutation.sessionID)

        var sessionRecords = records[mutation.sessionID, default: [:]]
        let existing = sessionRecords[mutation.clientInstanceID]
        let leaseID = existing?.leaseID ?? PresenceLeaseID(rawValue: UUID())
        let expiry = mutation.createdAt.addingTimeInterval(leaseDuration)

        sessionRecords[mutation.clientInstanceID] = Record(
            leaseID: leaseID,
            clientInstanceID: mutation.clientInstanceID,
            status: mutation.status,
            expiresAt: expiry
        )
        records[mutation.sessionID] = sessionRecords
        publishSnapshot(for: mutation.sessionID, at: mutation.createdAt)

        return PresenceLease(
            id: leaseID,
            sessionID: mutation.sessionID,
            status: mutation.status,
            expiresAt: expiry
        )
    }

    func refreshPresence(
        leaseID: PresenceLeaseID,
        status: BackendPresenceStatus,
        at date: Date
    ) async throws -> PresenceLease {
        guard let match = record(for: leaseID) else {
            throw BackendError.sessionUnavailable
        }

        removeExpiredRecords(at: date, sessionID: match.sessionID)
        guard var record = records[match.sessionID]?[match.clientInstanceID] else {
            throw BackendError.sessionUnavailable
        }

        record.status = status
        record.expiresAt = date.addingTimeInterval(leaseDuration)
        records[match.sessionID]?[match.clientInstanceID] = record
        publishSnapshot(for: match.sessionID, at: date)

        return PresenceLease(
            id: leaseID,
            sessionID: match.sessionID,
            status: status,
            expiresAt: record.expiresAt
        )
    }

    func leave(leaseID: PresenceLeaseID) async {
        guard let match = record(for: leaseID) else { return }
        records[match.sessionID]?[match.clientInstanceID] = nil
        publishSnapshot(for: match.sessionID, at: Date())
    }

    private func addContinuation(
        _ continuation: AsyncThrowingStream<PresenceSnapshot, Error>.Continuation,
        id: UUID,
        for sessionID: PrayerSessionID
    ) {
        continuations[sessionID, default: [:]][id] = continuation
        continuation.yield(snapshot(for: sessionID, at: Date()))
    }

    private func removeContinuation(_ id: UUID, from sessionID: PrayerSessionID) {
        continuations[sessionID]?[id] = nil
        if continuations[sessionID]?.isEmpty == true {
            continuations[sessionID] = nil
        }
    }

    private func record(for leaseID: PresenceLeaseID) -> (sessionID: PrayerSessionID, clientInstanceID: UUID)? {
        for (sessionID, sessionRecords) in records {
            if let record = sessionRecords.values.first(where: { $0.leaseID == leaseID }) {
                return (sessionID, record.clientInstanceID)
            }
        }
        return nil
    }

    private func removeExpiredRecords(at date: Date, sessionID: PrayerSessionID) {
        records[sessionID] = records[sessionID]?.filter { _, record in
            record.expiresAt > date
        }
    }

    private func publishSnapshot(for sessionID: PrayerSessionID, at date: Date) {
        let value = snapshot(for: sessionID, at: date)
        continuations[sessionID]?.values.forEach { $0.yield(value) }
    }

    private func snapshot(for sessionID: PrayerSessionID, at date: Date) -> PresenceSnapshot {
        removeExpiredRecords(at: date, sessionID: sessionID)
        var counts = PresenceCounts.zero

        records[sessionID]?.values.forEach { record in
            counts[record.status] += 1
        }

        return PresenceSnapshot(
            sessionID: sessionID,
            counts: counts,
            observedAt: date,
            source: .localSimulation,
            isStale: false
        )
    }
}
