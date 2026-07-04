import Foundation

actor SimulatedPresenceRepository: PresenceRepository {
    private struct LeaseRecord {
        let id: PresenceLeaseID
        let sessionID: PrayerSessionID
        var status: BackendPresenceStatus
        var expiresAt: Date
    }

    private let leaseDuration: TimeInterval
    private let minimumCount: Int
    private let maximumCount: Int
    private var ambientCount: Int
    private var stepIndex = 0
    private var leases: [PresenceLeaseID: LeaseRecord] = [:]
    private var continuations: [PrayerSessionID: [UUID: AsyncThrowingStream<PresenceSnapshot, Error>.Continuation]] = [:]
    private var simulationTask: Task<Void, Never>?
    private let movementPattern = [1, 1, -1, 2, -1, 1, -2, 1, 2, -1, -1, 1]

    init(initialCount: Int, leaseDuration: TimeInterval = 15 * 60) {
        let baseline = max(7, initialCount)
        ambientCount = baseline
        minimumCount = max(7, baseline - 3)
        maximumCount = max(baseline + 18, Int((Double(baseline) * 1.28).rounded()))
        self.leaseDuration = leaseDuration
    }

    nonisolated func snapshots(
        for sessionID: PrayerSessionID
    ) async -> AsyncThrowingStream<PresenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let subscriberID = UUID()
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(subscriberID, sessionID: sessionID) }
            }

            Task {
                await self.addSubscriber(continuation, id: subscriberID, sessionID: sessionID)
            }
        }
    }

    func upsertPresence(_ mutation: PresenceMutation) async throws -> PresenceLease {
        let existing = leases.values.first { $0.id.rawValue == mutation.clientInstanceID }
        let leaseID = existing?.id ?? PresenceLeaseID(rawValue: mutation.clientInstanceID)
        let expiry = mutation.createdAt.addingTimeInterval(leaseDuration)
        leases[leaseID] = LeaseRecord(
            id: leaseID,
            sessionID: mutation.sessionID,
            status: mutation.status,
            expiresAt: expiry
        )
        publishAll(at: mutation.createdAt)
        return PresenceLease(id: leaseID, sessionID: mutation.sessionID, status: mutation.status, expiresAt: expiry)
    }

    func refreshPresence(
        leaseID: PresenceLeaseID,
        status: BackendPresenceStatus,
        at date: Date
    ) async throws -> PresenceLease {
        guard var record = leases[leaseID], record.expiresAt > date else {
            leases[leaseID] = nil
            throw BackendError.sessionUnavailable
        }

        record.status = status
        record.expiresAt = date.addingTimeInterval(leaseDuration)
        leases[leaseID] = record
        publishAll(at: date)

        return PresenceLease(
            id: leaseID,
            sessionID: record.sessionID,
            status: status,
            expiresAt: record.expiresAt
        )
    }

    func leave(leaseID: PresenceLeaseID) async {
        leases[leaseID] = nil
        publishAll(at: Date())
    }

    private func addSubscriber(
        _ continuation: AsyncThrowingStream<PresenceSnapshot, Error>.Continuation,
        id: UUID,
        sessionID: PrayerSessionID
    ) {
        continuations[sessionID, default: [:]][id] = continuation
        continuation.yield(snapshot(sessionID: sessionID, at: Date()))
        startSimulationIfNeeded()
    }

    private func removeSubscriber(_ id: UUID, sessionID: PrayerSessionID) {
        continuations[sessionID]?[id] = nil
        if continuations[sessionID]?.isEmpty == true {
            continuations[sessionID] = nil
        }
        if continuations.isEmpty {
            simulationTask?.cancel()
            simulationTask = nil
        }
    }

    private func startSimulationIfNeeded() {
        guard simulationTask == nil else { return }
        simulationTask = Task { [weak self] in
            await self?.runSimulation()
        }
    }

    private func runSimulation() async {
        while !Task.isCancelled {
            let delay = UInt64.random(in: 1_550_000_000...3_100_000_000)
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }

            let proposedChange = movementPattern[stepIndex % movementPattern.count]
            stepIndex += 1
            ambientCount = min(maximumCount, max(minimumCount, ambientCount + proposedChange))
            publishAll(at: Date())
        }
    }

    private func publishAll(at date: Date) {
        removeExpiredLeases(at: date)
        for sessionID in continuations.keys {
            let value = snapshot(sessionID: sessionID, at: date)
            continuations[sessionID]?.values.forEach { $0.yield(value) }
        }
    }

    private func removeExpiredLeases(at date: Date) {
        leases = leases.filter { $0.value.expiresAt > date }
    }

    private func snapshot(sessionID: PrayerSessionID, at date: Date) -> PresenceSnapshot {
        var counts = distributedCounts(total: ambientCount)
        leases.values
            .filter { $0.sessionID == sessionID }
            .forEach { counts[$0.status] += 1 }

        return PresenceSnapshot(
            sessionID: sessionID,
            counts: counts,
            observedAt: date,
            source: .localSimulation,
            isStale: false
        )
    }

    private func distributedCounts(total: Int) -> PresenceCounts {
        let praying = Int((Double(total) * 0.12).rounded())
        let ready = Int((Double(total) * 0.24).rounded())
        let joining = Int((Double(total) * 0.10).rounded())
        let makingWudu = Int((Double(total) * 0.34).rounded())
        let gettingUp = max(0, total - praying - ready - joining - makingWudu)

        return PresenceCounts(
            gettingUp: gettingUp,
            makingWudu: makingWudu,
            joiningSaf: joining,
            ready: ready,
            praying: praying
        )
    }
}
