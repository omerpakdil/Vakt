import SwiftUI

struct PermissionSetupView: View {
    let step: PermissionSetupStore.Step
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var notificationManager: NotificationManager
    let onRequestLocation: () -> Void
    let onOpenLocationSettings: () -> Void
    let onCompleteNotificationDecision: () -> Void

    var body: some View {
        ZStack {
            PermissionSetupBackground(step: step)

            switch step {
            case .location:
                LocationPermissionSetupView(
                    prayerStore: prayerStore,
                    onRequestLocation: onRequestLocation,
                    onOpenSettings: onOpenLocationSettings
                )
                .transition(.opacity)
            case .notifications:
                NotificationPermissionSetupView(
                    manager: notificationManager,
                    onCompleteDecision: onCompleteNotificationDecision
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.38), value: step)
    }
}

private struct PermissionSetupBackground: View {
    let step: PermissionSetupStore.Step

    var body: some View {
        ZStack {
            Color.vaktDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.vaktBg.opacity(step == .location ? 0.96 : 0.82)
                    .frame(height: 310)

                Color.vaktDeep
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.vaktBorderStrong.opacity(0.28))
                    .frame(height: 0.5)
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, 126)
            }
        }
    }
}

private struct LocationPermissionSetupView: View {
    @ObservedObject var prayerStore: PrayerScheduleStore
    let onRequestLocation: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                PermissionSetupBrandMark(symbol: "location.fill")
                    .padding(.top, max(18, proxy.safeAreaInsets.top + 8))

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("onboarding.location.title.find"))
                        .font(VaktFont.title(31))
                        .foregroundStyle(Color.vaktPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.string("onboarding.location.body.approx"))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktMuted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)

                LocationPurposeList()
                    .padding(.top, 28)

                Spacer(minLength: 18)

                PermissionSetupStatusLine(
                    icon: locationStatusIcon,
                    text: locationStatusText,
                    isActive: prayerStore.hasUsablePrayerSchedule
                )

                PermissionPrimaryAction(
                    icon: locationActionIcon,
                    title: locationActionTitle,
                    isWorking: isLocating,
                    action: locationAction
                )
                .padding(.top, 14)
                .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 10))
            }
            .padding(.horizontal, VaktSpace.lg)
        }
    }

    private var isLocating: Bool {
        guard prayerStore.locationAuthorizationStatus != .notDetermined else { return false }
        switch prayerStore.status {
        case .locating, .loading:
            return true
        case .ready, .usingSavedTimes, .denied, .failed:
            return false
        }
    }

    private var locationStatusText: String {
        if prayerStore.locationAuthorizationStatus == .notDetermined {
            return L10n.string("permission.location.ready_to_request")
        }

        switch prayerStore.status {
        case .ready, .usingSavedTimes:
            return L10n.string("onboarding.location.status.ready")
        case .denied:
            return L10n.string("onboarding.location.status.later")
        case .failed:
            return L10n.string("onboarding.location.status.retry")
        case .locating, .loading:
            return L10n.string("onboarding.location.status.finding")
        }
    }

    private var locationStatusIcon: String {
        switch prayerStore.status {
        case .ready, .usingSavedTimes: return "checkmark"
        case .denied: return "location.slash"
        case .failed: return "arrow.clockwise"
        case .locating, .loading: return "location"
        }
    }

    private var locationActionTitle: String {
        if prayerStore.locationAccessNeedsSettings {
            return L10n.string("open_settings")
        }
        if case .failed = prayerStore.status {
            return L10n.string("common.retry")
        }
        return L10n.string("action.use_location")
    }

    private var locationActionIcon: String {
        prayerStore.locationAccessNeedsSettings ? "gear" : "location.fill"
    }

    private var locationAction: () -> Void {
        prayerStore.locationAccessNeedsSettings ? onOpenSettings : onRequestLocation
    }
}

private struct LocationPurposeList: View {
    private let purposes: [(icon: String, titleKey: String, detailKey: String)] = [
        ("clock", "profile.dock.prayer_times", "permission.location.prayer_times.detail"),
        ("location.north.line", "qibla", "permission.location.qibla.detail"),
        ("building.columns", "mosques.title", "permission.location.mosques.detail")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(purposes.enumerated()), id: \.offset) { index, purpose in
                HStack(spacing: 15) {
                    Group {
                        if index == 2 {
                            VaktMosqueGlyph()
                                .stroke(
                                    Color.vaktGlow,
                                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                                )
                                .frame(width: 18, height: 16)
                        } else {
                            Image(systemName: purpose.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.vaktGlow)
                        }
                    }
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.vaktElevated.opacity(0.78)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string(purpose.titleKey))
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktPrimary)

                        Text(L10n.string(purpose.detailKey))
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .frame(minHeight: 72)

                if index < purposes.count - 1 {
                    Rectangle()
                        .fill(Color.vaktBorder.opacity(0.55))
                        .frame(height: 0.5)
                        .padding(.leading, 51)
                }
            }
        }
    }
}

