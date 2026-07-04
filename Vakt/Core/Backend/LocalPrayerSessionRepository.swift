import Foundation

actor LocalPrayerSessionRepository: PrayerSessionRepository {
    private var sessions: [PrayerSessionScope: BackendPrayerSession] = [:]
    private let opensBeforePrayer: TimeInterval
    private let closesAfterPrayer: TimeInterval

    init(
        opensBeforePrayer: TimeInterval = 30 * 60,
        closesAfterPrayer: TimeInterval = 90 * 60
    ) {
        self.opensBeforePrayer = opensBeforePrayer
        self.closesAfterPrayer = closesAfterPrayer
    }

    func session(for request: PrayerSessionRequest) async throws -> BackendPrayerSession {
        if let existing = sessions[request.scope] {
            return existing
        }

        let session = BackendPrayerSession(
            id: PrayerSessionID(rawValue: UUID()),
            scope: request.scope,
            opensAt: request.expectedPrayerTime.addingTimeInterval(-opensBeforePrayer),
            prayerTime: request.expectedPrayerTime,
            closesAt: request.expectedPrayerTime.addingTimeInterval(closesAfterPrayer)
        )
        sessions[request.scope] = session
        return session
    }
}
