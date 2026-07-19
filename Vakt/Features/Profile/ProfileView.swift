import SwiftUI
import UserNotifications
import AuthenticationServices

struct ProfileView: View {
    @Binding var selectedTab: VaktTab
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var sessionStore: PrayerSessionStore
    @ObservedObject var onboardingStore: OnboardingStore
    @ObservedObject var subscriptionStore: SubscriptionStore
    @ObservedObject var profileSettings: ProfileSettingsStore
    @ObservedObject var reviewPromptStore: ReviewPromptStore
    @ObservedObject var socialAccountStore: SocialAccountStore
    @ObservedObject var socialPrayerStore: SocialPrayerStore
    @ObservedObject var referralStore: ReferralStore

    @Environment(\.openURL) private var openURL
    @State private var modal: VaktModalState?
    @State private var isPrayerMethodSheetPresented = false
    @State private var isSplashPreviewPresented = false
    @State private var isMakeupPreviewPresented = false
    @State private var isInsightsPresented = false
    @State private var isMakeupPresented = false
    @State private var isAccountPresented = false
    @State private var isRemindersPresented = false
    @State private var isDeletionAuthorizationPresented = false
    @State private var isDeveloperPresented = false
    @State private var isReferralPresented = false

    var body: some View {
        ZStack {
            Color.vaktBg.ignoresSafeArea()

            GeometryReader { geometry in
                profileContent(availableHeight: geometry.size.height)
            }
        }
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
        }
        .sheet(isPresented: $isPrayerMethodSheetPresented) {
            PrayerMethodSettingsSheet(
                method: $profileSettings.prayerCalculationMethod,
                asrMethod: $profileSettings.asrJuristicMethod,
                prayerStore: prayerStore,
                onOpenSystemSettings: openSystemSettings
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isInsightsPresented) {
            InsightsView(reflectionStore: reflectionStore)
        }
        .navigationDestination(isPresented: $isMakeupPresented) {
            MakeupPrayerCenterView(store: socialPrayerStore)
        }
        .sheet(isPresented: $isAccountPresented) {
            ProfileAccountSheet(
                accountStore: socialAccountStore,
                subscriptionStore: subscriptionStore,
                onManageSubscription: openSubscriptionSettings,
                onRestorePurchases: restorePurchases,
                onOpenReferrals: {
                    referralStore.clearMessage()
                    isAccountPresented = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        isReferralPresented = true
                    }
                },
                onOpenTerms: { openURL(VaktExternalLinks.terms) },
                onOpenPrivacy: { openURL(VaktExternalLinks.privacy) },
                onRequestSignOut: requestSignOut,
                onRequestDelete: requestAccountDeletion,
                onOpenDeveloper: openDeveloperTools
            )
        }
        .sheet(isPresented: $isRemindersPresented) {
            ReminderSettingsSheet(
                manager: notificationManager,
                quietSoundEnabled: $profileSettings.quietNotificationSoundEnabled,
                onOpenSystemSettings: openSystemSettings
            )
        }
        .sheet(isPresented: $isReferralPresented) {
            ReferralCenterView(store: referralStore, subscriptionStore: subscriptionStore)
        }
        .fullScreenCover(isPresented: $isDeletionAuthorizationPresented) {
            AppleAccountDeletionView(
                accountStore: socialAccountStore,
                onCancel: { isDeletionAuthorizationPresented = false }
            )
        }
        #if DEBUG
        .sheet(isPresented: $isDeveloperPresented) {
            ProfileDeveloperSheet(
                onResetOnboarding: { requestDeveloperAction(.resetOnboarding) },
                onClearEntries: { requestDeveloperAction(.clearReflections) },
                onShowRatePrompt: {
                    isDeveloperPresented = false
                    reviewPromptStore.presentForDebug()
                },
                onPreviewSplash: {
                    isDeveloperPresented = false
                    isSplashPreviewPresented = true
                },
                onPreviewMakeup: {
                    isDeveloperPresented = false
                    isMakeupPreviewPresented = true
                },
                onPreviewAtmosphere: { phase in
                    UserDefaults.standard.set(
                        phase?.rawValue ?? HomeAtmospherePhase.automaticPreviewValue,
                        forKey: HomeAtmospherePhase.previewStorageKey
                    )
                    isDeveloperPresented = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(260))
                        selectedTab = .home
                    }
                }
            )
        }
        #endif
        #if DEBUG
        .fullScreenCover(isPresented: $isSplashPreviewPresented) {
            VaktSplashView {
                isSplashPreviewPresented = false
            }
        }
        .fullScreenCover(isPresented: $isMakeupPreviewPresented) {
            MakeupPrayerPreviewHost()
        }
        #endif
        .vaktModal($modal)
    }

    @ViewBuilder
    private func profileContent(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PersonalVaktHeader(
                name: profileDisplayName,
                username: profileUsername,
                onSettings: { isAccountPresented = true }
            )

            TodayPrayerLedger(
                entries: todayEntries,
                availablePrayers: availableTodayPrayers,
                onSelect: presentPrayerOutcome
            )

            WeeklyVaktSummary(
                summary: reflectionStore.summary(for: .week),
                onOpen: { isInsightsPresented = true }
            )

            MakeupPrayerLine(
                count: socialPrayerStore.openMakeupPrayerCount,
                onOpen: {
                    if socialPrayerStore.openMakeupPrayerCount > 0 {
                        isMakeupPresented = true
                    }
                }
            )

            Spacer(minLength: 6)

            PersonalSettingsDock(
                reminderState: notificationManager.reminderState,
                methodTitle: profileSettings.prayerCalculationMethod.title,
                onReminders: { isRemindersPresented = true },
                onPrayerTimes: { isPrayerMethodSheetPresented = true },
                onAccount: { isAccountPresented = true }
            )
        }
        .padding(.horizontal, VaktSpace.lg)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(minHeight: availableHeight, alignment: .top)
    }

    private var todayEntries: [Prayer: PrayerReflectionOutcome] {
        let calendar = Calendar.autoupdatingCurrent
        return reflectionStore.entries.reduce(into: [:]) { result, entry in
            guard calendar.isDateInToday(entry.prayerDate) else { return }
            result[entry.prayer] = entry.outcome
        }
    }

    private var availableTodayPrayers: Set<Prayer> {
        Set(Prayer.allCases.filter { prayer in
            guard let prayerTime = prayerStore.prayerTime(for: prayer) else { return false }
            return prayerTime.time <= prayerStore.now
        })
    }

    private func presentPrayerOutcome(_ prayer: Prayer) {
        guard let prayerTime = prayerStore.prayerTime(for: prayer), prayerTime.time <= prayerStore.now else {
            return
        }

        modal = VaktModalState(
            tone: .warm,
            title: L10n.formatString("profile.prayer_modal.title", prayer.localizedName),
            message: L10n.string("profile.prayer_modal.message"),
            primaryAction: VaktModalAction(title: L10n.string("profile.prayer_modal.prayed")) {
                markPrayer(prayerTime, outcome: .prayed)
            },
            secondaryAction: VaktModalAction(title: L10n.string("profile.prayer_modal.missed"), role: .secondary) {
                markPrayer(prayerTime, outcome: .missed)
            }
        )
    }

    private func markPrayer(_ prayerTime: PrayerTime, outcome: PrayerReflectionOutcome) {
        if outcome == .prayed {
            sessionStore.markPrayerCompleted(for: prayerTime)
        }
        reflectionStore.mark(
            prayer: prayerTime.prayer,
            prayerDate: prayerTime.time,
            outcome: outcome
        )
        socialPrayerStore.mark(prayerTime, outcome: outcome)
    }

    private func requestSignOut() {
        isAccountPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            modal = VaktModalState(
                tone: .neutral,
                title: L10n.string("account.sign_out.confirm.title"),
                message: L10n.string("account.sign_out.confirm.message"),
                primaryAction: VaktModalAction(title: L10n.string("account.action.sign_out"), role: .destructive) {
                    Task { await socialAccountStore.signOut() }
                },
                secondaryAction: VaktModalAction(title: L10n.string("common.cancel"), role: .secondary, action: {})
            )
        }
    }

    private func requestAccountDeletion() {
        isAccountPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            modal = VaktModalState(
                tone: .destructive,
                title: L10n.string("account.delete.confirm.title"),
                message: L10n.string("account.delete.confirm.message"),
                primaryAction: VaktModalAction(title: L10n.string("account.action.delete"), role: .destructive) {
                    isDeletionAuthorizationPresented = true
                },
                secondaryAction: VaktModalAction(title: L10n.string("common.cancel"), role: .secondary, action: {})
            )
        }
    }

    private func requestDeveloperAction(_ action: DeveloperAction) {
        isDeveloperPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            presentDeveloperModal(action)
        }
    }

    private var profileDisplayName: String {
        socialAccountStore.profile?.displayName ?? "Vakt"
    }

    private var profileUsername: String {
        socialAccountStore.profile?.username ?? L10n.string("account.profile.fallback_username")
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func openDeveloperTools() {
        isAccountPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            isDeveloperPresented = true
        }
    }

    private func openSubscriptionSettings() {
        openURL(VaktExternalLinks.manageSubscription)
    }

    private func restorePurchases() {
        Task { @MainActor in
            await subscriptionStore.restorePurchases()

            if case .failed = subscriptionStore.purchaseState {
                return
            }

            modal = VaktModalState(
                tone: .warm,
                title: L10n.string("profile.subscription.checked_title"),
                message: L10n.string("profile.subscription.checked_message"),
                primaryAction: VaktModalAction(title: L10n.string("common.done"), action: {})
            )
        }
    }

    private func presentDeveloperModal(_ action: DeveloperAction) {
        modal = VaktModalState(
            tone: .destructive,
            title: developerTitle(for: action),
            message: developerMessage(for: action),
            primaryAction: VaktModalAction(
                title: developerButtonTitle(for: action),
                role: .destructive,
                action: { runDeveloperAction(action) }
            ),
            secondaryAction: VaktModalAction(
                title: L10n.string("common.cancel"),
                role: .secondary,
                action: {}
            )
        )
    }

    private func developerTitle(for action: DeveloperAction) -> String {
        switch action {
        case .resetOnboarding:
            return "Reset onboarding?"
        case .clearReflections:
            return "Clear entries?"
        }
    }

    private func developerButtonTitle(for action: DeveloperAction) -> String {
        switch action {
        case .resetOnboarding:
            return "Reset onboarding"
        case .clearReflections:
            return "Clear entries"
        }
    }

    private func developerMessage(for action: DeveloperAction) -> String {
        switch action {
        case .resetOnboarding:
            return "This signs out and brings the complete splash, onboarding, and Apple sign-in flow back on this device. Your prayer data stays local."
        case .clearReflections:
            return "This removes prayer entries from this device. Prayer times and settings stay untouched."
        }
    }

    private func runDeveloperAction(_ action: DeveloperAction) {
        switch action {
        case .resetOnboarding:
            Task {
                await socialAccountStore.signOut()
                onboardingStore.reset()
            }
        case .clearReflections:
            reflectionStore.clear()
            sessionStore.clear()
        }
    }
}
private enum DeveloperAction: Identifiable {
    case resetOnboarding
    case clearReflections

