import SwiftUI

struct AppRootView: View {
    @State private var selectedTab: VaktTab = .home
    @State private var hasStartedAppServices = false
    @State private var hasPendingSafDeepLink = false
    @StateObject private var onboardingStore = OnboardingStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var presenceStore: LiveSafPresenceStore
    @StateObject private var prayerStore = PrayerScheduleStore()
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var reflectionStore = PrayerReflectionStore()
    @StateObject private var sessionStore = PrayerSessionStore()
    @StateObject private var profileSettingsStore = ProfileSettingsStore()

    init() {
        _presenceStore = StateObject(
            wrappedValue: BackendComposition.makePresenceStore(
                initialCount: VaktMockData.globalSaf.memberCount
            )
        )
    }

    var body: some View {
        ZStack {
            if !onboardingStore.hasCompletedOnboarding && !onboardingStore.hasPassedSplash {
                VaktSplashView {
                    onboardingStore.passSplash()
                }
                .transition(.opacity)
            } else if !onboardingStore.hasCompletedOnboarding {
                OnboardingView(
                    store: onboardingStore,
                    prayerStore: prayerStore,
                    notificationManager: notificationManager
                )
                .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                subscriptionGate
            }
        }
        .preferredColorScheme(.dark)
        .task {
            notificationManager.start()
            updatePrayerCalculationSettings()
            await subscriptionStore.prepare()
            startAppServicesIfAllowed()
        }
        .onChange(of: onboardingStore.hasCompletedOnboarding) { _, hasCompleted in
            guard hasCompleted else { return }
            startAppServicesIfAllowed()
        }
        .onChange(of: subscriptionStore.entitlement) { _, entitlement in
            guard entitlement == .active else {
                presenceStore.leave()
                hasStartedAppServices = false
                return
            }

            startAppServicesIfAllowed()

            if hasPendingSafDeepLink {
                hasPendingSafDeepLink = false
                selectedTab = .safs
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .safs {
                presenceStore.leave()
            }
        }
        .onChange(of: prayerStore.now) { _, _ in
            updatePresencePrayerContext()
        }
        .onChange(of: prayerStore.scheduleVersion) { _, _ in
            updatePresencePrayerContext()
            schedulePrayerNotifications()
        }
        .onChange(of: notificationManager.authorizationStatus) { _, _ in
            schedulePrayerNotifications()
        }
        .onChange(of: notificationManager.isReminderEnabled) { _, _ in
            schedulePrayerNotifications()
        }
        .onChange(of: profileSettingsStore.quietNotificationSoundEnabled) { _, _ in
            schedulePrayerNotifications()
        }
        .onChange(of: profileSettingsStore.prayerCalculationMethod) { _, _ in
            updatePrayerCalculationSettings()
        }
        .onChange(of: profileSettingsStore.asrJuristicMethod) { _, _ in
            updatePrayerCalculationSettings()
        }
        .onChange(of: notificationManager.lastDeepLink) { _, deepLink in
            guard let deepLink else { return }
            switch deepLink {
            case .saf:
                if onboardingStore.hasCompletedOnboarding,
                   subscriptionStore.entitlement == .active {
                    selectedTab = .safs
                } else {
                    hasPendingSafDeepLink = true
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: onboardingStore.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.35), value: onboardingStore.hasPassedSplash)
        .animation(.easeInOut(duration: 0.35), value: subscriptionStore.entitlement)
    }

    @ViewBuilder
    private var subscriptionGate: some View {
        switch subscriptionStore.entitlement {
        case .checking:
            SubscriptionLaunchView()
                .transition(.opacity)
        case .inactive:
            PaywallView(store: subscriptionStore)
                .transition(.opacity)
        case .active:
            mainTabs
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                selectedTab: $selectedTab,
                presenceStore: presenceStore,
                prayerStore: prayerStore,
                sessionStore: sessionStore
            )
                .tabItem {
                    Label("Home", systemImage: "line.3.horizontal")
                }
                .tag(VaktTab.home)

            SafLobbyView(
                presenceStore: presenceStore,
                prayerStore: prayerStore,
                reflectionStore: reflectionStore,
                sessionStore: sessionStore
            )
                .tabItem {
                    Label("Safs", systemImage: "circle")
                }
                .tag(VaktTab.safs)

            InsightsView(reflectionStore: reflectionStore)
                .tabItem {
                    Label("Moments", systemImage: "minus")
                }
                .tag(VaktTab.insights)

            ProfileView(
                prayerStore: prayerStore,
                notificationManager: notificationManager,
                reflectionStore: reflectionStore,
                sessionStore: sessionStore,
                onboardingStore: onboardingStore,
                profileSettings: profileSettingsStore
            )
                .tabItem {
                    Label("My Vakt", systemImage: "circle.fill")
                }
                .tag(VaktTab.profile)
        }
        .tint(.vaktPrimary)
    }

    private func startAppServicesIfAllowed() {
        guard onboardingStore.hasCompletedOnboarding,
              subscriptionStore.entitlement == .active,
              !hasStartedAppServices else {
            return
        }

        hasStartedAppServices = true
        updatePrayerCalculationSettings()
        presenceStore.start()
        prayerStore.start()
        updatePresencePrayerContext()
        schedulePrayerNotifications()
    }

    private func updatePrayerCalculationSettings() {
        prayerStore.updateCalculationSettings(profileSettingsStore.prayerCalculationSettings)
    }

    private func updatePresencePrayerContext() {
        guard onboardingStore.hasCompletedOnboarding,
              subscriptionStore.entitlement == .active else { return }

        presenceStore.updatePrayerContext(prayerStore.nextPrayer)
    }

    private func schedulePrayerNotifications() {
        guard onboardingStore.hasCompletedOnboarding,
              subscriptionStore.entitlement == .active else { return }

        notificationManager.schedulePrayerNotifications(
            prayers: prayerStore.upcomingPrayers,
            now: prayerStore.now,
            liveMemberCount: presenceStore.displayMemberCount,
            quietSoundEnabled: profileSettingsStore.quietNotificationSoundEnabled
        )
    }
}

private struct SubscriptionLaunchView: View {
    var body: some View {
        ZStack {
            Color.vaktDeep.ignoresSafeArea()

            VStack(spacing: VaktSpace.md) {
                ProgressView()
                    .tint(Color.vaktGlow)

                Text("Preparing your Vakt…")
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktMuted)
            }
        }
    }
}

enum VaktTab: Hashable {
    case home
    case safs
    case insights
    case profile
}
