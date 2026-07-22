import SwiftUI
import UIKit
import WidgetKit

struct AppRootView: View {
    @State private var selectedTab: VaktTab = .home
    @State private var hasStartedAppServices = false
    @State private var prayerLaunchRequest: PrayerLaunchRequest?
    @StateObject private var onboardingStore = OnboardingStore()
    @StateObject private var permissionSetupStore = PermissionSetupStore()
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
        AnyView(
            ZStack {
            if let storeScreenshotScene = StoreScreenshotRuntime.scene {
                storeScreenshotPreview(storeScreenshotScene)
                    .transition(.opacity)
            } else if isOnboardingPromisePreview {
                OnboardingPromiseView(
                    stepIndex: 5,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: false,
                    onContinue: {}
                )
                .transition(.opacity)
            } else if isLocationPermissionPreview {
                PermissionSetupView(
                    step: .location,
                    prayerStore: prayerStore,
                    notificationManager: notificationManager,
                    onRequestLocation: requestPermissionSetupLocation,
                    onOpenLocationSettings: openSystemSettings,
                    onCompleteNotificationDecision: {}
                )
                .transition(.opacity)
            } else if isMosquesPreview {
                NearbyMosquesView(store: MosqueFinderStore())
                    .transition(.opacity)
            } else if isPaywallPreview {
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
            guard StoreScreenshotRuntime.scene == nil else { return }
            notificationManager.start()
            updatePrayerCalculationSettings()
            spiritualContentStore.prepare(languageCode: VaktLocalization.languageCode)
            await socialAccountStore.restoreSession()
            registerStoredRemoteNotificationTokenIfAvailable()
            await subscriptionStore.prepare()
            startAppServicesIfAllowed()
        }
        .onChange(of: onboardingStore.hasCompletedOnboarding) { _, hasCompleted in
            guard hasCompleted else { return }
            startAppServicesIfAllowed()
        }
        .onChange(of: subscriptionStore.entitlement) { _, entitlement in
            handleSurfaceEntitlementChange(entitlement)
        }
        .onChange(of: subscriptionStore.summary) { _, summary in
            handleSurfaceSubscriptionSummaryChange(summary)
        }
        .onChange(of: isSignedIn) { _, signedIn in
            guard signedIn else { return }
            registerStoredRemoteNotificationTokenIfAvailable()
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
                consumePendingSurfaceActions()
            }
        )
        .onChange(of: notificationManager.authorizationStatus) { _, _ in
            if notificationManager.authorizationStatus.allowsPrayerNotifications {
                UIApplication.shared.registerForRemoteNotifications()
                registerStoredRemoteNotificationTokenIfAvailable()
            }
            schedulePrayerNotifications()
        }
        .modifier(NotificationAuthorizationLifecycleModifier(manager: notificationManager))
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
        .modifier(
            PrayerSurfacePublicationModifier(
                prayerStore: prayerStore,
                reflectionStore: reflectionStore,
                sessionStore: sessionStore
            )
        )
        .modifier(PrayerLiveActivityReconciliationModifier(sessionStore: sessionStore))
        .modifier(SurfaceActionForegroundModifier(onActive: consumePendingSurfaceActions))
        .onOpenURL(perform: handleDeepLink)
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

    @ViewBuilder
    private func storeScreenshotPreview(_ scene: StoreScreenshotScene) -> some View {
        #if DEBUG
        StoreScreenshotPreviewRoot(scene: scene)
        #else
        EmptyView()
        #endif
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

    private var isOnboardingPromisePreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--vakt-onboarding-promise-preview")
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

    private var isMosquesPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--vakt-mosques-preview")
        #else
        false
        #endif
    }

    private var isLocationPermissionPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--vakt-location-permission-preview")
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
            } else if let step = permissionSetupStep {
                PermissionSetupView(
                    step: step,
                    prayerStore: prayerStore,
                    notificationManager: notificationManager,
                    onRequestLocation: requestPermissionSetupLocation,
                    onOpenLocationSettings: openSystemSettings,
                    onCompleteNotificationDecision: permissionSetupStore.completeNotificationDecision
                )
                .transition(.opacity)
            } else {
                mainTabs
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    private var permissionSetupStep: PermissionSetupStore.Step? {
        permissionSetupStore.nextStep(
            hasUsablePrayerSchedule: prayerStore.hasUsablePrayerSchedule,
            locationStatus: prayerStore.locationAuthorizationStatus,
            notificationStatus: notificationManager.authorizationStatus
        )
    }

    private func requestPermissionSetupLocation() {
        prayerStore.requestLocationPermission()
    }

    private func openSystemSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                selectedTab: $selectedTab,
                prayerStore: prayerStore,
                sessionStore: sessionStore,
                reflectionStore: reflectionStore,
                socialPrayerStore: socialPrayerStore,
                onReviewOpportunity: considerReviewPrompt
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
                    launchRequest: $prayerLaunchRequest,
                    onReviewOpportunity: considerReviewPrompt
                )
            }
                .tabItem {
                    Label(
                        L10n.text(.tabPrayer),
                        systemImage: selectedTab == .prayer ? "moon.stars.fill" : "moon.stars"
                    )
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
                    selectedTab: $selectedTab,
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
                    referralStore: referralStore,
                    onReviewOpportunity: considerReviewPrompt
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

    private func registerStoredRemoteNotificationTokenIfAvailable() {
        guard isSignedIn,
              let token = UserDefaults.standard.string(forKey: VaktAppDelegate.remoteNotificationTokenKey),
              !token.isEmpty else {
            return
        }
        socialPrayerStore.registerDeviceToken(token)
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

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            reviewPromptStore.considerPrompt(completedPrayerCount: completedPrayerCount)
        }
    }

    private func handlePrayerNotificationAction(_ action: PrayerNotificationAction) {
        defer { _ = PrayerSurfaceStore.shared.removePendingAction(id: action.id) }
        let prayerDate = action.prayerDate ?? Date()
        let prayerTime = PrayerTime(
            prayer: action.prayer,
            time: prayerDate,
            countdown: max(0, prayerDate.timeIntervalSince(prayerStore.now)),
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )

        if action.outcome == .prayed {
            let previousCompletionCount = reflectionStore.startedTogetherCount
            sessionStore.markPrayerCompleted(for: prayerTime)
            reflectionStore.mark(
                prayer: action.prayer,
                prayerDate: prayerDate,
                outcome: .prayed
            )
            socialPrayerStore.mark(
                prayerTime,
                outcome: .prayed,
                markedAt: Date()
            )
            presentReviewPromptIfCompletionWasAdded(after: previousCompletionCount)
        } else {
            socialPrayerStore.markNotYet(prayerTime, markedAt: Date())
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard onboardingStore.hasCompletedOnboarding,
              subscriptionStore.entitlement == .active,
              let deepLink = VaktDeepLink(url: url) else {
            return
        }

        selectedTab = .prayer
        if case .startPrayer(let prayer, let prayerDate) = deepLink {
            prayerLaunchRequest = PrayerLaunchRequest(
                prayer: prayer,
                prayerDate: prayerDate
            )
        }
    }

    private func consumePendingSurfaceActions() {
        guard onboardingStore.hasCompletedOnboarding,
              subscriptionStore.entitlement == .active else { return }

        let store = PrayerSurfaceStore.shared
        for action in store.pendingActions() {
            let prayer = action.prayer.prayer
            let prayerTime = prayerStore.prayerTime(for: prayer, on: action.prayerDate) ?? PrayerTime(
                prayer: prayer,
                time: action.prayerDate,
                countdown: max(0, action.prayerDate.timeIntervalSince(prayerStore.now)),
                timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
            )

            switch action.kind {
            case .markPrayed:
                let previousCompletionCount = reflectionStore.startedTogetherCount
                sessionStore.markPrayerCompleted(for: prayerTime, at: action.createdAt)
                reflectionStore.mark(
                    prayer: prayer,
                    prayerDate: prayerTime.time,
                    outcome: .prayed
                )
                socialPrayerStore.mark(
                    prayerTime,
                    outcome: .prayed,
                    markedAt: action.createdAt
                )
                presentReviewPromptIfCompletionWasAdded(after: previousCompletionCount)
            case .markNotYet:
                socialPrayerStore.markNotYet(
                    prayerTime,
                    markedAt: action.createdAt
                )
            case .startSalah:
                selectedTab = .prayer
                prayerLaunchRequest = PrayerLaunchRequest(
                    prayer: action.prayer,
                    prayerDate: action.prayerDate
                )
            }

            _ = store.removePendingAction(id: action.id)
        }
    }

    private func presentReviewPromptIfCompletionWasAdded(after previousCount: Int) {
        let completedPrayerCount = reflectionStore.startedTogetherCount
        guard completedPrayerCount > previousCount else { return }
        considerReviewPrompt(completedPrayerCount: completedPrayerCount)
    }

    private func handleSurfaceEntitlementChange(_ entitlement: SubscriptionStore.Entitlement) {
        guard entitlement == .active else {
            hasStartedAppServices = false
            PrayerSurfaceStore.shared.updateAccess(
                isActive: false,
                expirationDate: subscriptionStore.summary?.expirationDate
            )
            PrayerSurfaceStore.shared.clearSnapshot()
            WidgetCenter.shared.reloadTimelines(ofKind: "VaktPrayerWidget")
            return
        }

        PrayerSurfaceStore.shared.updateAccess(
            isActive: true,
            expirationDate: subscriptionStore.summary?.expirationDate
        )
        startAppServicesIfAllowed()
        consumePendingSurfaceActions()
    }

    private func handleSurfaceSubscriptionSummaryChange(_ summary: SubscriptionStore.Summary?) {
        guard subscriptionStore.entitlement == .active else { return }
        PrayerSurfaceStore.shared.updateAccess(
            isActive: true,
            expirationDate: summary?.expirationDate
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "VaktPrayerWidget")
    }

}