    var id: String {
        switch self {
        case .resetOnboarding:
            return "resetOnboarding"
        case .clearReflections:
            return "clearReflections"
        }
    }
}

private struct PrayerMethodSettingsSheet: View {
    @Binding var method: PrayerCalculationMethodPreference
    @Binding var asrMethod: AsrJuristicPreference
    @ObservedObject var prayerStore: PrayerScheduleStore
    let onOpenSystemSettings: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    header

                    PrayerLocationStatus(
                        status: prayerStore.status,
                        onOpenSettings: onOpenSystemSettings
                    )

                    VStack(alignment: .leading, spacing: 9) {
                        Text(L10n.string("prayer_settings.method.eyebrow"))
                            .font(VaktFont.eyebrow(9))
                            .foregroundStyle(Color.vaktMuted)
                            .tracking(1.4)

                        Menu {
                            Picker(L10n.string("prayer_settings.method.picker"), selection: $method) {
                                ForEach(PrayerCalculationMethodPreference.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        } label: {
                            PrayerMethodSelection(
                                title: method.title,
                                detail: method.detail,
                                isAutomatic: method == .automatic
                            )
                        }
                        .buttonStyle(VaktPressStyle())
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text(L10n.string("prayer_settings.asr.eyebrow"))
                            .font(VaktFont.eyebrow(9))
                            .foregroundStyle(Color.vaktMuted)
                            .tracking(1.4)

                        HStack(spacing: 7) {
                            ForEach(AsrJuristicPreference.allCases) { option in
                                PrayerAsrChoice(
                                    option: option,
                                    isSelected: asrMethod == option
                                ) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    asrMethod = option
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.string("prayer_settings.applied_note"), systemImage: "checkmark")
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(L10n.string("prayer_settings.automatic_note"))
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktMuted.opacity(0.78))
                            .lineSpacing(3)
                            .lineLimit(3)
                            .minimumScaleFactor(0.76)
                    }

                    Spacer()
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.done")) {
                        dismiss()
                    }
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktGlow)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.string("prayer_settings.header.title"))
                .font(VaktFont.title(28))
                .foregroundStyle(Color.vaktPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(L10n.string("prayer_settings.header.subtitle"))
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktMuted)
                .lineSpacing(3)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
    }
}

