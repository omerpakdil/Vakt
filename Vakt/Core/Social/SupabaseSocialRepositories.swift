import Foundation
import Supabase

actor SupabaseSocialAuthRepository: SocialAuthRepository {
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

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }
}

actor SupabaseSocialProfileRepository: SocialProfileRepository {
    private let client: SupabaseClient
    private let auth: any SocialAuthRepository

    init(client: SupabaseClient, auth: any SocialAuthRepository) {
        self.client = client
        self.auth = auth
    }

    func currentProfile() async throws -> SocialProfile? {
        let userID = try await auth.currentUserID()

        do {
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .select(Self.profileColumns)
                .eq("id", value: userID.rawValue.uuidString)
                .limit(1)
                .execute()
                .value

            return rows.first.map(SocialProfile.init(row:))
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func upsertProfile(
        displayName: String,
        username: String,
        avatarURL: URL?,
        isPrayerStatusVisible: Bool,
        profileCompletedAt: Date?
    ) async throws -> SocialProfile {
        let userID = try await auth.currentUserID()

        do {
            let payload = ProfileUpsertPayload(
                id: userID.rawValue,
                displayName: displayName,
                username: username.lowercased(),
                avatarURL: avatarURL?.absoluteString,
                isPrayerStatusVisible: isPrayerStatusVisible,
                profileCompletedAt: profileCompletedAt
            )
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .upsert(payload, onConflict: "id")
                .select(Self.profileColumns)
                .execute()
                .value

            guard let row = rows.first else { throw BackendError.invalidResponse }
            return SocialProfile(row: row)
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func availableUsernames(_ candidates: [String]) async throws -> [String] {
        guard !candidates.isEmpty else { return [] }

        do {
            return try await client
                .rpc("available_usernames", params: UsernameAvailabilityParameters(candidates: candidates))
                .execute()
                .value
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func searchProfiles(usernamePrefix: String) async throws -> [SocialProfile] {
        let trimmed = usernamePrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard trimmed.count >= 2 else { return [] }

        do {
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .select(Self.profileColumns)
                .ilike("username", pattern: "\(trimmed)%")
                .limit(20)
                .execute()
                .value

            return rows.map(SocialProfile.init(row:))
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    private static let profileColumns = "id,display_name,username,avatar_url,is_prayer_status_visible,profile_completed_at"
}

actor SupabaseFriendshipRepository: FriendshipRepository {
    private let client: SupabaseClient
    private let auth: any SocialAuthRepository

    init(client: SupabaseClient, auth: any SocialAuthRepository) {
        self.client = client
        self.auth = auth
    }

    func friends() async throws -> [SocialProfile] {
        let userID = try await auth.currentUserID()

        do {
            let rows: [FriendshipRow] = try await client
                .from("friendships")
                .select("id,requester_id,receiver_id,status,created_at,updated_at")
                .eq("status", value: FriendshipStatus.accepted.rawValue)
                .or("requester_id.eq.\(userID.rawValue.uuidString),receiver_id.eq.\(userID.rawValue.uuidString)")
                .execute()
                .value

            let friendIDs = rows.map { row in
                row.requesterID == userID.rawValue ? row.receiverID : row.requesterID
            }
            guard !friendIDs.isEmpty else { return [] }

            let profiles: [ProfileRow] = try await client
                .from("profiles")
                .select("id,display_name,username,avatar_url,is_prayer_status_visible")
                .in("id", values: friendIDs.map(\.uuidString))
                .execute()
                .value

            return profiles.map(SocialProfile.init(row:))
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func pendingRequests() async throws -> [PendingFriendRequest] {
        let userID = try await auth.currentUserID()

        do {
            let rows: [FriendshipRow] = try await client
                .from("friendships")
                .select("id,requester_id,receiver_id,status,created_at,updated_at")
                .eq("status", value: FriendshipStatus.pending.rawValue)
                .eq("receiver_id", value: userID.rawValue.uuidString)
                .execute()
                .value

            let requesterIDs = rows.map(\.requesterID)
            guard !requesterIDs.isEmpty else { return [] }

            let profiles: [ProfileRow] = try await client
                .from("profiles")
                .select("id,display_name,username,avatar_url,is_prayer_status_visible")
                .in("id", values: requesterIDs.map(\.uuidString))
                .execute()
                .value
            let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, SocialProfile(row: $0)) })

            return rows.compactMap { row in
                guard
                    let friendship = Friendship(row: row),
                    let requester = profilesByID[row.requesterID]
                else {
                    return nil
                }
                return PendingFriendRequest(friendship: friendship, requester: requester)
            }
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func requestFriendship(receiverID: VaktUserID) async throws -> FriendshipRequestResult {
        let userID = try await auth.currentUserID()

        do {
            if let existing = try await friendship(between: userID, and: receiverID) {
                return try FriendshipRequestClassifier.classify(existing, currentUserID: userID)
            }

            let payload = FriendshipInsertPayload(
                requesterID: userID.rawValue,
                receiverID: receiverID.rawValue,
                status: FriendshipStatus.pending.rawValue
            )
            let rows: [FriendshipRow] = try await client
                .from("friendships")
                .insert(payload)
                .select("id,requester_id,receiver_id,status,created_at,updated_at")
                .execute()
                .value

            guard let friendship = rows.first.flatMap(Friendship.init(row:)) else {
                throw BackendError.invalidResponse
            }
            try? await client.functions.invoke(
                "send-friend-event",
                options: FunctionInvokeOptions(
                    body: FriendEventDeliveryPayload(friendshipID: friendship.id, event: "requested")
                )
            )
            return .sent(friendship)
        } catch {
            let mappedError = SupabaseBackendErrorMapper.map(error)
            if mappedError == .conflict,
               let existing = await friendshipAfterConflict(between: userID, and: receiverID) {
                return try FriendshipRequestClassifier.classify(existing, currentUserID: userID)
            }
            throw mappedError
        }
    }

    private func friendshipAfterConflict(
        between userID: VaktUserID,
        and otherUserID: VaktUserID
    ) async -> Friendship? {
        try? await friendship(between: userID, and: otherUserID)
    }

    private func friendship(
        between userID: VaktUserID,
        and otherUserID: VaktUserID
    ) async throws -> Friendship? {
        let user = userID.rawValue.uuidString
        let other = otherUserID.rawValue.uuidString
        let rows: [FriendshipRow] = try await client
            .from("friendships")
            .select("id,requester_id,receiver_id,status,created_at,updated_at")
            .or("and(requester_id.eq.\(user),receiver_id.eq.\(other)),and(requester_id.eq.\(other),receiver_id.eq.\(user))")
            .limit(1)
            .execute()
            .value

        return rows.first.flatMap(Friendship.init(row:))
    }

    func acceptFriendship(_ friendshipID: UUID) async throws -> Friendship {
        do {
            let rows: [FriendshipRow] = try await client
                .from("friendships")
                .update(FriendshipStatusUpdatePayload(status: FriendshipStatus.accepted.rawValue))
                .eq("id", value: friendshipID.uuidString)
                .select("id,requester_id,receiver_id,status,created_at,updated_at")
                .execute()
                .value

            guard let friendship = rows.first.flatMap(Friendship.init(row:)) else {
                throw BackendError.invalidResponse
            }
            try? await client.functions.invoke(
                "send-friend-event",
                options: FunctionInvokeOptions(
                    body: FriendEventDeliveryPayload(friendshipID: friendship.id, event: "accepted")
                )
            )
            return friendship
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func removeFriendship(_ friendshipID: UUID) async throws {
        do {
            try await client
                .from("friendships")
                .delete()
                .eq("id", value: friendshipID.uuidString)
                .execute()
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }
}

actor SupabaseSocialPrayerStatusRepository: SocialPrayerStatusRepository {
    private let client: SupabaseClient
    private let auth: any SocialAuthRepository

    init(client: SupabaseClient, auth: any SocialAuthRepository) {
        self.client = client
        self.auth = auth
    }

    func statuses(for day: LocalPrayerDay) async throws -> [SocialPrayerStatusEntry] {
        let userID = try await auth.currentUserID()

        do {
            let rows: [PrayerStatusRow] = try await client
                .from("prayer_statuses")
                .select("id,user_id,prayer_date,prayer_name,timezone,status,marked_at")
                .eq("user_id", value: userID.rawValue.uuidString)
                .eq("prayer_date", value: day.databaseValue)
                .execute()
                .value

            return rows.compactMap(SocialPrayerStatusEntry.init(row:))
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func friendSummaries(for day: LocalPrayerDay) async throws -> [FriendPrayerSummary] {
        let friendsRepository = SupabaseFriendshipRepository(client: client, auth: auth)
        let friends = try await friendsRepository.friends()
        guard !friends.isEmpty else { return [] }

        do {
            let friendIDs = friends.map { $0.id.rawValue.uuidString }
            let rows: [PrayerStatusRow] = try await client
                .from("prayer_statuses")
                .select("id,user_id,prayer_date,prayer_name,timezone,status,marked_at")
                .in("user_id", values: friendIDs)
                .eq("prayer_date", value: day.databaseValue)
                .execute()
                .value

            let statuses = rows.compactMap(SocialPrayerStatusEntry.init(row:))
            return friends.map { profile in
                let userStatuses = statuses.filter { $0.userID == profile.id }
                let mapped = Dictionary(uniqueKeysWithValues: userStatuses.map { ($0.prayer, $0.status) })
                return FriendPrayerSummary(
                    id: profile.id,
                    profile: profile,
                    statuses: mapped,
                    lastMarkedAt: userStatuses.map(\.markedAt).max()
                )
            }
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func upsertStatus(
        prayer: PrayerKey,
        day: LocalPrayerDay,
        timeZoneIdentifier: String,
        status: SocialPrayerStatus,
        markedAt: Date
    ) async throws -> SocialPrayerStatusEntry {
        let userID = try await auth.currentUserID()

        do {
            let payload = PrayerStatusUpsertPayload(
                userID: userID.rawValue,
                prayerDate: day.databaseValue,
                prayerName: prayer.rawValue,
                timezone: timeZoneIdentifier,
                status: status.rawValue,
                markedAt: markedAt
            )
            let rows: [PrayerStatusRow] = try await client
                .from("prayer_statuses")
                .upsert(payload, onConflict: "user_id,prayer_date,prayer_name")
                .select("id,user_id,prayer_date,prayer_name,timezone,status,marked_at")
                .execute()
                .value

            guard let entry = rows.first.flatMap(SocialPrayerStatusEntry.init(row:)) else {
                throw BackendError.invalidResponse
            }
            return entry
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }
}

actor SupabaseMakeupPrayerRepository: MakeupPrayerRepository {
    private let client: SupabaseClient
    private let auth: any SocialAuthRepository

    init(client: SupabaseClient, auth: any SocialAuthRepository) {
        self.client = client
        self.auth = auth
    }

    func openMakeupPrayers() async throws -> [MakeupPrayer] {
        let userID = try await auth.currentUserID()

        do {
            let rows: [MakeupPrayerRow] = try await client
                .from("makeup_prayers")
                .select("id,user_id,original_prayer_date,prayer_name,timezone,status,created_at,completed_at")
                .eq("user_id", value: userID.rawValue.uuidString)
                .eq("status", value: MakeupPrayerStatus.open.rawValue)
                .order("original_prayer_date", ascending: true)
                .execute()
                .value

            return rows.compactMap(MakeupPrayer.init(row:))
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func openMakeupPrayers(in month: MakeupPrayerMonth) async throws -> [MakeupPrayer] {
        let userID = try await auth.currentUserID()

        do {
            let rows: [MakeupPrayerRow] = try await client
                .from("makeup_prayers")
                .select("id,user_id,original_prayer_date,prayer_name,timezone,status,created_at,completed_at")
                .eq("user_id", value: userID.rawValue.uuidString)
                .eq("status", value: MakeupPrayerStatus.open.rawValue)
                .gte("original_prayer_date", value: month.firstDay.databaseValue)
                .lt("original_prayer_date", value: month.nextMonthFirstDay.databaseValue)
                .order("original_prayer_date", ascending: true)
                .execute()
                .value

            return rows.compactMap(MakeupPrayer.init(row:))
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func openMakeupPrayerCount() async throws -> Int {
        let userID = try await auth.currentUserID()

        do {
            let response = try await client
                .from("makeup_prayers")
                .select("id", head: true, count: .exact)
                .eq("user_id", value: userID.rawValue.uuidString)
                .eq("status", value: MakeupPrayerStatus.open.rawValue)
                .execute()

            return response.count ?? 0
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func ensureOpenMakeupPrayer(
        prayer: PrayerKey,
        day: LocalPrayerDay,
        timeZoneIdentifier: String
    ) async throws -> MakeupPrayer {
        let userID = try await auth.currentUserID()

        do {
            let payload = MakeupPrayerUpsertPayload(
                userID: userID.rawValue,
                originalPrayerDate: day.databaseValue,
                prayerName: prayer.rawValue,
                timezone: timeZoneIdentifier,
                status: MakeupPrayerStatus.open.rawValue,
                completedAt: nil
            )
            let rows: [MakeupPrayerRow] = try await client
                .from("makeup_prayers")
                .upsert(payload, onConflict: "user_id,original_prayer_date,prayer_name")
                .select("id,user_id,original_prayer_date,prayer_name,timezone,status,created_at,completed_at")
                .execute()
                .value

            guard let makeup = rows.first.flatMap(MakeupPrayer.init(row:)) else {
                throw BackendError.invalidResponse
            }
            return makeup
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func completeMakeupPrayer(_ id: UUID, completedAt: Date) async throws -> MakeupPrayer {
        do {
            let payload = MakeupPrayerCompletePayload(
                status: MakeupPrayerStatus.completed.rawValue,
                completedAt: completedAt
            )
            let rows: [MakeupPrayerRow] = try await client
                .from("makeup_prayers")
                .update(payload)
                .eq("id", value: id.uuidString)
                .select("id,user_id,original_prayer_date,prayer_name,timezone,status,created_at,completed_at")
                .execute()
                .value

            guard let makeup = rows.first.flatMap(MakeupPrayer.init(row:)) else {
                throw BackendError.invalidResponse
            }
            return makeup
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }
}

actor SupabasePrayerDeadlineRepository: PrayerDeadlineRepository {
    private let client: SupabaseClient
    private let auth: any SocialAuthRepository

    init(client: SupabaseClient, auth: any SocialAuthRepository) {
        self.client = client
        self.auth = auth
    }

    func sync(_ deadlines: [PrayerDeadline]) async throws {
        guard !deadlines.isEmpty else { return }
        let userID = try await auth.currentUserID()
        let payload = deadlines.map {
            PrayerDeadlineUpsertPayload(
                userID: userID.rawValue,
                prayerDate: $0.localDay.databaseValue,
                prayerName: $0.prayer.rawValue,
                timezone: $0.timeZoneIdentifier,
                prayerAt: $0.prayerAt,
                closesAt: $0.closesAt
            )
        }

        do {
            try await client
                .from("prayer_deadlines")
                .upsert(payload, onConflict: "user_id,prayer_date,prayer_name")
                .execute()
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func reconcileOverdue() async throws {
        do {
            try await client
                .rpc("reconcile_my_overdue_prayers")
                .execute()
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }
}

actor SupabaseNudgeRepository: NudgeRepository {
    private let client: SupabaseClient
    private let auth: any SocialAuthRepository

    init(client: SupabaseClient, auth: any SocialAuthRepository) {
        self.client = client
        self.auth = auth
    }

    func sendNudge(to userID: VaktUserID, prayer: PrayerKey, day: LocalPrayerDay) async throws -> PrayerNudge {
        let currentUserID = try await auth.currentUserID()

        do {
            let payload = NudgeInsertPayload(
                fromUserID: currentUserID.rawValue,
                toUserID: userID.rawValue,
                prayerDate: day.databaseValue,
                prayerName: prayer.rawValue
            )
            let rows: [NudgeRow] = try await client
                .from("nudges")
                .insert(payload)
                .select("id,from_user_id,to_user_id,prayer_date,prayer_name,created_at")
                .execute()
                .value

            guard let nudge = rows.first.flatMap(PrayerNudge.init(row:)) else {
                throw BackendError.invalidResponse
            }

            do {
                try await client.functions.invoke(
                    "send-nudge",
                    options: FunctionInvokeOptions(body: NudgeDeliveryPayload(nudgeID: nudge.id))
                )
            } catch {
                throw SupabaseBackendErrorMapper.map(error)
            }
            return nudge
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }

    func sentNudges(for day: LocalPrayerDay) async throws -> [PrayerNudge] {
        let currentUserID = try await auth.currentUserID()

        do {
            let rows: [NudgeRow] = try await client
                .from("nudges")
                .select("id,from_user_id,to_user_id,prayer_date,prayer_name,created_at")
                .eq("from_user_id", value: currentUserID.rawValue.uuidString)
                .eq("prayer_date", value: day.databaseValue)
                .execute()
                .value
            return rows.compactMap(PrayerNudge.init(row:))
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }
}

actor SupabaseDeviceTokenRepository: DeviceTokenRepository {
    private let client: SupabaseClient
    private let auth: any SocialAuthRepository

    init(client: SupabaseClient, auth: any SocialAuthRepository) {
        self.client = client
        self.auth = auth
    }

    func register(token: String, languageCode: String) async throws {
        let userID = try await auth.currentUserID()
        let payload = DeviceTokenUpsertPayload(
            userID: userID.rawValue,
            token: token,
            platform: "ios",
            languageCode: languageCode,
            updatedAt: Date()
        )

        do {
            try await client
                .from("device_tokens")
                .upsert(payload, onConflict: "token")
                .execute()
        } catch {
            throw SupabaseBackendErrorMapper.map(error)
        }
    }
}

private struct ProfileRow: Decodable, Sendable {
    let id: UUID
    let displayName: String
    let username: String
    let avatarURL: String?
    let isPrayerStatusVisible: Bool
    let profileCompletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case avatarURL = "avatar_url"
        case isPrayerStatusVisible = "is_prayer_status_visible"
        case profileCompletedAt = "profile_completed_at"
    }
}

private struct NudgeDeliveryPayload: Encodable, Sendable {
    let nudgeID: UUID

    enum CodingKeys: String, CodingKey {
        case nudgeID = "nudge_id"
    }
}

private struct FriendEventDeliveryPayload: Encodable, Sendable {
    let friendshipID: UUID
    let event: String

    enum CodingKeys: String, CodingKey {
        case friendshipID = "friendship_id"
        case event
    }
}

private struct DeviceTokenUpsertPayload: Encodable, Sendable {
    let userID: UUID
    let token: String
    let platform: String
    let languageCode: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case token
        case platform
        case languageCode = "language_code"
        case updatedAt = "updated_at"
    }
}

private struct ProfileUpsertPayload: Encodable, Sendable {
    let id: UUID
    let displayName: String
    let username: String
    let avatarURL: String?
    let isPrayerStatusVisible: Bool
    let profileCompletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case avatarURL = "avatar_url"
        case isPrayerStatusVisible = "is_prayer_status_visible"
        case profileCompletedAt = "profile_completed_at"
    }
}

private struct UsernameAvailabilityParameters: Encodable, Sendable {
    let candidates: [String]
}

private struct FriendshipRow: Decodable, Sendable {
    let id: UUID
    let requesterID: UUID
    let receiverID: UUID
    let status: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case requesterID = "requester_id"
        case receiverID = "receiver_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct FriendshipInsertPayload: Encodable, Sendable {
    let requesterID: UUID
    let receiverID: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case requesterID = "requester_id"
        case receiverID = "receiver_id"
        case status
    }
}

private struct FriendshipStatusUpdatePayload: Encodable, Sendable {
    let status: String
}

private struct PrayerStatusRow: Decodable, Sendable {
    let id: UUID
    let userID: UUID
    let prayerDate: String
    let prayerName: String
    let timezone: String
    let status: String
    let markedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case prayerDate = "prayer_date"
        case prayerName = "prayer_name"
        case timezone
        case status
        case markedAt = "marked_at"
    }
}

private struct PrayerStatusUpsertPayload: Encodable, Sendable {
    let userID: UUID
    let prayerDate: String
    let prayerName: String
    let timezone: String
    let status: String
    let markedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case prayerDate = "prayer_date"
        case prayerName = "prayer_name"
        case timezone
        case status
        case markedAt = "marked_at"
    }
}

private struct MakeupPrayerRow: Decodable, Sendable {
    let id: UUID
    let userID: UUID
    let originalPrayerDate: String
    let prayerName: String
    let timezone: String
    let status: String
    let createdAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case originalPrayerDate = "original_prayer_date"
        case prayerName = "prayer_name"
        case timezone
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

private struct MakeupPrayerUpsertPayload: Encodable, Sendable {
    let userID: UUID
    let originalPrayerDate: String
    let prayerName: String
    let timezone: String
    let status: String
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case originalPrayerDate = "original_prayer_date"
        case prayerName = "prayer_name"
        case timezone
        case status
        case completedAt = "completed_at"
    }
}

private struct MakeupPrayerCompletePayload: Encodable, Sendable {
    let status: String
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case completedAt = "completed_at"
    }
}

private struct PrayerDeadlineUpsertPayload: Encodable, Sendable {
    let userID: UUID
    let prayerDate: String
    let prayerName: String
    let timezone: String
    let prayerAt: Date
    let closesAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case prayerDate = "prayer_date"
        case prayerName = "prayer_name"
        case timezone
        case prayerAt = "prayer_at"
        case closesAt = "closes_at"
    }
}

private struct NudgeRow: Decodable, Sendable {
    let id: UUID
    let fromUserID: UUID
    let toUserID: UUID
    let prayerDate: String
    let prayerName: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case fromUserID = "from_user_id"
        case toUserID = "to_user_id"
        case prayerDate = "prayer_date"
        case prayerName = "prayer_name"
        case createdAt = "created_at"
    }
}

private struct NudgeInsertPayload: Encodable, Sendable {
    let fromUserID: UUID
    let toUserID: UUID
    let prayerDate: String
    let prayerName: String

    enum CodingKeys: String, CodingKey {
        case fromUserID = "from_user_id"
        case toUserID = "to_user_id"
        case prayerDate = "prayer_date"
        case prayerName = "prayer_name"
    }
}

private extension SocialProfile {
    init(row: ProfileRow) {
        self.init(
            id: VaktUserID(rawValue: row.id),
            displayName: row.displayName,
            username: row.username,
            avatarURL: row.avatarURL.flatMap(URL.init(string:)),
            isPrayerStatusVisible: row.isPrayerStatusVisible,
            profileCompletedAt: row.profileCompletedAt
        )
    }
}

private extension Friendship {
    init?(row: FriendshipRow) {
        guard let status = FriendshipStatus(rawValue: row.status) else { return nil }
        self.init(
            id: row.id,
            requesterID: VaktUserID(rawValue: row.requesterID),
            receiverID: VaktUserID(rawValue: row.receiverID),
            status: status,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt
        )
    }
}

private extension SocialPrayerStatusEntry {
    init?(row: PrayerStatusRow) {
        guard
            let prayer = PrayerKey(rawValue: row.prayerName),
            let status = SocialPrayerStatus(rawValue: row.status),
            let day = LocalPrayerDay(databaseValue: row.prayerDate)
        else {
            return nil
        }

        self.init(
            id: row.id,
            userID: VaktUserID(rawValue: row.userID),
            localDay: day,
            prayer: prayer,
            timeZoneIdentifier: row.timezone,
            status: status,
            markedAt: row.markedAt
        )
    }
}

private extension MakeupPrayer {
    init?(row: MakeupPrayerRow) {
        guard
            let prayer = PrayerKey(rawValue: row.prayerName),
            let status = MakeupPrayerStatus(rawValue: row.status),
            let day = LocalPrayerDay(databaseValue: row.originalPrayerDate)
        else {
            return nil
        }

        self.init(
            id: row.id,
            userID: VaktUserID(rawValue: row.userID),
            originalLocalDay: day,
            prayer: prayer,
            timeZoneIdentifier: row.timezone,
            status: status,
            createdAt: row.createdAt,
            completedAt: row.completedAt
        )
    }
}

private extension PrayerNudge {
    init?(row: NudgeRow) {
        guard
            let prayer = PrayerKey(rawValue: row.prayerName),
            let day = LocalPrayerDay(databaseValue: row.prayerDate)
        else {
            return nil
        }

        self.init(
            id: row.id,
            fromUserID: VaktUserID(rawValue: row.fromUserID),
            toUserID: VaktUserID(rawValue: row.toUserID),
            localDay: day,
            prayer: prayer,
            createdAt: row.createdAt
        )
    }
}

private extension LocalPrayerDay {
    init?(databaseValue: String) {
        let parts = databaseValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

}
