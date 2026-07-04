import Foundation
import Supabase

actor SupabasePresenceRepository: PresenceRepository {
    private struct ChannelState {
        let channel: RealtimeChannelV2
        var subscribers: [UUID: AsyncThrowingStream<PresenceSnapshot, Error>.Continuation]
        var presences: [String: BackendPresenceStatus]
        var latestSnapshot: PresenceSnapshot?
        var listenerTask: Task<Void, Never>?
    }

    private struct ActiveLease {
        let lease: PresenceLease
        let status: BackendPresenceStatus
    }

    private let client: SupabaseClient
    private let identity: any AnonymousIdentityRepository
    private var channels: [PrayerSessionID: ChannelState] = [:]
    private var activeLeases: [PresenceLeaseID: ActiveLease] = [:]

    init(client: SupabaseClient, identity: any AnonymousIdentityRepository) {
        self.client = client
        self.identity = identity
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
                await self.registerSubscriber(continuation, id: subscriberID, sessionID: sessionID)
            }
        }
    }

    func upsertPresence(_ mutation: PresenceMutation) async throws -> PresenceLease {
        _ = try await identity.createIdentityIfNeeded()

        do {
            let parameters = UpsertPresenceParameters(
                sessionID: mutation.sessionID.rawValue,
                clientInstanceID: mutation.clientInstanceID,
                commandID: mutation.commandID,
                status: mutation.status.rawValue
            )
            let rows: [PresenceLeaseRow] = try await client
                .rpc("upsert_session_presence", params: parameters)
                .execute()
                .value
            let lease = try lease(from: rows)
            activeLeases[lease.id] = ActiveLease(lease: lease, status: mutation.status)
            await track(status: mutation.status, sessionID: mutation.sessionID)
            return lease
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func refreshPresence(
        leaseID: PresenceLeaseID,
        status: BackendPresenceStatus,
        at date: Date
    ) async throws -> PresenceLease {
        _ = try await identity.createIdentityIfNeeded()

        do {
            let rows: [PresenceLeaseRow] = try await client
                .rpc(
                    "refresh_session_presence",
                    params: RefreshPresenceParameters(leaseID: leaseID.rawValue, status: status.rawValue)
                )
                .execute()
                .value
            let lease = try lease(from: rows)
            activeLeases[leaseID] = ActiveLease(lease: lease, status: status)
            await track(status: status, sessionID: lease.sessionID)
            return lease
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func leave(leaseID: PresenceLeaseID) async {
        guard let activeLease = activeLeases.removeValue(forKey: leaseID) else { return }
        if let channel = channels[activeLease.lease.sessionID]?.channel {
            await channel.untrack()
        }

        do {
            let _: Bool = try await client
                .rpc(
                    "leave_session_presence",
                    params: LeavePresenceParameters(leaseID: leaseID.rawValue)
                )
                .execute()
                .value
        } catch {
            // Lease expiry remains the correctness fallback when an explicit leave cannot reach the server.
        }
    }

    private func registerSubscriber(
        _ continuation: AsyncThrowingStream<PresenceSnapshot, Error>.Continuation,
        id: UUID,
        sessionID: PrayerSessionID
    ) async {
        do {
            _ = try await identity.createIdentityIfNeeded()

            if var existing = channels[sessionID] {
                existing.subscribers[id] = continuation
                channels[sessionID] = existing
                if let latestSnapshot = existing.latestSnapshot {
                    continuation.yield(latestSnapshot)
                }
                return
            }

            let channel = client.realtimeV2.channel("saf:\(sessionID.rawValue.uuidString.lowercased())") {
                $0.isPrivate = true
                $0.presence.key = UUID().uuidString.lowercased()
            }
            channels[sessionID] = ChannelState(
                channel: channel,
                subscribers: [id: continuation],
                presences: [:],
                latestSnapshot: nil,
                listenerTask: nil
            )

            let presenceChanges = channel.presenceChange()
            let listenerTask = Task { [weak self] in
                for await action in presenceChanges {
                    guard !Task.isCancelled else { return }
                    await self?.apply(action: action, sessionID: sessionID)
                }
            }
            channels[sessionID]?.listenerTask = listenerTask

            try await channel.subscribeWithError()
            let initialSnapshot = try await fetchSnapshot(sessionID: sessionID)
            publish(initialSnapshot, sessionID: sessionID)

            if let activeLease = activeLeases.values.first(where: { $0.lease.sessionID == sessionID }) {
                try await channel.track(
                    RealtimePresencePayload(status: activeLease.status.rawValue, observedAt: Date())
                )
            }
        } catch {
            failChannel(sessionID: sessionID, error: SupabaseBackendErrorMapper.map(error))
        }
    }

    private func apply(action: any PresenceAction, sessionID: PrayerSessionID) {
        guard var state = channels[sessionID] else { return }

        action.leaves.values.forEach { state.presences[$0.ref] = nil }
        action.joins.values.forEach { presence in
            guard
                let payload = try? presence.decodeState(as: RealtimePresencePayload.self),
                let status = BackendPresenceStatus(rawValue: payload.status)
            else { return }
            state.presences[presence.ref] = status
        }

        var counts = PresenceCounts.zero
        state.presences.values.forEach { counts[$0] += 1 }
        let snapshot = PresenceSnapshot(
            sessionID: sessionID,
            counts: counts,
            observedAt: Date(),
            source: .realtime,
            isStale: false
        )
        state.latestSnapshot = snapshot
        channels[sessionID] = state
        state.subscribers.values.forEach { $0.yield(snapshot) }
    }

    private func fetchSnapshot(sessionID: PrayerSessionID) async throws -> PresenceSnapshot {
        let rows: [PresenceSnapshotRow] = try await client
            .rpc(
                "get_session_presence_snapshot",
                params: SnapshotParameters(sessionID: sessionID.rawValue)
            )
            .execute()
            .value
        guard let row = rows.first, row.sessionID == sessionID.rawValue else {
            throw BackendError.invalidResponse
        }
        return PresenceSnapshot(
            sessionID: sessionID,
            counts: PresenceCounts(
                gettingUp: row.gettingUp,
                makingWudu: row.makingWudu,
                joiningSaf: row.joiningSaf,
                ready: row.ready,
                praying: row.praying
            ),
            observedAt: row.observedAt,
            source: .realtime,
            isStale: false
        )
    }

    private func track(status: BackendPresenceStatus, sessionID: PrayerSessionID) async {
        guard let channel = channels[sessionID]?.channel else { return }
        try? await channel.track(RealtimePresencePayload(status: status.rawValue, observedAt: Date()))
    }

    private func publish(_ snapshot: PresenceSnapshot, sessionID: PrayerSessionID) {
        guard var state = channels[sessionID] else { return }
        state.latestSnapshot = snapshot
        channels[sessionID] = state
        state.subscribers.values.forEach { $0.yield(snapshot) }
    }

    private func failChannel(sessionID: PrayerSessionID, error: Error) {
        guard let state = channels.removeValue(forKey: sessionID) else { return }
        state.listenerTask?.cancel()
        state.subscribers.values.forEach { $0.finish(throwing: error) }
        Task {
            await state.channel.unsubscribe()
            await client.realtimeV2.removeChannel(state.channel)
        }
    }

    private func removeSubscriber(_ id: UUID, sessionID: PrayerSessionID) async {
        guard var state = channels[sessionID] else { return }
        state.subscribers[id] = nil
        guard state.subscribers.isEmpty else {
            channels[sessionID] = state
            return
        }

        channels[sessionID] = nil
        state.listenerTask?.cancel()
        await state.channel.unsubscribe()
        await client.realtimeV2.removeChannel(state.channel)
    }

    private func lease(from rows: [PresenceLeaseRow]) throws -> PresenceLease {
        guard let row = rows.first else { throw BackendError.sessionUnavailable }
        guard let status = BackendPresenceStatus(rawValue: row.status) else {
            throw BackendError.invalidResponse
        }
        return PresenceLease(
            id: PresenceLeaseID(rawValue: row.leaseID),
            sessionID: PrayerSessionID(rawValue: row.sessionID),
            status: status,
            expiresAt: row.expiresAt
        )
    }
}

private struct RealtimePresencePayload: Codable, Sendable {
    let status: String
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case observedAt = "observed_at"
    }
}

private struct UpsertPresenceParameters: Encodable, Sendable {
    let sessionID: UUID
    let clientInstanceID: UUID
    let commandID: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "p_session_id"
        case clientInstanceID = "p_client_instance_id"
        case commandID = "p_command_id"
        case status = "p_status"
    }
}

private struct RefreshPresenceParameters: Encodable, Sendable {
    let leaseID: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case leaseID = "p_lease_id"
        case status = "p_status"
    }
}

private struct LeavePresenceParameters: Encodable, Sendable {
    let leaseID: UUID

    enum CodingKeys: String, CodingKey {
        case leaseID = "p_lease_id"
    }
}

private struct SnapshotParameters: Encodable, Sendable {
    let sessionID: UUID

    enum CodingKeys: String, CodingKey {
        case sessionID = "p_session_id"
    }
}

private struct PresenceLeaseRow: Decodable, Sendable {
    let leaseID: UUID
    let sessionID: UUID
    let status: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case leaseID = "lease_id"
        case sessionID = "session_id"
        case status
        case expiresAt = "expires_at"
    }
}

private struct PresenceSnapshotRow: Decodable, Sendable {
    let sessionID: UUID
    let gettingUp: Int
    let makingWudu: Int
    let joiningSaf: Int
    let ready: Int
    let praying: Int
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case gettingUp = "getting_up"
        case makingWudu = "making_wudu"
        case joiningSaf = "joining_saf"
        case ready
        case praying
        case observedAt = "observed_at"
    }
}