private struct PrayerLocationStatus: View {
    let status: PrayerScheduleStatus
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status == .denied ? "location.slash" : "location")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("prayer_settings.location.title"))
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktPrimary)

                Text(detail)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Spacer()

            if status == .denied {
                Button(L10n.string("prayer_settings.location.settings"), action: onOpenSettings)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktGlow)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(Color.vaktSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.6), lineWidth: 0.5)
        )
    }

    private var accent: Color {
        status == .denied ? Color.vaktMuted : Color.vaktGlow
    }

    private var detail: String {
        switch status {
        case .ready: L10n.string("prayer_settings.location.ready")
        case .usingSavedTimes: L10n.string("prayer_settings.location.saved")
        case .loading, .locating: L10n.string("prayer_settings.location.loading")
        case .denied: L10n.string("prayer_settings.location.denied")
        case .failed: L10n.string("prayer_settings.location.failed")
        }
    }
}

private struct PrayerMethodSelection: View {
    let title: String
    let detail: String
    let isAutomatic: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: isAutomatic ? "location.north.line" : "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.vaktGlow)
                .frame(width: 38, height: 38)
                .background(Color.vaktGlow.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(VaktFont.body(15))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if isAutomatic {
                        Text(L10n.string("prayer_settings.recommended"))
                            .font(VaktFont.eyebrow(7))
                            .foregroundStyle(Color.vaktGlow)
                            .tracking(0.8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }
                }

                Text(detail)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            Spacer()

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.vaktMuted)
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(Color.vaktElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktGlow.opacity(isAutomatic ? 0.3 : 0.14), lineWidth: 0.6)
        )
    }
}

private struct PrayerAsrChoice: View {
    let option: AsrJuristicPreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(option.title)
                        .font(VaktFont.body(14))
                        .foregroundStyle(isSelected ? Color.vaktPrimary : Color.vaktMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.vaktGlow : Color.vaktBorderStrong)
                }

                Text(option.detail)
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 76)
            .background(isSelected ? Color.vaktElevated.opacity(0.58) : Color.vaktSurface.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(isSelected ? Color.vaktGlow.opacity(0.32) : Color.vaktBorder.opacity(0.55), lineWidth: 0.6)
            )
        }
        .buttonStyle(VaktPressStyle())
    }
}

private struct PersonalVaktHeader: View {
    let name: String
    let username: String
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ProfileAvatar(name: name)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(VaktFont.title(24))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(verbatim: "@\(username)")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vaktPrimary)
                    .frame(width: 38, height: 38)
                    .background(Color.vaktSurface.opacity(0.64))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.vaktBorder.opacity(0.7), lineWidth: 0.5))
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(L10n.string("profile.main.settings"))
        }
    }
}

private struct TodayPrayerLedger: View {
    let entries: [Prayer: PrayerReflectionOutcome]
    let availablePrayers: Set<Prayer>
    let onSelect: (Prayer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("profile.today.eyebrow"))
                    .font(VaktFont.eyebrow(9))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(1.6)

