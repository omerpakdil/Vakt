import SwiftUI
import UIKit

struct AppRootView: View {
    @State private var selectedTab: VaktTab = .home
    @State private var hasStartedAppServices = false
    @StateObject private var onboardingStore = OnboardingStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var prayerStore = PrayerScheduleStore()
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var reflectionStore = PrayerReflectionStore()
    @StateObject private var sessionStore = PrayerSessionStore()
    @StateObject private var profileSettingsStore = ProfileSettingsStore()
    @StateObject private var reviewPromptStore = ReviewPromptStore()
    @StateObject private var spiritualContentStore: SpiritualContentStore
    @StateObject private var socialAccountStore: SocialAccountStore
    @StateObject private var socialPrayerStore: SocialPrayerStore
    @StateObject private var referralStore: ReferralStore

    init() {
        _spiritualContentStore = StateObject(
            wrappedValue: BackendComposition.makeSpiritualContentStore()
        )
        _socialAccountStore = StateObject(
            wrappedValue: BackendComposition.makeSocialAccountStore()
        )
        _socialPrayerStore = StateObject(
            wrappedValue: BackendComposition.makeSocialPrayerStore()
        )
        _referralStore = StateObject(wrappedValue: BackendComposition.makeReferralStore())
    }

    var body: some View {
        ZStack {
            if isPaywallPreview {
                PaywallView(store: subscriptionStore, referralStore: referralStore)
                    .transition(.opacity)
            } else if isSignInPreview {
                SocialSignInView(store: socialAccountStore)
                    .transition(.opacity)
            } else if !onboardingStore.hasCompletedOnboarding && !onboardingStore.hasPassedSplash {
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
            } else if isCheckingAccount {
                SubscriptionLaunchView()
                    .transition(.opacity)
            } else if !isSignedIn {
                SocialSignInView(store: socialAccountStore)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                subscriptionGate
            }
        }
        .environment(\.locale, VaktLocalization.appLocale)
        .environment(\.layoutDirection, VaktLocalization.layoutDirection)
        .preferredColorScheme(.dark)
        .task {
            notificationManager.start()
            updatePrayerCalculationSettings()
            spiritualContentStore.prepare(languageCode: VaktLocalization.languageCode)
            await socialAccountStore.restoreSession()
            await subscriptionStore.prepare()
            startAppServicesIfAllowed()
        }
        .onChange(of: onboardingStore.hasCompletedOnboarding) { _, hasCompleted in
            guard hasCompleted else { return }
            startAppServicesIfAllowed()
        }
        .onChange(of: subscriptionStore.entitlement) { _, entitlement in
            guard entitlement == .active else {
                hasStartedAppServices = false
                return
            }

            startAppServicesIfAllowed()
        }
        .onChange(of: isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task {
                await subscriptionStore.refreshSubscription()
                await referralStore.refresh()
            }
        }
        .onChange(of: socialAccountStore.profile?.profileCompletedAt) { _, completedAt in
            guard completedAt != nil else { return }
            startAppServicesIfAllowed()
            if let token = UserDefaults.standard.string(forKey: VaktAppDelegate.remoteNotificationTokenKey) {
                socialPrayerStore.registerDeviceToken(token)
            }
            syncPrayerDeadlines()
        }
        .onChange(of: prayerStore.scheduleVersion) { _, _ in
            schedulePrayerNotifications()
            syncPrayerDeadlines()
        }
        .onChange(of: notificationManager.authorizationStatus) { _, _ in
            schedulePrayerNotifications()
        }
        .onChange(of: notificationManager.isReminderEnabled) { _, _ in
            schedulePrayerNotifications()
        }
        .onChange(of: notificationManager.preferences) { _, _ in
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
            case .prayer:
                if onboardingStore.hasCompletedOnboarding,
                   subscriptionStore.entitlement == .active {
                    selectedTab = .prayer
                }
            case .circle:
                if onboardingStore.hasCompletedOnboarding,
                   subscriptionStore.entitlement == .active {
                    selectedTab = .circle
                }
            case .profile:
                if onboardingStore.hasCompletedOnboarding,
                   subscriptionStore.entitlement == .active {
                    selectedTab = .profile
                }
            }
        }
        .onChange(of: notificationManager.lastPrayerAction) { _, action in
            guard let action else { return }
            handlePrayerNotificationAction(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaktDidRegisterRemoteNotificationToken)) { notification in
            guard let token = notification.object as? String else { return }
            socialPrayerStore.registerDeviceToken(token)
        }
        .animation(.easeInOut(duration: 0.35), value: onboardingStore.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.35), value: onboardingStore.hasPassedSplash)
        .animation(.easeInOut(duration: 0.35), value: subscriptionStore.entitlement)
        .animation(.easeInOut(duration: 0.28), value: subscriptionStore.completedPurchaseID)
        .animation(.easeInOut(duration: 0.35), value: isSignedIn)
        .fullScreenCover(isPresented: reviewPromptBinding) {
            RateVaktView(
                completedPrayerCount: reflectionStore.startedTogetherCount,
                onRate: {
                    reviewPromptStore.markNativeReviewRequested()
                },
                onNotNow: {
                    reviewPromptStore.dismissPrompt()
                }
            )
        }
    }

    private var reviewPromptBinding: Binding<Bool> {
        Binding(
            get: { reviewPromptStore.isPromptPresented },
            set: { isPresented in
                if !isPresented {
                    reviewPromptStore.dismissPrompt()
                }
            }
        )
    }

    private var isSignedIn: Bool {
        if case .signedIn = socialAccountStore.state {
            return true
        }
        return false
    }

    private var isCheckingAccount: Bool {
        if case .checking = socialAccountStore.state {
            return true
        }
        return false
    }

    private var isPaywallPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--vakt-paywall-preview")
        #else
        false
        #endif
    }

    private var isSignInPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--vakt-sign-in-preview")
        #else
        false
        #endif
    }

    @ViewBuilder
    private var subscriptionGate: some View {
        switch subscriptionStore.entitlement {
        case .checking:
            SubscriptionLaunchView()
                .transition(.opacity)
        case .inactive:
            PaywallView(store: subscriptionStore, referralStore: referralStore)
                .transition(.opacity)
        case .active:
            if subscriptionStore.completedPurchaseID != nil {
                PurchaseSuccessView {
                    subscriptionStore.consumeCompletedPurchase()
                }
                .transition(.opacity)
            } else if socialAccountStore.profile?.isComplete != true {
                ProfileCompletionView(store: socialAccountStore)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if prayerStore.hasUsablePrayerSchedule {
                mainTabs
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                prayerLocationSetup
                    .transition(.opacity)
            }
        }
    }

    private var prayerLocationSetup: some View {
        OnboardingLocationView(
            stepIndex: 0,
            stepCount: 1,
            prayerStore: prayerStore,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            showsPageMark: false,
            allowsSkip: false,
            onContinue: handlePrayerLocationSetup,
            onSkip: {}
        )
    }

    private func handlePrayerLocationSetup() {
        if prayerStore.locationAccessNeedsSettings,
           let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
            return
        }

        prayerStore.requestLocationPermission()
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                selectedTab: $selectedTab,
                prayerStore: prayerStore,
                sessionStore: sessionStore,
                reflectionStore: reflectionStore,
                socialPrayerStore: socialPrayerStore
            )
                .tabItem {
                    Label(L10n.text(.tabHome), systemImage: "line.3.horizontal")
                }
                .tag(VaktTab.home)

            NavigationStack {
                PrayerView(
                    prayerStore: prayerStore,
                    reflectionStore: reflectionStore,
                    sessionStore: sessionStore,
                    socialPrayerStore: socialPrayerStore,
                    spiritualContentStore: spiritualContentStore,
                    onReviewOpportunity: considerReviewPrompt
                )
            }
                .tabItem {
                    Label(L10n.text(.tabPrayer), systemImage: "checkmark.circle")
                }
                .tag(VaktTab.prayer)

            SocialCircleView(
                socialPrayerStore: socialPrayerStore,
                prayerStore: prayerStore,
                referralStore: referralStore,
                subscriptionStore: subscriptionStore
            )
                .tabItem {
                    Label(L10n.text(.tabCircle), systemImage: "person.2")
                }
                .tag(VaktTab.circle)

            NavigationStack {
                ProfileView(
                    prayerStore: prayerStore,
                    notificationManager: notificationManager,
                    reflectionStore: reflectionStore,
                    sessionStore: sessionStore,
                    onboardingStore: onboardingStore,
                    subscriptionStore: subscriptionStore,
                    profileSettings: profileSettingsStore,
                    reviewPromptStore: reviewPromptStore,
                    socialAccountStore: socialAccountStore,
                    socialPrayerStore: socialPrayerStore,
                    referralStore: referralStore
                )
            }
                .tabItem {
                    Label(L10n.text(.tabProfile), systemImage: "smallcircle.filled.circle")
                }
                .tag(VaktTab.profile)
        }
        .tint(.vaktPrimary)
    }

    private func startAppServicesIfAllowed() {
        guard onboardingStore.hasCompletedOnboarding,
              subscriptionStore.entitlement == .active,
              socialAccountStore.profile?.isComplete == true,
              !hasStartedAppServices else {
            return
        }

        hasStartedAppServices = true
        updatePrayerCalculationSettings()
        prayerStore.start()
        schedulePrayerNotifications()
        syncPrayerDeadlines()
    }

    private func updatePrayerCalculationSettings() {
        prayerStore.updateCalculationSettings(profileSettingsStore.prayerCalculationSettings)
    }

    private func schedulePrayerNotifications() {
        guard onboardingStore.hasCompletedOnboarding,
              subscriptionStore.entitlement == .active else { return }

        notificationManager.schedulePrayerNotifications(
            prayers: prayerStore.prayersForDeadlineSync,
            now: prayerStore.now,
            liveMemberCount: 0,
            quietSoundEnabled: profileSettingsStore.quietNotificationSoundEnabled
        )
    }

    private func syncPrayerDeadlines() {
        guard onboardingStore.hasCompletedOnboarding, isSignedIn else { return }
        socialPrayerStore.syncPrayerDeadlines(
            prayers: prayerStore.prayersForDeadlineSync,
            now: prayerStore.now
        )
    }

    private func considerReviewPrompt(completedPrayerCount: Int) {
        guard onboardingStore.hasCompletedOnboarding,
              subscriptionStore.entitlement == .active else { return }

        reviewPromptStore.considerPrompt(completedPrayerCount: completedPrayerCount)
    }

    private func handlePrayerNotificationAction(_ action: PrayerNotificationAction) {
        let prayerDate = action.prayerDate ?? Date()
        let prayerTime = PrayerTime(
            prayer: action.prayer,
            time: prayerDate,
            countdown: max(0, prayerDate.timeIntervalSince(prayerStore.now)),
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )

        if action.outcome == .prayed {
            sessionStore.markPrayerCompleted(for: prayerTime)
        }

        reflectionStore.mark(
            prayer: action.prayer,
            prayerDate: prayerDate,
            outcome: action.outcome
        )
        socialPrayerStore.mark(
            prayerTime,
            outcome: action.outcome,
            markedAt: Date()
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

                Text(L10n.text(.preparingVakt))
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktMuted)
            }
        }
    }
}

enum VaktTab: Hashable {
    case home
    case prayer
    case circle
    case profile
}
