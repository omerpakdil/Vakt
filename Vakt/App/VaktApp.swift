import SwiftUI
import UIKit

extension Notification.Name {
    static let vaktDidRegisterRemoteNotificationToken = Notification.Name(
        "vakt.didRegisterRemoteNotificationToken"
    )
}

final class VaktAppDelegate: NSObject, UIApplicationDelegate {
    static let remoteNotificationTokenKey = "vakt.apns.deviceToken.v1"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.registerForRemoteNotifications()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.remoteNotificationTokenKey)
        NotificationCenter.default.post(
            name: .vaktDidRegisterRemoteNotificationToken,
            object: token
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("Remote notification registration failed: \(error.localizedDescription)")
        #endif
    }
}

@main
struct VaktApp: App {
    @UIApplicationDelegateAdaptor(VaktAppDelegate.self) private var appDelegate

    init() {
        RevenueCatConfiguration.configure()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .preferredColorScheme(.dark)
        }
    }
}