                Spacer()

                Text(todaySummary)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 5) {
                ForEach(Prayer.allCases) { prayer in
                    TodayPrayerLedgerItem(
                        prayer: prayer,
                        outcome: entries[prayer],
                        isAvailable: availablePrayers.contains(prayer),
                        onSelect: { onSelect(prayer) }
                    )
                }
            }
        }
        .padding(13)
        .background(
            LinearGradient(
                colors: [Color.vaktSurface.opacity(0.72), Color.vaktSurface.opacity(0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.68), lineWidth: 0.5)
        )
    }

    private var todaySummary: String {
        let completed = entries.values.filter(\.contributesToRhythm).count
        guard completed > 0 else { return L10n.string("profile.today.none") }
        let key = completed == 1 ? "profile.today.prayed.one" : "profile.today.prayed.many"
        return L10n.formatString(key, ProfileNumberFormatter.string(completed))
    }
}

private struct TodayPrayerLedgerItem: View {
    let prayer: Prayer
    let outcome: PrayerReflectionOutcome?
    let isAvailable: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect()
        } label: {
            VStack(spacing: 8) {
                statusMark

                Text(prayer.localizedName)
                    .font(VaktFont.caption(8))
                    .foregroundStyle(outcome == nil ? Color.vaktMuted : Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(statusText)
                    .font(VaktFont.caption(8))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(outcome?.contributesToRhythm == true ? Color.vaktElevated.opacity(0.38) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .disabled(!isAvailable)
    }

    @ViewBuilder
    private var statusMark: some View {
        switch outcome {
        case .prayed, .later:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.vaktBg)
                .frame(width: 20, height: 20)
                .background(Color.vaktPrimary)
                .clipShape(Circle())
        case .missed:
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.vaktMuted)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.vaktBorderStrong, lineWidth: 0.7))
        case nil:
            Circle()
                .fill(Color.vaktBorder.opacity(0.7))
                .frame(width: 7, height: 7)
                .frame(width: 20, height: 20)
        }
    }

    private var statusText: String {
        switch outcome {
        case .prayed: L10n.string("profile.today.status.prayed")
        case .later: L10n.string("profile.today.status.later")
        case .missed: L10n.string("profile.today.status.missed")
        case nil:
            isAvailable
                ? L10n.string("profile.today.status.unmarked")
                : L10n.string("profile.today.status.upcoming")
        }
    }

    private var statusColor: Color {
        switch outcome {
        case .prayed, .later: Color.vaktGlow
        case .missed, nil: Color.vaktMuted
        }
    }
}

private struct WeeklyVaktSummary: View {
    let summary: ReflectionPeriodSummary
    let onOpen: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("profile.week.eyebrow"))
                        .font(VaktFont.eyebrow(9))
                        .foregroundStyle(Color.vaktMuted)
                        .tracking(1.4)

                    Text(summaryText)
                        .font(VaktFont.body(14))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text(L10n.string("profile.week.detail"))
                        .font(VaktFont.caption(9))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 4)

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(summary.buckets.prefix(7)) { bucket in
                        Capsule()
                            .fill(bucket.rhythmCount > 0 ? Color.vaktGlow : Color.vaktBorderStrong.opacity(0.7))
                            .frame(width: 5, height: max(9, 13 + CGFloat(bucket.rhythmCount) * 5))
                    }
                }
                .frame(height: 40, alignment: .bottom)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vaktMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 82)
            .background(Color.vaktSurface.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktBorder.opacity(0.58), lineWidth: 0.5)
            )
        }
        .buttonStyle(VaktPressStyle())
    }

    private var summaryText: String {
        let count = summary.rhythmCount
        guard count > 0 else { return L10n.string("profile.week.empty") }
        let key = count == 1 ? "profile.week.count.one" : "profile.week.count.many"
        return L10n.formatString(key, ProfileNumberFormatter.string(count))
    }
}

private struct MakeupPrayerLine: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: count == 0 ? "checkmark.circle" : "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(count == 0 ? Color.vaktMuted : Color.vaktGlow)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("profile.makeup.title"))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(makeupDetail)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer()

                if count > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.vaktMuted)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(Color.vaktSurface.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .disabled(count == 0)
    }

    private var makeupDetail: String {
        guard count > 0 else { return L10n.string("profile.makeup.empty") }
        let key = count == 1 ? "profile.makeup.count.one" : "profile.makeup.count.many"
        return L10n.formatString(key, ProfileNumberFormatter.string(count))
    }
}

private struct PersonalSettingsDock: View {
    let reminderState: ReminderState
    let methodTitle: String
    let onReminders: () -> Void
    let onPrayerTimes: () -> Void
    let onAccount: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            dockButton(
                icon: reminderState == .enabled ? "bell.fill" : "bell.slash",
                title: L10n.string("profile.dock.reminders"),
                detail: reminderDetail,
                action: onReminders
            )
            dockButton(
                icon: "clock",
                title: L10n.string("profile.dock.prayer_times"),
                detail: methodTitle,
                action: onPrayerTimes
            )
            dockButton(
                icon: "person.crop.circle",
                title: L10n.string("profile.dock.account"),
                detail: L10n.string("profile.dock.privacy"),
                action: onAccount
            )
        }
        .padding(6)
        .background(Color.vaktSurface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.6), lineWidth: 0.5)
        )
    }

    private var reminderDetail: String {
        switch reminderState {
        case .enabled:
            return L10n.string("profile.dock.on")
        case .paused:
            return L10n.string("profile.dock.off")
        case .notRequested, .denied:
            return L10n.string("profile.dock.permission_required")
        }
    }

    private func dockButton(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 7) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(Color.vaktElevated.opacity(0.9))
                            .frame(width: 30, height: 30)

                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.vaktGlow)
                    }

                    Spacer(minLength: 2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.vaktMuted.opacity(0.9))
                        .padding(.top, 3)
                }
                .padding(.horizontal, 9)

                Text(title)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(detail)
                    .font(VaktFont.caption(8))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(Color.vaktElevated.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.vaktBorder.opacity(0.72), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
    }
}

