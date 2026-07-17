import AuthenticationServices
import Foundation
import RevenueCat
import Supabase

actor SupabaseAppleSocialAuthRepository: SocialAuthRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentUserID() async throws -> VaktUserID {
        do {
            let session = try await client.auth.session
            await client.realtimeV2.setAuth(session.accessToken)
            return VaktUserID(rawValue: session.user.id)
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func signInWithApple(identityToken: String, fullName: String?) async throws -> VaktUserID {
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken
                )
            )
            await client.realtimeV2.setAuth(session.accessToken)
            if let fullName, !fullName.isEmpty {
                _ = try? await client.auth.update(
                    user: UserAttributes(data: ["full_name": .string(fullName)])
                )
            }
            _ = try? await Purchases.shared.logIn(session.user.id.uuidString)
            return VaktUserID(rawValue: session.user.id)
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
            _ = try? await Purchases.shared.logOut()
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func deleteAccount(authorizationCode: String) async throws {
        do {
            try await client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(
                    body: AppleAccountDeletionPayload(authorizationCode: authorizationCode)
                )
            )
            try? await client.auth.signOut(scope: .local)
            _ = try? await Purchases.shared.logOut()
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }
}

@MainActor
final class SocialAccountStore: ObservableObject {
    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(VaktUserID)
        case failed(String)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var profile: SocialProfile?

    private let auth: SupabaseAppleSocialAuthRepository?
    private let profiles: (any SocialProfileRepository)?

    init(auth: SupabaseAppleSocialAuthRepository?, profiles: (any SocialProfileRepository)?) {
        self.auth = auth
        self.profiles = profiles
    }

    func restoreSession() async {
        guard let auth else {
            state = .signedOut
            return
        }

        do {
            let userID = try await auth.currentUserID()
            state = .signedIn(userID)
            profile = try await profiles?.currentProfile()
            _ = try? await Purchases.shared.logIn(userID.rawValue.uuidString)
        } catch {
            state = .signedOut
        }
    }

    func signIn(authorization: ASAuthorization) async {
        guard let auth else {
            state = .failed(L10n.string("auth.sign_in.error.not_configured"))
            return
        }
        state = .checking
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
        else {
            state = .failed(L10n.string("auth.sign_in.error.invalid_token"))
            return
        }

        do {
            let fullName = credential.fullName?.formatted()
            let userID = try await auth.signInWithApple(identityToken: identityToken, fullName: fullName)
            state = .signedIn(userID)
            profile = try await ensureProfile(for: userID, fullName: fullName)
        } catch {
            state = .failed(L10n.string("auth.sign_in.error.sign_in_failed"))
        }
    }

    func signOut() async {
        guard let auth else {
            state = .signedOut
            return
        }

        do {
            try await auth.signOut()
            profile = nil
            state = .signedOut
        } catch {
            state = .failed(L10n.string("auth.sign_in.error.sign_out_failed"))
        }
    }

    func updateProfile(
        displayName: String,
        username: String,
        isPrayerStatusVisible: Bool
    ) async throws {
        guard let profiles else { throw BackendError.notConfigured }
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard (1...48).contains(cleanName.count) else {
            throw BackendError.invalidConfiguration(message: L10n.string("account.validation.name"))
        }
        guard cleanUsername.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil else {
            throw BackendError.invalidConfiguration(message: L10n.string("account.validation.username"))
        }

        profile = try await profiles.upsertProfile(
            displayName: cleanName,
            username: cleanUsername,
            avatarURL: profile?.avatarURL,
            isPrayerStatusVisible: isPrayerStatusVisible
        )
    }

    func deleteAccount(authorization: ASAuthorization) async throws {
        guard let auth else { throw BackendError.notConfigured }
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let codeData = credential.authorizationCode,
            let authorizationCode = String(data: codeData, encoding: .utf8),
            !authorizationCode.isEmpty
        else {
            throw BackendError.invalidResponse
        }

        try await auth.deleteAccount(authorizationCode: authorizationCode)
        profile = nil
        state = .signedOut
    }

    func showSignInError(_ message: String) {
        state = .failed(message)
    }

    private func ensureProfile(for userID: VaktUserID, fullName: String?) async throws -> SocialProfile? {
        if let existing = try await profiles?.currentProfile() {
            return existing
        }

        let displayName = normalizedDisplayName(fullName: fullName)
        let username = "vakt_\(userID.rawValue.uuidString.prefix(8).lowercased())"
        return try await profiles?.upsertProfile(
            displayName: displayName,
            username: username,
            avatarURL: nil,
            isPrayerStatusVisible: true
        )
    }

    private func normalizedDisplayName(fullName: String?) -> String {
        let candidate = fullName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty {
            return String(candidate.prefix(48))
        }
        return L10n.string("auth.sign_in.default_display_name")
    }
}

private struct AppleAccountDeletionPayload: Encodable, Sendable {
    let authorizationCode: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
    }
}
