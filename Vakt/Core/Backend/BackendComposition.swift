import Foundation

@MainActor
enum BackendComposition {
    static func makePresenceStore(initialCount: Int) -> LiveSafPresenceStore {
        guard let configuration = try? SupabaseBackendConfiguration.load() else {
            return LiveSafPresenceStore(initialCount: initialCount)
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
}