private struct SurfaceActionForegroundModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let onActive: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            onActive()
        }
    }
}

private struct PrayerSurfacePublicationModifier: ViewModifier {
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var sessionStore: PrayerSessionStore

    func body(content: Content) -> some View {
        content
            .onAppear(perform: publish)
            .onChange(of: prayerStore.scheduleVersion) { _, _ in publish() }
            .onReceive(reflectionStore.$entries) { _ in publish() }
            .onReceive(sessionStore.$sessions) { _ in publish() }
    }

    private func publish() {
        guard !prayerStore.prayersForDeadlineSync.isEmpty else { return }

        let snapshot = PrayerSurfaceSnapshotBuilder.make(
            prayers: prayerStore.prayersForDeadlineSync,
            now: prayerStore.now,
            reflectionStore: reflectionStore,
            sessionStore: sessionStore
        )
        let surfaceStore = PrayerSurfaceStore.shared
        let previous = surfaceStore.loadSnapshot()
        if surfaceStore.saveSnapshot(snapshot), previous?.timelineContent != snapshot.timelineContent {
            WidgetCenter.shared.reloadTimelines(ofKind: "VaktPrayerWidget")
        }
    }
}

private struct PrayerLiveActivityReconciliationModifier: ViewModifier {
    @ObservedObject var sessionStore: PrayerSessionStore

