import Foundation

enum VaktDeepLink: Equatable {
    case openPrayer(prayer: PrayerSurfacePrayerID, prayerDate: Date)
    case startPrayer(prayer: PrayerSurfacePrayerID, prayerDate: Date)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "vakt",
              url.host?.lowercased() == "prayer",
              ["/open", "/start"].contains(url.path.lowercased()),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let prayerValue = components.queryItems?.first(where: { $0.name == "prayer" })?.value,
              let prayer = PrayerSurfacePrayerID(rawValue: prayerValue.lowercased()),
              let timestampValue = components.queryItems?.first(where: { $0.name == "at" })?.value,
              let timestamp = TimeInterval(timestampValue) else {
            return nil
        }

        let prayerDate = Date(timeIntervalSince1970: timestamp)
        self = url.path.lowercased() == "/start"
            ? .startPrayer(prayer: prayer, prayerDate: prayerDate)
            : .openPrayer(prayer: prayer, prayerDate: prayerDate)
    }

    var url: URL? {
        switch self {
        case .openPrayer(let prayer, let prayerDate):
            return Self.url(path: "/open", prayer: prayer, prayerDate: prayerDate)
        case .startPrayer(let prayer, let prayerDate):
            return Self.url(path: "/start", prayer: prayer, prayerDate: prayerDate)
        }
    }

    private static func url(
        path: String,
        prayer: PrayerSurfacePrayerID,
        prayerDate: Date
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "vakt"
        components.host = "prayer"
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "prayer", value: prayer.rawValue),
            URLQueryItem(name: "at", value: String(prayerDate.timeIntervalSince1970))
        ]
        return components.url
    }
}

struct PrayerLaunchRequest: Identifiable, Equatable {
    let id = UUID()
    let prayer: PrayerSurfacePrayerID
    let prayerDate: Date
}
