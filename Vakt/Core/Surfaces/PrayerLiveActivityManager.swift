import ActivityKit
import Foundation

actor PrayerLiveActivityManager {
    static let shared = PrayerLiveActivityManager()

    static let maximumSessionDuration: TimeInterval = 90 * 60

    private let staleInterval = maximumSessionDuration
    private let completionVisibility: TimeInterval = 4

    func start(
        sessionID: UUID,
        prayer: PrayerSurfacePrayerID,
        prayerDate: Date,
        startedAt: Date
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let activities = Activity<PrayerLiveActivityAttributes>.activities
        for activity in activities
        where startedAt.timeIntervalSince(activity.attributes.startedAt) >= staleInterval {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if activities.contains(where: {
            $0.attributes.sessionID == sessionID &&
                startedAt.timeIntervalSince($0.attributes.startedAt) < staleInterval
        }) {
            return
        }

        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = PrayerLiveActivityAttributes(
            sessionID: sessionID,
            prayer: prayer,
            prayerDate: prayerDate,
            startedAt: startedAt
        )
        let content = ActivityContent(
            state: PrayerLiveActivityAttributes.ContentState.quiet,
            staleDate: startedAt.addingTimeInterval(staleInterval)
        )

        _ = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    func finish(sessionID: UUID, at date: Date = Date()) async {
        let content = ActivityContent(
            state: PrayerLiveActivityAttributes.ContentState.completed(at: date),
            staleDate: nil
        )

        for activity in Activity<PrayerLiveActivityAttributes>.activities
        where activity.attributes.sessionID == sessionID {
            await activity.end(
                content,
                dismissalPolicy: .after(date.addingTimeInterval(completionVisibility))
            )
        }
    }

    func finishAll(at date: Date = Date()) async {
        let content = ActivityContent(
            state: PrayerLiveActivityAttributes.ContentState.completed(at: date),
            staleDate: nil
        )

        for activity in Activity<PrayerLiveActivityAttributes>.activities {
            await activity.end(
                content,
                dismissalPolicy: .after(date.addingTimeInterval(completionVisibility))
            )
        }
    }

    func reconcile(openSessionIDs: Set<UUID>) async {
        let now = Date()
        for activity in Activity<PrayerLiveActivityAttributes>.activities
        where !openSessionIDs.contains(activity.attributes.sessionID) ||
            now.timeIntervalSince(activity.attributes.startedAt) >= staleInterval {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
