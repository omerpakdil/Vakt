import Foundation

@MainActor
enum BackendComposition {
    static func makePresenceStore(initialCount _: Int) -> LiveSafPresenceStore {
        guard let configuration = try? SupabaseBackendConfiguration.load() else {
            return LiveSafPresenceStore(initialCount: 0)
        }

        let client = configuration.makeClient()
        let identity = SupabaseAnonymousIdentityRepository(client: client)
        let sessions = SupabasePrayerSessionRepository(client: client, identity: identity)
        let presence = SupabasePresenceRepository(client: client, identity: identity)

        return LiveSafPresenceStore(
            initialCount: 0,
            sessions: sessions,
            presence: presence,
            minimumInitialCount: 0,
            initialSource: .cached
        )
    }

    static func makeSpiritualContentStore() -> SpiritualContentStore {
        guard let configuration = try? SupabaseBackendConfiguration.load() else {
            return SpiritualContentStore()
        }

        let repository = SupabaseSpiritualContentRepository(
            client: configuration.makeClient()
        )
        return SpiritualContentStore(repository: repository)
    }

    static func makeSocialAccountStore() -> SocialAccountStore {
        guard let configuration = try? SupabaseBackendConfiguration.load() else {
            return SocialAccountStore(auth: nil, profiles: nil)
        }

        let client = configuration.makeClient()
        let auth = SupabaseAppleSocialAuthRepository(client: client)
        let profiles = SupabaseSocialProfileRepository(client: client, auth: auth)
        return SocialAccountStore(auth: auth, profiles: profiles)
    }

    static func makeSocialRepositories() -> SocialRepositories? {
        guard let configuration = try? SupabaseBackendConfiguration.load() else {
            return nil
        }

        let client = configuration.makeClient()
        let auth = SupabaseAppleSocialAuthRepository(client: client)
        return SocialRepositories(
            auth: auth,
            profiles: SupabaseSocialProfileRepository(client: client, auth: auth),
            friendships: SupabaseFriendshipRepository(client: client, auth: auth),
            prayerStatuses: SupabaseSocialPrayerStatusRepository(client: client, auth: auth),
            makeupPrayers: SupabaseMakeupPrayerRepository(client: client, auth: auth),
            prayerDeadlines: SupabasePrayerDeadlineRepository(client: client, auth: auth),
            nudges: SupabaseNudgeRepository(client: client, auth: auth),
            deviceTokens: SupabaseDeviceTokenRepository(client: client, auth: auth)
        )
    }

    static func makeSocialPrayerStore() -> SocialPrayerStore {
        SocialPrayerStore(repositories: makeSocialRepositories())
    }

    static func makeReferralStore() -> ReferralStore {
        guard let configuration = try? SupabaseBackendConfiguration.load() else {
            return ReferralStore(repository: nil)
        }
        return ReferralStore(
            repository: SupabaseReferralRepository(client: configuration.makeClient())
        )
    }
}