private struct NotificationPermissionSetupView: View {
    @ObservedObject var manager: NotificationManager
    let onCompleteDecision: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeMoment = 0
    @State private var isRequesting = false
    @State private var isReady = false

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                PermissionSetupBrandMark(symbol: "bell.badge.fill")
                    .padding(.top, max(18, proxy.safeAreaInsets.top + 8))

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("onboarding.reminders.title.screen"))
                        .font(VaktFont.title(31))
                        .foregroundStyle(Color.vaktPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.string("onboarding.reminders.body.screen"))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktMuted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)

                ReminderMomentTimeline(activeMoment: activeMoment, isReady: isReady)
                    .padding(.top, 34)

                Spacer(minLength: 18)

                PermissionSetupStatusLine(
                    icon: isReady ? "checkmark" : "bell",
                    text: isReady
                        ? L10n.string("onboarding.reminders.on_detail")
                        : L10n.string("reminder.master.permission.detail"),
                    isActive: isReady
                )

                PermissionPrimaryAction(
                    icon: isReady ? "checkmark" : "bell.badge.fill",
                    title: isReady
                        ? L10n.string("onboarding.reminders.on")
                        : L10n.string("action.allow_prayer_reminders"),
                    isWorking: isRequesting,
                    action: requestPermission
                )
                .padding(.top, 14)

                Button {
                    manager.setReminderEnabled(false)
                    onCompleteDecision()
                } label: {
                    Text(L10n.string("action.not_now"))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(VaktPressStyle())
                .disabled(isRequesting || isReady)
                .padding(.bottom, max(8, proxy.safeAreaInsets.bottom))
            }
            .padding(.horizontal, VaktSpace.lg)
        }
        .task { await animateMoments() }
    }

    private func requestPermission() {
        guard !isRequesting, !isReady else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isRequesting = true

        Task { @MainActor in
            let granted = await manager.enableRemindersAndRequestAuthorization()
            isRequesting = false

            guard granted else {
                onCompleteDecision()
                return
            }

            withAnimation(.easeInOut(duration: 0.4)) {
                isReady = true
                activeMoment = 2
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 850))
            onCompleteDecision()
        }
    }

    private func animateMoments() async {
        guard !reduceMotion else {
            activeMoment = 1
            return
        }

        while !Task.isCancelled, !isReady {
            try? await Task.sleep(for: .milliseconds(1_450))
            guard !Task.isCancelled, !isReady else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                activeMoment = (activeMoment + 1) % 3
            }
        }
    }
}

private struct ReminderMomentTimeline: View {
    let activeMoment: Int
    let isReady: Bool

    private var moments: [(icon: String, title: String, detail: String)] {
        [
            (
                "hourglass",
                L10n.string("reminder.before.title"),
                [30, 10]
                    .map {
                        L10n.formatString(
                            "reminder.minutes_before",
                            $0.formatted(.number.locale(VaktLocalization.appLocale))
                        )
                    }
                    .joined(separator: " · ")
            ),
            (
                "clock",
                L10n.string("reminder.at_time.title"),
                L10n.string("reminder.at_time.detail")
            ),
            (
                "checkmark.circle",
                L10n.string("reminder.checkin.title"),
                L10n.formatString(
                    "reminder.checkin.detail",
                    20.formatted(.number.locale(VaktLocalization.appLocale))
                )
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                HStack(spacing: 15) {
                    Image(systemName: isReady ? "checkmark" : moment.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(index == activeMoment || isReady ? Color.vaktGlow : Color.vaktMuted)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(
                                Color.vaktElevated.opacity(index == activeMoment || isReady ? 0.9 : 0.42)
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(moment.title)
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktPrimary)

                        Text(moment.detail)
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktMuted)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .frame(minHeight: 70)
                .opacity(index == activeMoment || isReady ? 1 : 0.58)

                if index < moments.count - 1 {
                    Rectangle()
                        .fill(Color.vaktBorder.opacity(0.55))
                        .frame(height: 0.5)
                        .padding(.leading, 49)
                }
            }
        }
    }
}

private struct PermissionSetupBrandMark: View {
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.vaktGlow)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.vaktElevated.opacity(0.9)))

            Text(verbatim: "VAKT")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktSecondary)
                .tracking(1.4)
        }
    }
}

private struct PermissionSetupStatusLine: View {
    let icon: String
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.vaktGlow : Color.vaktMuted)
                .frame(width: 20)

            Text(text)
                .font(VaktFont.caption(11))
                .foregroundStyle(isActive ? Color.vaktSecondary : Color.vaktMuted)
                .lineLimit(2)

            Spacer()
        }
        .frame(minHeight: 32)
    }
}

private struct PermissionPrimaryAction: View {
    let icon: String
    let title: String
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))

                Text(title)
                    .font(VaktFont.button(15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                if isWorking {
                    ProgressView()
                        .tint(Color.vaktBg)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(Color.vaktBg)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Color.vaktPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .disabled(isWorking)
    }
}
