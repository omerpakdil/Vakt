import Foundation

enum VaktExternalLinks {
    private static let legalBaseURL = "https://vakt-app.vercel.app"

    static let privacy = URL(string: "\(legalBaseURL)/privacy")!
    static let terms = URL(string: "\(legalBaseURL)/terms")!
    static let support = URL(string: "\(legalBaseURL)/support")!
    static let manageSubscription = URL(string: "https://apps.apple.com/account/subscriptions")!
    static var appStore: URL? {
        guard let appID = Bundle.main.object(forInfoDictionaryKey: "VAKT_APP_STORE_ID") as? String,
              !appID.isEmpty, !appID.contains("$(") else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)")
    }
}