private enum ProfileNumberFormatter {
    static func string(_ value: Int) -> String {
        value.formatted(.number.locale(VaktLocalization.appLocale))
    }
}

private struct ReminderSettingsSheet: View {
    @ObservedObject var manager: NotificationManager
    @Binding var quietSoundEnabled: Bool
    let onOpenSystemSettings: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.string("reminder.header.title"))
                            .font(VaktFont.title(25))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)

                        Text(L10n.string("reminder.header.subtitle"))
                            .font(VaktFont.body(12))
                            .foregroundStyle(Color.vaktMuted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }

                    ReminderMasterControl(
                        state: manager.reminderState,
                        onToggle: {
                            switch manager.reminderState {
                            case .denied:
                                onOpenSystemSettings()
                            case .enabled:
                                manager.setReminderEnabled(false)
                            case .notRequested, .paused:
                                Task {
                                    _ = await manager.enableRemindersAndRequestAuthorization()
                                }
                            }
                        }
                    )

                    VStack(spacing: 0) {
                        ReminderPreferenceRow(
                            icon: "hourglass",
                            title: L10n.string("reminder.before.title"),
                            detail: L10n.formatString(
                                "reminder.minutes_before",
                                ProfileNumberFormatter.string(manager.preferences.minutesBeforePrayer)
                            ),
                            isOn: manager.preferences.prayerOpeningEnabled,
                            isEnabled: manager.areRemindersActive
                        ) {
                            manager.setPrayerOpeningEnabled(!manager.preferences.prayerOpeningEnabled)
                        }

                        VaktDivider().padding(.leading, 48)

                        ReminderPreferenceRow(
                            icon: "clock",
                            title: L10n.string("reminder.at_time.title"),
                            detail: L10n.string("reminder.at_time.detail"),
                            isOn: manager.preferences.prayerTimeEnabled,
                            isEnabled: manager.areRemindersActive
                        ) {
                            manager.setPrayerTimeEnabled(!manager.preferences.prayerTimeEnabled)
                        }

                        VaktDivider().padding(.leading, 48)

                        ReminderPreferenceRow(
                            icon: "sunrise",
                            title: L10n.string("reminder.fajr.title"),
                            detail: L10n.formatString(
                                "reminder.minutes_before",
                                ProfileNumberFormatter.string(manager.preferences.fajrWakeMinutesBefore)
                            ),
                            isOn: manager.preferences.fajrWakeEnabled,
                            isEnabled: manager.areRemindersActive
                        ) {
                            manager.setFajrWakeEnabled(!manager.preferences.fajrWakeEnabled)
                        }

                        VaktDivider().padding(.leading, 48)

                        ReminderPreferenceRow(
                            icon: "checkmark.circle",
                            title: L10n.string("reminder.checkin.title"),
                            detail: L10n.formatString(
                                "reminder.checkin.detail",
                                ProfileNumberFormatter.string(manager.preferences.checkInMinutesBeforeNextPrayer)
                            ),
                            isOn: manager.preferences.checkInEnabled,
                            isEnabled: manager.areRemindersActive
                        ) {
                            manager.setCheckInEnabled(!manager.preferences.checkInEnabled)
                        }
                    }
                    .padding(.horizontal, 13)
                    .background(Color.vaktSurface.opacity(0.68))
                    .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                            .strokeBorder(Color.vaktBorder.opacity(0.65), lineWidth: 0.5)
                    )

                    Button {
                        quietSoundEnabled.toggle()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: quietSoundEnabled ? "speaker.wave.1" : "speaker.slash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.vaktGlow)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.string("reminder.sound.title"))
                                    .font(VaktFont.body(13))
                                    .foregroundStyle(Color.vaktPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)

                                Text(L10n.string("reminder.sound.detail"))
                                    .font(VaktFont.caption(9))
                                    .foregroundStyle(Color.vaktMuted)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.72)
                            }

                            Spacer()
                            VaktTogglePill(isOn: quietSoundEnabled)
                                .scaleEffect(0.82)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 58)
                        .background(Color.vaktSurface.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                    }
                    .buttonStyle(VaktPressStyle())

                    Text(L10n.string("reminder.social_note"))
                        .font(VaktFont.caption(9))
                        .foregroundStyle(Color.vaktMuted.opacity(0.8))
                        .lineSpacing(3)

                    Spacer()
                }
                .padding(VaktSpace.lg)
            }
            .navigationTitle(L10n.string("reminder.navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("reminder.action.done")) { dismiss() }
                        .foregroundStyle(Color.vaktPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ReminderMasterControl: View {
    let state: ReminderState
    let onToggle: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onToggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: masterIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isActive ? Color.vaktBg : Color.vaktMuted)
                    .frame(width: 38, height: 38)
                    .background(isActive ? Color.vaktPrimary : Color.vaktBorder.opacity(0.5))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(masterTitle)
                        .font(VaktFont.body(14))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    Text(masterDetail)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }

                Spacer()

                if state == .denied {
                    Text(L10n.string("reminder.action.settings"))
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktGlow)
                } else if state == .notRequested {
                    Text(L10n.string("reminder.action.allow"))
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktGlow)
                } else {
                    VaktTogglePill(isOn: isActive)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .background(Color.vaktElevated.opacity(isActive ? 0.52 : 0.25))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktGlow.opacity(isActive ? 0.28 : 0.1), lineWidth: 0.6)
            )
        }
        .buttonStyle(VaktPressStyle())
    }

    private var masterTitle: String {
        state == .denied
            ? L10n.string("reminder.master.denied.title")
            : L10n.string("reminder.master.title")
    }

    private var masterDetail: String {
        switch state {
        case .denied:
            return L10n.string("reminder.master.denied.detail")
        case .notRequested:
            return L10n.string("reminder.master.permission.detail")
        case .enabled:
            return L10n.string("reminder.master.enabled.detail")
        case .paused:
            return L10n.string("reminder.master.disabled.detail")
        }
    }

    private var isActive: Bool {
        state == .enabled
    }

    private var masterIcon: String {
        switch state {
        case .enabled:
            return "bell.badge.fill"
        case .paused:
            return "bell"
        case .notRequested:
            return "bell.badge"
        case .denied:
            return "bell.slash"
        }
    }
}

