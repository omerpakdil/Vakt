import Foundation

@MainActor
final class PresenceCoordinator {
    var onSnapshot: ((PresenceSnapshot) -> Void)?
    var onConnectionStateChange: ((BackendConnectionState) -> Void)?

    private let sessions: any PrayerSessionRepository
    private let presence: any PresenceRepository
    private let clientInstanceID: UUID
    private let heartbeatInterval: UInt64

    private var request: PrayerSessionRequest?
    private var session: BackendPrayerSession?
    private var lease: PresenceLease?
    private var desiredStatus: BackendPresenceStatus?
    private var generation = UUID()
    private var setupTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init(
        sessions: any PrayerSessionRepository,
        presence: any PresenceRepository,
        clientInstanceID: UUID = UUID(),
        heartbeatInterval: TimeInterval = 5 * 60
    ) {
        self.sessions = sessions
        self.presence = presence
        self.clientInstanceID = clientInstanceID
        self.heartbeatInterval = UInt64(max(1, heartbeatInterval) * 1_000_000_000)
    }

    func observe(_ request: PrayerSessionRequest) {
        guard self.request?.scope != request.scope else { return }
        resetForNewSession()
        self.request = request
        let currentGeneration = generation
        setConnectionState(.connecting)

        setupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolvedSession = try await sessions.session(for: request)
                guard generation == currentGeneration else { return }
                session = resolvedSession
                startSnapshotStream(for: resolvedSession, generation: currentGeneration)

                if let desiredStatus {
                    try await createLease(status: desiredStatus, generation: currentGeneration)
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == currentGeneration else { return }
                setConnectionState(.failed(map(error)))
            }
        }
    }

    func join(status: BackendPresenceStatus) {
        desiredStatus = status
        if lease != nil {
            updateStatus(status)
            return
        }
        guard session != nil else { return }

        let currentGeneration = generation
        Task { [weak self] in
            try? await self?.createLease(status: status, generation: currentGeneration)
        }
    }

    func updateStatus(_ status: BackendPresenceStatus) {
        desiredStatus = status
        guard let lease else {
            if session != nil {
                join(status: status)
            }
            return
        }

        let currentGeneration = generation
        Task { [weak self] in
            await self?.refreshLease(lease, status: status, generation: currentGeneration)
        }
    }

    func leave() {
        desiredStatus = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        guard let lease else { return }
        self.lease = nil
        Task { [presence] in
            await presence.leave(leaseID: lease.id)
        }
    }

    func stop() {
        resetForNewSession()
        request = nil
        setConnectionState(.idle)
    }

    private func startSnapshotStream(for session: BackendPrayerSession, generation: UUID) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            var retryAttempt = 0

            while !Task.isCancelled, self.generation == generation {
                do {
                    let stream = await presence.snapshots(for: session.id)
                    setConnectionState(retryAttempt == 0 ? .connected : .reconnecting(attempt: retryAttempt))

                    for try await snapshot in stream {
                        guard self.generation == generation else { return }
                        retryAttempt = 0
                        setConnectionState(.connected)
                        onSnapshot?(snapshot)
                    }

                    if !Task.isCancelled {
                        throw BackendError.offline
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.generation == generation else { return }
                    retryAttempt += 1
                    setConnectionState(.reconnecting(attempt: retryAttempt))
                    let delay = reconnectDelayNanoseconds(attempt: retryAttempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }

    private func createLease(status: BackendPresenceStatus, generation: UUID) async throws {
        guard let session, self.generation == generation else { return }
        let mutation = PresenceMutation(
            commandID: UUID(),
            sessionID: session.id,
            clientInstanceID: clientInstanceID,
            status: status,
            createdAt: Date()
        )
        let newLease = try await presence.upsertPresence(mutation)
        guard self.generation == generation else {
            await presence.leave(leaseID: newLease.id)
            return
        }
        lease = newLease
        startHeartbeat(generation: generation)
    }

    private func refreshLease(
        _ lease: PresenceLease,
        status: BackendPresenceStatus,
        generation: UUID
    ) async {
        do {
            let refreshed = try await presence.refreshPresence(
                leaseID: lease.id,
                status: status,
                at: Date()
            )
            guard self.generation == generation else { return }
            self.lease = refreshed
        } catch {
            guard self.generation == generation else { return }
            self.lease = nil
            try? await createLease(status: status, generation: generation)
        }
    }

    private func startHeartbeat(generation: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == generation {
                try? await Task.sleep(nanoseconds: heartbeatInterval)
                guard
                    !Task.isCancelled,
                    self.generation == generation,
                    let lease,
                    let desiredStatus
                else { return }
                await refreshLease(lease, status: desiredStatus, generation: generation)
            }
        }
    }

    private func resetForNewSession() {
        generation = UUID()
        setupTask?.cancel()
        streamTask?.cancel()
        heartbeatTask?.cancel()
        setupTask = nil
        streamTask = nil
        heartbeatTask = nil

        if let lease {
            Task { [presence] in
                await presence.leave(leaseID: lease.id)
            }
        }

        session = nil
        lease = nil
        desiredStatus = nil
    }

    private func setConnectionState(_ state: BackendConnectionState) {
        onConnectionStateChange?(state)
    }

    private func reconnectDelayNanoseconds(attempt: Int) -> UInt64 {
        let cappedAttempt = min(6, max(1, attempt))
        let base = min(30.0, pow(2.0, Double(cappedAttempt - 1)))
        let jitter = Double.random(in: 0.85...1.15)
        return UInt64(base * jitter * 1_000_000_000)
    }

    private func map(_ error: Error) -> BackendError {
        if let backendError = error as? BackendError { return backendError }
        if error is CancellationError { return .cancelled }
        return .server(message: error.localizedDescription)
    }
}