    func body(content: Content) -> some View {
        content
            .onAppear {
                reconcile(sessionStore.sessions)
            }
            .onReceive(sessionStore.$sessions) { sessions in
                reconcile(sessions)
            }
    }

    private func reconcile(_ sessions: [PrayerQuietSession]) {
        let now = Date()
        let liveSessionIDs = Set(
            sessions
                .filter {
                    $0.isOpen &&
                        now.timeIntervalSince($0.startedAt) < PrayerLiveActivityManager.maximumSessionDuration
                }
                .map(\.id)
        )
        Task {
            await PrayerLiveActivityManager.shared.reconcile(openSessionIDs: liveSessionIDs)
        }
    }
}

private extension PrayerSurfaceSnapshot {
    var timelineContent: PrayerSurfaceTimelineContent {
        PrayerSurfaceTimelineContent(
            phase: phase,
            currentPrayer: currentPrayer,
            nextPrayer: nextPrayer,
            schedule: schedule,
            hasPendingActions: hasPendingActions
        )
    }
}

private struct PrayerSurfaceTimelineContent: Equatable {
    let phase: PrayerSurfacePhase
    let currentPrayer: PrayerSurfacePrayer?
    let nextPrayer: PrayerSurfacePrayer?
    let schedule: [PrayerSurfacePrayer]
    let hasPendingActions: Bool
}

private struct NotificationAuthorizationLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var manager: NotificationManager

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            manager.refreshAuthorizationStatus()
        }
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