private struct ReminderPreferenceRow: View {
    let icon: String
    let title: String
    let detail: String
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn && isEnabled ? Color.vaktGlow : Color.vaktMuted.opacity(0.55))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VaktFont.body(13))
                        .foregroundStyle(isEnabled ? Color.vaktPrimary : Color.vaktMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(detail)
                        .font(VaktFont.caption(9))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer()
                VaktTogglePill(isOn: isOn && isEnabled)
                    .scaleEffect(0.8)
            }
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .disabled(!isEnabled)
    }
}

private struct SubscriptionAccountSummary: View {
    let summary: SubscriptionStore.Summary?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary?.billingIssueDetectedAt == nil ? "calendar" : "exclamationmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(summary?.billingIssueDetectedAt == nil ? Color.vaktGlow : Color.vaktAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(planTitle)
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Text(statusTitle)
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.vaktGlow.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    private var planTitle: String {
        guard let summary else { return L10n.string("account.subscription.loading") }
        return summary.cadence == .yearly
            ? L10n.string("account.subscription.yearly")
            : L10n.string("account.subscription.monthly")
    }

    private var statusTitle: String {
        guard let summary else { return L10n.string("account.subscription.checking") }
        if summary.billingIssueDetectedAt != nil {
            return L10n.string("account.subscription.billing_issue")
        }
        guard let date = summary.expirationDate else {
            return L10n.string("account.subscription.active")
        }
        let formatted = date.formatted(
            .dateTime.day().month(.wide).year().locale(VaktLocalization.appLocale)
        )
        return summary.willRenew
            ? L10n.formatString("account.subscription.renews_on", formatted)
            : L10n.formatString("account.subscription.active_until", formatted)
    }
}

