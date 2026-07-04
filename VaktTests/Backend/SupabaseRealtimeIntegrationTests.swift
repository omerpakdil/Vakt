import XCTest
import Supabase
@testable import Vakt

final class SupabaseRealtimeIntegrationTests: XCTestCase {
    func testTwoPrivateConnectionsSharePresenceChannel() async throws {
        let cloudTestEnabled = ProcessInfo.processInfo.environment["VAKT_RUN_CLOUD_INTEGRATION"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--vakt-cloud-integration=1")
        guard cloudTestEnabled else {
            throw XCTSkip("Set VAKT_RUN_CLOUD_INTEGRATION=1 to run the cloud Realtime test.")
        }

        let configuration = try SupabaseBackendConfiguration.load()
        let bootstrapClient = makeIsolatedClient(configuration)
        let authSession = try await bootstrapClient.auth.signInAnonymously()
        let identity = FixedAnonymousIdentityRepository(
            identity: AnonymousBackendIdentity(
                userID: BackendUserID(rawValue: authSession.user.id),
                isAnonymous: authSession.user.isAnonymous
            )
        )
        let firstClient = makeTokenClient(configuration, accessToken: authSession.accessToken)
        let secondClient = makeTokenClient(configuration, accessToken: authSession.accessToken)
        await firstClient.realtimeV2.setAuth(authSession.accessToken)
        await secondClient.realtimeV2.setAuth(authSession.accessToken)
        let sessions = SupabasePrayerSessionRepository(client: firstClient, identity: identity)
        let firstPresence = SupabasePresenceRepository(client: firstClient, identity: identity)
        let secondPresence = SupabasePresenceRepository(client: secondClient, identity: identity)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let now = Date()
        let scope = PrayerSessionScope(prayer: .dhuhr, prayerTime: now, calendar: calendar)
        let session = try await sessions.session(
            for: PrayerSessionRequest(scope: scope, expectedPrayerTime: now)
        )

        let firstRecorder = SnapshotRecorder()
        let secondRecorder = SnapshotRecorder()
        let firstStream = await firstPresence.snapshots(for: session.id)
        let secondStream = await secondPresence.snapshots(for: session.id)
        let firstObservation = record(firstStream, in: firstRecorder)
        let secondObservation = record(secondStream, in: secondRecorder)
        defer {
            firstObservation.cancel()
            secondObservation.cancel()
        }

        do {
            try await waitUntil("both private channel subscriptions are ready") {
                let firstIsReady = await firstRecorder.hasSnapshot
                let secondIsReady = await secondRecorder.hasSnapshot
                return firstIsReady && secondIsReady
            }
        } catch {
            let firstFailure = await firstRecorder.failureDescription
            let secondFailure = await secondRecorder.failureDescription
            XCTFail("Realtime subscribe failures: first=\(firstFailure), second=\(secondFailure)")
            throw error
        }

        let firstLease = try await firstPresence.upsertPresence(
            PresenceMutation(
                commandID: UUID(),
                sessionID: session.id,
                clientInstanceID: UUID(),
                status: .ready,
                createdAt: now
            )
        )
        defer { Task { await firstPresence.leave(leaseID: firstLease.id) } }

        try await waitUntil("the second client sees the first client join") {
            await secondRecorder.latest?.counts.ready == 1
        }

        let secondLease = try await secondPresence.upsertPresence(
            PresenceMutation(
                commandID: UUID(),
                sessionID: session.id,
                clientInstanceID: UUID(),
                status: .makingWudu,
                createdAt: now
            )
        )

        try await waitUntil("the first client sees both participants") {
            guard let counts = await firstRecorder.latest?.counts else { return false }
            return counts.ready == 1 && counts.makingWudu == 1 && counts.total == 2
        }

        await secondPresence.leave(leaseID: secondLease.id)
        try await waitUntil("the first client sees the second client leave") {
            guard let counts = await firstRecorder.latest?.counts else { return false }
            return counts.ready == 1 && counts.makingWudu == 0 && counts.total == 1
        }
    }

    private func record(
        _ stream: AsyncThrowingStream<PresenceSnapshot, Error>,
        in recorder: SnapshotRecorder
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await snapshot in stream {
                    await recorder.append(snapshot)
                }
            } catch {
                await recorder.fail(error)
            }
        }
    }

    private func makeIsolatedClient(_ configuration: SupabaseBackendConfiguration) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(storage: InMemoryAuthStorage())
            )
        )
    }

    private func makeTokenClient(
        _ configuration: SupabaseBackendConfiguration,
        accessToken: String
    ) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: InMemoryAuthStorage(),
                    accessToken: { accessToken }
                ),
                realtime: .init(
                    maxRetryAttempts: 1,
                    handleAppLifecycle: false
                )
            )
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(15),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTFail("Timed out waiting for \(description).")
        throw RealtimeIntegrationError.timeout
    }
}

private final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        lock.withLock { values[key] = nil }
    }
}

private struct FixedAnonymousIdentityRepository: AnonymousIdentityRepository {
    let identity: AnonymousBackendIdentity

    func currentIdentity() async throws -> AnonymousBackendIdentity { identity }
    func createIdentityIfNeeded() async throws -> AnonymousBackendIdentity { identity }
}

private actor SnapshotRecorder {
    private(set) var latest: PresenceSnapshot?
    private(set) var failure: Error?

    var hasSnapshot: Bool { latest != nil }
    var failureDescription: String { failure.map { String(reflecting: $0) } ?? "none" }

    func append(_ snapshot: PresenceSnapshot) {
        latest = snapshot
    }

    func fail(_ error: Error) {
        failure = error
    }
}

private enum RealtimeIntegrationError: Error {
    case timeout
}
