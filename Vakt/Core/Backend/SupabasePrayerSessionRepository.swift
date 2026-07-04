import Foundation
import Supabase

actor SupabasePrayerSessionRepository: PrayerSessionRepository {
    private let client: SupabaseClient
    private let identity: any AnonymousIdentityRepository

    init(client: SupabaseClient, identity: any AnonymousIdentityRepository) {
        self.client = client
        self.identity = identity
    }

    func session(for request: PrayerSessionRequest) async throws -> BackendPrayerSession {
        _ = try await identity.createIdentityIfNeeded()

        do {
            let parameters = ResolveSessionParameters(
                prayerName: request.scope.prayer.rawValue,
                prayerDate: request.scope.localDay.databaseValue,
                timezone: request.scope.timeZoneIdentifier,
                expectedPrayerTime: Self.timestamp(request.expectedPrayerTime)
            )
            let rows: [PrayerSessionRow] = try await client
                .rpc("resolve_prayer_session", params: parameters)
                .execute()
                .value

            guard let row = rows.first else {
                throw BackendError.invalidResponse
            }
            guard
                row.prayerName == request.scope.prayer.rawValue,
                row.prayerDate == request.scope.localDay.databaseValue,
                row.timezone == request.scope.timeZoneIdentifier
            else {
                throw BackendError.invalidResponse
            }

            return BackendPrayerSession(
                id: PrayerSessionID(rawValue: row.id),
                scope: request.scope,
                opensAt: row.opensAt,
                prayerTime: row.prayerTime,
                closesAt: row.closesAt
            )
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private struct ResolveSessionParameters: Encodable, Sendable {
    let prayerName: String
    let prayerDate: String
    let timezone: String
    let expectedPrayerTime: String

    enum CodingKeys: String, CodingKey {
        case prayerName = "p_prayer_name"
        case prayerDate = "p_prayer_date"
        case timezone = "p_timezone"
        case expectedPrayerTime = "p_expected_prayer_time"
    }
}

private struct PrayerSessionRow: Decodable, Sendable {
    let id: UUID
    let prayerName: String
    let prayerDate: String
    let timezone: String
    let opensAt: Date
    let prayerTime: Date
    let closesAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case prayerName = "prayer_name"
        case prayerDate = "prayer_date"
        case timezone
        case opensAt = "opens_at"
        case prayerTime = "prayer_time"
        case closesAt = "closes_at"
    }
}
