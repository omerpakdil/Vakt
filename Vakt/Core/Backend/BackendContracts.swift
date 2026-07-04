import Foundation

struct AnonymousBackendIdentity: Codable, Equatable, Sendable {
    let userID: BackendUserID
    let isAnonymous: Bool
}

protocol AnonymousIdentityRepository: Sendable {
    func currentIdentity() async throws -> AnonymousBackendIdentity
    func createIdentityIfNeeded() async throws -> AnonymousBackendIdentity
}

protocol PrayerSessionRepository: Sendable {
    func session(for request: PrayerSessionRequest) async throws -> BackendPrayerSession
}

protocol PresenceRepository: Sendable {
    func snapshots(for sessionID: PrayerSessionID) async -> AsyncThrowingStream<PresenceSnapshot, Error>

    func upsertPresence(_ mutation: PresenceMutation) async throws -> PresenceLease

    func refreshPresence(
        leaseID: PresenceLeaseID,
        status: BackendPresenceStatus,
        at date: Date
    ) async throws -> PresenceLease

    func leave(leaseID: PresenceLeaseID) async
}

struct BackendRepositories: Sendable {
    let identity: any AnonymousIdentityRepository
    let prayerSessions: any PrayerSessionRepository
    let presence: any PresenceRepository
}