private struct ProfileAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountStore: SocialAccountStore
    @ObservedObject var subscriptionStore: SubscriptionStore
    let onManageSubscription: () -> Void
    let onRestorePurchases: () -> Void
    let onOpenReferrals: () -> Void
    let onOpenTerms: () -> Void
    let onOpenPrivacy: () -> Void
    let onRequestSignOut: () -> Void
    let onRequestDelete: () -> Void
    let onOpenDeveloper: () -> Void

    @State private var displayName: String
    @State private var username: String
    @State private var isPrayerStatusVisible: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        accountStore: SocialAccountStore,
        subscriptionStore: SubscriptionStore,
        onManageSubscription: @escaping () -> Void,
        onRestorePurchases: @escaping () -> Void,
        onOpenReferrals: @escaping () -> Void,
        onOpenTerms: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void,
        onRequestSignOut: @escaping () -> Void,
        onRequestDelete: @escaping () -> Void,
        onOpenDeveloper: @escaping () -> Void
    ) {
        self.accountStore = accountStore
        self.subscriptionStore = subscriptionStore
        self.onManageSubscription = onManageSubscription
        self.onRestorePurchases = onRestorePurchases
        self.onOpenReferrals = onOpenReferrals
        self.onOpenTerms = onOpenTerms
        self.onOpenPrivacy = onOpenPrivacy
        self.onRequestSignOut = onRequestSignOut
        self.onRequestDelete = onRequestDelete
        self.onOpenDeveloper = onOpenDeveloper
        _displayName = State(initialValue: accountStore.profile?.displayName ?? "")
        _username = State(initialValue: accountStore.profile?.username ?? "")
        _isPrayerStatusVisible = State(initialValue: accountStore.profile?.isPrayerStatusVisible ?? true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ProfileAvatar(name: displayName)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName.isEmpty ? L10n.string("account.profile.title") : displayName)
                                .font(VaktFont.title(20))
                                .foregroundStyle(Color.vaktPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)

                            Text(username.isEmpty ? L10n.string("account.profile.username_prompt") : "@\(username)")
                                .font(VaktFont.caption(11))
                                .foregroundStyle(Color.vaktMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        Spacer()
                    }
                    .padding(.bottom, 8)

                    VStack(spacing: 8) {
                        profileField(title: L10n.string("account.profile.name"), text: $displayName, capitalization: .words, disablesAutocorrection: false)
                        profileField(title: L10n.string("account.profile.username"), text: $username, capitalization: .never, disablesAutocorrection: true)
                    }

                    Button {
                        isPrayerStatusVisible.toggle()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.vaktGlow)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.string("account.privacy.share_prayer_status"))
                                    .font(VaktFont.body(13))
                                    .foregroundStyle(Color.vaktPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)

                                Text(L10n.string("account.privacy.makeup_private"))
                                    .font(VaktFont.caption(9))
                                    .foregroundStyle(Color.vaktMuted)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                            }

                            Spacer()
                            VaktTogglePill(isOn: isPrayerStatusVisible)
                                .scaleEffect(0.82)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 58)
                        .background(Color.vaktSurface.opacity(0.68))
                        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                    }
                    .buttonStyle(VaktPressStyle())

                    if hasProfileChanges || isSaving || errorMessage != nil {
                        Button {
                            saveProfile()
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(Color.vaktBg)
                                }
                                Text(isSaving
                                     ? L10n.string("account.profile.saving")
                                     : L10n.string("account.profile.save"))
                                    .font(VaktFont.button(14))
                            }
                            .foregroundStyle(Color.vaktBg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.vaktPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                        }
                        .buttonStyle(VaktPressStyle())
                        .disabled(isSaving || !hasProfileChanges)
                        .opacity(hasProfileChanges || isSaving ? 1 : 0.45)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktGlow)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SubscriptionAccountSummary(summary: subscriptionStore.summary)
                    accountRow(icon: "person.badge.plus", title: L10n.string("account.action.referrals"), action: onOpenReferrals)
                    accountRow(icon: "rectangle.stack", title: L10n.string("account.action.manage_subscription"), action: onManageSubscription)
                    accountRow(icon: "arrow.clockwise", title: L10n.string("account.action.restore_purchases"), action: onRestorePurchases)

                    HStack(spacing: 8) {
                        compactLegalButton(title: L10n.string("common.terms"), action: onOpenTerms)
                        compactLegalButton(title: L10n.string("common.privacy"), action: onOpenPrivacy)
                    }

                    #if DEBUG
                    accountRow(icon: "hammer", title: "Developer araçları", action: onOpenDeveloper)
                    #endif

                    Spacer()

                    HStack(spacing: 8) {
                        Button(L10n.string("account.action.sign_out")) {
                            onRequestSignOut()
                        }
                        .foregroundStyle(Color.vaktMuted)

                        Rectangle()
                            .fill(Color.vaktBorder)
                            .frame(width: 0.5, height: 18)

                        Button(L10n.string("account.action.delete")) {
                            onRequestDelete()
                        }
                        .foregroundStyle(Color.vaktGlow.opacity(0.72))
                    }
                    .font(VaktFont.body(12))
                }
                .padding(VaktSpace.lg)
            }
            .navigationTitle(L10n.string("account.navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.close")) { dismiss() }
                        .foregroundStyle(Color.vaktPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var hasProfileChanges: Bool {
        guard let profile = accountStore.profile else { return false }
        return displayName.trimmingCharacters(in: .whitespacesAndNewlines) != profile.displayName ||
            username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != profile.username ||
            isPrayerStatusVisible != profile.isPrayerStatusVisible
    }

    private func profileField(
        title: String,
        text: Binding<String>,
        capitalization: TextInputAutocapitalization,
        disablesAutocorrection: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(VaktFont.caption(9))
                .foregroundStyle(Color.vaktMuted)

            TextField(title, text: text)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(disablesAutocorrection)
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktPrimary)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Color.vaktSurface.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    private func compactLegalButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(VaktFont.caption(11))
            .foregroundStyle(Color.vaktMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Color.vaktSurface.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .buttonStyle(VaktPressStyle())
    }

    private func saveProfile() {
        guard hasProfileChanges, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await accountStore.updateProfile(
                    displayName: displayName,
                    username: username,
                    isPrayerStatusVisible: isPrayerStatusVisible
                )
            } catch {
                if let backendError = error as? BackendError,
                   case let .invalidConfiguration(message) = backendError {
                    errorMessage = message
                } else {
                    errorMessage = L10n.string("account.profile.save_error")
                }
            }
            isSaving = false
        }
    }

    private func accountRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vaktGlow)
                    .frame(width: 28)

                Text(title)
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vaktMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.vaktSurface.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
    }
}

private struct AppleAccountDeletionView: View {
    @ObservedObject var accountStore: SocialAccountStore
    let onCancel: () -> Void

    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.vaktDeep.ignoresSafeArea()

            RadialGradient(
                colors: [Color.vaktElevated.opacity(0.48), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 330
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(L10n.string("common.cancel"), action: onCancel)
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktMuted)
                        .disabled(isDeleting)
                }

                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 35, weight: .ultraLight))
                        .foregroundStyle(Color.vaktGlow)

                    VStack(spacing: 7) {
                        Text(L10n.string("account.delete.authorization.title"))
                            .font(VaktFont.title(28))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)

                        Text(L10n.string("account.delete.authorization.message"))
                            .font(VaktFont.body(13))
                            .foregroundStyle(Color.vaktMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .minimumScaleFactor(0.78)
                    }
                }
                .padding(.horizontal, 18)

                Spacer()

                VStack(spacing: 12) {
                    if isDeleting {
                        HStack(spacing: 9) {
                            ProgressView()
                                .tint(Color.vaktPrimary)
                            Text(L10n.string("account.delete.in_progress"))
                                .font(VaktFont.body(13))
                                .foregroundStyle(Color.vaktMuted)
                        }
                        .frame(height: 52)
                    } else {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = []
                        } onCompletion: { result in
                            handleAuthorization(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktGlow)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    Text(L10n.string("account.delete.irreversible"))
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted.opacity(0.72))
                }
            }
            .padding(.horizontal, VaktSpace.lg)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            errorMessage = L10n.string("account.delete.authorization_error")
        case .success(let authorization):
            isDeleting = true
            errorMessage = nil
            Task { @MainActor in
                do {
                    try await accountStore.deleteAccount(authorization: authorization)
                    onCancel()
                } catch {
                    errorMessage = L10n.string("account.delete.error")
                    isDeleting = false
                }
            }
        }
    }
}

