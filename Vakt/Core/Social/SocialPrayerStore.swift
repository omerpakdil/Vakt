import Foundation

@MainActor
final class SocialPrayerStore: ObservableObject {
    @Published private(set) var todayEntries: [SocialPrayerStatusEntry] = []
    @Published private(set) var friendSummaries: [FriendPrayerSummary] = []
    @Published private(set) var openMakeupPrayers: [MakeupPrayer] = []
    @Published private(set) var openMakeupPrayerCount = 0
    @Published private(set) var makeupMonth: MakeupPrayerMonth?
    @Published private(set) var makeupDaySummaries: [MakeupPrayerDaySummary] = []
    @Published private(set) var isLoadingMakeupCalendar = false
    @Published private(set) var profileSearchResults: [SocialProfile] = []
    @Published private(set) var pendingRequests: [PendingFriendRequest] = []
    @Published private(set) var sentNudges: [PrayerNudge] = []
    @Published private(set) var sendingNudgeKeys: Set<String> = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastErrorMessage: String?

    private let repositories: SocialRepositories?

    init(repositories: SocialRepositories?) {
        self.repositories = repositories
    }

    var isConfigured: Bool {
        repositories != nil
    }

    func refresh(for date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        guard let repositories else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.refresh(
                repositories: repositories,
                day: Self.localDay(for: date, timeZone: timeZone)
            )
        }
    }

    func mark(_ prayerTime: PrayerTime, outcome: PrayerReflectionOutcome, markedAt: Date = Date()) {
        guard let repositories else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.syncMark(
                repositories: repositories,
                prayerTime: prayerTime,
                outcome: outcome,
                markedAt: markedAt
            )
        }
    }

    func completeMakeupPrayer(_ makeup: MakeupPrayer, completedAt: Date = Date()) {
        #if DEBUG
        if repositories == nil {
            openMakeupPrayers.removeAll { $0.id == makeup.id }
            openMakeupPrayerCount = openMakeupPrayers.count
            rebuildMakeupDaySummaries()
            return
        }
        #endif

        guard let repositories else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.syncMakeupCompletion(
                repositories: repositories,
                makeup: makeup,
                completedAt: completedAt
            )
        }
    }

    func loadMakeupCalendar(
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard let repositories else { return }
        let month = MakeupPrayerMonth(date: date, calendar: calendar)

        Task { [weak self] in
            guard let self else { return }
            isLoadingMakeupCalendar = true
            defer { isLoadingMakeupCalendar = false }

            do {
                async let prayers = repositories.makeupPrayers.openMakeupPrayers(in: month)
                async let count = repositories.makeupPrayers.openMakeupPrayerCount()
                let (monthPrayers, totalCount) = try await (prayers, count)
                applyMakeupCalendar(month: month, prayers: monthPrayers, totalCount: totalCount)
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func makeupPrayers(on day: LocalPrayerDay) -> [MakeupPrayer] {
        openMakeupPrayers.filter { $0.originalLocalDay == day }
    }

    #if DEBUG
    func configureMakeupPreview(calendar: Calendar = .autoupdatingCurrent) {
        guard repositories == nil, openMakeupPrayers.isEmpty else { return }

        let datesAndPrayers: [(Int, [PrayerKey])] = [
            (-1, [.fajr, .dhuhr, .asr, .maghrib, .isha]),
            (-5, [.fajr]),
            (-9, [.dhuhr, .maghrib, .isha])
        ]
        let previewUser = VaktUserID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

        openMakeupPrayers = datesAndPrayers.flatMap { dayOffset, prayers in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            let day = LocalPrayerDay(date: date, calendar: calendar)
            return prayers.map { prayer in
                MakeupPrayer(
                    id: UUID(),
                    userID: previewUser,
                    originalLocalDay: day,
                    prayer: prayer,
                    timeZoneIdentifier: calendar.timeZone.identifier,
                    status: .open,
                    createdAt: date,
                    completedAt: nil
                )
            }
        }
        openMakeupPrayerCount = openMakeupPrayers.count
        makeupMonth = MakeupPrayerMonth(date: Date(), calendar: calendar)
        rebuildMakeupDaySummaries()
    }
    #endif

    func registerDeviceToken(_ token: String, languageCode: String = VaktLocalization.languageCode) {
        guard let repositories, !token.isEmpty else { return }

        Task { [weak self] in
            do {
                try await repositories.deviceTokens.register(
                    token: token,
                    languageCode: languageCode
                )
                self?.lastErrorMessage = nil
            } catch {
                self?.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func syncPrayerDeadlines(prayers: [PrayerTime], now: Date = Date()) {
        guard let repositories else { return }
        let deadlines = PrayerDeadlineBuilder.build(from: prayers, now: now)

        guard !deadlines.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repositories.prayerDeadlines.sync(deadlines)
                try await repositories.prayerDeadlines.reconcileOverdue()
                await refresh(
                    repositories: repositories,
                    day: Self.localDay(for: now, timeZone: .autoupdatingCurrent)
                )
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func searchProfiles(matching query: String) {
        guard let repositories else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            profileSearchResults = []
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                profileSearchResults = try await repositories.profiles.searchProfiles(usernamePrefix: trimmed)
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func requestFriendship(with profile: SocialProfile) async -> FriendshipRequestFeedback? {
        guard let repositories else { return nil }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let result = try await repositories.friendships.requestFriendship(receiverID: profile.id)
            profileSearchResults.removeAll { $0.id == profile.id }
            pendingRequests = try await repositories.friendships.pendingRequests()
            lastErrorMessage = nil

            return switch result {
            case .sent:
                .sent(profile)
            case .alreadyPending:
                .alreadyPending(profile)
            case .alreadyFriends:
                .alreadyFriends(profile)
            case .incomingRequest:
                .incomingRequest(profile)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func acceptFriendship(_ request: PendingFriendRequest, date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        guard let repositories else { return }

        Task { [weak self] in
            guard let self else { return }
            isSyncing = true
            do {
                _ = try await repositories.friendships.acceptFriendship(request.friendship.id)
                await refresh(
                    repositories: repositories,
                    day: Self.localDay(for: date, timeZone: timeZone)
                )
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
            isSyncing = false
        }
    }

    func sendNudge(to friend: FriendPrayerSummary, prayerTime: PrayerTime) {
        guard let repositories else { return }
        let day = Self.localDay(for: prayerTime.time, timeZone: prayerTime.timeZone)
        let key = nudgeKey(friendID: friend.id, prayer: PrayerKey(prayerTime.prayer), day: day)
        guard !sendingNudgeKeys.contains(key), !hasSentNudge(to: friend, prayerTime: prayerTime) else { return }
        sendingNudgeKeys.insert(key)

        Task { [weak self] in
            guard let self else { return }
            defer { sendingNudgeKeys.remove(key) }
            do {
                let nudge = try await repositories.nudges.sendNudge(
                    to: friend.id,
                    prayer: PrayerKey(prayerTime.prayer),
                    day: day
                )
                sentNudges.append(nudge)
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func hasSentNudge(to friend: FriendPrayerSummary, prayerTime: PrayerTime) -> Bool {
        let day = Self.localDay(for: prayerTime.time, timeZone: prayerTime.timeZone)
        return sentNudges.contains {
            $0.toUserID == friend.id &&
            $0.prayer == PrayerKey(prayerTime.prayer) &&
            $0.localDay == day
        }
    }

    func isSendingNudge(to friend: FriendPrayerSummary, prayerTime: PrayerTime) -> Bool {
        let day = Self.localDay(for: prayerTime.time, timeZone: prayerTime.timeZone)
        return sendingNudgeKeys.contains(
            nudgeKey(friendID: friend.id, prayer: PrayerKey(prayerTime.prayer), day: day)
        )
    }

    private func syncMark(
        repositories: SocialRepositories,
        prayerTime: PrayerTime,
        outcome: PrayerReflectionOutcome,
        markedAt: Date
    ) async {
        isSyncing = true
        lastErrorMessage = nil

        do {
            let day = Self.localDay(for: prayerTime.time, timeZone: prayerTime.timeZone)
            let prayer = PrayerKey(prayerTime.prayer)
            let status = SocialPrayerStatus(outcome: outcome)

            _ = try await repositories.prayerStatuses.upsertStatus(
                prayer: prayer,
                day: day,
                timeZoneIdentifier: prayerTime.timeZone.identifier,
                status: status,
                markedAt: markedAt
            )

            if outcome == .missed {
                _ = try await repositories.makeupPrayers.ensureOpenMakeupPrayer(
                    prayer: prayer,
                    day: day,
                    timeZoneIdentifier: prayerTime.timeZone.identifier
                )
            } else {
                try await closeMatchingMakeupPrayer(
                    repositories: repositories,
                    prayer: prayer,
                    day: day,
                    completedAt: markedAt
                )
            }

            await refresh(repositories: repositories, day: day)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isSyncing = false
    }

    private func syncMakeupCompletion(
        repositories: SocialRepositories,
        makeup: MakeupPrayer,
        completedAt: Date
    ) async {
        isSyncing = true
        lastErrorMessage = nil

        do {
            _ = try await repositories.makeupPrayers.completeMakeupPrayer(
                makeup.id,
                completedAt: completedAt
            )
            openMakeupPrayers.removeAll { $0.id == makeup.id }
            openMakeupPrayerCount = max(0, openMakeupPrayerCount - 1)
            rebuildMakeupDaySummaries()
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isSyncing = false
    }

    private func refresh(repositories: SocialRepositories, day: LocalPrayerDay) async {
        do {
            async let entries = repositories.prayerStatuses.statuses(for: day)
            async let friends = repositories.prayerStatuses.friendSummaries(for: day)
            let calendar = Calendar.autoupdatingCurrent
            let month = MakeupPrayerMonth(date: Date(), calendar: calendar)
            async let makeup = repositories.makeupPrayers.openMakeupPrayers(in: month)
            async let makeupCount = repositories.makeupPrayers.openMakeupPrayerCount()
            async let nudges = repositories.nudges.sentNudges(for: day)

            todayEntries = try await entries
            friendSummaries = try await friends
            openMakeupPrayers = try await makeup
            openMakeupPrayerCount = try await makeupCount
            makeupMonth = month
            rebuildMakeupDaySummaries()
            sentNudges = try await nudges
            pendingRequests = try await repositories.friendships.pendingRequests()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func closeMatchingMakeupPrayer(
        repositories: SocialRepositories,
        prayer: PrayerKey,
        day: LocalPrayerDay,
        completedAt: Date
    ) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? Date()
        let openItems = try await repositories.makeupPrayers.openMakeupPrayers(
            in: MakeupPrayerMonth(date: date, calendar: calendar)
        )
        guard let matching = openItems.first(where: {
            $0.prayer == prayer && $0.originalLocalDay == day
        }) else {
            return
        }

        _ = try await repositories.makeupPrayers.completeMakeupPrayer(
            matching.id,
            completedAt: completedAt
        )
    }

    private static func localDay(for date: Date, timeZone: TimeZone) -> LocalPrayerDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return LocalPrayerDay(date: date, calendar: calendar)
    }

    private func nudgeKey(friendID: VaktUserID, prayer: PrayerKey, day: LocalPrayerDay) -> String {
        "\(friendID.rawValue.uuidString)|\(day.databaseValue)|\(prayer.rawValue)"
    }

    private func applyMakeupCalendar(
        month: MakeupPrayerMonth,
        prayers: [MakeupPrayer],
        totalCount: Int
    ) {
        makeupMonth = month
        openMakeupPrayers = prayers
        openMakeupPrayerCount = totalCount
        rebuildMakeupDaySummaries()
    }

    private func rebuildMakeupDaySummaries() {
        makeupDaySummaries = Dictionary(grouping: openMakeupPrayers, by: \.originalLocalDay)
            .map { day, prayers in
                MakeupPrayerDaySummary(day: day, prayers: prayers.map(\.prayer))
            }
            .sorted { $0.day.databaseValue < $1.day.databaseValue }
    }
}

private extension SocialPrayerStatus {
    init(outcome: PrayerReflectionOutcome) {
        switch outcome {
        case .prayed:
            self = .prayedOnTime
        case .later:
            self = .prayedLater
        case .missed:
            self = .notMarked
        }
    }
}
