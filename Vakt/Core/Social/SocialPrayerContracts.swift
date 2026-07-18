import Foundation

protocol SocialAuthRepository: Sendable {
    func currentUserID() async throws -> VaktUserID
    func signOut() async throws
}

protocol SocialProfileRepository: Sendable {
    func currentProfile() async throws -> SocialProfile?
    func upsertProfile(
        displayName: String,
        username: String,
        avatarURL: URL?,
        isPrayerStatusVisible: Bool,
        profileCompletedAt: Date?
    ) async throws -> SocialProfile
    func availableUsernames(_ candidates: [String]) async throws -> [String]
    func searchProfiles(usernamePrefix: String) async throws -> [SocialProfile]
}

protocol FriendshipRepository: Sendable {
    func friends() async throws -> [SocialProfile]
    func pendingRequests() async throws -> [PendingFriendRequest]
    func requestFriendship(receiverID: VaktUserID) async throws -> FriendshipRequestResult
    func acceptFriendship(_ friendshipID: UUID) async throws -> Friendship
    func removeFriendship(_ friendshipID: UUID) async throws
}

protocol SocialPrayerStatusRepository: Sendable {
    func statuses(for day: LocalPrayerDay) async throws -> [SocialPrayerStatusEntry]
    func friendSummaries(for day: LocalPrayerDay) async throws -> [FriendPrayerSummary]
    func upsertStatus(
        prayer: PrayerKey,
        day: LocalPrayerDay,
        timeZoneIdentifier: String,
        status: SocialPrayerStatus,
        markedAt: Date
    ) async throws -> SocialPrayerStatusEntry
}

protocol MakeupPrayerRepository: Sendable {
    func openMakeupPrayers() async throws -> [MakeupPrayer]
    func openMakeupPrayers(in month: MakeupPrayerMonth) async throws -> [MakeupPrayer]
    func openMakeupPrayerCount() async throws -> Int
    func ensureOpenMakeupPrayer(
        prayer: PrayerKey,
        day: LocalPrayerDay,
        timeZoneIdentifier: String
    ) async throws -> MakeupPrayer
    func completeMakeupPrayer(_ id: UUID, completedAt: Date) async throws -> MakeupPrayer
}

protocol PrayerDeadlineRepository: Sendable {
    func sync(_ deadlines: [PrayerDeadline]) async throws
    func reconcileOverdue() async throws
}

protocol NudgeRepository: Sendable {
    func sendNudge(to userID: VaktUserID, prayer: PrayerKey, day: LocalPrayerDay) async throws -> PrayerNudge
    func sentNudges(for day: LocalPrayerDay) async throws -> [PrayerNudge]
}

protocol DeviceTokenRepository: Sendable {
    func register(token: String, languageCode: String) async throws
}

struct SocialRepositories: Sendable {
    let auth: any SocialAuthRepository
    let profiles: any SocialProfileRepository
    let friendships: any FriendshipRepository
    let prayerStatuses: any SocialPrayerStatusRepository
    let makeupPrayers: any MakeupPrayerRepository
    let prayerDeadlines: any PrayerDeadlineRepository
    let nudges: any NudgeRepository
    let deviceTokens: any DeviceTokenRepository
}