#if DEBUG
private struct ProfileDeveloperSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onResetOnboarding: () -> Void
    let onClearEntries: () -> Void
    let onShowRatePrompt: () -> Void
    let onPreviewSplash: () -> Void
    let onPreviewMakeup: () -> Void
    let onPreviewAtmosphere: (HomeAtmospherePhase?) -> Void

    @AppStorage(HomeAtmospherePhase.previewStorageKey)
    private var selectedAtmosphere = HomeAtmospherePhase.automaticPreviewValue

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        atmospherePreviewSection

                        developerRow(icon: "arrow.counterclockwise", title: "Reset onboarding", detail: "Splash ve onboarding akışını yeniden aç", action: onResetOnboarding)
                        developerRow(icon: "trash", title: "Clear entries", detail: "Cihazdaki namaz kayıtlarını temizle", action: onClearEntries)
                        developerRow(icon: "star", title: "Show rate prompt", detail: "Değerlendirme ekranını göster", action: onShowRatePrompt)
                        developerRow(icon: "sparkles", title: "Preview splash", detail: "Splash deneyimini önizle", action: onPreviewSplash)
                        developerRow(icon: "calendar", title: "Preview makeup calendar", detail: "Örnek kaza günleriyle ekranı aç", action: onPreviewMakeup)
                    }
                    .padding(VaktSpace.lg)
                }
            }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(Color.vaktPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var atmospherePreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ana sayfa atmosferi")
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktPrimary)

                    Text("Bir duruma dokununca ana sayfada açılır")
                        .font(VaktFont.caption(9))
                        .foregroundStyle(Color.vaktMuted)
                }

                Spacer()

                Button {
                    selectedAtmosphere = HomeAtmospherePhase.automaticPreviewValue
                    onPreviewAtmosphere(nil)
                } label: {
                    Text("Otomatik")
                        .font(VaktFont.caption(9))
                        .foregroundStyle(
                            selectedAtmosphere == HomeAtmospherePhase.automaticPreviewValue
                                ? Color.vaktBg
                                : Color.vaktSecondary
                        )
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            selectedAtmosphere == HomeAtmospherePhase.automaticPreviewValue
                                ? Color.vaktPrimary
                                : Color.vaktElevated.opacity(0.55)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(VaktPressStyle())
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
                spacing: 7
            ) {
                ForEach(HomeAtmospherePhase.allCases) { phase in
                    atmosphereButton(phase)
                }
            }
        }
        .padding(13)
        .background(Color.vaktSurface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorderStrong.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func atmosphereButton(_ phase: HomeAtmospherePhase) -> some View {
        let isSelected = selectedAtmosphere == phase.rawValue

        return Button {
            selectedAtmosphere = phase.rawValue
            onPreviewAtmosphere(phase)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: phase.developerIcon)
                    .font(.system(size: 11, weight: .medium))

                Text(phase.developerTitle)
                    .font(VaktFont.caption(9))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.vaktBg : Color.vaktSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(isSelected ? Color.vaktPrimary : Color.vaktElevated.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
    }

    private func developerRow(
        icon: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vaktGlow)
                    .frame(width: 32, height: 32)
                    .background(Color.vaktGlow.opacity(0.09))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktPrimary)
                    Text(detail)
                        .font(VaktFont.caption(9))
                        .foregroundStyle(Color.vaktMuted)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.vaktMuted)
            }
            .padding(.horizontal, 13)
            .frame(height: 52)
            .background(Color.vaktSurface.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
    }
}

private struct MakeupPrayerPreviewHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SocialPrayerStore(repositories: nil)

    var body: some View {
        NavigationStack {
            MakeupPrayerCenterView(store: store)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Kapat") { dismiss() }
                            .foregroundStyle(Color.vaktSecondary)
                    }
                }
        }
        .onAppear {
            store.configureMakeupPreview()
        }
    }
}
#endif

private struct ProfileAvatar: View {
    let name: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.vaktGlow.opacity(0.13))

            Text(initials)
                .font(VaktFont.title(18))
                .foregroundStyle(Color.vaktPrimary)
        }
        .frame(width: 54, height: 54)
        .overlay(
            Circle()
                .strokeBorder(Color.vaktAccent.opacity(0.28), lineWidth: 0.7)
        )
    }

    private var initials: String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(letters).uppercased()
        return value.isEmpty ? "V" : value
    }
}

private struct VaktTogglePill: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.vaktAccent.opacity(0.88) : Color.vaktBorderStrong)
                .frame(width: 44, height: 26)

            Circle()
                .fill(isOn ? Color.vaktBg : Color.vaktMuted)
                .frame(width: 20, height: 20)
                .padding(.horizontal, 3)
        }
    }
}
