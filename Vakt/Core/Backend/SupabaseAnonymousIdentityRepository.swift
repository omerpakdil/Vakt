import Foundation
import Supabase

actor SupabaseAnonymousIdentityRepository: AnonymousIdentityRepository {
    typealias CaptchaTokenProvider = @Sendable () async throws -> String?

    private let client: SupabaseClient
    private let captchaTokenProvider: CaptchaTokenProvider
    private var identityTask: Task<AnonymousBackendIdentity, Error>?

    init(
        client: SupabaseClient,
        captchaTokenProvider: @escaping CaptchaTokenProvider = { nil }
    ) {
        self.client = client
        self.captchaTokenProvider = captchaTokenProvider
    }

    func currentIdentity() async throws -> AnonymousBackendIdentity {
        guard client.auth.currentSession != nil else {
            throw BackendError.unauthenticated
        }

        do {
            let session = try await client.auth.session
            await client.realtimeV2.setAuth(session.accessToken)
            return identity(from: session.user)
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func createIdentityIfNeeded() async throws -> AnonymousBackendIdentity {
        if client.auth.currentSession != nil {
            return try await currentIdentity()
        }

        if let identityTask {
            return try await identityTask.value
        }

        let client = self.client
        let captchaTokenProvider = self.captchaTokenProvider
        let task = Task<AnonymousBackendIdentity, Error> {
            do {
                let captchaToken = try await captchaTokenProvider()
                let session = try await client.auth.signInAnonymously(captchaToken: captchaToken)
                await client.realtimeV2.setAuth(session.accessToken)
                return AnonymousBackendIdentity(
                    userID: BackendUserID(rawValue: session.user.id),
                    isAnonymous: session.user.isAnonymous
                )
            } catch {
                throw SupabaseBackendErrorMapper.map(error)
            }
        }

        identityTask = task
        defer { identityTask = nil }
        return try await task.value
    }

    private func identity(from user: User) -> AnonymousBackendIdentity {
        AnonymousBackendIdentity(
            userID: BackendUserID(rawValue: user.id),
            isAnonymous: user.isAnonymous
        )
    }

}
