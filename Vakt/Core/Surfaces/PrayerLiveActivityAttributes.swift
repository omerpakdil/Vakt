import ActivityKit
import Foundation

struct PrayerLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case quiet
            case completed
        }

        let phase: Phase
        let completedAt: Date?

        static let quiet = ContentState(phase: .quiet, completedAt: nil)

        static func completed(at date: Date) -> ContentState {
            ContentState(phase: .completed, completedAt: date)
        }
    }

    let sessionID: UUID
    let prayer: PrayerSurfacePrayerID
    let prayerDate: Date
    let startedAt: Date
}
